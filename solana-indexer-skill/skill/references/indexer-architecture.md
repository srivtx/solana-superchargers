---
name: indexer-architecture
description: Decision tree for choosing the right indexing approach on Solana — Geyser gRPC vs WebSocket vs webhooks vs polling vs subgraphs. Covers cost, latency, complexity, and when each method wins.
---

# Indexer Architecture — Choosing the Right Approach

The single most important decision when building a Solana indexer is **how you get data off-chain**. There are five viable methods, each with different tradeoffs on cost, latency, complexity, and what you can do. Most projects pick the wrong one and end up rewriting.

## The five methods

| Method | Latency | Cost (mainnet) | Complexity | Best for |
|---|---|---|---|---|
| **Geyser gRPC plugin** (Yellowstone) | <100ms | $$ (server cost) | High (Rust) | High-throughput, custom filtering, on-prem data |
| **Enhanced WebSocket** (Helius, QuickNode) | 200-500ms | $ (RPC plan) | Medium | Most dApps, default choice |
| **Webhooks** (Helius, QuickNode) | 1-5s | $ (per-event) | Low | Event-driven, low-throughput |
| **Polling** (`getSignaturesForAddress`) | 5-30s | $$ (per-call) | Low | Cold start, simple backfill |
| **Subgraph** (The Graph on Solana) | 30s-2m | $ (indexer fees) | Lowest | Public data, queryable GraphQL |

## Decision tree

```
START: How much data per day?
│
├── < 10K events/day (e.g., small NFT project, low-volume DeFi)
│   └── → WEBHOOKS
│       Cheapest. Push model. Easy to set up. Helius webhooks
│       can filter by program + account. ~$0.40 per 1M credits.
│
├── 10K - 1M events/day (e.g., mid-size DeFi, NFT marketplace)
│   └── → WEBSOCKET (Enhanced)
│       Helius `enhancedWebSocket` or QuickNode Streams.
│       Subscribe to `programSubscribe` or `accountSubscribe`.
│       Good balance of latency, cost, complexity.
│
├── 1M - 100M events/day (e.g., Jupiter aggregator, Raydium)
│   └── → YELLOWSTONE gRPC
│       Direct gRPC stream from a validator (Triton, Helius
│       Laserstream, or self-hosted). Filter at source.
│       <100ms latency. Pay for server, not per-call.
│
└── 100M+ events/day (e.g., full chain archive, MEV searcher)
    └── → CUSTOM GEYSER PLUGIN
        Run your own validator or partner with one. Write a
        Rust Geyser plugin that filters and ships to your DB
        directly. Lowest latency, lowest per-event cost at scale.
        High complexity. See geyser-plugins.md.
```

## When each method wins

### Webhooks (low-volume, event-driven)

- **Win**: 1-5s latency is fine. You don't need real-time. Lowest cost.
- **Lose**: Webhook delivery is at-most-once. If your server is down, you miss the event. Replay support is limited.
- **Use when**: small project, low TPS, infrequent events (NFT sales, big trades).

### Enhanced WebSocket (default choice)

- **Win**: real-time, low complexity (just open a WS connection), replay support.
- **Lose**: connection management (reconnect, dedupe, backpressure). RPC rate limits can bite at scale.
- **Use when**: any dApp with 10K-1M events/day. This is the **default** for 80% of projects.

### Yellowstone gRPC (high-volume, low-latency)

- **Win**: <100ms latency, filter at source (saves bandwidth), no per-call cost (server rental).
- **Lose**: more setup, need a gRPC client, vendor lock-in (Triton, Helius Laserstream, or self-host).
- **Use when**: you need sub-second latency, you're doing per-account tracking, or you want to push back the cost cliff.

### Polling (cold start, simple backfill)

- **Win**: simplest possible code, no streaming infrastructure.
- **Lose**: high latency, high cost at scale, doesn't scale to 100+ accounts.
- **Use when**: cold-starting, backfilling, or watching 1-5 accounts. **Not for production dApps.**

### Subgraph (public data, GraphQL query)

- **Win**: declarative schema (GraphQL), no backend to run, hosted indexer (The Graph).
- **Lose**: 30s-2m latency, public data only, monthly cost for hosted service.
- **Use when**: you need GraphQL for a frontend, data is public, you can wait 30s.

## Composition patterns

Most production indexers **combine** methods:

### Pattern 1: Geyser for live, polling for backfill

```typescript
// 1. Run Geyser/Yellowstone to stream live updates
const liveStream = yellowstone.subscribe(programId, handleUpdate);

// 2. On startup, poll historical signatures to backfill
const historicalSigs = await rpc.getSignaturesForAddress(programId, {
  until: lastSeenSignature,
  limit: 1000,
});

// 3. Process historical in parallel with live
await Promise.all([
  processHistorical(historicalSigs),
  liveStream.run(),
]);
```

### Pattern 2: Webhook for triggers, RPC for details

```typescript
// 1. Webhook fires on target event (e.g., new pool created)
// 2. Webhook handler fetches full transaction via getTransaction
// 3. Webhook handler parses IDL and writes to DB
app.post("/webhook", async (req, res) => {
  const sig = req.body[0].signature;
  const tx = await helius.connection.getTransaction(sig, { maxSupportedTransactionVersion: 0 });
  const parsed = parseTransaction(tx);
  await db.upsert(parsed);
  res.sendStatus(200);
});
```

### Pattern 3: Subgraph for read, custom indexer for write

```typescript
// Subgraph indexes public data (read path: GraphQL queries from frontend)
// Custom indexer handles user-specific data (write path: notifications, dashboards)
```

## Architecture: the 3 components

Every production indexer has these:

```
┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│  INGESTION   │ →  │   STORAGE   │ →  │    SERVE     │
│  (live)      │    │  (Postgres) │    │  (API/WS)    │
└──────────────┘    └─────────────┘    └──────────────┘
   Geyser gRPC        TimescaleDB        GraphQL
   WebSocket          + Redis cache      REST
   Webhook            + S3 archive       WebSocket
   Polling
```

**Ingestion** is what we've been discussing.

**Storage** is almost always Postgres + an optional cache (Redis) + cold storage (S3/GCS) for raw transaction data. See `postgres-schemas.md`.

**Serve** is your query layer. GraphQL is most flexible. REST is simplest. WebSocket for live dashboards.

## The right architecture for a new project

1. **Start with Enhanced WebSocket** (Helius or QuickNode). It's the right default.
2. **Add polling for backfill** (one-time, can run for hours/days).
3. **Add webhooks for low-volume events** (e.g., user-specific notifications).
4. **Only move to Geyser/Yellowstone** if you hit latency, cost, or volume limits.
5. **Only build a custom Geyser plugin** if you're processing >100M events/day.

## What you should NOT do

- **Don't build a custom Geyser plugin on day 1.** Maintenance burden is huge. Use Helius/QuickNode until you can't.
- **Don't poll in production.** It's the first thing people do, the first thing they regret.
- **Don't skip dedupe.** Every streaming method can deliver the same event twice. Your DB needs ON CONFLICT DO NOTHING or equivalent.
- **Don't store raw transactions in Postgres.** Use S3/GCS, store the URI in Postgres. Raw blobs will eat your disk.
- **Don't ignore backfill.** Streaming tells you what's *new*. You also need what's *old*. Plan the backfill before the live stream.

## Cost comparison (mainnet, 2026)

Assuming 1M events/day, 200 bytes per event:

| Method | Monthly cost | Latency | Setup time |
|---|---|---|---|
| Webhook (Helius) | ~$5-20 | 1-5s | 1 hour |
| Enhanced WebSocket (Helius Business) | ~$49-249 | 200-500ms | 1 day |
| Yellowstone gRPC (Triton dedicated) | ~$300-1000 | <100ms | 1 week |
| Custom Geyser plugin (self-hosted validator) | $1000+ (validator) | <50ms | 1 month |

For most dApps, the WebSocket tier is the right answer.

## Related references

- [geyser-plugins.md](geyser-plugins.md) — when and how to build a custom Geyser plugin
- [real-time-streaming.md](real-time-streaming.md) — WebSocket and gRPC streaming patterns
- [backfill-strategies.md](backfill-strategies.md) — historical data ingestion
- [cost-optimization.md](cost-optimization.md) — reducing credit usage
