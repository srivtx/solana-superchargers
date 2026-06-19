# Subgraph Template — Raydium CLMM

A minimal manifest + schema + mapping for indexing Raydium CLMM via [The Graph on Solana](https://thegraph.com/docs/solana).

## What this is

A **managed indexer** — you deploy this to The Graph's hosted service (or your own node), and they handle the validator, the storage, and the GraphQL API. You write the mapping logic (TypeScript → WASM), they run it.

## When to use a subgraph vs. your own indexer

| Use a subgraph | Run your own indexer |
|---|---|
| Public, queryable data (GraphQL is great for this) | Need < 1s latency |
| < 30s freshness is fine | Need < 1s freshness |
| < $100/mo budget | Will spend > $1000/mo on RPC |
| Don't want to operate Postgres + streams | Need full control over schema, ops, joins |
| Just need swaps, pools, basic metrics | Need raw transactions, inner ixs, deshred |

## Prerequisites

- Node 20+
- The Graph CLI: `npm install -g @graphprotocol/graph-cli`
- The Graph account + subgraph deployed

## Setup

```bash
# 1. Install
npm install

# 2. Generate types from the IDL
graph codegen

# 3. Build WASM
graph build

# 4. Authenticate
graph auth --studio <DEPLOY_KEY>

# 5. Deploy
npm run deploy
```

## What it indexes

- **Pool** entity: every Raydium CLMM pool with its current state
- **Swap** entity: every swap with full event details
- **BlockMeta** entity: per-block metadata

## Querying

Once deployed, your subgraph is queryable via GraphQL at:
```
https://api.thegraph.com/subgraphs/name/<your-username>/<subgraph-name>
```

```graphql
query TopPoolsByVolume {
  pools(orderBy: totalVolumeToken0, orderDirection: desc, first: 10) {
    id
    tokenMint0
    tokenMint1
    totalSwapCount
    totalVolumeToken0
    totalVolumeToken1
  }
}

query RecentSwaps($pool: ID!) {
  swaps(where: { pool: $pool }, orderBy: blockTime, orderDirection: desc, first: 100) {
    id
    inputMint
    inputAmount
    outputMint
    outputAmount
    sqrtPriceX64
    tick
  }
}
```

## Customizing

To add more event types, mint metadata, position tracking, etc.:

1. Add the entity to `schema.graphql`
2. Add the event handler in `subgraph.yaml`
3. Implement the handler in `src/mapping.ts`
4. Rebuild + redeploy

## Limitations

- **30s-2m freshness** (the Graph polls validators, doesn't stream)
- **Public data only** (no private state)
- **No raw transactions** (only decoded events)
- **Monthly cost** for hosted service (free tier available)

For real-time, raw-tx, private-state indexing, run your own indexer using the parent skill's references.

## Related

- Parent skill: [`solana-indexer-skill`](../../SKILL.md)
- Indexer architecture: [`../../references/indexer-architecture.md`](../../references/indexer-architecture.md)
- Postgres schemas: [`../../references/postgres-schemas.md`](../../references/postgres-schemas.md)
- The Graph on Solana docs: https://thegraph.com/docs/solana
