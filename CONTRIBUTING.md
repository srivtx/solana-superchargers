# Contributing to solana-superchargers

Thanks for considering a contribution. This guide covers how to add a new
skill, fix a bug in an existing skill, or improve the installer.

## Adding a new skill

### 1. Pick a gap that matters

Before writing code, check that the gap is real:

- Search the [Solana AI Kit SKILL.md hub](https://github.com/solanabr/solana-ai-kit/blob/main/.claude/skills/SKILL.md)
  to see what's bundled
- Check the [sendai/skills marketplace](https://github.com/sendaifun/skills) for existing community skills
- Read [`sendai/skills/IDEAS.md`](https://github.com/sendaifun/skills/blob/main/IDEAS.md) for
  community-acknowledged gaps
- Read the Superteam Earn bounty listings for what's actively being paid for

If your idea is a "wrapper around the Helius SDK" or a "tutorial on Anchor" — don't.
The kit already has `ext/helius` and `ext/solana-dev`. Find something the kit *doesn't* have.

### 2. Create the directory structure

Every skill is a self-contained subdirectory at the repo root. The structure
is fixed:

```
solana-<name>-skill/
├── CLAUDE.md            # system personality + routing (entry point for Claude)
├── README.md            # human-readable: what + why + how to use
├── LICENSE              # MIT
├── TODO.md              # roadmap for this skill
├── install.sh           # per-skill installer (delegates to ../install.sh)
├── skill/
│   ├── SKILL.md         # REQUIRED: frontmatter (name, description) + routing
│   ├── references/      # progressive-loading .md files
│   │   └── *.md
│   └── examples/        # working, runnable code
│       └── <example-name>/
├── agents/              # specialized agents (optional)
│   └── <name>.md
├── commands/            # slash commands (optional)
│   └── <name>.md
└── rules/               # auto-loading rules (optional)
    └── <name>.md
```

### 3. Required frontmatter

Every `.md` file in `skill/`, `agents/`, `commands/`, `rules/` MUST start with:

```yaml
---
name: <kebab-case-name>
description: <one-line description with USE-WHEN trigger phrases>
user-invocable: true   # for skill/SKILL.md only
---
```

The `description` is what Claude matches against user requests. Be specific
and include trigger phrases.

### 4. Reference files (the meat)

Skills use **progressive loading** — Claude reads `SKILL.md` first, then
follows links to specific references based on the user's intent. Each
reference should be 150-500 lines, focused on one topic, with code examples
verified against real docs.

Topics that have worked well:
- Architecture decision trees
- Canonical schema patterns
- Cost analysis with verified pricing
- Common pitfalls (with code-level fixes)
- Production runbook patterns

### 5. Examples

Working, runnable code. Every example should:
- Have a `README.md` explaining what it does
- Have a `package.json` / `Cargo.toml` / `subgraph.yaml` that builds
- Compile / type-check cleanly (CI runs this)
- Be small enough to read in 5 minutes

### 6. Tests (optional but encouraged)

Golden tests with real mainnet txs as fixtures. See
`solana-indexer-skill/skill/examples/minimal-indexer-ts/` for the pattern.

### 7. Add the entry to SKILLS.md

The installer reads `SKILLS.md` to know what skills exist. Add an entry
under the right category:

```markdown
## <category-name>
- [skill-name](path/to/skill) — short description
```

Format is strict — the installer parses it. The description should be one
line, no newlines, starting with a verb or noun phrase.

### 8. Run the installer

```bash
./install.sh verify
./install.sh info <your-skill>
./install.sh add <your-skill>
ls ~/.claude/skills/<your-skill>/
```

### 9. Open a PR

CI will run:
- `./install.sh verify` — checks every skill is valid
- TypeScript examples: `tsc --noEmit`
- Rust examples: `cargo check`

Your PR description should explain:
- The gap it fills (cite SKILLS.md, sendai/skills/IDEAS.md, or a bounty listing)
- How it was verified (real code? docs? testing?)
- Any dependencies (external MCPs, CLIs)

## Fixing an existing skill

- Small fixes (typos, broken links): just open a PR
- Substantive changes: open an issue first to discuss
- Update the version in the skill's `CLAUDE.md` if you change the routing
- Update `CHANGELOG.md`

## Reporting issues

- Skill bugs: open an issue at https://github.com/srivtx/solana-superchargers/issues
- Security issues: DM the maintainer
- Bounty-specific questions: contact the bounty sponsor

## Style guide

- **No emojis** in docs (superteam-br style)
- **Cite sources** for any pricing, version numbers, or API details
- **Verified content** — if you write about an SDK, link to the actual repo
  and check the current version
- **Frontmatter on every skill file** — the installer relies on it
- **No "AI slop"** — the bounty judges call this out specifically. Test
  your examples actually compile.

## License

By contributing, you agree to license your work under MIT.
