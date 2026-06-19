# Geyser Plugin Skeleton

A minimal Rust Geyser plugin that forwards account updates and transactions to Postgres. The starting point for building a custom plugin (e.g., for Solana program IDs that need custom filtering or deserialization).

## What this does

- Runs **inside the Solana validator** process
- Receives `update_account`, `update_transaction`, `update_block_metadata` callbacks
- Forwards events to a background Tokio task
- Batches and writes to Postgres using `INSERT ... ON CONFLICT DO UPDATE WHERE existing.slot < new.slot`
- Skips startup snapshot replay (don't flood DB with snapshot data)

## Prerequisites

- Rust 1.80+
- Solana validator (you'll need a custom validator build to load this)
- Postgres 14+

## Build

```bash
cargo build --release
# Output: target/release/libmy_geyser_indexer.so
```

## Configure the validator

Edit your validator startup config:

```json
{
  "libpath": "/path/to/target/release/libmy_geyser_indexer.so",
  "name": "my-geyser-indexer",
  "config_file": "/path/to/config.json"
}
```

The `config_file` (separate from the validator config) contains plugin-specific options. For this skeleton, the only config is the database URL (read from `DATABASE_URL` env var).

## Run the validator

```bash
DATABASE_URL=postgres://user:pass@host:5432/geyser \
  solana-validator \
    --geyser-plugin-config /path/to/config.json \
    ...
```

## Schema

The plugin auto-creates the schema on first startup:

```sql
CREATE TABLE accounts (
  pubkey BYTEA PRIMARY KEY,
  owner BYTEA NOT NULL,
  lamports BIGINT NOT NULL,
  slot BIGINT NOT NULL,
  data BYTEA,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE transactions (
  signature BYTEA PRIMARY KEY,
  slot BIGINT NOT NULL,
  success BOOLEAN NOT NULL,
  fee BIGINT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## What to customize

This is a skeleton — it forwards every account and transaction. In production:

1. **Add filters**: skip non-program accounts, filter by owner program
2. **Add deserialization**: parse the `data` field into typed fields
3. **Add batching by slot**: flush per-block for predictable lag
4. **Add metrics**: Prometheus counters for events in/out, errors
5. **Add deadletter queue**: if a row fails to insert, write to S3 for replay

## When to use this

Use a custom Geyser plugin (instead of Yellowstone gRPC) when:
- You process >100M events/day (per-event cost matters)
- You need <50ms latency (in-process beats network)
- You need custom deserialization in the validator (avoid 2x parsing)
- You can run a validator (or partner with one that does)

For everything else, use the Yellowstone gRPC client (`@triton-one/yellowstone-grpc` or Rust client). See [`../../../references/geyser-plugins.md`](../../../references/geyser-plugins.md).

## Pitfalls

- **Don't include startup snapshot replay** (`is_startup: true`). It floods the DB. This skeleton handles it.
- **Don't use sync I/O in the plugin callbacks.** Use a channel + background task. This skeleton uses `mpsc::unbounded_channel` + `tokio::spawn`.
- **Don't crash the validator.** A panic in `update_account` will crash the validator. Wrap risky code in `catch_unwind` or handle errors gracefully.
- **Don't store raw bytes larger than necessary.** Most programs have padding. Truncate to the known account size.

## Related

- Parent skill: [`solana-indexer-skill`](../../../SKILL.md)
- Geyser plugin docs: [`../../../references/geyser-plugins.md`](../../../references/geyser-plugins.md)
- Indexer architecture: [`../../../references/indexer-architecture.md`](../../../references/indexer-architecture.md)
- Solana Geyser plugin interface: https://github.com/solana-labs/solana/blob/master/geyser-plugin-interface
- Yellowstone gRPC (alternative to custom plugin): https://github.com/rpcpool/yellowstone-grpc
