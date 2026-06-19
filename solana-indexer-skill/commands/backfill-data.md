---
description: Backfill historical data into a running Solana indexer. Plans the backfill strategy (snapshot, replay, or hybrid), estimates cost, writes the script, and runs it with checkpointing.
---

# /backfill — Backfill Historical Data into an Indexer

Populate a running indexer with historical on-chain data. Use this when you need to catch up to a specific slot, recover from data loss, or onboard a new program.

## What this command does

1. **Identify the target**: parse the user's input to determine the program, slot range, and backfill mode
2. **Decide the strategy**: snapshot, replay, or hybrid (see `references/backfill-strategies.md`)
3. **Estimate cost**: RPC credits, time, disk
4. **Write the backfill script**: with checkpointing so it can resume
5. **Run it** (if the user confirms)
6. **Verify**: gap detection + golden test against a known slot

## Usage

```
/backfill "from genesis to current for Raydium CLMM pools"
/backfill "last 90 days of Jupiter swaps"
/backfill "slots 350000000 to 350100000 for Magic Eden listings"
/backfill "snapshot of all Orca positions, then catch up to live"
```

## Process

1. **Parse the input**:
   - Program name → look up Pubkey
   - Slot range → either explicit (`350000000-350100000`) or relative ("last 90 days" → calculate from block time)
   - Mode → snapshot only, replay only, or hybrid

2. **Read** the relevant references:
   - `references/backfill-strategies.md` (always)
   - `references/cost-optimization.md` (for credit budgeting)
   - `references/postgres-schemas.md` (for the destination tables)

3. **Inspect the current state of the indexer**:
   - Check `MAX(slot)` in each table
   - Check if the indexer is currently running (if so, lock tables or coordinate)
   - Check available disk space (estimated: 1KB per event × event count)

4. **Decide the strategy**:
   - **Snapshot only** (fastest, lossy): `getProgramAccounts` for current state
   - **Replay only** (slow, complete): iterate signatures from old to new, fetch each
   - **Hybrid** (recommended): snapshot + replay in parallel

5. **Estimate cost**:
   - Snapshot: `accounts / 1000` credits (Helius `getProgramAccounts`)
   - Replay: `signatures / 1000 + txs * 5` credits
   - Total in $ using the formula from `references/cost-optimization.md`

6. **Write the backfill script** with:
   - **Checkpointing**: store last-processed slot/signature in a `backfill_state` table
   - **Parallelism**: 5-10 concurrent RPC calls (tune to your rate limit)
   - **Batch DB writes**: 500 events per `INSERT`
   - **Slot-conditional upsert**: `ON CONFLICT DO UPDATE WHERE new.slot > existing.slot`
   - **Resume from checkpoint**: if crashed, read the checkpoint and continue
   - **Rate limit handling**: exponential backoff on 429 responses
   - **Progress logging**: every 1000 events

7. **Test** on a small range first (e.g., 100 slots) to verify correctness

8. **Run** for the full range, with periodic progress reports

9. **Verify**:
   - Gap detection query (from `references/backfill-strategies.md`)
   - Compare event count to expected (from chain analytics)
   - Spot-check 5-10 random signatures against Helius DAS

## Output

```
/backfill "last 90 days of Jupiter swaps"
  → identified: program=JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4, range=slots 336000000-351000000
  → strategy: hybrid (snapshot + parallel replay)
  → estimated: 8.4M signatures, ~3-6 hours, ~10K credits (~$5 on Business plan)
  → wrote ./scripts/backfill-jupiter.ts
  → disk needed: ~8GB
  → test run (100 slots): ✓ 142 events in 12s
  → full run: starting now, checkpoint at every 10K signatures
  → progress: 12% (1M/8.4M) — 18 min elapsed, ~2.5h remaining
  → done: 8,432,193 swaps inserted, 0 errors, gap check: 0 missing slots
```

## Reference skills to compose

- `ext/helius` — for Helius RPC + enhanced WebSocket for gap-filling
- `ext/sendai/skills/quicknode` — if using QuickNode
- `ext/solana-dev` — for Solana program structure

## What NOT to do

- Don't run backfill against mainnet without testing on devnet first
- Don't run backfill without a checkpoint (a crash means starting over)
- Don't run backfill during peak hours (impacts user-facing RPC)
- Don't store raw transactions in Postgres (use S3)
- Don't dedupe by (slot) alone — use (slot, signature) to handle forks
- Don't backfill from genesis if the program didn't exist back then
- Don't use `getProgramAccounts` without `dataSlice` for large programs (expensive)
