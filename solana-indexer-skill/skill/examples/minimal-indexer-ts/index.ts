import 'dotenv/config';
import express, { Request, Response } from 'express';
import { Pool } from 'pg';
import { createHelius } from 'helius-sdk';
import bs58 from 'bs58';
import pino from 'pino';

const log = pino({ transport: { target: 'pino-pretty', options: { colorize: true } } });

// ─── config ───────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT || '3000', 10);
const HELIUS_API_KEY = process.env.HELIUS_API_KEY!;
const DATABASE_URL = process.env.DATABASE_URL!;
const PROGRAM_ID = process.env.PROGRAM_ID || 'CAMMCzo5YL8w4VFF8KVHrK22GgU4tBh1WaxgLsD1YwbF'; // Raydium CLMM
const WEBHOOK_URL = process.env.WEBHOOK_URL!;  // public URL where this server is reachable

// ─── helius client ────────────────────────────────────────────────────
const helius = createHelius({ apiKey: HELIUS_API_KEY });

// ─── db ────────────────────────────────────────────────────────────────
const db = new Pool({ connectionString: DATABASE_URL, max: 10 });

await db.query(`
  CREATE TABLE IF NOT EXISTS swaps (
    signature    BYTEA PRIMARY KEY,
    slot         BIGINT NOT NULL,
    block_time   BIGINT NOT NULL,
    program_id   BYTEA NOT NULL,
    pool         BYTEA NOT NULL,
    user_wallet BYTEA NOT NULL,
    input_mint   BYTEA NOT NULL,
    input_amount NUMERIC(20, 0) NOT NULL,
    output_mint  BYTEA NOT NULL,
    output_amount NUMERIC(20, 0) NOT NULL,
    fee_lamports NUMERIC(20, 0) NOT NULL DEFAULT 0,
    raw          JSONB NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_swaps_pool_time ON swaps (pool, block_time DESC);
  CREATE INDEX IF NOT EXISTS idx_swaps_user_time ON swaps (user_wallet, block_time DESC);
`);

// ─── helius webhook setup ─────────────────────────────────────────────
async function setupWebhook() {
  const all = await helius.webhooks.getAll();
  const matching = all.find(
    (w: any) => w.webhookURL === WEBHOOK_URL && w.accountAddresses?.includes(PROGRAM_ID)
  );
  if (matching) {
    log.info({ id: matching.webhookID }, 'webhook already exists');
    return matching.webhookID!;
  }
  const wh = await helius.webhooks.create({
    webhookURL: WEBHOOK_URL,
    transactionTypes: ['SWAP'],
    accountAddresses: [PROGRAM_ID],
    webhookType: 'enhanced',
  } as any);
  log.info({ id: wh.webhookID }, 'webhook created');
  return wh.webhookID!;
}

// ─── parser ───────────────────────────────────────────────────────────
// Raydium CLMM SwapEvent shape:
//   pool_state, sender, token_account_0/1, amount_0/1, transfer_fee_0/1,
//   zero_for_one, sqrt_price_x64, liquidity, tick, trade_fee_0/1
// Inner instructions: 3 transfers (input, output, fee) + 1 swap
type HeliusEnhancedTx = any;  // helius-sdk type is verbose; using any for readability

function parseSwap(tx: HeliusEnhancedTx, programId: string) {
  if (tx.type !== 'SWAP') return null;
  if (tx.source !== 'RAYDIUM_CLMM') return null;

  const swapEvent = tx.events?.swap;
  if (!swapEvent) return null;

  // Inner instructions: token transfers show the actual mints + amounts
  const transfers = tx.tokenTransfers ?? [];
  if (transfers.length < 2) return null;

  // First transfer = input (user → pool), second = output (pool → user)
  const [input, output] = transfers;

  return {
    signature: bs58.decode(tx.signature),
    slot: tx.slot,
    block_time: Math.floor(new Date(tx.timestamp).getTime() / 1000),
    program_id: bs58.decode(programId),
    pool: bs58.decode(swapEvent.pool || tx.accountData?.[0]?.account || ''),
    user_wallet: bs58.decode(tx.feePayer),
    input_mint: bs58.decode(input.mint),
    input_amount: BigInt(input.tokenAmount?.amount || '0'),
    output_mint: bs58.decode(output.mint),
    output_amount: BigInt(output.tokenAmount?.amount || '0'),
    fee_lamports: BigInt(tx.fee || 0),
    raw: tx,
  };
}

// ─── writer (batched) ──────────────────────────────────────────────────
const BATCH_SIZE = 100;
const FLUSH_MS = 500;
let buffer: any[] = [];

async function flush() {
  if (buffer.length === 0) return;
  const batch = buffer;
  buffer = [];
  // Use unnest for batch insert
  const placeholders = batch
    .map(
      (_, i) =>
        `($${i * 12 + 1}, $${i * 12 + 2}, $${i * 12 + 3}, $${i * 12 + 4}, ` +
        `$${i * 12 + 5}, $${i * 12 + 6}, $${i * 12 + 7}, $${i * 12 + 8}, ` +
        `$${i * 12 + 9}, $${i * 12 + 10}, $${i * 12 + 11}, $${i * 12 + 12})`
    )
    .join(',');
  const params = batch.flatMap((r) => [
    r.signature,
    r.slot,
    r.block_time,
    r.program_id,
    r.pool,
    r.user_wallet,
    r.input_mint,
    r.input_amount,
    r.output_mint,
    r.output_amount,
    r.fee_lamports,
    r.raw,
  ]);
  try {
    await db.query(
      `INSERT INTO swaps (signature, slot, block_time, program_id, pool, user_wallet, input_mint, input_amount, output_mint, output_amount, fee_lamports, raw)
       VALUES ${placeholders}
       ON CONFLICT (signature) DO NOTHING`,
      params
    );
    log.info({ count: batch.length }, 'flushed batch');
  } catch (err) {
    log.error({ err, count: batch.length }, 'flush failed');
    // Re-buffer for retry
    buffer.unshift(...batch);
  }
}

setInterval(flush, FLUSH_MS);

// ─── http server ──────────────────────────────────────────────────────
const app = express();
app.use(express.json({ limit: '10mb' }));

app.get('/health', async (_req: Request, res: Response) => {
  try {
    await db.query('SELECT 1');
    res.json({ status: 'ok', queued: buffer.length });
  } catch (e) {
    res.status(503).json({ status: 'down', error: (e as Error).message });
  }
});

app.post('/webhook', async (req: Request, res: Response) => {
  const txs: HeliusEnhancedTx[] = Array.isArray(req.body) ? req.body : [req.body];
  let parsed = 0;
  for (const tx of txs) {
    const swap = parseSwap(tx, PROGRAM_ID);
    if (swap) {
      buffer.push(swap);
      parsed++;
    }
  }
  if (buffer.length >= BATCH_SIZE) await flush();
  res.status(200).send({ received: txs.length, parsed });
});

// ─── main ─────────────────────────────────────────────────────────────
async function main() {
  await setupWebhook();
  app.listen(PORT, () => log.info({ port: PORT }, 'minimal-indexer listening'));

  // Graceful shutdown
  const shutdown = async (sig: string) => {
    log.info({ sig }, 'shutting down');
    await flush();
    await db.end();
    process.exit(0);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((err) => {
  log.fatal({ err }, 'fatal');
  process.exit(1);
});
