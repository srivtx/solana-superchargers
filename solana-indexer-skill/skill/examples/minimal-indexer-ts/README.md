# Minimal Indexer — Raydium CLMM Swaps → Postgres

A 100-line Solana indexer that:
- Subscribes to a Helius webhook for a program (default: Raydium CLMM)
- Parses SWAP events from enhanced transactions
- Batches writes (100 events or 500ms) to Postgres
- Exposes `/health` and `/webhook` endpoints

## Prerequisites

- Node 20+
- Postgres 14+
- Helius API key (free tier works for devnet)

## Setup

```bash
# 1. Install
npm install

# 2. Create the database
createdb minimal_indexer
psql $DATABASE_URL < schema.sql

# 3. Configure
cp .env.example .env
# Edit .env with your keys

# 4. Run (with public URL for webhook)
ngrok http 3000  # or your reverse proxy
# Update WEBHOOK_URL in .env
npm run dev
```

The server will:
1. Auto-create the webhook on Helius
2. Listen for incoming webhooks at `/webhook`
3. Parse swaps, batch to Postgres every 500ms
4. Expose `/health` for monitoring

## What it indexes

For every Raydium CLMM swap (verified from [`raydium-clmm/programs/amm/src/states/pool.rs`](https://github.com/raydium-io/raydium-clmm/blob/master/programs/amm/src/states/pool.rs)):

| Field | Source | Type |
|---|---|---|
| `signature` | tx | BYTEA |
| `slot` | tx | BIGINT |
| `block_time` | tx | BIGINT (unix seconds) |
| `program_id` | constant | BYTEA |
| `pool` | swap event | BYTEA |
| `user_wallet` | fee payer | BYTEA |
| `input_mint` | first transfer | BYTEA |
| `input_amount` | first transfer | NUMERIC(20) |
| `output_mint` | second transfer | BYTEA |
| `output_amount` | second transfer | NUMERIC(20) |
| `fee_lamports` | tx fee | NUMERIC(20) |
| `raw` | full tx | JSONB |

## Adapting to other programs

To index a different program (Jupiter, Orca, etc.):

1. Change `PROGRAM_ID` in `.env`
2. Update `parseSwap` to match that program's event shape
3. Update the `transfers` extraction logic if needed

See the Helius enhanced transaction docs: https://docs.helius.dev/webhooks-and-websockets/webhooks

## Testing

```bash
# Run a test swap on devnet
ts-node scripts/test-swap.ts

# Or use a hardcoded signature
ts-node scripts/replay-sig.ts <SIGNATURE>
```

## Limitations

- Single-instance only. For multi-instance, add a Redis dedup layer.
- Webhook delivery is at-most-once. Missed events need re-fetching from Helius.
- No backfill. Use `backfill-strategies.md` from the parent skill.

## Next steps

- Add `/backfill?from=350000000&to=350100000` endpoint
- Add Prometheus metrics
- Add structured logging
- Add rate limiting on `/webhook`
- Add a `/replay/:signature` endpoint for missed events
- Add multiple program support (route by `program_id`)

## Related

- Parent skill: [`solana-indexer-skill`](../../SKILL.md)
- Architecture: [`../../references/indexer-architecture.md`](../../references/indexer-architecture.md)
- Real-time streaming: [`../../references/real-time-streaming.md`](../../references/real-time-streaming.md)
- Postgres schemas: [`../../references/postgres-schemas.md`](../../references/postgres-schemas.md)
