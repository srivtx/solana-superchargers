<div align="center">

<a href="/.github/assets/supercharger.jpg"><img src="./.github/assets/supercharger.jpg" width="500" alt="solana-superchargers" /></a>

# solana-superchargers

**Production-grade Claude Code / Codex skills for Solana builders.**

A curated set of production-grade skills that complement and extend the
[Solana AI Kit](https://github.com/solanabr/solana-ai-kit) ecosystem. Every
skill is self-contained, MIT-licensed, and verified against real code.

[![CI](https://github.com/srivtx/solana-superchargers/actions/workflows/validate.yml/badge.svg)](https://github.com/srivtx/solana-superchargers/actions/workflows/validate.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](./CHANGELOG.md)
[![License MIT](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Solana](https://img.shields.io/badge/Solana-black?logo=solana)](https://solana.com)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-ready-cc785c)](https://claude.ai/code)
[![Codex](https://img.shields.io/badge/Codex-ready-000000)](https://openai.com/codex)

</div>

---

## What's in v0.1

- **1 skill** — `solana-indexer` (Geyser plugins, backfill, Postgres schemas, real-time streaming, cost optimization, production ops)
- **9 references** — every fact cross-checked against real code and docs
- **3 working examples** — `minimal-indexer-ts` (TypeScript, `tsc --noEmit` clean), `geyser-plugin/skeleton` (Rust, `cargo check` clean), `subgraph-template` (The Graph on Solana)
- **2 agents** — `indexer-architect`, `indexer-qa`
- **2 commands** — `/build-indexer`, `/backfill`
- **1 rule** — `indexer-defaults.md`
- **6 CI jobs** — `Skills`, `TypeScript examples`, `Subgraph template`, `Rust examples`, `Internal links`, `Frontmatter`

## Install the most popular skill

The most popular entry point — `solana-indexer` — installs in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/solana-indexer-skill/install.sh | bash
```

That copies the skill into `~/.claude/skills/solana-indexer/` (and
`~/.codex/skills/solana-indexer/` if Codex is detected). Restart Claude
Code or Codex to pick it up.

> **Other skills in this repo** (each has its own one-liner at
> `https://raw.githubusercontent.com/srivtx/solana-superchargers/main/<skill>/install.sh`):
>
> | Skill | Curated link |
> |---|---|
> | `solana-indexer` | `…/solana-indexer-skill/install.sh \| bash` |
> | _(more coming — see [`SKILLS.md`](./SKILLS.md))_ | |

## Install everything (or pick a subset)

The repo is a multi-skill marketplace. The top-level installer knows about
every skill via `SKILLS.md`:

```bash
# Clone once
git clone https://github.com/srivtx/solana-superchargers.git
cd solana-superchargers

# Install everything
./install.sh add all

# Or pick a subset
./install.sh add solana-indexer
./install.sh add preset:core
./install.sh add category:indexers

# Or just download the manager without cloning
curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/install.sh | bash -s -- add solana-indexer
```

## Commands

| Command | What it does |
|---|---|
| `add <skill\|category:<name>\|preset:<name>\|all> [...]` | Install skills, categories, or presets |
| `remove <skill> [...]` | Uninstall one or more skills |
| `remove --all` | Uninstall every supercharger-installed skill |
| `list` | Show all skills with install status |
| `categories` | Show all categories |
| `presets` | Show all preset bundles |
| `info <skill\|preset>` | Show details for one target |
| `verify` | Check installed skills are valid |
| `help` | Show usage |

## Why a multi-skill repo

Most Solana skills share the same primitives — they reference the same
MCPs (`ext/helius`, `ext/sendai/...`), they build on the same `solana-dev`
foundation, they need the same testing setup. A multi-skill repo gives you:

- **Shared installer** — one `install.sh` knows about every skill
- **Coordinated releases** — when Solana tooling changes (new RPC
  provider, new SDK version), update once, benefit everywhere
- **Cross-skill patterns** — patterns from one skill (e.g., slot-conditional
  upserts, dedup via `(slot, signature)`) apply to others
- **Single `SKILLS.md` index** — discoverable from one place

Each skill is still a self-contained directory that you can install
independently. The repo structure doesn't change the per-skill contract.

## Repository layout

```
solana-superchargers/
├── install.sh              # multi-skill installer (add/remove/list/verify/presets)
├── SKILLS.md               # marketplace index (parsed by install.sh)
├── CONTRIBUTING.md         # how to add a new skill
├── CHANGELOG.md            # version history
├── LICENSE                 # MIT
├── .github/
│   ├── assets/             # logo + banner
│   │   └── supercharger.jpg
│   └── workflows/          # CI: validate every skill on every push
│       └── validate.yml
└── solana-<name>-skill/    # one subdirectory per skill
    ├── install.sh         # per-skill one-liner (delegates to ../install.sh)
    └── skill/             # SKILL.md + references/ + examples/ + agents/ + commands/ + rules/
```

## Adding a new skill

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the full checklist. Short
version:

1. Create a subdirectory: `mkdir solana-foo-skill`
2. Add `skill/SKILL.md` with the required frontmatter (`name`, `description`)
3. Add `references/`, `examples/`, `agents/`, `commands/`, `rules/` as needed
4. Add a `LICENSE` (MIT) and `install.sh`
5. Add an entry under the right category in `SKILLS.md` — this is what the installer reads
6. Open a PR. CI runs `install.sh verify` on every skill.

## License

[MIT](./LICENSE)

---

<sub>Built by [@srivtx](https://github.com/srivtx) · A Superteam Earn
submission · Used as a reference for the
[Solana AI Kit](https://github.com/solanabr/solana-ai-kit) ecosystem</sub>
