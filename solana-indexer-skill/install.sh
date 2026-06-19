#!/usr/bin/env bash
#
# install.sh — per-skill installer for solana-indexer-skill
#
# This is a thin wrapper that delegates to the top-level ./install.sh
# at the repo root. Most users should run that one instead:
#
#   curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/install.sh | bash -s -- add solana-indexer
#
# Or from a clone:
#
#   cd solana-superchargers && ./install.sh add solana-indexer
#
# This per-skill file exists for the case where you want to install just
# this skill from inside its own subdirectory, with no args. It then
# installs itself only.

set -euo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

# If we have args, delegate to the multi-skill installer at the repo root
if [[ $# -gt 0 && -f "${REPO_ROOT}/install.sh" ]]; then
  exec "${REPO_ROOT}/install.sh" "$@"
fi

# No args + repo root has the multi-skill installer → delegate add of self
if [[ $# -eq 0 && -f "${REPO_ROOT}/install.sh" ]]; then
  exec "${REPO_ROOT}/install.sh" add solana-indexer
fi

# Standalone mode (sparse checkout) — copy this skill's files directly
: "${CLAUDE_SKILLS_HOME:=$HOME/.claude/skills}"
CODEX_SKILLS_HOME="${CODEX_SKILLS_HOME:-$HOME/.codex/skills}"
SKILL_NAME="solana-indexer"
DEST="${CLAUDE_SKILLS_HOME}/${SKILL_NAME}"

cmd="${1:-add}"
shift || true

case "$cmd" in
  add)
    echo "→ installing ${SKILL_NAME} to ${DEST}/"
    mkdir -p "${DEST}"
    rsync -a --delete \
      --exclude='install.sh' \
      --exclude='.git' \
      --exclude='**/node_modules' \
      --exclude='**/target' \
      --exclude='**/.DS_Store' \
      --exclude='**/dist' \
      "${SCRIPT_DIR}/" "${DEST}/"
    echo "  ✓ installed"
    if command -v codex &> /dev/null; then
      mkdir -p "${CODEX_SKILLS_HOME}/${SKILL_NAME}"
      rsync -a --delete \
        --exclude='install.sh' \
        --exclude='.git' \
        --exclude='**/node_modules' \
        --exclude='**/target' \
        --exclude='**/.DS_Store' \
        --exclude='**/dist' \
        "${SCRIPT_DIR}/" "${CODEX_SKILLS_HOME}/${SKILL_NAME}/"
      echo "  ✓ mirrored to ${CODEX_SKILLS_HOME}/${SKILL_NAME}/"
    fi
    echo ""
    echo "Done. Restart Claude Code or Codex to pick up the skill."
    echo "Tip: from a full clone, use ../install.sh for the multi-skill manager."
    ;;
  remove|rm)
    rm -rf "${DEST}"
    rm -rf "${CODEX_SKILLS_HOME}/${SKILL_NAME}" 2>/dev/null || true
    echo "removed ${SKILL_NAME}"
    ;;
  *)
    cat <<EOF
solana-indexer-skill installer (standalone fallback)

Most users should run the top-level installer from the repo root:
  cd solana-superchargers && ./install.sh add solana-indexer

This file works standalone if you have only this skill's directory.

Usage:
  ./install.sh            Install this skill
  ./install.sh add        (same, explicit)
  ./install.sh remove     Uninstall this skill
  ./install.sh help       Show this message
EOF
    ;;
esac
