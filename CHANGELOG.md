# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
calendar-based (`YYYY.MM`) since Solana tooling moves fast.

## [Unreleased]

### Added
- Multi-skill `install.sh` with `add` / `remove` / `list` / `categories` /
  `presets` / `info` / `verify` commands. Supports `add all`, `add category:<name>`,
  `add preset:<name>`. Parses `SKILLS.md` as the marketplace index.
- `SKILLS.md` marketplace index — single source of truth for what skills exist
- `CONTRIBUTING.md` skill-author guide with frontmatter spec and structure
- GitHub Actions CI: 5-job pipeline validates every skill on every push
  (skills verify, TS typecheck, Rust check, link check, frontmatter check)
- `assets/supercharger.png` logo (referenced from README)
- Per-skill `install.sh` in `solana-indexer-skill/` — works as
  `curl .../solana-indexer-skill/install.sh | bash` for one-liner share
- Top-level README rewritten production-grade (logo, badges, install,
  commands, repo layout, no roadmap noise)

### Changed
- Per-skill `install.sh` now delegates to top-level multi-skill installer
  when run from inside the repo. When run via `curl | bash` it downloads
  the top-level installer and delegates to it. Single source of truth.

## [2026.06] — v0.1.0

### Added
- `solana-indexer-skill` v0.1: build custom Solana indexers
  - 9 reference files (architecture, geyser-plugins, postgres-schemas,
    backfill, real-time-streaming, cost-optimization, testing,
    production-ops, resources)
  - 3 working examples (minimal-indexer-ts, geyser-plugin skeleton, subgraph-template)
  - 2 agents (indexer-architect, indexer-qa)
  - 2 commands (`/build-indexer`, `/backfill`)
  - 1 rule (indexer-defaults)
  - Verified against real code: `raydium-io/raydium-clmm` PoolState struct,
    `rpcpool/yellowstone-grpc` v13.2.5+solana.4.0.0,
    `helius-sdk` v3.0.0, `solana-geyser-plugin-interface` 1.18
  - TypeScript examples: `tsc --noEmit` clean
  - Rust Geyser plugin: `cargo check` clean
  - 72 internal markdown cross-links, 0 broken

[Unreleased]: https://github.com/srivtx/solana-superchargers/compare/v0.1.0...HEAD
[2026.06]: https://github.com/srivtx/solana-superchargers/releases/tag/v0.1.0
