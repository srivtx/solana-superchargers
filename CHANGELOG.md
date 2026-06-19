# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
calendar-based (`YYYY.MM`) since Solana tooling moves fast.

## [Unreleased]

### Added
- Multi-skill `install.sh` with `add` / `remove` / `list` / `categories` /
  `presets` / `info` / `verify` commands
- `SKILLS.md` marketplace index (parsed by installer)
- `CONTRIBUTING.md` skill-author guide
- GitHub Actions CI: validate every skill on every push
- `assets/supercharger.png` logo
- Top-level README with badges, install instructions, and roadmap

### Changed
- Renamed the first skill's top-level from `# solana-superchargers` repo
  with one skill to a true multi-skill repo
- Moved the per-skill install from `./solana-indexer-skill/install.sh` to
  the top-level `./install.sh add solana-indexer` pattern

## [2026.06] — v0.1.0 — Initial release

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
  - All TypeScript examples: `tsc --noEmit` clean
  - Rust Geyser plugin: `cargo check` clean
  - 72 internal markdown cross-links, 0 broken

### Notes
- Submitted to Superteam Earn bounty:
  "Ship useful agent skills we can add to Solana AI Kit" (July 8, 2026 cutoff)
- Architecture decision documented in the planning session
- 3 seed skills checked (`crypto-legal`, `position-manager`,
  `solana-auditor`) — 2 are empty (just LICENSE), 1 has content but
  is in starting phase
- Solana AI Kit gap analysis: `ext/helius` and `ext/quicknode` are
  consumer-side (use their APIs); no skill teaches *building* an indexer
  from scratch. The kit's `backend-async.md` has one 20-line polling
  pattern. The local `token-2022.md` is comprehensive (verified) and
  covers transfer hooks + confidential transfers.

[Unreleased]: https://github.com/srivtx/solana-superchargers/compare/v0.1.0...HEAD
[2026.06]: https://github.com/srivtx/solana-superchargers/releases/tag/v0.1.0
