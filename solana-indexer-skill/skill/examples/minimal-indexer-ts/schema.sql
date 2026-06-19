-- Minimal indexer schema for Raydium CLMM swaps
-- Run with: psql $DATABASE_URL -f schema.sql

CREATE TABLE IF NOT EXISTS swaps (
  signature    BYTEA PRIMARY KEY,
  slot         BIGINT NOT NULL,
  block_time   BIGINT NOT NULL,
  program_id   BYTEA NOT NULL,
  pool         BYTEA NOT NULL,
  user_wallet  BYTEA NOT NULL,
  input_mint   BYTEA NOT NULL,
  input_amount NUMERIC(20, 0) NOT NULL,
  output_mint  BYTEA NOT NULL,
  output_amount NUMERIC(20, 0) NOT NULL,
  fee_lamports NUMERIC(20, 0) NOT NULL DEFAULT 0,
  raw          JSONB NOT NULL,
  inserted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_swaps_pool_time  ON swaps (pool, block_time DESC);
CREATE INDEX IF NOT EXISTS idx_swaps_user_time  ON swaps (user_wallet, block_time DESC);
CREATE INDEX IF NOT EXISTS idx_swaps_input_mint ON swaps (input_mint, block_time DESC);
CREATE INDEX IF NOT EXISTS idx_swaps_output_mint ON swaps (output_mint, block_time DESC);
CREATE INDEX IF NOT EXISTS idx_swaps_block_time ON swaps (block_time DESC);
