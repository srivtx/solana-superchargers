---
name: testing-indexers
description: Testing strategies for Solana indexers — unit tests with LiteSVM, integration tests with Surfpool fork, replay fixtures, golden tests, end-to-end with devnet, and chaos testing for reconnect/buffer behavior.
---

# Testing Indexers

Indexers fail in two ways: **silently** (drop events, miss updates) and **noisily** (DB corruption, OOM). You need tests that catch both.

This reference covers the test pyramid for indexers: fast unit tests with LiteSVM, integration tests with Surfpool, replay fixtures for golden tests, and chaos tests for the live stream.

## Test pyramid

```
                  /\
                 /  \
                / E2E\          ← Devnet, real program, slow (1-2 per day)
               /______\
              /        \
             /  Chaos   \      ← Kill connection, replay chaos (continuous)
            /____________\
           /              \
          /  Integration  \    ← Surfpool fork, real Anchor program (per PR)
         /________________\
        /                  \
       /   Unit (LiteSVM)   \  ← Pure functions, fast (per save)
      /______________________\
```

**Most tests should be unit. Integration for every PR. E2E + chaos for pre-release.**

## Unit tests (LiteSVM)

[LiteSVM](https://github.com/LiteSVM/LiteSVM) is a fast in-process Solana VM for tests. No validator, no Docker, no network. Tests run in milliseconds.

```toml
# Cargo.toml
[dev-dependencies]
litesvm = "0.6"
solana-sdk = "2.0"
```

```rust
use litesvm::LiteSVM;
use solana_sdk::{pubkey::Pubkey, signature::Keypair, transaction::Transaction};

#[test]
fn test_pool_initialization() {
  let mut svm = LiteSVM::new();
  svm.add_program_from_file(
    RAYDIUM_CLMM_PROGRAM_ID,
    "tests/fixtures/raydium_clmm.so",
  );

  let payer = Keypair::new();
  svm.airdrop(&payer.pubkey(), 10_000_000_000).unwrap();

  // Build a transaction that initializes a pool
  let ix = initialize_pool_ix(/* ... */);
  let tx = Transaction::new_signed_with_payer(
    &[ix],
    Some(&payer.pubkey()),
    &[&payer],
    svm.latest_blockhash(),
  );

  let result = svm.send_transaction(tx);
  assert!(result.is_ok());

  // Read the resulting account
  let pool_data = svm.get_account(&pool_key).unwrap();
  let pool = PoolState::try_from_slice(&pool_data.data).unwrap();
  assert_eq!(pool.liquidity, 0);
  assert_eq!(pool.sqrt_price_x64, expected_sqrt_price);
}
```

For TypeScript:

```bash
npm install --save-dev solana-bankrun
```

```typescript
import { startAnchor } from "solana-bankrun";
import { BankrunProvider } from "anchor-bankrun";
import { Program, AnchorProvider, web3 } from "@coral-xyz/anchor";
import idl from "./target/idl/my_program.json";

describe("indexer handler", () => {
  let context, provider, program;

  beforeAll(async () => {
    context = await startAnchor("./", [], []);
    provider = new BankrunProvider(context);
    program = new Program(idl, provider);
  });

  it("parses initialize pool ix correctly", async () => {
    // Build a tx that creates a pool
    const tx = await program.methods
      .initializePool(...)
      .accounts({...})
      .rpc();

    // Get the transaction
    const parsed = await context.banksClient.getTransaction(tx);

    // Run the indexer handler on it
    const events = parseSwapEvents(parsed);
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("POOL_CREATED");
  });
});
```

## Integration tests (Surfpool fork)

[Surfpool](https://github.com/txtx/surfpool) is a local validator with mainnet-forking support. Lets you test your indexer against the **actual current state of mainnet** without affecting it.

```bash
npm install --save-dev @txtx/surfpool
```

```bash
# Start Surfpool
surfpool start --network mainnet --port 8899
```

```typescript
import { Connection, PublicKey } from "@solana/web3.js";

const conn = new Connection("http://localhost:8899");

// Run a real transaction against a forked mainnet state
const sig = await conn.sendTransaction(testTx);

// Run your indexer on it
const events = await indexer.processTransaction(sig);
expect(events.length).toBeGreaterThan(0);
```

Surfpool features:
- **Mainnet fork**: state is a copy of mainnet at a chosen slot
- **Cheatcodes**: skip time, modify accounts, force slot increments
- **Surfnet MCP**: agent-driven validator control (see Solana AI Kit's `/test-rust`)

```typescript
// Skip forward in time
await cheatcodes.warpToSlot(351_000_000n);

// Force a slot increment
await cheatcodes.advanceSlot();

// Modify an account
await cheatcodes.setAccount(pubkey, accountData);
```

## Replay fixtures (golden tests)

The most important test for an indexer: **does it produce the same output for the same input, every time, forever?**

Approach: capture a real input, capture the expected output, run the indexer on the input, compare.

```typescript
import { readFileSync } from "fs";

describe("golden test: Raydium swap parser", () => {
  it("matches snapshot", () => {
    const input = JSON.parse(readFileSync("tests/fixtures/swap-tx.json", "utf-8"));
    const expected = JSON.parse(readFileSync("tests/fixtures/swap-tx.expected.json", "utf-8"));

    const actual = parseSwapEvents(input);

    expect(actual).toEqual(expected);
  });
});
```

`tests/fixtures/swap-tx.json` is a real transaction captured from mainnet. `tests/fixtures/swap-tx.expected.json` is what the parser should produce. Both checked in to git.

**Run golden tests on every PR**. If a parser output changes, the PR must include an explanation (e.g., "we added a new event type").

To capture fixtures:

```typescript
// tests/capture.ts
import { writeFileSync } from "fs";
import { Connection } from "@solana/web3.js";

const conn = new Connection(process.env.MAINNET_RPC!);
const sig = "5j7Bz...";  // some interesting tx

const tx = await conn.getTransaction(sig, { maxSupportedTransactionVersion: 0 });
writeFileSync("tests/fixtures/swap-tx.json", JSON.stringify(tx, null, 2));
```

Run once, commit, never modify.

## What to test (and what not to)

### Test (pure functions)

- **Parsers**: event extraction from transaction bytes
- **Schema mapping**: account data → DB row
- **Filters**: which transactions to index
- **Deduplication**: same (slot, sig) is recognized
- **Ordering**: events are ordered by slot

### Test (DB layer)

- **Slot-conditional upserts**: newer slot wins, older is skipped
- **Schema constraints**: numeric(40,0) accepts 128-bit values
- **Indexes**: query plans use them

### Don't test

- The exact behavior of Solana RPC (it's not your code)
- The exact behavior of LiteSVM/Surfpool (test theirs)
- The exact behavior of Postgres (test yours)
- Anything that requires a network call in unit tests

## Test the parser, not the chain

The biggest mistake teams make: testing "did I get the right slot?" instead of "did my parser produce the right output?"

```typescript
// BAD: integration test
it("parses a real transaction correctly", async () => {
  const tx = await conn.getTransaction(realMainnetSig);
  const result = parseSwap(tx);
  expect(result).toEqual(expected);
});
// Slow, flaky, requires network.

// GOOD: unit test with fixture
it("parses the swap-tx fixture correctly", () => {
  const tx = loadFixture("swap-tx.json");
  const result = parseSwap(tx);
  expect(result).toEqual(loadFixture("swap-tx.expected.json"));
});
// Fast, deterministic, no network.
```

## Property-based testing for parsers

Use `fast-check` (TS) or `proptest` (Rust) to generate random inputs and check invariants.

```typescript
import fc from "fast-check";
import { parseSwapEvent } from "../parser";

fc.assert(
  fc.property(
    fc.record({
      slot: fc.bigInt({ min: 0n, max: 1_000_000_000n }),
      signature: fc.array(fc.integer({ min: 0, max: 255 }), { minLength: 64, maxLength: 64 }),
      amountIn: fc.bigInt({ min: 0n, max: 1_000_000_000_000n }),
      amountOut: fc.bigInt({ min: 0n, max: 1_000_000_000_000n }),
    }),
    (event) => {
      const parsed = parseSwapEvent(event);
      // Invariants
      expect(parsed.slot).toBe(event.slot);
      expect(parsed.amountIn).toBeGreaterThanOrEqual(0n);
      expect(parsed.amountOut).toBeGreaterThanOrEqual(0n);
    }
  ),
  { numRuns: 1000 }
);
```

Property tests catch off-by-one errors, integer overflow, and weird input combinations.

## Chaos testing for live streams

The most important test for the **live** part of the indexer: what happens when the connection dies, the DB goes down, or the stream floods?

```typescript
describe("chaos: live stream", () => {
  let stream: StreamManager;
  let eventCount = 0;

  beforeEach(() => {
    stream = new StreamManager({ /* ... */ });
    stream.on("event", () => eventCount++);
  });

  it("reconnects after disconnect", async () => {
    await stream.start();
    await sleep(1000);

    // Simulate disconnect
    stream.connection.destroy();
    await sleep(2000);

    // Should have reconnected and processed more events
    expect(eventCount).toBeGreaterThan(10);
  });

  it("dedups after reconnect", async () => {
    await stream.start();
    await sleep(1000);
    const before = await db.query("SELECT COUNT(*) FROM swaps");
    stream.connection.destroy();
    await sleep(2000);
    const after = await db.query("SELECT COUNT(*) FROM swaps");

    // Same count, not double
    expect(after.rows[0].count).toBeLessThanOrEqual(before.rows[0].count * 1.01);
  });

  it("recovers from DB outage", async () => {
    await stream.start();
    await sleep(500);

    // Simulate DB down
    db.disconnect();
    await sleep(2000);

    // DB comes back
    db.connect();
    await sleep(2000);

    // Should have buffered and written
    const count = await db.query("SELECT COUNT(*) FROM swaps");
    expect(count.rows[0].count).toBeGreaterThan(10);
  });

  it("handles backpressure without OOM", async () => {
    // Slow down the DB to simulate backpressure
    db.addQueryInterceptor(async (q) => {
      await sleep(100);  // 10x slower
      return q();
    });

    await stream.start();
    await sleep(10_000);

    // Memory should not have grown unbounded
    expect(process.memoryUsage().heapUsed).toBeLessThan(500 * 1024 * 1024);  // < 500MB
  });
});
```

Run chaos tests in a separate `chaos` test suite, run on every push, fail loudly.

## E2E tests with devnet

Last line of defense. Run the indexer against a deployed program on devnet, push real events through, verify it works.

```bash
# 1. Deploy your program to devnet
anchor deploy --provider.cluster devnet

# 2. Generate test transactions
ts-node scripts/gen-test-txs.ts

# 3. Run the indexer
E2E_RPC=https://api.devnet.solana.com ts-node src/index.ts

# 4. Wait 1 hour, then check the dashboard
psql -c "SELECT COUNT(*) FROM swaps WHERE slot > 0"
# Should match the number of generated txs
```

E2E tests are slow and flaky. Run them:
- Pre-release (every release branch)
- Nightly (cron)
- On explicit `/e2e` command

Don't run them on every PR.

## Coverage

Aim for:
- **Unit test coverage**: 80%+ for parsers, schemas, helpers
- **Integration test coverage**: every code path that talks to DB or external service
- **E2E coverage**: at least one happy path through the full system

Don't measure "lines covered". Measure "scenarios covered": every error case has a test, every parser handles every event type, every DB query has a happy + sad path.

## CI integration

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run test:unit
      - run: npm run test:integration
      - run: npm run lint

  chaos:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run test:chaos
```

## Common test mistakes

1. **Mocking the Solana SDK.** Don't. Use real fixtures. The whole point of testing is to catch SDK version regressions.
2. **Testing implementation details.** Test behavior, not internal calls. If you mock `getMultipleAccountsInfo`, you're not testing your indexer.
3. **No replay tests.** The most common bug in an indexer is "missed event X". Replay tests catch this. Skip them at your peril.
4. **Ignoring the dedup contract.** Every test should verify that the same (slot, signature) doesn't write twice.
5. **Not testing reconnect.** The stream WILL disconnect. Test that recovery is correct.

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [real-time-streaming.md](real-time-streaming.md) — what needs testing
- [backfill-strategies.md](backfill-strategies.md) — replay test source
- [production-ops.md](production-ops.md) — what to monitor in production
- [resources.md](resources.md) — official test tools
