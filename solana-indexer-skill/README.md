<div align="center">

<a href="./assets/indexer.webp"><img src="./assets/indexer.webp" width="500" alt="solana-indexer skill — build custom Solana indexers end-to-end" /></a>

# solana-indexer

**Build custom Solana indexers end-to-end.** Geyser plugins, backfill strategies, Postgres schemas, real-time streaming, cost optimization, production ops — verified against real code.

> Part of [solana-superchargers](https://github.com/srivtx/solana-superchargers) — a curated set of skills that complement and extend the [Solana AI Kit](https://github.com/solanabr/solana-ai-kit) ecosystem.

[![CI](https://github.com/srivtx/solana-superchargers/actions/workflows/validate.yml/badge.svg)](https://github.com/srivtx/solana-superchargers/actions/workflows/validate.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](./CHANGELOG.md)
[![License MIT](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Solana](https://img.shields.io/badge/Solana-black?logo=solana)](https://solana.com)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-ready-cc785c)](https://claude.ai/code)
[![Codex](https://img.shields.io/badge/Codex-ready-000000)](https://openai.com/codex)

</div>

---

## What's in this skill

- **9 references** — every fact cross-checked against real SDK code, repo source, and official docs
- **3 working examples** — `minimal-indexer-ts` (`tsc --noEmit` clean), `geyser-plugin/skeleton` (`cargo check` clean), `subgraph-template` (The Graph on Solana)
- **2 agents** — `indexer-architect`, `indexer-qa`
- **2 commands** — `/build-indexer`, `/backfill`
- **1 rule** — `indexer-defaults.md` (auto-loads in `/indexer` folders)
- **6 CI jobs** — Skills, TypeScript examples, Subgraph template, Rust examples, Internal links, Frontmatter

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/solana-indexer-skill/install.sh | bash
```

Installs to `~/.claude/skills/solana-indexer/` and
`~/.codex/skills/solana-indexer/` (if Codex is installed). Restart
Claude Code or Codex.

### From a clone (if you want to inspect first)

```bash
git clone https://github.com/srivtx/solana-superchargers.git
cd solana-superchargers
./install.sh add solana-indexer
```

### Manual copy (no install script)

```bash
git clone https://github.com/srivtx/solana-superchargers.git

mkdir -p ~/.claude/skills/solana-indexer
cp -R solana-superchargers/solana-indexer-skill/skill \
      solana-superchargers/solana-indexer-skill/agents \
      solana-superchargers/solana-indexer-skill/commands \
      solana-superchargers/solana-indexer-skill/rules \
      solana-superchargers/solana-indexer-skill/assets \
      solana-superchargers/solana-indexer-skill/CLAUDE.md \
      ~/.claude/skills/solana-indexer/
```

### Project-local install

```bash
CLAUDE_SKILLS_HOME=./.claude ./install.sh add solana-indexer
```

Installs into `./.claude/skills/solana-indexer/` of the current
directory. Useful for committing the skill into a specific repo.

> Want to install everything in the repo? `curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/install.sh | bash -s -- add all`

## What this skill does

You describe a Solana dApp. The skill routes you to the right approach:

| You say... | The skill reads |
|---|---|
| "I need to build an indexer" | `references/indexer-architecture.md` (decision tree) |
| "Geyser / Yellowstone gRPC" | `references/geyser-plugins.md` |
| "Postgres schema for swaps" | `references/postgres-schemas.md` |
| "Backfill historical data" | `references/backfill-strategies.md` |
| "Real-time account updates" | `references/real-time-streaming.md` |
| "Reduce RPC costs" | `references/cost-optimization.md` |
| "Test my indexer" | `references/testing-indexers.md` |
| "Run in production" | `references/production-ops.md` |

## Why this exists

The Solana AI Kit ecosystem has hundreds of skills (Helius, QuickNode, light-protocol, vulnhunter, code-recon, etc.) but **no skill teaches how to *build* an indexer**. Helius/QuickNode skills are *consumers* of their streams. The kit's `backend-async.md` has one 20-line polling pattern. This skill covers that ground end-to-end.

Indexers are the backbone of every serious Solana dApp — DeFi dashboards, NFT marketplaces, gaming leaderboards, social graphs, analytics. This skill lets Claude design, build, test, and operate them.

## Quick start

In Claude Code:

```
/build-indexer "index Raydium CLMM swaps and positions on mainnet"
```

Or just talk to it:

```
"Help me set up a Geyser gRPC plugin to index Magic Eden listings."
"Design a Postgres schema for a Jupiter swap indexer with hourly OHLCV aggregation."
"What's the cheapest way to backfill 90 days of pool state?"
```

## Examples

| Example | Language | What it shows |
|---|---|---|
| `examples/minimal-indexer-ts/` | TypeScript | 100-line indexer: Helius enhanced webhook → Postgres. `tsc --noEmit` clean. |
| `examples/geyser-plugin/skeleton/` | Rust | Geyser plugin skeleton using `solana-geyser-plugin-interface` 1.18. `cargo check` clean. |
| `examples/subgraph-template/` | YAML + TypeScript | The Graph on Solana: manifest, schema, mapping stub. |

## Commands

| Command | What it does |
|---|---|
| `/build-indexer "<description>"` | Scaffold a complete indexer from a natural-language spec |
| `/backfill [range]` | Backfill historical data with checkpointing + parallelism |

## Agents

| Agent | When to use |
|---|---|
| `indexer-architect` | Design an indexer for a given dApp (ingestion method, schema, stack) |
| `indexer-qa` | Test an indexer for correctness, dedup, replay safety, and ops health |

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
│   ├── references/
│   │   ├── indexer-architecture.md
│   │   ├── geyser-plugins.md
│   │   ├── postgres-schemas.md
│   │   ├── backfill-strategies.md
│   │   ├── real-time-streaming.md
│   │   ├── cost-optimization.md
│   │   ├── testing-indexers.md
│   │   ├── production-ops.md
│   │   └── resources.md
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

## When NOT to use this skill

- **Using an indexer's data** → read `ext/helius` (RPC queries), `ext/sendai/skills/pyth` (price feeds), or `ext/sendai/skills/solana-agent-kit` (AI agents)
- **Building a Solana program** (not an indexer) → read `ext/solana-dev/programs/anchor.md` or `ext/solana-dev/programs/pinocchio.md`
- **Auditing an existing indexer** → `ext/trailofbits` (security) or `ext/safe-solana-builder` (audit-derived rules)

## License

[MIT](./LICENSE)

---

<sub>Built by [@srivtx](https://github.com/srivtx) · Part of
[Solana AI Kit](https://github.com/solanabr/solana-ai-kit) ecosystem</sub>
