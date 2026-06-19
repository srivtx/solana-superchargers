---
description: Auto-loads when working in folders related to indexing (indexer/, data-pipeline/, db-migrations/, etc.) and in TypeScript files that import Solana SDKs. Enforces the canonical patterns from this skill.
---

# Indexer Defaults

When working on a Solana indexer, follow these defaults. Auto-loaded for files in:
- `indexer/`, `indexers/`, `data-pipeline/`, `data-pipelines/`
- `db-migrations/`, `schemas/`
- TypeScript files that import `@solana/web3.js`, `@solana/kit`, `@triton-one/yellowstone-grpc`, or `helius-sdk`
- Rust files that import `solana-sdk`, `yellowstone-grpc`, or `solana-geyser-plugin-interface`

## Streaming

- **Use streaming, not polling**, for any production data ingestion. WebSocket (Helius enhanced) for < 1M events/day, Yellowstone gRPC for > 1M events/day.
- **Always set `vote: false` and `failed: false`** in transaction filters unless the user explicitly wants them.
- **Always include a `ping`** or use auto-reconnect options to prevent idle-connection drops from load balancers.

## Dedup

- **Every DB write must have a unique key**. Use `(slot, signature)` for transactions, `(pubkey, slot)` for account updates.
- **Use slot-conditional upsert**: `ON CONFLICT (pubkey) DO UPDATE SET ... WHERE existing.slot < EXCLUDED.slot`. This prevents out-of-order replays from corrupting state.
- **Never delete on reorg** — mark as inactive. Solana's confirmed state can still reorg within 12-15s.

## Type mapping

- **u64 → `NUMERIC(20, 0)`** (NOT `BIGINT` — it's signed and overflows)
- **u128, i128, Q64.64 → `NUMERIC(40, 0)`**
- **u256, u512 → `BYTEA`** (32/64 bytes)
- **Pubkey → `BYTEA(32)`** (NOT `VARCHAR(44)` — the base58 string is variable length and slow to compare)
- **bool → `BOOLEAN`**
- **`Pubkey::default()` → `'\x'::bytea`** (treat as "uninitialized")
- **i64 (timestamps, signed amounts) → `BIGINT`**

## Storage

- **Store raw account data as `BYTEA`**, not parsed JSON. Re-parse on schema changes.
- **Never store raw transactions in Postgres** — use S3/GCS, store the URI in Postgres.
- **Use TimescaleDB hypertables** for time-series (swaps, sales, snapshots).
- **Add `slot` and `updated_at` columns** to every indexed table.
- **Index on `(pubkey, slot DESC)`** for "latest state" queries.
- **Index on `(slot)` or `(block_time DESC)`** for "history at slot X" queries.
- **Partition by month** for tables > 10M rows.

## Batching

- **Always batch writes** to the DB. 500-1000 events per `INSERT`.
- **Always batch reads** to RPC. `getMultipleAccountsInfo` not per-key `getAccountInfo`.
- **Use `UNNEST` for bulk inserts** in Postgres. Don't loop with single-row inserts.

## Error handling

- **Exponential backoff with jitter** on every RPC call. Cap at 30s.
- **Never crash the validator** (Geyser plugins). Wrap risky code in `catch_unwind` or `try/catch`.
- **Graceful shutdown** on SIGTERM: stop accepting events, flush queue, close DB, exit. Cap at 30s.
- **Deadletter queue**: if a write fails repeatedly, write to S3 for manual replay. Don't lose data.

## Testing

- **Every parser has a golden test** with a real mainnet tx as fixture.
- **Test the dedup contract** explicitly. Same (slot, signature) must not write twice.
- **Test the slot-conditional upsert**. Newer slot wins, older is skipped.
- **Test reconnect behavior**. Random disconnects every 5 minutes for 1 hour. Verify no data loss.
- **Test backpressure**. Slow DB by 10x. Verify memory doesn't grow unbounded.
- **Use LiteSVM for unit tests**, Surfpool for integration, devnet for E2E.

## Performance

- **Use `dataSlice`** to fetch only the fields you need. Saves bandwidth and credits.
- **Use `getMultipleAccountsInfo`** for batch reads. 5-10x cheaper than per-key.
- **Cache with Redis** for read-heavy paths. 60-90% hit rate is typical.
- **Filter at source** (server-side). Whitelist accounts, use memcmp, exclude votes.
- **Bulk insert with `UNNEST`** not loop-insert.

## Monitoring

- **Always expose `/health`** returning 200 if all deps are up, 503 if any are down.
- **Always expose `/metrics`** in Prometheus format.
- **Track lag**: `stream_lag_slots` = `chain_tip - last_processed_slot`. Alert at > 100.
- **Track staleness**: `stream_staleness_seconds` = `now - last_event_time`. Alert at > 60.
- **Track dedup rate**: `deduped / total`. High rate = reconnect storm. Alert at > 5%.
- **Track DB write latency**: p99. Alert at > 100ms.

## Defaults (2026 stack)

- **Streaming**: Helius enhanced WebSocket (default) or Yellowstone gRPC (high volume)
- **Storage**: Postgres 16 + TimescaleDB
- **Backfill**: snapshot + incremental replay
- **Test**: LiteSVM (unit), Surfpool (integration), devnet (E2E)
- **Local validator**: Surfpool
- **Migrations**: sqlx-cli (Rust) or Drizzle (TS)
- **Cache**: Redis
- **Queue (if needed)**: Kafka or NATS JetStream
- **Deployment**: Docker + k8s
- **Metrics**: Prometheus + Grafana
- **Logs**: structured JSON (pino, tracing)
- **Tracing**: OpenTelemetry
- **Alerts**: Alertmanager + PagerDuty

## When in doubt, read

- `references/indexer-architecture.md` — overall design
- `references/geyser-plugins.md` — Geyser plugin code
- `references/postgres-schemas.md` — DB schema patterns
- `references/real-time-streaming.md` — live stream patterns
- `references/backfill-strategies.md` — historical data
- `references/cost-optimization.md` — credit budgeting
- `references/testing-indexers.md` — test pyramid
- `references/production-ops.md` — on-call playbook
- `references/resources.md` — official docs and links
