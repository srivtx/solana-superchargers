---
name: backfill-strategies
description: Backfill historical Solana on-chain data into your indexer — snapshot+incremental, gap detection, dump-and-replay, parallel backfill, RPC credit budgeting, and the gotchas that bite in production.
---

# Backfill Strategies

A backfill is the one-time (or periodic) job of populating your indexer with historical on-chain data. It runs before your live stream starts, runs again every time you add a new program to index, and runs *constantly* if your live stream ever falls behind.

This is where most teams get stuck. They start the live stream, watch new events come in, then realize their dashboard is empty for the last 90 days. This reference is the playbook for doing it right.

## The fundamental challenge

Solana has no "query all events for this program from slot X to slot Y" API. To backfill, you have to:

1. Know the **range of slots** you care about (genesis → now, or last_processed_slot → now)
2. For each program, find the **set of accounts** or **signatures** to replay
3. Fetch and parse each one, in order, with dedup

The two main strategies are:

- **Account-state replay**: fetch the current state of every account owned by the program, then stream live updates
- **Transaction replay**: fetch every transaction for the program, parse all events, write all state transitions

Each has tradeoffs.

## Strategy 1: Account-state snapshot (fast, lossy)

**Best for**: pool state, positions, vaults, token accounts, anything that's "the current value of an account".

**Approach**:

1. Use `getProgramAccounts` to fetch every account owned by the program
2. Parse each account (deserialize the bytes into your schema)
3. Upsert into DB at the **current** slot (not the account's last-update slot, which is unknown without fetching each transaction)
4. Start the live stream from `latest_slot + 1`

```typescript
import { Connection, PublicKey } from "@solana/web3.js";

const PROGRAM_ID = new PublicKey("CAMMCzo5YL8w4VFF8KVHrK22GgU4tBh1WaxgLsD1YwbF"); // Raydium CLMM
const conn = new Connection(process.env.RPC_URL!);

async function backfillAccounts() {
  console.log("Fetching all program accounts...");
  const accounts = await conn.getProgramAccounts(PROGRAM_ID, {
    dataSlice: { offset: 0, length: 0 },  // just get keys, skip data
    filters: [],
  });
  console.log(`Found ${accounts.length} accounts`);

  // Batch fetch data
  const BATCH = 100;
  for (let i = 0; i < accounts.length; i += BATCH) {
    const batch = accounts.slice(i, i + BATCH);
    const pubkeys = batch.map(([pk]) => pk);

    const infos = await conn.getMultipleAccountsInfo(pubkeys);

    for (let j = 0; j < infos.length; j++) {
      const info = infos[j];
      if (!info) continue;
      try {
        const parsed = parsePool(info.data);
        await db.upsertPool({ pubkey: pubkeys[j], ...parsed, slot: latestSlot });
      } catch (e) {
        console.error(`Parse failed for ${pubkeys[j]}: ${e}`);
      }
    }
    console.log(`Processed ${i + batch.length}/${accounts.length}`);
  }
}
```

**Pros**:
- Fast (one big RPC call, then batched fetches)
- Simple to implement
- Works for any program

**Cons**:
- **Lossy**: you lose the per-slot history. You know the *current* state, not how you got there.
- **Current slot only**: you don't know when each account was last updated. If you want "balance at slot X", you can't.
- **RPC cost**: `getProgramAccounts` is expensive (often 100K+ credits per call on Helius). May need to filter by data size to reduce response.

**Credit cost estimate (Helius, 2026)**: ~1 credit per 1000 accounts. A 100K-account program = 100 credits, ~$0.10.

## Strategy 2: Transaction replay (slow, complete)

**Best for**: events, swaps, transfers, anything that's "X happened at slot Y".

**Approach**:

1. Use `getSignaturesForAddress` (or program-level equivalent) to get every signature for the program, oldest first
2. For each signature, call `getTransaction` to get the full transaction
3. Parse the transaction's inner instructions + logs to extract events
4. Write events to DB

```typescript
async function backfillTransactions(programId: PublicKey) {
  const conn = new Connection(process.env.RPC_URL!, "confirmed");
  const latestSlot = await conn.getSlot();

  let before: string | undefined = undefined;
  let totalProcessed = 0;

  while (true) {
    const sigs = await conn.getSignaturesForAddress(programId, {
      before,
      limit: 1000,
      commitment: "confirmed",
    });

    if (sigs.length === 0) break;
    before = sigs[sigs.length - 1].signature;

    for (const sigInfo of sigs) {
      if (sigInfo.err) continue;  // skip failed
      const tx = await conn.getParsedTransaction(sigInfo.signature, {
        maxSupportedTransactionVersion: 0,
      });
      if (!tx) continue;

      const events = parseSwapEvents(tx);
      for (const ev of events) {
        await db.upsertSwap(ev);
      }
    }

    totalProcessed += sigs.length;
    console.log(`Processed ${totalProcessed} signatures, last: ${sigs[sigs.length - 1].signature}`);
  }
}
```

**Pros**:
- **Complete history**: you get every event ever, in order
- **Per-slot data**: you know the exact slot
- **Replayable**: you can re-run the backfill and get the same data

**Cons**:
- **Slow**: 1000s of RPC calls. For a busy program with millions of txs, this can take days.
- **RPC cost**: `getSignaturesForAddress` is 1 credit/call (1000 sigs). `getTransaction` is 1-5 credits depending on version. For 1M txs: 5000-10000 credits, ~$5-50.
- **Pagination complexity**: you need to handle rate limits, retries, and resume from the last processed signature.

**Credit cost estimate (Helius, 2026)**: ~1 credit per signature + 1-5 per transaction. 1M txs ≈ 2-6M credits, ~$2-6 on Business plan.

## Strategy 3: Snapshot + incremental (recommended)

**Best for**: most production indexers.

**Approach**:

1. **Snapshot** the current account state with Strategy 1 (fast, lossy)
2. **Backfill events** with Strategy 2 in *parallel* with the live stream starting
3. As you discover new accounts (via live stream), fetch their state and add to snapshot
4. For accounts that close/disappear, mark them in the DB (don't delete — you want history)

```typescript
async function backfillHybrid(programId: PublicKey) {
  // Step 1: snapshot all current state (parallel)
  const snapshotPromise = backfillAccounts(programId);

  // Step 2: start backfill of events (parallel with snapshot)
  const eventsPromise = backfillTransactions(programId);

  // Step 3: start live stream as soon as snapshot completes
  // (or after a delay, to give events a head start)
  const livePromise = snapshotPromise.then(() => startLiveStream(programId));

  await Promise.all([snapshotPromise, eventsPromise, livePromise]);
}
```

**Pros**:
- Fast initial load (snapshot gives you "now" in seconds)
- Complete event history (tx replay gives you "what happened")
- Live stream is up quickly

**Cons**:
- Complex to coordinate
- Race conditions: live event arrives before its account snapshot. Handle by slot-conditional upserts.

## Strategy 4: Geyser gRPC for backfill

If you have a Geyser endpoint (Triton, Helius Laserstream, self-hosted), you can use it for backfill too:

1. Subscribe with `fromSlot: <last_processed_slot>` and a large `untilSlot: <latest_slot>`
2. The server replays all events in that range
3. Same handler as live stream — just with a different start point

```typescript
const stream = await client.subscribe();
stream.write({
  transactions: {
    client: {
      accountInclude: ["<program-id>"],
      // ...
    },
  },
  fromSlot: 350_000_000n,
  untilSlot: 350_100_000n,  // explicit end
});
```

**Pros**:
- Much faster than per-tx RPC calls
- Same handler code as live

**Cons**:
- Requires Geyser endpoint ($$$)
- Server may cap the range (e.g., 100K slots max). If so, paginate.

## Strategy 5: Compressed snapshot (for very large datasets)

If your program has 10M+ accounts and you need to ship snapshots to others (or to test environments), compress them.

```bash
# Dump current state to JSONL
psql -t -A -F"," -c "SELECT * FROM raydium_clmm_pools" > pools.csv
gzip -9 pools.csv
# → 1GB → 50MB

# Or use parquet for analytics
COPY (SELECT * FROM raydium_clmm_pools) TO '/tmp/pools.parquet' (FORMAT PARQUET);
```

Tools: `pg_dump`, `COPY ... TO`, parquet export via `pg_parquet` extension.

## Gap detection

After a backfill, you need to verify completeness. "Did we get every event?" Use a **gap detector**.

```sql
-- Find gaps in slot coverage
SELECT
  slot,
  LEAD(slot) OVER (ORDER BY slot) AS next_slot,
  LEAD(slot) OVER (ORDER BY slot) - slot - 1 AS gap
FROM swaps
WHERE program_id = X
HAVING LEAD(slot) OVER (ORDER BY slot) - slot > 1
ORDER BY slot;
```

Or use `getSignaturesForAddress` to find missing signatures and re-fetch them.

```typescript
async function detectGaps(programId: PublicKey, fromSlot: number, toSlot: number) {
  const conn = new Connection(process.env.RPC_URL!);

  // Get all signatures we have
  const ourSigs = new Set(
    (await db.query("SELECT DISTINCT signature FROM swaps WHERE slot BETWEEN $1 AND $2", [fromSlot, toSlot]))
      .map((r) => r.signature.toString("base58"))
  );

  // Get all signatures from RPC
  const theirSigs = await conn.getSignaturesForAddress(programId, {
    minContextSlot: fromSlot,
    until: undefined,  // getSignaturesForAddress is limited; use multiple calls
  });

  // Find missing
  const missing = theirSigs.filter((s) => !ourSigs.has(s.signature));
  console.log(`Missing ${missing.length}/${theirSigs.length} signatures`);
  return missing;
}
```

## Resume from failure

Backfills fail. RPCs go down, you hit rate limits, you crash. The job must be **resumable**.

Approach 1: checkpoint in DB

```sql
CREATE TABLE backfill_state (
  program_id    BYTEA NOT NULL,
  strategy      TEXT NOT NULL,            -- 'txs' | 'accounts'
  last_signature TEXT,                   -- null if not started
  last_slot     BIGINT,
  completed     BOOLEAN NOT NULL DEFAULT false,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (program_id, strategy)
);
```

Before each batch, update the checkpoint. On restart, read the checkpoint and resume from `last_signature`.

Approach 2: idempotent writes

Every write is `INSERT ... ON CONFLICT DO UPDATE WHERE new.slot > existing.slot`. So re-running a backfill is safe — newer slot wins.

## RPC credit budgeting

Real numbers (Helius, 2026, Business plan $249/mo, 10M credits):

| Operation | Credits | Time |
|---|---|---|
| `getProgramAccounts` (100K accounts) | ~100 | 1-5s |
| `getSignaturesForAddress` (1000 sigs) | 1 | 1s |
| `getMultipleAccountsInfo` (100 accounts) | 1-2 | 1s |
| `getTransaction` (with parsed, full) | 5-10 | 1-2s |
| `getTransaction` (with jsonParsed, latest) | 1-2 | 0.5s |
| Yellowstone gRPC stream | server cost, ~$300/mo flat | realtime |

**Backfill a 1M-tx program**: 1K (sigs) + 1M * 5 (tx) = 5M credits, ~$125 on Business plan, ~$50 on Developer.

**Backfill a 100K-account program**: 100 (program accounts) + 100 (multi-fetch) = 200 credits, ~$0.20.

## Parallelism

```typescript
const PARALLEL = 10;  // tune based on your RPC rate limit

async function parallelBackfill(programId: PublicKey) {
  const allSigs = await getAllSignatures(programId);  // 1000s of sigs
  const queue = [...allSigs];

  const workers = Array.from({ length: PARALLEL }, async () => {
    while (queue.length > 0) {
      const sig = queue.shift()!;
      try {
        const tx = await conn.getParsedTransaction(sig, { maxSupportedTransactionVersion: 0 });
        if (tx) await processTransaction(tx);
      } catch (e) {
        queue.push(sig);  // retry
        await sleep(1000);
      }
    }
  });
  await Promise.all(workers);
}
```

Start with PARALLEL=5. Increase until you hit rate limits.

## Common pitfalls

1. **Forgetting to handle failed transactions**. `getTransaction` returns them too. Skip them or note them.
2. **Not handling forks**. Solana has forks, and the "main" version at slot X may differ from what you processed. Use `commitment: "finalized"` for backfill (slower but stable).
3. **Parsing changes between program versions**. Anchor IDL upgrades change field layouts. Always store `raw` bytes so you can re-parse later.
4. **Rate limits hit silently**. Wrap every RPC call in retry-with-backoff.
5. **Paging breaks mid-backfill**. Use checkpoints and resume, not "start from scratch".
6. **Storage explodes**. Compress old slots. Archive to S3. Use partitioning.
7. **Indexing the wrong commitment level**. `confirmed` can be skipped/reorged. `finalized` is stable but 12-15s slower. For backfill, use `finalized`.

## When to skip backfill

- **You're building a "live" feature** (e.g., current price only). Skip backfill, start live.
- **The data is public via a GraphQL endpoint** (subgraph). Use their data.
- **It's a one-time dump**. Just use the `getProgramAccounts` snapshot, no live updates.

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [postgres-schemas.md](postgres-schemas.md) — where to put the data
- [real-time-streaming.md](real-time-streaming.md) — picking up where backfill ends
- [cost-optimization.md](cost-optimization.md) — reducing backfill cost
- [production-ops.md](production-ops.md) — gap detection in production
