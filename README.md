# solana-superchargers

A collection of high-quality, production-grade Claude Code / Codex skills that extend the [Solana AI Kit](https://github.com/solanabr/solana-ai-kit). Each skill is a self-contained subdirectory that solves a specific, unclaimed gap in the Solana builder ecosystem.

## Skills

| Skill | Status | Description |
|---|---|---|
| [`solana-indexer-skill`](./solana-indexer-skill) | In progress | Build custom indexers: Geyser plugins, backfill strategies, Postgres schemas, cost optimization, production ops. |
| _(more coming)_ | | Future: production observability, MEV protection, upgrade patterns, dApp E2E testing. |

## Why a multi-skill repo?

The Solana AI Kit ecosystem has hundreds of skills — but most categories (DeFi, security, mobile) are saturated. The gaps are narrower, deeper problems. This repo hosts a curated set of skills that fill those gaps with production-grade quality.

## Install

Each skill installs independently:

```bash
git clone https://github.com/srivtx/solana-superchargers.git
cd solana-superchargers/solana-indexer-skill
./install.sh
```

## License

MIT.
