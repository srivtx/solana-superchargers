---
name: solana-indexer
description: Build custom Solana indexers end-to-end. Geyser gRPC plugins, backfill strategies, Postgres schema design, real-time streaming, cost optimization, testing with LiteSVM/Surfpool, and production operations. Use when designing a new indexer, choosing between Geyser/WebSocket/webhooks/polling, designing a schema, planning a backfill, reducing RPC costs, or operating an indexer in production.
user-invocable: true
---

# Solana Indexer — Skill Hub

Routes to the right reference based on intent. Read only the section you need; the references are designed for progressive loading.

## Quick Routing

| Intent | Read first |
|---|---|
| "I need to build an indexer for X" | [references/indexer-architecture.md](references/indexer-architecture.md) — decision tree for the right approach |
| "Geyser / Yellowstone gRPC / Rust plugin" | [references/geyser-plugins.md](references/geyser-plugins.md) |
| "Postgres schema for [swaps / NFTs / pools / vaults]" | [references/postgres-schemas.md](references/postgres-schemas.md) |
| "How do I backfill [N days] of historical data" | [references/backfill-strategies.md](references/backfill-strategies.md) |
| "Real-time WebSocket / gRPC streaming patterns" | [references/real-time-streaming.md](references/real-time-streaming.md) |
| "Reduce RPC costs / credit usage" | [references/cost-optimization.md](references/cost-optimization.md) |
| "Test my indexer" | [references/testing-indexers.md](references/testing-indexers.md) |
| "Run in production — slot lag, alerts, failover" | [references/production-ops.md](references/production-ops.md) |
| "Where are the official docs" | [references/resources.md](references/resources.md) |

## Examples

See [examples/](examples/) for runnable code:

- `examples/minimal-indexer-ts/` — 100-line TypeScript indexer using Helius webhooks → Postgres. Runnable against devnet.
- `examples/geyser-plugin/skeleton/` — Rust Geyser plugin skeleton (filter `ProgramSubscribe` → batched Postgres writes).
- `examples/subgraph-template/` — The Graph subgraph manifest for Solana (compressed subgraph).

## When to use this skill

Activate when:

- User wants to build, modify, debug, or operate a Solana data indexer
- User asks about Geyser, Yellowstone, account subscriptions, program subscriptions
- User asks about historical data backfill, slot ranges, replay
- User asks about RPC cost optimization, polling vs streaming tradeoffs
- User asks about dApp backend architecture involving on-chain data aggregation
- User wants to add a new table/schema for tracking Solana protocol state
- User wants to test indexer logic without hitting mainnet

Do NOT use for:

- One-off RPC queries (use Helius/QuickNode skills directly)
- Wallet integration / signing (use `ext/solana-dev/frontend-framework-kit`)
- Program development (Anchor/Pinocchio patterns are in `ext/solana-dev/programs/`)
- Frontend dashboards that *consume* indexed data (not the indexer itself)

## Routing rules

- **Primary**: this skill for all *building*/*operating* an indexer questions
- **Composes with**: `ext/helius` (for *using* Helius APIs inside the indexer), `ext/sendai/skills/quicknode` (for *using* QuickNode), `ext/cloudflare` (for deploying the indexer on Workers)
- **Source precedence**: this skill covers Geyser plugin authoring. For *consuming* Yellowstone gRPC streams (not authoring), defer to `ext/sendai/skills/quicknode` or `ext/helius`.

## Defaults (2026 stack)

- **Streaming**: Yellowstone gRPC (Triton, Helius Laserstream, QuickNode Streams)
- **Polling fallback**: Helius enhanced transactions API
- **Storage**: Postgres 16, optional TimescaleDB for time-series aggregations
- **Backfill**: Snapshot + incremental replay
- **Test**: LiteSVM (unit), Surfpool fork (integration)
- **Local validator**: Surfpool
- **Migrations**: sqlx-cli (Rust) or Drizzle/Knex (TS)
- **Service**: Docker + k8s, Prometheus, PagerDuty
