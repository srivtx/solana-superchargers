---
description: Scaffold a complete Solana indexer for a given dApp or program. Designs the architecture, generates the schema, writes the parser, sets up backfill and live stream, and produces a working starter project.
---

# /build-indexer — Scaffold a Solana Indexer

Build a complete indexer for a Solana dApp or program. Use this when starting a new indexer from scratch.

## What this command does

1. **Identify the target**: parse the user's input to determine the program ID, dApp, and events to index
2. **Design the architecture**: invoke the `indexer-architect` agent to design the full plan
3. **Generate the schema**: write the Postgres DDL based on `references/postgres-schemas.md`
4. **Scaffold the project**: create a directory with the chosen stack (TypeScript or Rust)
5. **Write the parser**: generate the event-extraction code with verified IDL fields
6. **Write the backfill script**: snapshot + incremental replay
7. **Write the live stream consumer**: Helius WS or Yellowstone gRPC
8. **Add tests**: golden tests from `references/testing-indexers.md`
9. **Add install + run instructions**: how to deploy, monitor, debug

## Usage

```
/build-indexer "index Raydium CLMM swaps on mainnet"
/build-indexer "index Magic Eden NFT listings for collection X"
/build-indexer "backfill 90 days of Orca Whirlpool positions"
/build-indexer "set up a Yellowstone gRPC indexer for Jupiter V6 swaps"
```

## Process

1. **Parse the input**:
   - Program name → look up Pubkey from `resources.md` or ask user
   - "mainnet" / "devnet" → set network
   - Event type ("swaps", "listings", "positions", "all events") → narrow scope

2. **Read** the relevant references:
   - `references/indexer-architecture.md` (always)
   - `references/postgres-schemas.md` (always)
   - `references/backfill-strategies.md` (always)
   - `references/real-time-streaming.md` (always)
   - `references/cost-optimization.md` (always)
   - Protocol-specific: see `resources.md`

3. **Decide the stack**:
   - TypeScript + Helius WS + Postgres: default for 80% of cases
   - Rust + Yellowstone gRPC + Postgres: for high-volume (>1M events/day)
   - Subgraph: for public GraphQL data with relaxed latency

4. **Generate the project** in `./<project-name>/`:
   ```
   <project-name>/
   ├── package.json (or Cargo.toml)
   ├── README.md
   ├── schema.sql
   ├── .env.example
   ├── src/
   │   ├── parser.ts (or .rs)
   │   ├── db.ts
   │   ├── stream.ts
   │   ├── backfill.ts
   │   └── server.ts (if webhook-based)
   ├── tests/
   │   ├── fixtures/ (golden test data)
   │   └── parser.test.ts
   └── scripts/
       ├── migrate.ts
       └── test-swap.ts
   ```

5. **Fill in the code**:
   - **Parser**: extract events from tx bytes using the verified IDL from the program repo
   - **Schema**: based on `postgres-schemas.md` canonical templates
   - **Stream**: copy from `examples/minimal-indexer-ts/` or `examples/geyser-plugin/skeleton/`
   - **Backfill**: snapshot + replay pattern from `references/backfill-strategies.md`
   - **Tests**: golden test fixture from a real mainnet tx

6. **Verify** (if possible):
   - Run `tsc --noEmit` or `cargo check`
   - Run unit tests
   - Test against devnet

7. **Output summary**:
   - File tree created
   - Commands to run
   - Estimated cost (from `references/cost-optimization.md`)
   - Known limitations (e.g., "no backfill yet, add via `references/backfill-strategies.md`")

## Example output

```
/build-indexer "index Raydium CLMM swaps on mainnet"
  → identified: program=CAMMCzo5YL8w4VFF8KVHrK22GgU4tBh1WaxgLsD1YwbF, network=mainnet, events=swap
  → architecture: Helius enhanced WS + Postgres, 1000 events/day estimate
  → created ./raydium-clmm-indexer/ with:
    - schema.sql (3 tables: pools, swaps, positions)
    - src/parser.ts (parses SwapEvent from event log + inner ixs)
    - src/stream.ts (Helius enhanced WebSocket subscriber)
    - src/db.ts (batched Postgres writer with slot-conditional upsert)
    - tests/fixtures/swap-tx.json (real mainnet tx)
    - README.md
  → run: cd raydium-clmm-indexer && npm install && npm run dev
  → cost: ~$5-15/mo on Helius Business for 1M events
  → known gaps: no backfill (see ../references/backfill-strategies.md)
```

## Reference skills to compose

- `ext/helius` — for Helius API patterns
- `ext/solana-dev` — for Solana Foundation best practices
- `ext/sendai/skills/quicknode` — if using QuickNode instead of Helius
- `ext/cloudflare` — for deploying the indexer on Workers

## What NOT to do

- Don't generate code that calls the raw RPC for every event (use streaming)
- Don't generate code that stores raw transactions in Postgres (use S3)
- Don't generate code without dedup logic (always include `(slot, signature)` keys)
- Don't generate code without backfill (live stream alone has gaps)
- Don't generate code without a test plan (every output must include test instructions)
- Don't include `verify` instructions that require the user to have a keypair / wallet

## Examples of well-formed outputs

See `examples/minimal-indexer-ts/` (Helius webhook) and `examples/geyser-plugin/skeleton/` (Rust Geyser) for templates this command should aim to produce.
