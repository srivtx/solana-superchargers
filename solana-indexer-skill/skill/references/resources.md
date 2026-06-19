---
name: resources
description: Official docs, repos, and tools for building Solana indexers. Verified links as of June 2026. Use this as a starting point, not the source of truth — Solana tooling moves fast.
---

# Resources

Verified links to the official docs, repos, and tools used by Solana indexers. Last verified June 2026.

## Geyser & Yellowstone gRPC

| Resource | Description | Link |
|---|---|---|
| Yellowstone gRPC (canonical) | Open-source Geyser gRPC plugin + client SDKs. 969 stars. AGPL-3.0. | https://github.com/rpcpool/yellowstone-grpc |
| Yellowstone gRPC docs (Triton) | Service docs, subscription filters, account/transaction/block details | https://docs.triton.one/rpc-pool/grpc-subscriptions |
| Yellowstone TypeScript client | `@triton-one/yellowstone-grpc` on npm. v5.0.0+ uses napi-rs. | https://www.npmjs.com/package/@triton-one/yellowstone-grpc |
| Yellowstone Rust client | Native Rust client with auto-reconnect, backfill, dedup | https://github.com/rpcpool/yellowstone-grpc/tree/master/yellowstone-grpc-client |
| Triton One | Hosted Yellowstone gRPC service (Dragon's Mouth) | https://triton.one |
| Yellowstone gRPC → Kafka | Forward gRPC stream to Kafka for downstream consumers | https://github.com/rpcpool/yellowstone-grpc-kafka |
| Deshred transactions | Triton-only feature for pre-execution tx data | https://docs.triton.one/rpc-pool/grpc-subscriptions#deshred-transactions |

## Solana Foundation & ecosystem

| Resource | Description | Link |
|---|---|---|
| Solana docs | Official Solana documentation | https://solana.com/docs |
| Solana Cookbook | Practical Solana recipes (RPC, transactions, accounts) | https://solanacookbook.com/ |
| Solana GitHub | Monorepo for the validator SDK | https://github.com/solana-labs/solana |
| Geyser plugin interface | Rust trait for writing custom Geyser plugins | https://github.com/solana-labs/solana/blob/master/geyser-plugin-interface |
| Anchor framework | Most popular Solana program framework | https://www.anchor-lang.com/ |
| Pinocchio framework | Zero-copy CU-optimized programs (88-95% savings) | https://github.com/anza-xyz/pinocchio |
| LiteSVM | Fast in-process Solana VM for tests | https://github.com/LiteSVM/LiteSVM |
| Surfpool | Local validator with mainnet forking + cheatcodes | https://github.com/txtx/surfpool |
| Bankrun | Anchor-friendly test framework built on LiteSVM | https://github.com/kevinheavey/solana-bankrun |

## RPC providers (Solana-specialized)

| Provider | Plan tier | Notes |
|---|---|---|
| Helius | Developer / Business / Professional | Best Solana-specialized. Enhanced WebSocket with typed events. Has LaserStream (Yellowstone-compatible gRPC). |
| QuickNode | Marketplace | Multi-chain. Streams product is Yellowstone-compatible. |
| Triton | Custom | Hosts Yellowstone gRPC. Best for high-volume. |
| Chainstack | Pay-as-you-go | Multi-chain. |
| dRPC | Pay-as-you-go | Decentralized. |
| GenesysGo (now Triton) | n/a | Acquired by Triton. |

## Protocol accounts to index (verified June 2026)

| Protocol | Repo | Program ID | Notes |
|---|---|---|---|
| Raydium CLMM | https://github.com/raydium-io/raydium-clmm | `CAMMCzo5YL8w4VFF8KVHrK22GgU4tBh1WaxgLsD1YwbF` | Was `raydium-amm-v3`. 386 stars. Apache-2.0. |
| Raydium AMM v4 | https://github.com/raydium-io/raydium-amm | `675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8` | Constant product. |
| Orca Whirlpools | https://github.com/orca-so/whirlpools | `whirLbMiicVdio4qvUfM5KAg8CT1BgXoF6NTB2dQeK3` | Original CLMM. |
| Jupiter (Aggregator) | https://github.com/jup-ag | `JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4` | Routes swaps. |
| Meteora DLMM | https://github.com/MeteoraAg | `LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo` | Dynamic Liquidity. |
| Marinade Finance | https://github.com/marinade-finance | `MarBmsSgKXdrN1egZf5sqi1kmBZj9GU9J4iDf8DQ2f7` | Liquid staking. |
| Lido for Solana | https://github.com/lidofinance | `CrX7kM6Lysi9yHqo7McZQGyV7M2jMhB7EsiztSqC2wz` | Liquid staking. |
| Sanctum | https://github.com/igneous-labs | Multiple LSTs | Liquid staking aggregator. |
| Magic Eden | https://github.com/magiceden | Marketplace v1 + v2 | |
| Tensor | https://github.com/tensor-foundation | `TSWAPaqyCSx2KABk68Shruf4t7rP6hhY7D6QiA5e72tt` | NFT marketplace. |
| Magicblock (ephemeral rollups) | https://github.com/magicblock-labs | `MBEnqycSiX6VHYZ9YsEBKq7i9NqzprYr7ZephHbPdrS` | Sub-10ms latency. |

## Solana AI Kit skills (for indexer work)

| Skill | Repo | Use for |
|---|---|---|
| `ext/helius` | https://github.com/solanabr/solana-ai-kit | Using Helius RPC, webhooks, enhanced WebSocket, LaserStream gRPC |
| `ext/sendai/skills/helius` | https://github.com/sendaifun/skills | Older Helius skill (superseded by ext/helius) |
| `ext/sendai/skills/quicknode` | https://github.com/sendaifun/skills | Using QuickNode Streams, RPC, gRPC |
| `ext/sendai/skills/quicknode-anchor` | https://github.com/quiknode-labs/solana-anchor-claude-skill | Anchor financial-math reference (quarantined) |
| `.claude/skills/backend-async.md` | https://github.com/solanabr/solana-ai-kit | Generic Axum/Tokio patterns. One small indexer pattern. |
| `.claude/skills/deployment.md` | https://github.com/solanabr/solana-ai-kit | CI/CD, multisig, deployment |
| `ext/sendai/skills/pyth` | https://github.com/sendaifun/skills | Oracle price feeds (often indexed) |
| `ext/sendai/skills/solana-kit` | https://github.com/sendaifun/skills | Modern SDK (for writing the indexer in TS) |
| `ext/cloudflare` | https://github.com/cloudflare-labs/agents | Deploying indexer on Workers |

## Indexer examples to learn from

| Example | Description |
|---|---|
| `rpcpool/yellowstone-grpc/examples/typescript` | Official TS examples for Yellowstone |
| `helius-labs/laserstream-sdk` | Helius's optimized gRPC client (the one that inspired napi-rs) |
| `metaplex-foundation/digital-asset-standard-api` | Reference indexer for NFTs (DAS API) |
| `rpcpool/yellowstone-grpc-kafka` | Production pattern: gRPC → Kafka → consumer |
| `jito-labs/mev-searcher` | MEV indexer using Geyser |
| `coral-xyz/anchor-ts-cpi` | Anchor TS reference |

## Observability & infra

| Tool | Use for |
|---|---|
| Prometheus | Metrics, alerting |
| Grafana | Dashboards |
| Datadog | Hosted metrics + logs |
| Honeycomb | Distributed tracing (great for indexer debugging) |
| Sentry | Error tracking |
| Better Stack (Logtail) | Hosted log aggregation |
| PagerDuty | Pager rotation |
| TimescaleDB | Postgres extension for time-series compression |
| Postgres LISTEN/NOTIFY | Cross-process notifications (alternative to Redis pub/sub) |
| Redis | Cache + dedup + queue |
| Kafka | Durable event queue |
| NATS JetStream | Lightweight durable queue (good Redis alternative) |

## Test fixtures

| Tool | Use for |
|---|---|
| `solana-program-test` | Run a real BPF program in tests |
| LiteSVM | In-process SVM, no validator |
| `solana-bankrun` | Anchor-friendly LiteSVM wrapper |
| `surfpool` | Local validator with mainnet fork |
| `anchor test` | Full end-to-end against local validator |
| `metaplex-foundation/solana-test` | Reusable test helpers |
| `drizzle-kit` | SQL migrations (if writing the indexer in TS) |
| `sqlx-cli` | SQL migrations (if writing in Rust) |

## Specific docs to keep open while building

| Topic | URL |
|---|---|
| Solana transactions | https://solana.com/docs/core/transactions |
| Solana accounts model | https://solana.com/docs/core/accounts |
| Solana rent | https://solana.com/docs/core/fees |
| Anchor accounts | https://www.anchor-lang.com/docs/account-constraints |
| Anchor IDL | https://www.anchor-lang.com/docs/idl |
| Token-2022 extensions | https://spl.solana.com/token-2022 |
| Pyth price feeds | https://docs.pyth.network/price-feeds |
| Light Protocol ZK Compression | https://www.zkcompression.com/ |
| Helius Enhanced WebSocket | https://docs.helius.dev/webhooks-and-websockets/websocket |
| Helius Webhooks | https://docs.helius.dev/webhooks-and-websockets/webhooks |
| Helius LaserStream | https://docs.helius.dev/laserstream/ |
| Helius DAS API | https://docs.helius.dev/das-api/ |

## When docs are stale

Solana tooling moves fast. If a doc is outdated:
- Check the GitHub repo for the latest version (`@latest` tag, latest release)
- Open an issue on the doc repo (they usually fix it fast)
- The SendAI skills are kept more current than docs (the team actively maintains them)

## Related references

- [indexer-architecture.md](indexer-architecture.md) — overall design
- [geyser-plugins.md](geyser-plugins.md) — Geyser plugin code
- [real-time-streaming.md](real-time-streaming.md) — live stream patterns
- [backfill-strategies.md](backfill-strategies.md) — historical data
- [postgres-schemas.md](postgres-schemas.md) — DB schema patterns
- [cost-optimization.md](cost-optimization.md) — RPC credit budgeting
- [testing-indexers.md](testing-indexers.md) — test pyramid
- [production-ops.md](production-ops.md) — on-call playbook
