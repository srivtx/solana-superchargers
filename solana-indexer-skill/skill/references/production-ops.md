---
name: production-ops
description: Operating a Solana indexer in production — health checks, slot-lag detection, alert thresholds, deployment, scaling, on-call playbooks, and what to do when things break.
---

# Production Operations for Solana Indexers

A Solana indexer in production is a long-running service that processes millions of events, talks to several external systems, and quietly fails in interesting ways. This reference is the on-call playbook.

## Health checks

A health endpoint that reports the current state of every dependency.

```typescript
// Express example
app.get("/health", async (req, res) => {
  const checks = {
    stream: streamManager.isConnected() ? "ok" : "down",
    stream_lag_slots: streamManager.getLag(),
    stream_staleness_seconds: streamManager.getStaleness(),
    db: await db.query("SELECT 1").then(() => "ok").catch(() => "down"),
    db_lag_seconds: await db.query("SELECT EXTRACT(EPOCH FROM (now() - max(updated_at))) AS s FROM swaps").then(r => r.rows[0].s).catch(() => null),
    redis: await redis.ping().then(() => "ok").catch(() => "down"),
    rpc: await rpc.getSlot().then(() => "ok").catch(() => "down"),
    chain_tip: await rpc.getSlot("finalized"),
  };
  const healthy = checks.stream === "ok" && checks.db === "ok" && checks.redis === "ok" && checks.rpc === "ok";
  res.status(healthy ? 200 : 503).json(checks);
});
```

Three states:

- **200 OK**: all deps green
- **503 Service Unavailable**: at least one dep is down
- **Liveness vs readiness**: split these. Liveness = "is the process alive?" (return 200 if event loop is responsive). Readiness = "should I get traffic?" (return 200 only if all deps are healthy).

## Key metrics

### Stream metrics

```typescript
const metrics = {
  // Lag
  stream_lag_slots: 0,              // current_chain_slot - last_processed_slot
  stream_staleness_seconds: 0,     // seconds since last event

  // Throughput
  events_per_second: 0,            // rolling 1-minute average
  events_total: 0,                 // lifetime counter

  // Health
  stream_connected: 0,             // 0 or 1 (gauge)
  reconnect_count: 0,              // lifetime counter
  reconnect_success_rate: 1.0,     // ratio over last 24h
  last_error: null,                // last error message
  last_error_at: 0,                // timestamp

  // Dedup
  events_dropped_dedup: 0,         // lifetime counter
  dedup_rate: 0.0,                 // ratio over last 1h
};
```

### DB metrics

```typescript
const dbMetrics = {
  db_query_duration_seconds: 0,   // histogram
  db_slow_queries: 0,              // > 100ms
  db_connection_pool_used: 0,      // current connections
  db_connection_pool_size: 50,    // max
  db_rows_inserted: 0,            // counter
  db_rows_updated: 0,             // counter
  db_rows_skipped_slot: 0,        // counter (out-of-order skips)
  db_lag_writes: 0,                // count of writes > 5s behind
};
```

### RPC metrics

```typescript
const rpcMetrics = {
  rpc_credits_used_today: 0,
  rpc_credits_remaining: 0,
  rpc_rate_limit_remaining: 0,
  rpc_errors: 0,
  rpc_latency_ms: 0,
};
```

## Alert thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| `stream_lag_slots` | > 100 | > 500 | Backfill missing slots |
| `stream_staleness_seconds` | > 60 | > 300 | Reconnect, check chain tip |
| `stream_connected` | 0 (down) | 0 for >5min | Force reconnect, restart |
| `reconnect_success_rate` | < 0.8 (last 24h) | < 0.5 | Check RPC, network |
| `db_query_duration_seconds` (p99) | > 100ms | > 1s | Check indexes, slow queries |
| `db_connection_pool_used` / size | > 0.8 | > 0.95 | Increase pool size |
| `rpc_credits_remaining` | < 20% | < 10% | Upgrade plan or optimize |
| `db_lag_writes` | > 10 (per minute) | > 100 | Check writer process |
| Disk usage | > 80% | > 90% | Add disk, archive old data |

Use Prometheus + Alertmanager or hosted (Datadog, Grafana Cloud).

## Deployment

### Blue-green

Run two indexer instances. Only one is "active" (writing to DB). On deploy, swap.

```
[stream A] → [writer A (active)] → [DB]
[stream B] → [writer B (standby)] → [DB]
```

On deploy, B becomes active, A restarts.

### Rolling

For stateless components. Run 3 instances, redeploy one at a time.

### Schema migrations

Always backward-compatible:
- **Adding columns**: safe
- **Removing columns**: do in two steps (1) stop writing, 2) drop)
- **Renaming columns**: never. Add new, copy data, drop old.
- **Changing types**: create new column, backfill, swap, drop old.

```sql
-- Step 1: add new column
ALTER TABLE swaps ADD COLUMN new_field NUMERIC(20, 0);

-- Step 2: backfill
UPDATE swaps SET new_field = old_field WHERE new_field IS NULL;

-- Step 3: switch reads
-- (deploy code that reads new_field)

-- Step 4: switch writes
-- (deploy code that writes new_field)

-- Step 5: drop old
ALTER TABLE swaps DROP COLUMN old_field;
```

## On-call playbooks

### Symptom: stream lag growing

```
stream_lag_slots: 50, 100, 200, 500, ...
```

**Diagnosis**:
1. Check if events are arriving at all: `SELECT MAX(slot), MAX(updated_at) FROM swaps`
2. If events are arriving but slowly: backpressure. Check DB write latency.
3. If events aren't arriving: stream is stuck. Check `last_error`.

**Fix**:
- Backpressure: scale up DB writes (more connections, faster queries, batch larger)
- Stuck: force reconnect, then backfill the gap

### Symptom: stream disconnected

```
stream_connected: 0
last_error: "Connection lost"
```

**Diagnosis**:
1. Check RPC: `curl $RPC_URL -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'`
2. Check network: can the indexer host reach the RPC?
3. Check stream: did it try to reconnect?

**Fix**:
- If RPC is down: wait, the StreamManager will retry with backoff
- If network is down: check security groups, firewall, DNS
- If reconnect is failing: check auth token, check for code errors

### Symptom: DB writes failing

```
db_query_duration_seconds: 0.05, 0.1, 0.5, 5, ...
db_errors: increasing
```

**Diagnosis**:
1. `psql -c "SELECT pid, state, wait_event, query FROM pg_stat_activity WHERE state != 'idle'"`
2. Look for long-running queries, locks
3. Check disk space, replication lag

**Fix**:
- Long queries: `SELECT pg_terminate_backend(pid)` for stuck ones
- Locks: identify the blocker, wait or kill
- Disk: archive old data, add volume
- Connections: increase pool size if exhausted

### Symptom: gaps in data

```
SELECT slot, LEAD(slot) OVER (ORDER BY slot) - slot AS gap
FROM swaps
HAVING gap > 1;
-- shows slots [350M, 350M+5, 350M+12] with gaps
```

**Diagnosis**:
1. Check stream logs around the gap slot
2. Check if RPC had an outage
3. Check if deploy happened around that time

**Fix**: backfill the missing slots. See [backfill-strategies.md](backfill-strategies.md).

### Symptom: duplicate events

```
-- Same (slot, signature) twice
SELECT slot, signature, COUNT(*)
FROM swaps
GROUP BY slot, signature
HAVING COUNT(*) > 1;
```

**Diagnosis**: dedup is broken. Check the (slot, signature) check in your code.

**Fix**:
- `INSERT ... ON CONFLICT (slot, signature) DO NOTHING` if not present
- Verify your dedup key is computed before the write
- Check that reconnects don't bypass dedup

### Symptom: indexer using too much memory

```
process.memoryUsage().heapUsed: 500MB, 1GB, 2GB, ...
```

**Diagnosis**:
1. Check the in-process queue size: `Buffer.length`, `Map.size`
2. Check for leaking subscriptions, intervals, listeners
3. Check the dedup Set — it should be bounded by `slotRetention`

**Fix**:
- Add a max size to your queue, drop oldest
- Use Redis for dedup, not in-memory
- Make sure intervals are `clearInterval`-ed when the stream ends

## Scaling

### Vertical

Start small, scale up:
- 2 vCPU / 4GB RAM: 100K events/day
- 4 vCPU / 8GB RAM: 1M events/day
- 8 vCPU / 16GB RAM: 10M events/day
- 16 vCPU / 32GB RAM: 100M events/day

### Horizontal

When vertical doesn't cut it, separate concerns:
- **Ingest service**: stream → Kafka. Scales independently.
- **Process service**: Kafka → DB. Multiple instances, each handling a partition.
- **Query service**: DB → API. Read replicas.

```
[stream] → [ingest] → [Kafka] → [processor 1] → [DB] → [query] → [client]
                              [processor 2] ↗
                              [processor 3] ↗
```

### Database scaling

- **Vertical**: Postgres scales well to ~1TB on a single node
- **Read replicas**: for query load
- **Partitioning**: by slot, by time
- **Sharding**: per-program databases (overkill for most)

## Logging

Use structured logs. JSON in production, human in dev.

```typescript
logger.info({
  event: "tx_processed",
  slot: update.transaction.slot,
  signature: bs58.encode(update.transaction.transaction.signature),
  duration_ms: 12,
  program: "RAYDIUM_CLMM",
  event_type: "SWAP",
}, "Processed swap");
```

Include:
- `slot`, `signature` for any tx event
- `duration_ms` for any operation
- `event` as a discriminator (e.g., "tx_processed", "stream_reconnected")
- `error` and `stack` for any error

Don't log raw account data (PII risk for user-owned accounts).

## Metrics export

Use Prometheus format. Most monitoring tools (Grafana, Datadog, Honeycomb) accept it.

```typescript
import { Registry, Gauge, Counter, Histogram } from "prom-client";

const registry = new Registry();

const eventsProcessed = new Counter({
  name: "indexer_events_total",
  help: "Total events processed",
  labelNames: ["program", "event_type"],
  registers: [registry],
});

const processingDuration = new Histogram({
  name: "indexer_event_duration_seconds",
  help: "Time to process a single event",
  labelNames: ["event_type"],
  buckets: [0.001, 0.01, 0.1, 1, 10],
  registers: [registry],
});

// Expose
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", registry.contentType);
  res.send(await registry.metrics());
});
```

## Configuration management

12-factor: config from environment.

```bash
# .env
DATABASE_URL=postgresql://user:pass@host:5432/indexer
REDIS_URL=redis://localhost:6379
HELIUS_API_KEY=...
YELLOWSTONE_ENDPOINT=https://...
YELLOWSTONE_TOKEN=...
LOG_LEVEL=info
ENV=production
```

Use a config library that validates at startup:
- **TS**: `zod-env`, `envalid`
- **Rust**: `figment`, `config-rs`

Don't read env vars scattered through the code. Centralize.

## Graceful shutdown

When you deploy, you need to:
1. Stop accepting new events
2. Flush in-memory queues to DB
3. Close Kafka producers
4. Close DB connections
5. Exit

```typescript
async function shutdown(signal: string) {
  logger.info({ event: "shutdown_start", signal });
  await streamManager.stop();      // stops the geyser stream
  await queue.drain();             // flushes pending events
  await db.close();                // closes DB pool
  await redis.quit();
  logger.info({ event: "shutdown_complete" });
  process.exit(0);
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
```

Kubernetes sends SIGTERM, waits 30s, then SIGKILL. Make sure shutdown completes in 30s.

## Capacity planning

For N events/day:
- DB: ~1KB per event → N MB/day → 365 * N MB/year. With compression: 1/10.
- Network: N * 1KB/second average, peaks at 10x.
- Memory: 100MB baseline + 1KB * max_queue_size
- CPU: ~1ms per event. 1M events/day = 12 events/sec average, peaks at 120 events/sec. Each takes 1ms = 0.012 cores.

Example for 10M events/day:
- DB: 10GB/day → 3.6TB/year → 360GB with compression
- Memory: 100MB + 100MB queue = 200MB
- CPU: 0.1 cores average, 1 core peak

## Runbook template

```markdown
# Runbook: Indexer

## Quick links
- Grafana: https://...
- PagerDuty: https://...
- DB: postgres://...
- Stream endpoint: https://...

## Health check
curl http://indexer:3000/health

## Restart
kubectl rollout restart deployment/indexer

## Backfill specific range
psql -c "INSERT INTO backfill_jobs (from_slot, to_slot) VALUES (350000000, 350100000)"

## View recent errors
kubectl logs -l app=indexer --tail=1000 | grep -i error

## Common issues
- See `production-ops.md` for symptom → fix mapping
```

Keep this in the repo as `RUNBOOK.md`.

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [real-time-streaming.md](real-time-streaming.md) — what to monitor
- [testing-indexers.md](testing-indexers.md) — pre-deploy testing
- [cost-optimization.md](cost-optimization.md) — capacity vs cost
- [resources.md](resources.md) — official observability tools
