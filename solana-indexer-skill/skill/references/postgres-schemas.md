---
name: postgres-schemas
description: Canonical Postgres schemas for common Solana indexing use cases — Raydium CLMM pools, AMM swaps, Orca positions, NFT marketplaces, vaults, and token accounts. Includes account layout references, DDL, indexes, and partition strategies.
---

# Postgres Schemas for Solana Indexers

The schema is the spine of your indexer. Get it right and queries stay fast for years. Get it wrong and you're rewriting in 6 months.

This reference covers the **most-indexed** Solana program data with verified account layouts, ready-to-use DDL, and the indexes you'll actually need.

## Design principles

1. **Store the raw bytes** alongside the parsed data. Anchor IDL versions change, parsers break, but the bytes are the truth.
2. **Tag every row with `slot` and `updated_at`**. Lets you detect gaps, replay, and audit history.
3. **Use `numeric(78, 0)` for u128/i128/u256/u512** fields. Postgres `bigint` is signed 64-bit and overflows. Solana uses these for liquidity, sqrt_price, fees.
4. **Slot-conditional upserts**: `WHERE existing.slot < new.slot`. Prevents out-of-order replays from corrupting state.
5. **Use `bytea` for account data**, not `jsonb`. The deserialized form changes; the bytes don't.
6. **Index on `(pubkey, slot DESC)`** for "latest state" queries. Index on `(slot)` for "history at slot X" queries.
7. **For time-series data (OHLCV, TVL)**, use TimescaleDB hypertables. Don't store millions of rows in a flat table.

## Extensions to install

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- for bytea hashing
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- for range queries on time + slot
-- Optional but recommended:
CREATE EXTENSION IF NOT EXISTS timescaledb;  -- for time-series
```

## Canonical schema 1: Token account (SPL Token + Token-2022)

SPL Token account layout: 165 bytes (Token-2022 may be larger if it has extensions).

```
+--------+--------+--------+--------+--------+
| 0      | 32     | 32     | 8      | 8      |  -- mint, owner, amount, delegate?
+--------+--------+--------+--------+--------+
| 4      | 4      | 1      | 1      | 1      |  -- state, is_native, decimals, close_authority?
+--------+--------+--------+--------+--------+
```

DDL:

```sql
CREATE TABLE token_accounts (
  pubkey        BYTEA PRIMARY KEY,            -- 32 bytes
  mint          BYTEA NOT NULL,
  owner         BYTEA NOT NULL,
  amount        NUMERIC(20, 0) NOT NULL,      -- u64
  delegate      BYTEA,                         -- nullable
  delegated_amount NUMERIC(20, 0) NOT NULL DEFAULT 0,
  state         SMALLINT NOT NULL,            -- 0=Uninitialized, 1=Initialized, 2=Frozen
  is_native     NUMERIC(20, 0),               -- wrapped SOL amount
  close_authority BYTEA,
  slot          BIGINT NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw           BYTEA NOT NULL                -- full 165+ bytes
);

CREATE INDEX idx_token_accounts_owner   ON token_accounts (owner);
CREATE INDEX idx_token_accounts_mint    ON token_accounts (mint);
CREATE INDEX idx_token_accounts_slot    ON token_accounts (slot DESC);
```

## Canonical schema 2: Mint (SPL + Token-2022)

```sql
CREATE TABLE mints (
  pubkey              BYTEA PRIMARY KEY,
  supply              NUMERIC(20, 0) NOT NULL,
  decimals            SMALLINT NOT NULL,
  mint_authority      BYTEA,                  -- COption<Pubkey>
  freeze_authority    BYTEA,                  -- COption<Pubkey>
  is_initialized      BOOLEAN NOT NULL,
  -- Token-2022 extensions
  extensions          JSONB NOT NULL DEFAULT '[]'::jsonb,  -- array of extension types
  slot                BIGINT NOT NULL,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw                 BYTEA NOT NULL
);
```

## Canonical schema 3: AMM swap (Jupiter / Raydium AMM v4 / Orca)

A "swap" is a parser-level event, not an on-chain account. Store it as an event row.

```sql
CREATE TABLE swaps (
  id                BIGSERIAL,
  signature         BYTEA NOT NULL,
  slot              BIGINT NOT NULL,
  block_time        BIGINT NOT NULL,         -- unix timestamp
  program_id        BYTEA NOT NULL,         -- which DEX
  pool_address      BYTEA NOT NULL,
  user              BYTEA NOT NULL,         -- signer
  input_mint        BYTEA NOT NULL,
  input_amount      NUMERIC(20, 0) NOT NULL,
  output_mint       BYTEA NOT NULL,
  output_amount     NUMERIC(20, 0) NOT NULL,
  fee_amount        NUMERIC(20, 0) NOT NULL DEFAULT 0,
  fee_mint          BYTEA,
  -- Optional: pool state snapshot at swap time
  pool_sqrt_price   NUMERIC(40, 0),         -- Q64.64 = 128 bits
  pool_liquidity    NUMERIC(40, 0),         -- u128
  raw_events        JSONB NOT NULL,         -- full inner ixs + logs
  PRIMARY KEY (signature)
);

-- Time-series query: "all SOL/USDC swaps in last 1h, grouped by minute"
CREATE INDEX idx_swaps_pool_time     ON swaps (pool_address, block_time DESC);
CREATE INDEX idx_swaps_user_time     ON swaps (user, block_time DESC);
CREATE INDEX idx_swaps_input_mint    ON swaps (input_mint, block_time DESC);
CREATE INDEX idx_swaps_output_mint   ON swaps (output_mint, block_time DESC);

-- If you use TimescaleDB:
-- SELECT create_hypertable('swaps', 'block_time', chunk_time_interval => INTERVAL '1 day');
-- CREATE INDEX idx_swaps_pool_time ON swaps (pool_address, block_time DESC);
```

## Canonical schema 4: Raydium CLMM pool state

Verified from [raydium-clmm/programs/amm/src/states/pool.rs](https://github.com/raydium-io/raydium-clmm/blob/master/programs/amm/src/states/pool.rs):

```rust
pub struct PoolState {
    pub bump: [u8; 1],
    pub amm_config: Pubkey,        // config this pool belongs to
    pub owner: Pubkey,             // pool creator
    pub token_mint_0: Pubkey,      // token_0 < token_1 by address
    pub token_mint_1: Pubkey,
    pub token_vault_0: Pubkey,
    pub token_vault_1: Pubkey,
    pub observation_key: Pubkey,
    pub mint_decimals_0: u8,
    pub mint_decimals_1: u8,
    pub tick_spacing: u16,
    pub liquidity: u128,           // in-range liquidity
    pub sqrt_price_x64: u128,      // Q64.64 price
    pub tick_current: i32,
    pub fee_growth_global_0_x64: u128,
    pub fee_growth_global_1_x64: u128,
    pub protocol_fees_token_0: u64,
    pub protocol_fees_token_1: u64,
    pub status: u8,                // bitfield
    pub fee_on: u8,
    pub reward_infos: [RewardInfo; 3],
    pub tick_array_bitmap: [u64; 16],
    pub fund_fees_token_0: u64,
    pub fund_fees_token_1: u64,
    pub open_time: u64,
    pub recent_epoch: u64,
    pub dynamic_fee_info: DynamicFeeInfo,  // 80 bytes
}
```

DDL (numeric precision sized for safety):

```sql
CREATE TABLE raydium_clmm_pools (
  pubkey                BYTEA PRIMARY KEY,
  amm_config            BYTEA NOT NULL,
  owner                 BYTEA NOT NULL,
  token_mint_0          BYTEA NOT NULL,
  token_mint_1          BYTEA NOT NULL,
  token_vault_0         BYTEA NOT NULL,
  token_vault_1         BYTEA NOT NULL,
  observation_key       BYTEA NOT NULL,
  mint_decimals_0       SMALLINT NOT NULL,
  mint_decimals_1       SMALLINT NOT NULL,
  tick_spacing          SMALLINT NOT NULL,
  liquidity             NUMERIC(40, 0) NOT NULL,         -- u128
  sqrt_price_x64        NUMERIC(40, 0) NOT NULL,         -- Q64.64
  tick_current          INTEGER NOT NULL,
  fee_growth_global_0   NUMERIC(40, 0) NOT NULL,
  fee_growth_global_1   NUMERIC(40, 0) NOT NULL,
  protocol_fees_token_0 NUMERIC(20, 0) NOT NULL,
  protocol_fees_token_1 NUMERIC(20, 0) NOT NULL,
  fund_fees_token_0     NUMERIC(20, 0) NOT NULL,
  fund_fees_token_1     NUMERIC(20, 0) NOT NULL,
  status                SMALLINT NOT NULL,
  fee_on                SMALLINT NOT NULL,
  -- 3 reward infos (serialized as JSONB for flexibility)
  reward_infos          JSONB NOT NULL,
  tick_array_bitmap     JSONB NOT NULL,
  open_time             BIGINT NOT NULL,
  recent_epoch          BIGINT NOT NULL,
  slot                  BIGINT NOT NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw                   BYTEA NOT NULL                  -- full account data
);

CREATE INDEX idx_clmm_token_pair ON raydium_clmm_pools (token_mint_0, token_mint_1);
CREATE INDEX idx_clmm_amm_config ON raydium_clmm_pools (amm_config);
CREATE INDEX idx_clmm_slot       ON raydium_clmm_pools (slot DESC);
```

For positions (NFTs that represent LP shares):

```sql
CREATE TABLE raydium_clmm_positions (
  pubkey        BYTEA PRIMARY KEY,
  pool          BYTEA NOT NULL REFERENCES raydium_clmm_pools(pubkey),
  owner         BYTEA NOT NULL,
  tick_lower    INTEGER NOT NULL,
  tick_upper    INTEGER NOT NULL,
  liquidity     NUMERIC(40, 0) NOT NULL,
  fee_growth_inside_0_last NUMERIC(40, 0) NOT NULL,
  fee_growth_inside_1_last NUMERIC(40, 0) NOT NULL,
  token_fees_owed_0 NUMERIC(20, 0) NOT NULL,
  token_fees_owed_1 NUMERIC(20, 0) NOT NULL,
  reward_infos  JSONB NOT NULL,
  slot          BIGINT NOT NULL,
  raw           BYTEA NOT NULL
);

CREATE INDEX idx_clmm_pos_owner ON raydium_clmm_positions (owner);
CREATE INDEX idx_clmm_pos_pool  ON raydium_clmm_positions (pool);
```

## Canonical schema 5: Orca Whirlpool (similar to Raydium CLMM)

Orca Whirlpool is the original CLMM implementation. Layout is similar but with different field names. See the [Orca Whirlpool reference](https://github.com/orca-so/whirlpools) and `sendai/skills/orca` for the full struct.

```sql
CREATE TABLE orca_whirlpools (
  pubkey            BYTEA PRIMARY KEY,
  token_mint_a      BYTEA NOT NULL,
  token_mint_b      BYTEA NOT NULL,
  token_vault_a     BYTEA NOT NULL,
  token_vault_b     BYTEA NOT NULL,
  tick_spacing      SMALLINT NOT NULL,
  sqrt_price_x64    NUMERIC(40, 0) NOT NULL,
  tick_current_index INTEGER NOT NULL,
  liquidity         NUMERIC(40, 0) NOT NULL,
  fee_rate          INTEGER NOT NULL,
  fee_growth_global_a NUMERIC(40, 0) NOT NULL,
  fee_growth_global_b NUMERIC(40, 0) NOT NULL,
  protocol_fee_owed_a NUMERIC(20, 0) NOT NULL,
  protocol_fee_owed_b NUMERIC(20, 0) NOT NULL,
  slot              BIGINT NOT NULL,
  raw               BYTEA NOT NULL
);
```

## Canonical schema 6: NFT marketplace listing (Magic Eden, Tensor)

```sql
CREATE TABLE nft_listings (
  pubkey            BYTEA PRIMARY KEY,
  marketplace       BYTEA NOT NULL,            -- program ID
  seller            BYTEA NOT NULL,
  nft_mint          BYTEA NOT NULL,
  nft_token_account BYTEA NOT NULL,
  price_lamports    NUMERIC(20, 0) NOT NULL,
  expiry            BIGINT,                    -- unix seconds, nullable
  status            SMALLINT NOT NULL,          -- 0=active, 1=filled, 2=cancelled
  slot              BIGINT NOT NULL,
  tx_signature      BYTEA NOT NULL,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_nft_list_mint   ON nft_listings (nft_mint, status);
CREATE INDEX idx_nft_list_seller ON nft_listings (seller);
CREATE INDEX idx_nft_list_status ON nft_listings (status, slot DESC);
```

For trades (the fill event):

```sql
CREATE TABLE nft_sales (
  id              BIGSERIAL,
  signature       BYTEA NOT NULL,
  slot            BIGINT NOT NULL,
  block_time      BIGINT NOT NULL,
  buyer           BYTEA NOT NULL,
  seller          BYTEA NOT NULL,
  nft_mint        BYTEA NOT NULL,
  price_lamports  NUMERIC(20, 0) NOT NULL,
  marketplace     BYTEA NOT NULL,
  fee_lamports    NUMERIC(20, 0) NOT NULL,
  raw             JSONB NOT NULL,
  PRIMARY KEY (signature)
);

CREATE INDEX idx_nft_sales_buyer  ON nft_sales (buyer, block_time DESC);
CREATE INDEX idx_nft_sales_seller ON nft_sales (seller, block_time DESC);
CREATE INDEX idx_nft_sales_mint   ON nft_sales (nft_mint, block_time DESC);
```

## Canonical schema 7: Vault / Stake account (Marinade, Lido, etc.)

```sql
CREATE TABLE vaults (
  pubkey              BYTEA PRIMARY KEY,
  program             BYTEA NOT NULL,            -- Marinade, Lido, etc.
  vault_authority     BYTEA,
  total_assets        NUMERIC(30, 0) NOT NULL,
  total_shares        NUMERIC(30, 0) NOT NULL,
  exchange_rate       NUMERIC(30, 18) NOT NULL,  -- assets per share, scaled
  last_update_slot    BIGINT NOT NULL,
  last_update_time    BIGINT NOT NULL,
  rewards             JSONB NOT NULL DEFAULT '[]'::jsonb,
  raw                 BYTEA NOT NULL
);

-- Share price over time
CREATE TABLE vault_snapshots (
  vault              BYTEA NOT NULL,
  slot               BIGINT NOT NULL,
  block_time         BIGINT NOT NULL,
  total_assets       NUMERIC(30, 0) NOT NULL,
  total_shares       NUMERIC(30, 0) NOT NULL,
  exchange_rate      NUMERIC(30, 18) NOT NULL,
  PRIMARY KEY (vault, slot)
);
```

## Indexing patterns for `getProgramAccounts`-style queries

When you need to filter by `data` contents (not just by `pubkey`):

```sql
-- For pools with a specific tick_spacing
CREATE INDEX idx_clmm_tick_spacing ON raydium_clmm_pools (tick_spacing)
  WHERE tick_spacing = 64;  -- partial index, very efficient

-- For active pools (status bitmask)
CREATE INDEX idx_clmm_active ON raydium_clmm_pools (pubkey)
  WHERE (status & 16) = 0;  -- bit 4 = swap disabled; we want swappable

-- For tokens by symbol (uses extensions JSONB)
CREATE INDEX idx_mints_symbol ON mints ((extensions->>'symbol'))
  WHERE extensions ? 'symbol';
```

## Partitioning for time-series

```sql
-- Partition swaps by month
CREATE TABLE swaps (...) PARTITION BY RANGE (slot);

CREATE TABLE swaps_2026_06 PARTITION OF swaps
  FOR VALUES FROM (350000000) TO (355000000);

-- Or use TimescaleDB (recommended for high-volume)
SELECT create_hypertable('swaps', 'block_time', chunk_time_interval => INTERVAL '7 days');
SELECT create_hypertable('nft_sales', 'block_time', chunk_time_interval => INTERVAL '30 days');
```

## Type mapping (Solana → Postgres)

| Solana type | Rust | Postgres | Notes |
|---|---|---|---|
| `Pubkey` (32 bytes) | `[u8; 32]` | `BYTEA` | Always 32 bytes |
| `bool` | `bool` | `BOOLEAN` | 1 byte |
| `u8` | `u8` | `SMALLINT` | 0-255 |
| `u16` | `u16` | `INTEGER` | 0-65535 |
| `u32` | `u32` | `BIGINT` | 0-2^32-1 |
| `u64` | `u64` | `NUMERIC(20, 0)` | unsigned, 0-2^64-1 |
| `u128` | `u128` | `NUMERIC(40, 0)` | Q64.64 prices, liquidity |
| `i32` | `i32` | `INTEGER` | ticks, current slot relative |
| `i64` | `i64` | `BIGINT` | timestamps, signed amounts |
| `i128` | `i128` | `NUMERIC(40, 0)` | signed amounts |
| `u256`, `u512` | custom | `BYTEA` (32/64 bytes) | Solvency, math lib |
| `String` (max 32 chars) | `String` | `VARCHAR(32)` | |
| `[u8; N]` | `[u8; N]` | `BYTEA` | |
| `Pubkey::default()` | `[0u8; 32]` | `'\x'::bytea` | Treat as "uninitialized" |
| `Option<T>` | `Option<T>` | `T NULL` | |
| `COption<T>` | `COption<T>` | `T NULL` (with discriminator) | SPL Token COption |

## Deduplication

```sql
-- Slot-conditional upsert: don't overwrite newer state with older
INSERT INTO raydium_clmm_pools (pubkey, liquidity, sqrt_price_x64, slot, updated_at, raw)
VALUES ($1, $2, $3, $4, now(), $5)
ON CONFLICT (pubkey) DO UPDATE SET
  liquidity       = EXCLUDED.liquidity,
  sqrt_price_x64  = EXCLUDED.sqrt_price_x64,
  slot            = EXCLUDED.slot,
  updated_at      = EXCLUDED.updated_at,
  raw             = EXCLUDED.raw
WHERE raydium_clmm_pools.slot < EXCLUDED.slot;
```

## Schema migrations

Use `sqlx-cli` (Rust) or `node-pg-migrate` (TS) for versioned migrations. Each migration is `NNNN_name.sql` with both `up` and `down`.

```bash
# Create
sqlx migrate add add_clmm_positions
# Edit migrations/20260619000000_add_clmm_positions.sql
# Run
sqlx migrate run
```

Never edit a deployed migration. Always add a new one.

## What NOT to store in Postgres

- **Raw transaction bytes** → S3/GCS, store the URL in Postgres
- **Per-slot snapshots of every account** → only snapshot pools/positions you actually query
- **All inner instructions** → flatten what you need (swaps, transfers), discard the rest
- **Full transaction metadata** → store the signature + slot, re-fetch on demand from Helius DAS

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [geyser-plugins.md](geyser-plugins.md) — Geyser plugin code
- [backfill-strategies.md](backfill-strategies.md) — populating these tables
- [production-ops.md](production-ops.md) — keeping them fast in production
- [resources.md](resources.md) — official program repos for verification
