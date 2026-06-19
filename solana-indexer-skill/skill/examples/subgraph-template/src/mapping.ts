// Mapping for Raydium CLMM subgraph
// Run with: graph codegen && graph build

import { Pool, Swap, BlockMeta } from "../generated/schema";
import { RaydiumClmm } from "../generated/RaydiumClmm/RaydiumClmm";
import { BigInt, Bytes, store } from "@graphprotocol/graph-ts";

const ZERO_BI = BigInt.fromI32(0);
const ONE_BI = BigInt.fromI32(1);

export function handleSwap(event: RaydiumClmm.swap): void {
  // Load pool (lazy)
  let pool = Pool.load(event.pool.toBase58());
  if (!pool) {
    pool = new Pool(event.pool.toBase58());
    pool.createdAt = event.block.timestamp;
    pool.createdTx = event.transaction.hash;
  }

  // Update pool state
  pool.liquidity = event.liquidity;
  pool.sqrtPriceX64 = event.sqrtPriceX64;
  pool.tickCurrent = event.tick;
  pool.slot = BigInt.fromUnsignedBytes(event.slot);
  pool.totalSwapCount = pool.totalSwapCount + 1;

  // Update volume
  if (event.zeroForOne) {
    pool.totalVolumeToken0 = pool.totalVolumeToken0 + event.amount0;
    pool.totalVolumeToken1 = pool.totalVolumeToken1 + event.amount1;
    pool.totalFeesToken1 = pool.totalFeesToken1 + event.tradeFee1;
  } else {
    pool.totalVolumeToken0 = pool.totalVolumeToken0 + event.amount0;
    pool.totalVolumeToken1 = pool.totalVolumeToken1 + event.amount1;
    pool.totalFeesToken0 = pool.totalFeesToken0 + event.tradeFee0;
  }
  pool.save();

  // Create swap entity
  const swap = new Swap(event.transaction.hash.toHex());
  swap.pool = pool.id;
  swap.user = event.sender;
  swap.inputMint = event.zeroForOne ? event.pool.tokenMint0 : event.pool.tokenMint1;
  swap.outputMint = event.zeroForOne ? event.pool.tokenMint1 : event.pool.tokenMint0;
  swap.inputAmount = event.zeroForOne ? event.amount0.abs() : event.amount1.abs();
  swap.outputAmount = event.zeroForOne ? event.amount1.abs() : event.amount0.abs();
  swap.feeAmount = event.zeroForOne ? event.tradeFee0 : event.tradeFee1;
  swap.sqrtPriceX64 = event.sqrtPriceX64;
  swap.liquidity = event.liquidity;
  swap.tick = event.tick;
  swap.zeroForOne = event.zeroForOne;
  swap.slot = BigInt.fromUnsignedBytes(event.slot);
  swap.blockTime = event.block.timestamp;
  swap.save();
}

export function handleLiquidityChange(event: RaydiumClmm.liquidityChange): void {
  // Update pool in-range liquidity
  const pool = Pool.load(event.pool.toBase58());
  if (!pool) return;
  pool.liquidity = event.liquidityAfter;
  pool.slot = BigInt.fromUnsignedBytes(event.slot);
  pool.save();
}

export function handlePoolCreated(event: RaydiumClmm.poolCreated): void {
  const pool = new Pool(event.poolState.toBase58());
  pool.ammConfig = event.ammConfig;
  pool.owner = event.poolCreator;
  pool.tokenMint0 = event.tokenMint0;
  pool.tokenMint1 = event.tokenMint1;
  pool.tokenVault0 = event.tokenVault0;
  pool.tokenVault1 = event.tokenVault1;
  pool.mintDecimals0 = 0;  // fetch separately if needed
  pool.mintDecimals1 = 0;
  pool.tickSpacing = event.tickSpacing;
  pool.liquidity = ZERO_BI;
  pool.sqrtPriceX64 = event.sqrtPriceX64;
  pool.tickCurrent = event.tick;
  pool.feeGrowthGlobal0X64 = ZERO_BI;
  pool.feeGrowthGlobal1X64 = ZERO_BI;
  pool.protocolFeesToken0 = ZERO_BI;
  pool.protocolFeesToken1 = ZERO_BI;
  pool.fundFeesToken0 = ZERO_BI;
  pool.fundFeesToken1 = ZERO_BI;
  pool.status = 0;
  pool.openTime = event.openTime;
  pool.recentEpoch = ZERO_BI;
  pool.slot = BigInt.fromUnsignedBytes(event.slot);
  pool.createdAt = event.block.timestamp;
  pool.createdTx = event.transaction.hash;
  pool.totalSwapCount = 0;
  pool.totalVolumeToken0 = ZERO_BI;
  pool.totalVolumeToken1 = ZERO_BI;
  pool.totalFeesToken0 = ZERO_BI;
  pool.totalFeesToken1 = ZERO_BI;
  pool.save();
}

export function handleBlock(block: RaydiumClmm.block): void {
  const meta = new BlockMeta(block.slot.toString());
  meta.blockhash = block.blockhash;
  meta.blockTime = block.block.timestamp;
  meta.parentSlot = block.parentSlot;
  meta.swapCount = 0;
  meta.save();
}
