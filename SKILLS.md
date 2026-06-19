# Skills

This is the marketplace index of every skill in this repo. The installer reads this file — to add a new skill, add an entry under a category.

## How entries are parsed

The installer reads this file looking for sections in this form:

```
## <category-name>
- [skill-name](path/to/skill) — short description
```

Each subdirectory at the repo root is one self-contained skill. Each must contain a `skill/SKILL.md` (entry point) and optionally `references/`, `examples/`, `agents/`, `commands/`, `rules/`, `install.sh`, `CLAUDE.md`, `README.md`, `LICENSE`, `TODO.md`.

See `CONTRIBUTING.md` for the full skill-author checklist.

## Indexers (start here if you build Solana backends)

- [solana-indexer](solana-indexer-skill) — Build custom Solana indexers: Geyser plugins, backfill strategies, Postgres schemas, real-time streaming, cost optimization, production ops. 9 references, 3 working examples, 2 agents, 2 commands, 1 rule.

## DeFi

_(coming soon: solana-defi-skill — Jupiter/Raydium/Orca integration recipes, swap parsing, AMM math)_

## Tokens

_(coming soon: solana-token2022-skill — Transfer hooks, confidential transfers, KYC tokens, interest-bearing)_

## Security

_(coming soon: solana-security-skill — Solana-specific audit patterns beyond Trail of Bits)_

## Observability

_(coming soon: solana-observability-skill — Production monitoring, slot-lag alerting, RPC failover)_

## MEV

_(coming soon: solana-mev-skill — Jito bundles, sandwich detection, priority fees)_

## Frontend / dApp UX

_(coming soon: solana-dapp-ux-skill — Wallet adapter patterns, transaction signing UX, error states)_

## Testing

_(coming soon: solana-e2e-skill — Playwright + wallet, Surfpool fork, dApp testing)_

## Mobile

_(coming soon: solana-mobile-ux-skill — MWA patterns, deep links, biometric signing)_

## GTM / Startup

_(coming soon: solana-gtm-skill — Superteam Earn submissions, grant writing, pitch decks for Solana projects)_

## Infrastructure

_(coming soon: solana-infra-skill — RPC selection, validator hosting, Geyser deployment)_

## Compliance

_(coming soon: solana-compliance-skill — Token-2022 KYC extensions, OFAC screening, audit trails)_

## AI Agents

_(coming soon: solana-agent-skill — Agent wallets, session keys, autonomous DeFi on Solana)_

## Presets

- core: solana-indexer
- indexer-starter: solana-indexer
