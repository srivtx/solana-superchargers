---
name: cost-optimization
description: Reduce RPC and streaming costs for Solana indexers — credit budgeting, filter at source, batching, dedup, RPC pool selection, and the most common cost sinks to audit.
---

# Cost Optimization for Solana Indexers

A poorly optimized indexer can cost 10-100x more than a well-designed one. The savings come from one principle: **do less, earlier, on the server**.

This reference catalogs the cost levers and the actual numbers, with verified pricing from Helius and Triton (June 2026).

## Cost levers (ranked by impact)

| Lever | Typical savings | Effort |
|---|---|---|
| 1. Filter at source (server-side) | 50-90% | Low |
| 2. Use `finalized` selectively, `confirmed` for live | 30-50% (latency) | Low |
| 3. Batch RPC calls (`getMultipleAccountsInfo`) | 5-10x | Low |
| 4. Cache with Redis | 30-70% on reads | Medium |
| 5. Use `dataSlice` to fetch only what you need | 50-90% on large accounts | Low |
| 6. Compress old slots to S3 | 90% storage cost | Medium |
| 7. Use the right RPC plan tier | varies | Low |
| 8. Self-host a validator with Geyser (only at scale) | 50%+ at >100M events/day | High |

## RPC pricing (verified, June 2026)

### Helius (most common for Solana indexers)

| Plan | Monthly $ | Credits/mo | Per-call cost |
|---|---|---|---|
| Free | $0 | 0 (test only) | n/a |
| Developer | $49 | 1M | ~$0.000049/credit |
| Business | $249 | 10M | ~$0.000025/credit |
| Professional | $999 | 50M | ~$0.000020/credit |

| Endpoint | Credits | Notes |
|---|---|---|
| `getAccountInfo` | 1 | per pubkey |
| `getMultipleAccountsInfo` | 1 + 1 per 100 keys | cheap batch |
| `getProgramAccounts` | 1 per 1000 accounts | expensive on large programs |
| `getSignaturesForAddress` | 1 per 1000 sigs | cheap |
| `getTransaction` (json) | 1 | |
| `getTransaction` (jsonParsed) | 2 | |
| `getTransaction` (full) | 5-10 | depends on version |
| WebSocket subscribe | 0 (counts as 1 subscription) | 100K subs/day on Business |
| `enhancedWebSocket` (typed events) | 0 (counts as 1 subscription) | bigger payload, but no parsing |
| Webhooks | 0 (counts as 1 webhook) | $0.40 per 1M credits processed |
| LaserStream gRPC | server cost (not metered) | separate pricing, contact sales |

### Triton (Yellowstone gRPC)

- Self-host validator: $1000+/month (validator + ops)
- Triton hosted: contact for pricing (typical $300-2000/month for shared)
- For 100M+ events/day, this is cheaper than Helius

### QuickNode

- Streams: starts at $49/month
- Per-call pricing: 1 credit per `getAccountInfo`, etc.
- Less Solana-specific than Helius but multi-chain

### Public RPC (free, not for production)

- `api.mainnet-beta.solana.com`: rate limited, ~40 req/10s/IP
- Don't use for production indexers

## Lever 1: Filter at source

**Most common win.** Solana RPCs charge by what they send you, not by what they fetch. A `getProgramAccounts` with no filter returns every account on the program.

### Bad: program-wide subscription

```typescript
// Helius: gets every tx touching any Jupiter-related program
// 100K+ txs/day
helius.rpc.subscribe({
  accountInclude: ["JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"],
});
```

### Good: pool-specific

```typescript
// Only txs that touch THIS pool
// 100-1000 txs/day
helius.rpc.subscribe({
  accountRequired: ["<pool-address>"],
});
```

### Best: with memcmp

```typescript
// Only token accounts for owner X, of size Y
helius.rpc.subscribe({
  accounts: {
    client: {
      owner: ["TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
      filters: [
        { dataSize: 165 },
        { memcmp: { offset: 32, bytes: "<base58-owner>" } },
      ],
    },
  },
});
```

**Impact**: 50-90% reduction in events delivered.

## Lever 2: Commitment level

| Commitment | Speed | Cost | Use for |
|---|---|---|---|
| `processed` | <1s | Higher (more reorgs) | Real-time UI (accept reorg risk) |
| `confirmed` | 1-2s | Medium | Live stream (most apps) |
| `finalized` | 12-15s | Lower (1 credit vs 2) | Backfill, settlements, anything financial |

For a swap indexer:
- Use `confirmed` for live stream
- Use `finalized` for backfill and post-trade settlement

## Lever 3: Batch RPC calls

### Bad: 100 individual calls

```typescript
for (const pk of pubkeys) {
  const info = await conn.getAccountInfo(pk);  // 100 RPC calls
  process(info);
}
// 100 credits, ~10s
```

### Good: `getMultipleAccountsInfo`

```typescript
const infos = await conn.getMultipleAccountsInfo(pubkeys);  // 2 credits
// 50x cheaper, ~1s
```

Helius rate limits `getMultipleAccountsInfo` to 100 keys per call (200 on Professional). For 1000 keys, do 10 calls in parallel.

```typescript
const PARALLEL = 10;
const BATCH = 100;
for (let i = 0; i < pubkeys.length; i += PARALLEL * BATCH) {
  const batch = pubkeys.slice(i, i + PARALLEL * BATCH);
  await Promise.all(
    chunk(batch, BATCH).map(keys => conn.getMultipleAccountsInfo(keys))
  );
}
```

## Lever 4: Cache with Redis

Many queries hit the same data. The current price of SOL/USDC, the latest block, your own balance. Cache it.

```typescript
async function getCachedAccount(pk: PublicKey): Promise<AccountInfo | null> {
  const key = `acc:${pk.toBase58()}`;
  const cached = await redis.get(key);
  if (cached) {
    return JSON.parse(cached);  // serialize carefully — Pubkey is 32 bytes
  }

  const info = await conn.getAccountInfo(pk);
  if (info) {
    await redis.setex(key, 30, JSON.stringify(info));  // 30s TTL
  }
  return info;
}
```

**Cache hit rates in production**: 60-90% for popular pools. **Credit savings**: 60-90%.

**Don't cache**:
- The latest slot (you need the truth)
- User-specific data (privacy)
- Data that changes every block (slot, leader, etc.)

## Lever 5: `dataSlice`

For large accounts, only fetch the fields you need. Saves bandwidth AND credits.

```typescript
// PoolState is ~1500 bytes. We only need sqrt_price, liquidity, tick.
// They're at offsets:
//   sqrt_price_x64:  8 + 1 + 32*3 + 1 + 1 + 2 = 138
//   liquidity:        8 + 1 + 32*3 + 1 + 1 + 2 + 16 = 154
//   tick_current:     8 + 1 + 32*3 + 1 + 1 + 2 + 16 + 16 = 162

const SLICE = { offset: 138, length: 4 + 16 + 16 + 4 + 2 };  // 42 bytes

const info = await conn.getAccountInfo(poolAddress, { dataSlice: SLICE });
// 4-10x cheaper, 10x faster
```

But: you lose the raw bytes for re-parsing. Trade-off.

## Lever 6: Storage compression

Slot data accumulates. By slot 350M (mid-2026), Solana has 100TB+ of historical state.

```sql
-- Use TimescaleDB to compress old data
ALTER TABLE swaps SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'pool_address',
  timescaledb.compress_orderby = 'block_time DESC'
);

SELECT add_compression_policy('swaps', INTERVAL '30 days');
-- After 30 days, data is automatically compressed (10-20x)
```

For raw transaction storage:

```typescript
// Don't store raw tx in Postgres. Use S3.
const tx = await conn.getParsedTransaction(sig);
await s3.putObject({
  Bucket: 'tx-archive',
  Key: `tx/${slot}/${sig}.json`,
  Body: JSON.stringify(tx),
}).promise();
await db.query(
  "INSERT INTO tx_archive (signature, slot, s3_uri) VALUES ($1, $2, $3)",
  [sig, slot, `s3://tx-archive/tx/${slot}/${sig}.json`]
);
```

**Impact**: 90% storage cost reduction.

## Lever 7: Choose the right RPC plan

Most projects over-pay. Match plan to actual usage.

| Monthly events | Plan | Cost |
|---|---|---|
| < 100K | Free + public RPC | $0 |
| 100K - 1M | Developer | $49 |
| 1M - 10M | Business | $249 |
| 10M - 100M | Professional | $999 |
| 100M+ | Self-host Geyser | $1000+ |

Use Helius's [credit calculator](https://dashboard.helius.dev/credits) to estimate based on your actual call pattern.

## Lever 8: Self-host a validator (only at scale)

If you're processing >100M events/day, the math flips:
- Helius Professional: $999/mo + overage
- Self-hosted validator + Geyser: $1000-3000/mo (server + ops)

Self-hosting gives you:
- No per-call cost
- Lowest latency (<50ms)
- Custom filtering, custom deserialization
- Direct control over what's stored

**Don't self-host** until you can clearly justify the ops cost.

## Common cost sinks to audit

### 1. Unfiltered `getProgramAccounts` in hot path

```typescript
// BAD: called on every page load
async function getAllPools() {
  return conn.getProgramAccounts(RAYDIUM_CLMM);
}
```

Fix: cache the result, only refresh every 5-10 minutes.

### 2. `getTransaction` in a tight loop

```typescript
// BAD: 1 credit per tx, no batching
for (const sig of signatures) {
  const tx = await conn.getTransaction(sig);
  processTx(tx);
}
```

Fix: use a bulk transaction fetcher. Helius has `getTransactions` (plural) which is much cheaper.

### 3. Webhook for high-volume events

```typescript
// BAD: webhooks are at-most-once, but for high-volume events they're expensive
helius.webhook.create({
  accountAddresses: [...1000addresses],
  webhookURL: "...",
});
// 1000 webhooks = 1000 separate event streams, expensive
```

Fix: use `accountInclude` on a single subscription, filter at source.

### 4. Storing raw bytes in Postgres

Each row in a `bytea` column with 1KB of data = ~10x storage vs storing a URI.

Fix: S3 for raw, URI in Postgres. See [postgres-schemas.md](postgres-schemas.md).

### 5. Missing indexes

```sql
-- This query scans 10M rows
SELECT * FROM swaps WHERE pool_address = $1 ORDER BY block_time DESC LIMIT 100;
```

Fix: composite index `(pool_address, block_time DESC)`. 1000x faster.

## Credit budget calculator

```typescript
function monthlyCredits(events: number) {
  // Helius Enhanced WebSocket: ~1 credit per 100 events
  const streamCredits = events / 100;

  // Polling fallback: 1 credit per call, 1000 events per call
  const pollCredits = events / 1000;

  // Backfill: 5 credits per tx
  const backfillCredits = events * 0.1 * 5;  // 10% re-backfill

  // getMultipleAccountsInfo for snapshots: 2 credits per 100 accounts
  const snapshotCredits = events * 0.01;  // 1% as accounts

  return streamCredits + pollCredits + backfillCredits + snapshotCredits;
}

console.log(monthlyCredits(1_000_000));  // ~15,500 credits/mo for 1M events
```

Use this to estimate costs before you start.

## When you should pay for the better plan

If you're hitting rate limits on Developer ($49), upgrading to Business ($249) gives you 10x the throughput. The break-even is:
- If your time costs >$200/mo, upgrade
- If your data loss from rate limiting costs >$200/mo, upgrade
- If neither, optimize first

## When to negotiate

If you're spending >$1000/mo on Helius, contact them. They have:
- Custom plans for high-volume
- Discounts for annual commit
- Free upgrades to Professional features for partners (e.g., listing as a Helius case study)

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [geyser-plugins.md](geyser-plugins.md) — when self-hosting wins
- [backfill-strategies.md](backfill-strategies.md) — credit costs of backfill
- [real-time-streaming.md](real-time-streaming.md) — backpressure and batching
- [resources.md](resources.md) — official docs, links
