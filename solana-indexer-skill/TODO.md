# TODO — solana-indexer-skill v0.1 roadmap

> Calendar versioning: v0.x during the public-bounty submission phase, v1.0 once stable.

## v0.1 (ship to Superteam Earn bounty) — current

- [x] 9 reference files (architecture, geyser, schemas, backfill, streaming, cost, testing, ops, resources)
- [x] 3 working examples (minimal TS, Geyser skeleton, subgraph template)
- [x] 2 agents (architect, qa)
- [x] 2 commands (`/build-indexer`, `/backfill`)
- [x] 1 rule (indexer-defaults)
- [x] install.sh
- [x] CLAUDE.md, README, LICENSE
- [x] Top-level repo with multi-skill structure (`solana-superchargers/`)
- [x] Verify minimal-indexer-ts compiles (`npm install && tsc --noEmit`) — CI passes
- [x] Verify geyser-plugin/skeleton builds (`cargo check`) — CI passes
- [x] Top-level + skill LICENSE (MIT)
- [x] Top-level + skill CHANGELOG.md, CONTRIBUTING.md, SKILLS.md
- [x] CI: 6 jobs (Skills, TypeScript, Subgraph, Rust, Internal links, Frontmatter)
- [x] Banner image (WebP, transparent background, blends with GitHub)
- [x] Solana badge + CI badge + Version badge on both READMEs
- [x] GitHub topics + description set
- [x] Push to GitHub: https://github.com/srivtx/solana-superchargers
- [ ] Add 3-5 golden test fixtures (real mainnet txs) — needs a Helius key
- [ ] Add demo video / screenshots
- [ ] Submit to https://superteam.fun/earn/listing/ship-useful-agent-skills-we-can-add-to-solana-ai-kit

## v0.2 — coverage expansion

- [ ] Add a Solana Foundation compatibility test (does the skill install correctly on the latest AI Kit release?)
- [ ] Add a "design review" command that critiques an existing indexer
- [ ] Add compressed NFT (cNFT / Bubblegum) schema + parser example
- [ ] Add Token-2022 advanced indexing patterns (transfer hooks, confidential transfers)
- [ ] Add Pyth price feed integration example (hybrid: index tx events + price at slot)
- [ ] Add the Graph "subgraph" comparison section to indexer-architecture.md

## v0.3 — operational maturity

- [ ] Add Prometheus example config + Grafana dashboard JSON
- [ ] Add S3 archive example (raw tx → S3)
- [ ] Add Litestream / pg-backup example for indexer DBs
- [ ] Add chaos test suite as a separate npm script
- [ ] Add load test (1M synthetic events, measure lag + memory)
- [ ] Add a "runbook template" the user can copy

## v1.0 — stable

- [ ] Cross-validated against 3+ real production indexers (community feedback)
- [ ] All example code runs against devnet without modification
- [ ] All schema examples match the actual program source code (Anchor IDL diff = 0)
- [ ] Golden test fixtures cover all major event types
- [ ] Documentation covers: what to do, what NOT to do, when to upgrade plan, when to self-host
- [ ] Skill is referenced in the Solana AI Kit's `skill-registry.json`

## Future skills (solana-superchargers expansion)

- [ ] `solana-observability-skill` — production monitoring/monitoring
- [ ] `solana-mev-skill` — MEV protection / Jito bundles
- [ ] `solana-upgrade-skill` — program upgrade patterns (data migrations, schema changes, feature flags)
- [ ] `solana-e2e-skill` — dApp E2E testing (Playwright + wallet, Surfpool fork)
- [ ] `solana-wallet-ux-skill` — dApp design patterns (signing UX, error states, multi-wallet)

## Backlog (not planned)

- ~~Audit for solana-auditor-skill~~ (declined: too saturated, see submission analysis)
- ~~Position manager for solana-position-manager-skill~~ (declined: too narrow, requires live data)
- ~~Token-2022 advanced as a separate skill~~ (covered by Solana AI Kit's `token-2022.md`)

## Reporting issues

Open an issue at https://github.com/srivtx/solana-superchargers/issues.

For bounty-related questions, DM @kauenet on the Superteam Discord.
