<div align="center">

<a href="./assets/indexer.webp"><img src="./assets/indexer.webp" width="500" alt="solana-indexer skill" /></a>

</div>

# solana-indexer-skill

A Claude Code / Codex skill for building **custom indexers** on Solana. Covers Geyser plugin development, backfill strategies, Postgres schema design, cost optimization, real-time streaming, testing, and production operations.

> **Part of [solana-superchargers](https://github.com/srivtx/solana-superchargers)** — a curated set of skills that complement and extend the Solana AI Kit ecosystem.

## Install this skill

The "curated link" for this skill — share this one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/solana-indexer-skill/install.sh | bash
```

That's it. The installer:
1. Downloads the multi-skill manager from this repo
2. Runs `add solana-indexer`
3. Copies the skill to `~/.claude/skills/solana-indexer/` and `~/.codex/skills/solana-indexer/`

Restart Claude Code or Codex to pick it up.

> Want to install everything in the repo? `curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/install.sh | bash -s -- add all`

## What this skill does

You describe a Solana dApp. The skill routes you to the right approach:

| You say... | The skill routes to |
|---|---|
| "I need to build an indexer" | `references/indexer-architecture.md` (decision tree) |
| "Geyser / Yellowstone gRPC" | `references/geyser-plugins.md` |
| "Postgres schema for swaps" | `references/postgres-schemas.md` |
| "Backfill historical data" | `references/backfill-strategies.md` |
| "Real-time account updates" | `references/real-time-streaming.md` |
| "Reduce RPC costs" | `references/cost-optimization.md` |
| "Test my indexer" | `references/testing-indexers.md` |
| "Run in production" | `references/production-ops.md` |

Plus 3 working examples, 2 agents, 2 commands, and 1 rule.

## Why this exists

The Solana AI Kit ecosystem has hundreds of skills (Helius, QuickNode, light-protocol, vulnhunter, code-recon, etc.) but **no skill teaches how to *build* an indexer**. Helius/QuickNode skills are *consumers* of their streams. The kit's `backend-async.md` has one 20-line polling pattern. This skill covers that ground end-to-end.

Indexers are the backbone of every serious Solana dApp — DeFi dashboards, NFT marketplaces, gaming leaderboards, social graphs, analytics. This skill lets Claude design, build, test, and operate them.

## Quick start

After install, in Claude Code:

```
/build-indexer "index Raydium CLMM swaps and positions on mainnet"
```

Or just ask naturally:

```
"Help me set up a Geyser gRPC plugin to index Magic Eden listings."
"Design a Postgres schema for a Jupiter swap indexer with hourly OHLCV aggregation."
"What's the cheapest way to backfill 90 days of pool state?"
```

## Repository layout

```
solana-indexer-skill/
├── CLAUDE.md                 # system personality + routing
├── README.md                 # this file
├── LICENSE                   # MIT
├── TODO.md                   # roadmap
├── install.sh                # per-skill installer (delegates to ../install.sh)
├── skill/
│   ├── SKILL.md              # entry point
│   └── references/
│       ├── indexer-architecture.md
│       ├── geyser-plugins.md
│       ├── postgres-schemas.md
│       ├── backfill-strategies.md
│       ├── real-time-streaming.md
│       ├── cost-optimization.md
│       ├── testing-indexers.md
│       ├── production-ops.md
│       └── resources.md
│   └── examples/
│       ├── minimal-indexer-ts/        # 100-line TS indexer (Helius webhook → Postgres)
│       ├── geyser-plugin/skeleton/    # Rust Geyser plugin skeleton
│       └── subgraph-template/         # The Graph on Solana
├── agents/
│   ├── indexer-architect.md           # designs an indexer for a given dApp
│   └── indexer-qa.md                  # tests indexer correctness
├── commands/
│   ├── build-indexer.md               # /build-indexer
│   └── backfill-data.md               # /backfill
└── rules/
    └── indexer-defaults.md            # auto-loads in /indexer folders
```

## Default stack (2026)

| Layer | Choice |
|---|---|
| Real-time | Yellowstone gRPC (Triton, Helius Laserstream, or QuickNode) |
| Polling fallback | Helius enhanced transactions API |
| Storage | Postgres 16 + TimescaleDB for time-series |
| Backfill | Snapshot + incremental replay (RPC + Geyser) |
| Testing | LiteSVM (unit), Surfpool fork (integration) |
| Local validator | Surfpool |
| Schema migrations | sqlx-cli (Rust) or Drizzle/Knex (TS) |
| Indexing-as-a-service fallback | The Graph on Solana (subgraphs) |
| Production | Docker + k8s, Prometheus metrics, PagerDuty alerts |

## License

MIT.
