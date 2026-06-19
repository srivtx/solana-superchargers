#!/usr/bin/env bash
#
# install.sh — install solana-indexer-skill into Claude Code / Codex
#
# Mirrors the skill into ~/.claude/skills/solana-indexer/ (and ~/.codex/skills/
# if the codex CLI is detected), so Claude can discover it via the
# "skill" tool. Existing installs are overwritten.
#
# Idempotent. Re-run after pulling upstream changes.

set -euo pipefail

SKILL_NAME="solana-indexer"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Where the install lives. Override with CLAUDE_SKILLS_HOME=/path ./install.sh
: "${CLAUDE_SKILLS_HOME:=$HOME/.claude/skills}"
CODEX_SKILLS_HOME="${CODEX_SKILLS_HOME:-$HOME/.codex/skills}"

echo "→ installing ${SKILL_NAME} to ${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/"
mkdir -p "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}"

# Copy everything except the install script and example node_modules
rsync -a --delete \
  --exclude='install.sh' \
  --exclude='.git' \
  --exclude='**/node_modules' \
  --exclude='**/target' \
  --exclude='**/.DS_Store' \
  --exclude='**/dist' \
  "${SCRIPT_DIR}/" \
  "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/"

# Mirror to codex if the codex CLI is installed
if command -v codex &> /dev/null; then
  echo "→ codex detected, also installing to ${CODEX_SKILLS_HOME}/${SKILL_NAME}/"
  mkdir -p "${CODEX_SKILLS_HOME}/${SKILL_NAME}"
  rsync -a --delete \
    --exclude='install.sh' \
    --exclude='.git' \
    --exclude='**/node_modules' \
    --exclude='**/target' \
    --exclude='**/.DS_Store' \
    --exclude='**/dist' \
    "${SCRIPT_DIR}/" \
    "${CODEX_SKILLS_HOME}/${SKILL_NAME}/"
else
  echo "→ codex not detected, skipping"
fi

# Verify the install
SKILL_FILE="${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/skill/SKILL.md"
if [[ ! -f "${SKILL_FILE}" ]]; then
  echo "✗ install failed: ${SKILL_FILE} not found" >&2
  exit 1
fi

# Count what was installed
REF_COUNT=$(find "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/skill/references" -name '*.md' | wc -l | tr -d ' ')
EX_COUNT=$(find "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/skill/examples" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
AGENT_COUNT=$(find "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/agents" -name '*.md' | wc -l | tr -d ' ')
CMD_COUNT=$(find "${CLAUDE_SKILLS_HOME}/${SKILL_NAME}/commands" -name '*.md' | wc -l | tr -d ' ')

echo ""
echo "✓ installed ${SKILL_NAME}:"
echo "  → ${REF_COUNT} reference files"
echo "  → ${EX_COUNT} examples"
echo "  → ${AGENT_COUNT} agents"
echo "  → ${CMD_COUNT} commands"
echo "  → 1 rule"
echo ""
echo "Try it: open Claude Code and run"
echo "  /build-indexer \"index Raydium CLMM swaps on mainnet\""
echo ""
echo "Or ask naturally:"
echo "  \"Help me design a Geyser plugin for Jupiter V6 swaps\""
echo "  \"What's the best way to backfill 90 days of pool state?\""
