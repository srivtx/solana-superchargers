---
name: real-time-streaming
description: Real-time streaming patterns for Solana indexers — Helius Enhanced WebSocket, Yellowstone gRPC, reconnect logic, dedup, backpressure, ordering, and what to do when the stream falls behind.
---

# Real-Time Streaming Patterns

Once your backfill is done, you need a **live stream** to keep the indexer current. This is where most teams cut corners and regret it later.

This reference covers the actual mechanics of staying live: how to connect, how to stay connected, how to dedup, what to do when the stream falls behind, and how to recover from a crash.

## The two main stream types

### Type 1: Enhanced WebSocket (Helius)

Helius parses raw Solana events and gives you **typed** updates. Best for most dApps.

```typescript
import { createHelius } from "helius-sdk";

const helius = createHelius({ apiKey: process.env.HELIUS_API_KEY! });

const stream = await helius.rpc.subscribe({
  accountInclude: ["<program-id>"],   // OR specific accounts
  accountExclude: [],
  accountRequired: [],
  vote: false,
  failed: false,
  type: "transaction",                // 'transaction' | 'account'
});

stream.on("transaction", (tx) => {
  console.log({
    signature: tx.signature,
    slot: tx.slot,
    type: tx.type,
    source: tx.source,
    fee: tx.fee,
    feePayer: tx.feePayer,
    instructions: tx.instructions,
    events: tx.events,                 // typed: SWAP, TRANSFER, etc.
    accountData: tx.accountData,
  });
});

stream.on("error", (err) => console.error("Stream error:", err));
```

**Pros**:
- Typed events (SWAP, TRANSFER, NFT_SALE, etc.) — no parsing
- Built-in reconnection in `helius-sdk`
- Covers 90% of use cases

**Cons**:
- Vendor lock-in (Helius)
- Rate limits on burst (subscription capped per plan)
- Events are parsed using Helius's interpretation (may differ from your IDL)

### Type 2: Yellowstone gRPC (Triton, Helius Laserstream)

Raw Solana events via gRPC. Best for high-throughput or custom filtering.

```typescript
import Client from "@triton-one/yellowstone-grpc";

const client = new Client(endpoint, xToken, channelOptions, {
  backoff: { initialIntervalMs: 100, multiplier: 2, maxRetries: 10 },
  slotRetention: 250,
});

await client.connect();
const stream = await client.subscribe();
stream.write({
  transactions: {
    client: {
      accountInclude: ["<program-id>"],
      vote: false, failed: false,
    },
  },
  transactionsStatus: {},
  blocks: {},
  blocksMeta: {},
  entry: {},
  slots: {},
  accounts: {},
  accountsDataSlice: [],
});

stream.on("data", (update) => {
  if (update.transaction) handleTx(update.transaction);
  if (update.blockMeta) handleBlockMeta(update.blockMeta);
  if (update.slot) handleSlot(update.slot);
});
```

**Pros**:
- Filter at source (server-side, saves bandwidth)
- <100ms latency
- Same protocol works for Triton / Helius Laserstream / QuickNode Streams

**Cons**:
- You write the parser
- More complex than Helius
- Server cost (not per-call)

See [geyser-plugins.md](geyser-plugins.md) for the full API.

## Connection lifecycle

```
[disconnected] -- connect() --> [connecting] --> [connected]
                                                          |
                                                          v
                                              [receiving events]
                                                          |
                                                          v
                                  [error/timeout/disconnect] -- reconnect() --> [connecting]
```

Implement this as a state machine, not a chain of promises.

```typescript
type State = "disconnected" | "connecting" | "connected" | "reconnecting";

class StreamManager {
  private state: State = "disconnected";
  private lastSlot = 0n;
  private retryCount = 0;
  private backoffMs = 100;
  private MAX_BACKOFF_MS = 30_000;

  async run() {
    while (true) {
      this.state = "connecting";
      try {
        await this.connect();
        this.state = "connected";
        this.retryCount = 0;
        this.backoffMs = 100;
        await this.readForever();
      } catch (e) {
        this.state = "reconnecting";
        this.retryCount++;
        this.backoffMs = Math.min(this.backoffMs * 2, this.MAX_BACKOFF_MS);
        await sleep(this.backoffMs + Math.random() * 1000);  // jitter
      }
    }
  }

  private async readForever() {
    return new Promise<void>((resolve, reject) => {
      this.stream.on("data", (msg) => this.handle(msg).catch(reject));
      this.stream.on("error", reject);
      this.stream.on("end", resolve);
    });
  }
}
```

**Critical details**:
- **Exponential backoff** with jitter. Don't reconnect instantly.
- **Max backoff** ~30s. If you can't connect in 30s, something is broken, not transient.
- **Reset backoff on successful connect**. Don't accumulate forever.

## Reconnection with dedup

When you reconnect, the server may replay events from the last 250 slots (Yellowstone `slotRetention`) or nothing at all (Helius). Either way, you might see the same event twice.

**Idempotency key**: `(slot, signature)`. If you've processed this pair, skip.

```typescript
const processed = new Set<string>();  // or Redis for multi-instance

function handle(update: any) {
  if (update.transaction) {
    const key = `${update.transaction.slot}:${bs58.encode(update.transaction.transaction.signature)}`;
    if (processed.has(key)) return;  // dup
    processed.add(key);
    processTx(update.transaction);
  }
}

// Periodically clean up old keys to avoid memory growth
setInterval(() => {
  const cutoff = latestSlot - 1000n;
  for (const k of processed) {
    const slot = BigInt(k.split(":")[0]);
    if (slot < cutoff) processed.delete(k);
  }
}, 60_000);
```

For multi-instance indexers, use Redis:
```typescript
const wasNew = await redis.set(`processed:${slot}:${sig}`, "1", "NX", "EX", 3600);
if (!wasNew) return;  // already processed by another instance
processTx(tx);
```

## Backpressure

When the stream is faster than your DB, you have backpressure. Options:

### Option 1: Drop events (worst)

Don't do this unless you really don't care about data. Even with dedup, you lose ordering.

### Option 2: Buffer in memory (OK for small bursts)

```typescript
const queue: any[] = [];
const MAX_QUEUE = 10_000;
let processing = false;

stream.on("data", (msg) => {
  if (queue.length >= MAX_QUEUE) {
    queue.shift();  // drop oldest
    metrics.dropped++;
  }
  queue.push(msg);
  if (!processing) drain();
});

async function drain() {
  processing = true;
  while (queue.length > 0) {
    const msg = queue.shift();
    await processTx(msg);
  }
  processing = false;
}
```

**Limit**: ~10K-100K events depending on event size. If you have more, see Option 3.

### Option 3: Stream to Kafka / Redis Streams (production)

For >100K events/day, don't buffer in process. Push to a durable queue.

```typescript
stream.on("data", async (msg) => {
  await producer.send({
    topic: "solana.transactions",
    key: `${msg.transaction.slot}:${bs58.encode(msg.transaction.transaction.signature)}`,
    value: msg,
  });
});
```

Then have a separate consumer process read from Kafka and write to DB. This decouples ingestion from processing and lets you scale them independently.

### Option 4: Bulk write to DB (10-100x faster)

Don't write one row per event. Batch:

```typescript
const BATCH_SIZE = 500;
const FLUSH_INTERVAL_MS = 100;
let buffer: any[] = [];

stream.on("data", (msg) => {
  buffer.push(toDbRow(msg));
  if (buffer.length >= BATCH_SIZE) flush();
});

setInterval(flush, FLUSH_INTERVAL_MS);

async function flush() {
  if (buffer.length === 0) return;
  const batch = buffer;
  buffer = [];
  await db.query(
    "INSERT INTO swaps (signature, slot, ...) VALUES " +
    batch.map((_, i) => `($${i*9+1}, $${i*9+2}, ...)`).join(",") +
    " ON CONFLICT (signature) DO NOTHING",
    batch.flatMap((r) => [r.signature, r.slot, /* ... */])
  );
}
```

## Ordering

**Important**: Solana streams do NOT guarantee per-account ordering across event types. A swap on pool X at slot 100 may arrive *after* a swap on pool X at slot 105 if they were on different geyser threads.

Three approaches:

### Approach 1: Order by slot in DB

Use slot-conditional upserts. Out-of-order events are skipped if older than the current state. See [postgres-schemas.md](postgres-schemas.md).

### Approach 2: Per-account sequencing

```typescript
const accountSeq = new Map<string, bigint>();  // pubkey -> last seen slot

function handle(update: any) {
  const pubkey = update.account.account.pubkey;
  const slot = BigInt(update.account.account.slot);
  const last = accountSeq.get(pubkey) || 0n;
  if (slot <= last) return;  // out of order, skip
  accountSeq.set(pubkey, slot);
  processUpdate(update);
}
```

### Approach 3: Batched + sorted

If you really need strict ordering, buffer per-account and flush when the slot is older than the next expected:

```typescript
const buffers = new Map<string, any[]>();
const minSlot = new Map<string, bigint>();

function handle(update: any) {
  const pubkey = update.account.account.pubkey;
  const slot = BigInt(update.account.account.slot);
  const min = minSlot.get(pubkey) || 0n;

  if (slot < min) return;  // older than the next one to write, drop

  const buf = buffers.get(pubkey) || [];
  buf.push(update);
  buffers.set(pubkey, buf);

  // Sort by slot and write contiguous prefix
  buf.sort((a, b) => Number(BigInt(a.account.slot) - BigInt(b.account.slot)));
  while (buf.length > 0) {
    const next = buf[0];
    if (BigInt(next.account.slot) === min + 1n || min === 0n) {
      processUpdate(next);
      minSlot.set(pubkey, BigInt(next.account.slot));
      buf.shift();
    } else {
      break;
    }
  }
}
```

**Note**: this is only needed if your queries are order-sensitive (e.g., "show me the last 10 swaps on this pool"). For most, "latest state" is enough.

## Watermarks and lag detection

Track how far behind the stream is from the chain tip.

```typescript
let lastEventSlot = 0n;
let lastEventTime = Date.now();
let lastChainSlot = 0n;

setInterval(async () => {
  const tip = await conn.getSlot("confirmed");
  lastChainSlot = BigInt(tip);
  const lag = lastChainSlot - lastEventSlot;
  const staleness = (Date.now() - lastEventTime) / 1000;

  metrics.gauge("stream.lag_slots", Number(lag));
  metrics.gauge("stream.staleness_seconds", staleness);

  if (lag > 50) console.warn(`Stream lagging ${lag} slots behind chain tip`);
  if (staleness > 30) console.warn(`No events for ${staleness}s, may be stuck`);
}, 5000);
```

Alert thresholds:
- `lag > 100 slots` (40s @ 2.5 slots/s): degraded
- `lag > 500 slots`: critical
- `staleness > 60s`: stream is dead

## Crash recovery

When your process crashes mid-stream, you need to:
1. **Detect the last slot you processed** (from DB: `MAX(slot)`)
2. **Backfill the gap** (slot 0 → last slot is fine, you just need last → current)
3. **Start the live stream from `current`**

```typescript
async function recover() {
  const ourMaxSlot = await db.query("SELECT MAX(slot) AS max FROM swaps");
  const chainTip = await conn.getSlot("finalized");
  if (ourMaxSlot.max < chainTip) {
    console.log(`Recovering ${chainTip - ourMaxSlot.max} slots`);
    await backfillRange(ourMaxSlot.max + 1, chainTip);
  }
  await startLiveStream();
}
```

**Critical**: use `finalized` commitment for the recovery check, not `confirmed`. Otherwise your stream will have gaps from reorgs.

## Filter best practices

### Whitelist accounts when possible

```typescript
// Bad: get every tx touching the program
accountInclude: ["<program-id>"]

// Better: only txs that touch a specific pool
accountRequired: ["<pool-address>"]

// Even better: only txs with both mints (for swap indexer)
accountRequired: ["<pool>", "<mint_a>", "<mint_b>"]
```

### Exclude vote and failed txs

```typescript
{
  vote: false,
  failed: false,
}
```

### Use memcmp to filter by data contents

```typescript
{
  accounts: {
    client: {
      owner: ["<program-id>"],
      filters: [
        { dataSize: 165 },  // SPL token account size
        { memcmp: { offset: 32, bytes: "<base58-owner>" } },  // only certain owners
      ],
    },
  },
}
```

## Testing live streaming

You can't test reconnect/buffer/ordering in unit tests. Use:

1. **LiteSVM** for unit tests of the handler logic
2. **Surfpool fork** for integration tests against a real program
3. **Devnet** for end-to-end with real events
4. **Chaos testing** for reconnect: kill the connection mid-stream, verify resume

```typescript
// Chaos test
setInterval(() => {
  if (Math.random() < 0.05) {
    console.log("Simulating disconnect");
    stream.destroy();
  }
}, 10_000);
```

Run for an hour. Verify no events lost, no DB corruption, no memory leak.

## What NOT to do

1. **Don't trust event order across accounts.** Use slot-conditional upserts.
2. **Don't buffer unbounded in memory.** At 100K events/day, 1 day of buffer = 1M+ items. Use Kafka.
3. **Don't reconnect without backoff.** You'll DDoS yourself.
4. **Don't write per-event to the DB.** Batch 100-1000 events per write.
5. **Don't store the raw transaction in the row.** Keep it in S3 or re-fetch from RPC.
6. **Don't skip the finalizer.** Use `getSlot("finalized")` for watermark, not `confirmed`.

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [geyser-plugins.md](geyser-plugins.md) — Yellowstone gRPC details
- [postgres-schemas.md](postgres-schemas.md) — DB-side dedup patterns
- [backfill-strategies.md](backfill-strategies.md) — populating before live
- [production-ops.md](production-ops.md) — keeping the stream healthy
- [cost-optimization.md](cost-optimization.md) — reducing event volume
