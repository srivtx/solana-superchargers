---
name: geyser-plugins
description: Build and operate Geyser plugins for Solana — Rust plugin development against the Yellowstone gRPC interface, custom filters, account/transaction/block subscription patterns, and when to write your own plugin vs use a managed service.
---

# Geyser Plugins — Building Custom Streaming on Solana

Geyser is Solana's validator-side plugin interface. Plugins run inside the validator process and stream data out before it hits the RPC layer. The Yellowstone gRPC plugin is the de-facto standard: it runs alongside the validator and exposes a gRPC stream that clients subscribe to.

This reference covers how to **build** (Rust) and **use** (Rust/TS) Yellowstone-compatible geyser plugins. For the higher-level "should I use geyser vs WebSocket vs webhook" question, see [indexer-architecture.md](indexer-architecture.md).

## When to write a custom Geyser plugin

| Signal | Use a managed service | Write a custom plugin |
|---|---|---|
| Volume | < 10M events/day | > 100M events/day |
| Filter needs | Standard account/owner/tx filters | Custom deserialization, multi-stage filters |
| Latency | < 1s is fine | Need < 100ms or sub-slot |
| Cost | Per-call billing is OK | Per-server billing is cheaper at scale |
| Ops | Don't want to run a validator | Have a validator or partner with one |

**Don't write a Geyser plugin on day 1.** Use Helius/QuickNode/Triton until you can't.

## The Yellowstone gRPC ecosystem

The canonical implementation is [rpcpool/yellowstone-grpc](https://github.com/rpcpool/yellowstone-grpc) (969 stars, AGPL-3.0, latest v13.2.5+solana.4.0.0). The repo contains:

- `yellowstone-grpc-geyser/` — the Geyser plugin (Rust, runs inside the validator)
- `yellowstone-grpc-client/` — Rust client SDK
- `yellowstone-grpc-client-nodejs/` — Node.js/TypeScript client SDK (since v5.0.0 uses napi-rs for performance)
- `yellowstone-grpc-proto/` — protobuf definitions
- `examples/` — Go, Rust, TypeScript examples
- `yellowstone-grpc-kafka/` — separate project that forwards gRPC stream to Kafka

Related services that use this protocol:
- [Triton](https://triton.one) — `Dragon's Mouth` hosted Yellowstone (the original)
- [Helius LaserStream](https://github.com/helius-labs/laserstream-sdk) — compatible SDK
- [QuickNode Streams](https://www.quicknode.com/streams) — Yellowstone-compatible

## Running the plugin (validator side)

The plugin runs as part of the validator. Config example:

```bash
solana-validator \
  --geyser-plugin-config yellowstone-grpc-geyser/config.json
```

A minimal `config.json`:

```json
{
  "libpath": "/path/to/libyellowstone_grpc_geyser.so",
  "name": "yellowstone-grpc",
  "config_file": "/path/to/yellowstone-grpc-geyser/config.json"
}
```

And the inner plugin config:

```json
{
  "grpc": {
    "address": "0.0.0.0:10000",
    "tls_config": null
  },
  "filters": {
    "accounts": { "max": 1, "any": false },
    "slots": { "max": 1 },
    "transactions": { "max": 1, "any": false },
    "blocks": { "max": 1 },
    "blocks_meta": { "max": 1 },
    "entry": { "max": 1 }
  }
}
```

Production configs add TLS, auth tokens, replay config, Prometheus metrics. See the [repo's example configs](https://github.com/rpcpool/yellowstone-grpc/tree/master/yellowstone-grpc-geyser).

**Don't run a validator yourself** unless you have ops experience. Most teams rent a validator slot from Triton, Helius, or another RPC provider that runs the plugin for you.

## Writing a custom plugin (Rust)

If you need custom filtering, custom deserialization, or want to push data to a non-gRPC sink (Kafka, S3, in-process), you can write a custom Geyser plugin.

A Geyser plugin implements the `GeyserPlugin` trait from `solana-geyser-plugin-interface`:

```rust
use solana_geyser_plugin_interface::geyser_plugin::{
    GeyserPlugin, GeyserPluginError, ReplicaAccountInfoVersions,
    ReplicaBlockInfoVersions, ReplicaTransactionInfoVersions, SlotStatus,
};
use std::sync::Arc;
use tokio::sync::mpsc;

pub struct MyPlugin {
    tx: mpsc::UnboundedSender<PluginEvent>,
}

#[derive(Debug, Clone)]
pub enum PluginEvent {
    AccountUpdate { pubkey: String, lamports: u64, data: Vec<u8>, slot: u64 },
    Transaction { signature: String, slot: u64, success: bool },
    Block { slot: u64, blockhash: String, parent_slot: u64 },
}

impl GeyserPlugin for MyPlugin {
    fn name(&self) -> &'static str { "my-plugin" }

    fn on_load(&mut self, config_file: &str) -> Result<(), GeyserPluginError> {
        // Parse config_file, set up DB connection, channels
        Ok(())
    }

    fn on_unload(&mut self) {}

    fn update_account(
        &self,
        account: ReplicaAccountInfoVersions,
        slot: u64,
        is_startup: bool,
    ) -> Result<(), GeyserPluginError> {
        if is_startup { return Ok(()); } // skip snapshot
        match account {
            ReplicaAccountInfoVersions::V0_0_1(a) => {
                let _ = self.tx.send(PluginEvent::AccountUpdate {
                    pubkey: bs58::encode(&a.pubkey).into_string(),
                    lamports: a.lamports,
                    data: a.data.to_vec(),
                    slot,
                });
            }
            _ => {}
        }
        Ok(())
    }

    fn update_transaction(
        &self,
        transaction: ReplicaTransactionInfoVersions,
        slot: u64,
    ) -> Result<(), GeyserPluginError> {
        // Similar pattern
        Ok(())
    }

    fn update_block_metadata(
        &self,
        blockinfo: ReplicaBlockInfoVersions,
        slot: u64,
        is_startup: bool,
    ) -> Result<(), GeyserPluginError> {
        // Block meta
        Ok(())
    }

    fn notify_end_of_startup(&self) -> Result<(), GeyserPluginError> { Ok(()) }

    fn account_data_notifications_enabled(&self) -> bool { true }
    fn transaction_notifications_enabled(&self) -> bool { true }
    fn block_metadata_notifications_enabled(&self) -> bool { true }
}
```

Build and load:

```toml
# Cargo.toml
[dependencies]
solana-geyser-plugin-interface = "2.0"
solana-sdk = "2.0"
tokio = { version = "1", features = ["full"] }
bs58 = "0.5"
```

Compile to a `cdylib`, drop into the validator's plugin path, reference in the validator config.

**Pitfalls:**
- Plugins run inside the validator. A bug in your plugin can crash the validator. Test heavily.
- `is_startup: true` means the validator is replaying from snapshot. Skip these or your DB will be flooded with state that's about to be overwritten.
- `notify_end_of_startup` is the "you can now serve real-time" signal. Don't accept client requests before this fires.
- `on_unload` is called on graceful shutdown. Close DB connections, flush buffers.

## Consuming Yellowstone from TypeScript (the common case)

The `@triton-one/yellowstone-grpc` package is the standard client. Since v5.0.0 it uses napi-rs for performance (no more @grpc/grpc-js bottleneck).

```bash
npm install @triton-one/yellowstone-grpc
```

Subscribe to transactions on a program:

```typescript
import Client from "@triton-one/yellowstone-grpc";
import { SubscribeRequest, CommitmentLevel } from "@triton-one/yellowstone-grpc";

const client = new Client(
  process.env.GRPC_ENDPOINT!,    // e.g. https://laserstream-mainnet.helius-rpc.com
  process.env.GRPC_TOKEN!,       // x-token
);

await client.connect();

const stream = await client.subscribe();

const req: SubscribeRequest = {
  accounts: {},
  slots: {},
  transactions: {
    client: {
      accountInclude: ["JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"], // Jupiter
      accountExclude: [],
      accountRequired: [],
      vote: false,
      failed: false,
    },
  },
  transactionsStatus: {},
  blocks: {},
  blocksMeta: {},
  entry: {},
  accountsDataSlice: [],
};

stream.write(req);

stream.on("data", (update) => {
  if (update.transaction) {
    const tx = update.transaction.transaction;
    const meta = update.transaction.transaction.meta;
    console.log({
      signature: bs58.encode(tx.signature),
      slot: tx.slot,
      fee: meta.fee,
      success: !meta.err,
    });
  }
});

stream.on("error", (err) => console.error("Stream error:", err));
```

## Auto-reconnect, backfill, dedup

Standard `subscribe` streams can opt into the native Rust client's reconnect, backfill, and dedup:

```typescript
const client = new Client(endpoint, xToken, channelOptions, {
  backoff: {
    initialIntervalMs: 100,
    multiplier: 2,
    maxRetries: 10,
  },
  slotRetention: 250,  // re-send events from last 250 slots on reconnect
});
```

The dedup is done by (slot, signature) tuple. On reconnect, you may get the same event twice from a higher slot — always have idempotent upserts in your DB (`ON CONFLICT DO NOTHING`).

## Large account sets: compressed filters

For 10K+ accounts, sending the full list every time is expensive. Use `CompressedAccountFilterSet` (a cuckoo filter sent to the server, exact membership checked locally):

```typescript
import Client, { CompressedAccountFilterSet } from "@triton-one/yellowstone-grpc";

const accounts = new CompressedAccountFilterSet(2_000_000);
for (const pk of trackedPubkeys) accounts.insert(pk);

const req: SubscribeRequest = {
  accounts: {},
  // ... other fields
};

accounts.insertIntoSubscribeRequest(req, "tracked");
const stream = await client.subscribe();

stream.on("data", (u) => {
  const pk = u.account?.account?.pubkey;
  if (pk && accounts.contains(pk)) { /* exact local match */ }
});

// Add/remove accounts dynamically
accounts.insert(newPk);
accounts.remove(oldPk);
accounts.insertIntoSubscribeRequest(req, "tracked");
stream.write(req);
```

## Filters reference

### Account filter

```typescript
accounts: {
  client: {
    account: ["<pubkey>", "<pubkey>"],          // OR within array
    owner: ["<program-id>"],                     // OR within array
    filters: [                                   // AND across filters
      { dataSize: 165 },                         // exact account size (SPL token)
      { memcmp: { offset: 0, bytes: "<base58>" } }, // memcmp at offset
    ],
  },
},
```

If `account`, `owner`, AND `filters` are all empty, **all accounts** are broadcast — usually a mistake.

### Transaction filter

```typescript
transactions: {
  client: {
    vote: false,                                // skip vote txs
    failed: false,                              // skip failed txs
    signature: "<sig>",                         // specific tx (rare)
    accountInclude: ["<program-id>"],            // tx touches any of these
    accountExclude: ["<noise-program>"],         // tx does NOT touch any
    accountRequired: ["<must-touch>"],           // tx MUST touch ALL of these
  },
},
```

`accountInclude` is what you usually want. `accountRequired` is useful for swaps (must touch both mints + a DEX program).

### Block filter

```typescript
blocks: {
  client: {
    accountInclude: ["<program-id>"],
    includeTransactions: true,                  // include full tx bodies
    includeAccounts: false,                     // skip account updates (saves bandwidth)
    includeEntries: false,                      // skip entry data
  },
},
blocksMeta: { client: {} },                     // block metadata only (cheap)
entry: { client: {} },                          // raw entries
```

### Slots

```typescript
slots: {
  client: {
    filterByCommitment: true,                   // only one commitment level
  },
},
```

## Deshred transactions (Triton only)

A separate bi-directional stream for **pre-execution** transactions — reconstructed from incoming shreds, available before the transaction executes.

```typescript
const stream = await client.subscribeDeshred();
stream.write({
  deshred: {
    filter: {
      vote: false,
      accountInclude: ["<program-id>"],
      accountExclude: [],
      accountRequired: [],
    },
  },
});
```

Available fields: `slot`, `signature`, `is_vote`, raw `transaction`, `loaded_writable_addresses`, `loaded_readonly_addresses`.

Unavailable: execution status, error details, logs, inner instructions, balances, compute usage.

Useful for MEV search (see tx before it lands). Only on Triton extension servers — open-source `yellowstone-grpc-geyser` returns `UNIMPLEMENTED`.

## Unary RPCs (also on the same connection)

```typescript
// Get latest blockhash
const bh = await client.getLatestBlockhash({ commitment: CommitmentLevel.Confirmed });

// Get current slot
const { slot } = await client.getSlot({ commitment: CommitmentLevel.Confirmed });

// Get block height
const { blockHeight } = await client.getBlockHeight({ commitment: CommitmentLevel.Confirmed });

// Is this blockhash still valid?
const { valid } = await client.isBlockhashValid({ blockhash, commitment: CommitmentLevel.Confirmed });

// Version
const version = await client.getVersion();
```

These are useful for sanity checks, dedup, and slot tracking. Don't use them as a substitute for regular RPC — they only see what the plugin is processing.

## Common patterns

### 1. Slot-tracked DB writes

Tag every row with the slot it was confirmed at. Lets you detect gaps and rollback if needed.

```typescript
stream.on("data", (u) => {
  if (u.account) {
    const slot = u.account.account.slot;
    db.query(
      `INSERT INTO accounts (pubkey, data, slot) VALUES ($1, $2, $3)
       ON CONFLICT (pubkey) DO UPDATE SET data = $2, slot = $3
       WHERE accounts.slot < $3`,  // only overwrite if newer slot
      [bs58.encode(u.account.account.pubkey), u.account.account.data, slot]
    );
  }
});
```

### 2. Block-based batching

Don't write per-transaction. Buffer and write per-block for 10-100x throughput.

```typescript
const blockBuffer: TxEvent[] = [];
let lastBlock = 0;

stream.on("data", (u) => {
  if (u.transaction) blockBuffer.push(toEvent(u.transaction));
  if (u.blockMeta && u.blockMeta.blockHeight > lastBlock) {
    flushBlock(blockBuffer);  // bulk insert
    blockBuffer.length = 0;
    lastBlock = u.blockMeta.blockHeight;
  }
});
```

### 3. Lag detection

Track current slot vs your DB's max slot. Alert if it grows.

```typescript
let lastDbSlot = 0;
let lastStreamSlot = 0;

setInterval(() => {
  const lag = lastStreamSlot - lastDbSlot;
  if (lag > 10) console.warn(`DB lagging ${lag} slots behind stream`);
}, 5000);
```

## Troubleshooting

- **"rpc error: code = Unimplemented desc = unknown service SubscribeDeshred"** — server doesn't support deshred. Only Triton ext servers do.
- **"Connection lost after 5 minutes"** — load balancer is closing idle connections. Send a `ping` periodically (the SDK does this if `ping: true` in SubscribeRequest).
- **Memory grows unbounded** — your filter is too broad. Add `accountInclude` and `dataSize` filters.
- **CPU 100% on validator** — your deserialization is too heavy. Move it to a separate consumer process; the plugin should only forward bytes.
- **Different events from the same slot** — slot ordering isn't guaranteed across event types. Use `blockHeight` or `slot + signature` for dedup.

## Related references

- [indexer-architecture.md](indexer-architecture.md) — when to use Geyser vs alternatives
- [real-time-streaming.md](real-time-streaming.md) — WebSocket alternatives and patterns
- [production-ops.md](production-ops.md) — running a Geyser-based indexer in production
- [resources.md](resources.md) — official docs, links
