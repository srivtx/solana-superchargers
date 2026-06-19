#!/usr/bin/env bash
#
# install.sh — per-skill installer for solana-indexer-skill
#
# Two modes:
#
#   1. Inside the repo (rare):
#        cd solana-superchargers/solana-indexer-skill
#        ./install.sh                  # installs just this skill
#        ./install.sh remove           # uninstalls it
#
#   2. Standalone (the common one — for sharing as a one-liner):
#
#      The "curated link" for THIS skill:
#
#        curl -fsSL https://raw.githubusercontent.com/srivtx/solana-superchargers/main/solana-indexer-skill/install.sh | bash
#
#      When you curl|bash this, we download the top-level multi-skill
#      installer to /tmp and delegate to it, so all installs go through
#      one source of truth.
#
# The top-level installer is the multi-skill manager. This per-skill
# script is just a thin "share one URL for this skill" wrapper.

set -euo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
SKILL_NAME="solana-indexer"

# Where skills install. Override with CLAUDE_SKILLS_HOME=/path ./install.sh
: "${CLAUDE_SKILLS_HOME:=$HOME/.claude/skills}"

# ── detect mode ──────────────────────────────────────────────────────
# We're "inside the repo" if the parent directory has the multi-skill install.sh.
# Otherwise we're a piped curl|bash call (SCRIPT_DIR will be /tmp or a temp dir).

inside_repo=false
if [[ -f "${REPO_ROOT}/install.sh" ]]; then
  # Verify the parent is actually the repo (has SKILLS.md, .git, etc.)
  if [[ -f "${REPO_ROOT}/SKILLS.md" ]] || [[ -d "${REPO_ROOT}/.git" ]]; then
    inside_repo=true
  fi
fi

if [[ "$inside_repo" == "true" ]]; then
  # Mode 1: inside the repo. Delegate add/remove to the multi-skill installer.
  # For help and other commands, handle locally so the per-skill docs are useful
  # when the user is exploring the skill directory.
  cmd="${1:-add}"
  case "$cmd" in
    add|remove|rm)
      if [[ $# -le 1 ]]; then
        # ./install.sh or ./install.sh add or ./install.sh remove
        # Default to operating on this skill.
        exec "${REPO_ROOT}/install.sh" "$cmd" "$SKILL_NAME"
      else
        # ./install.sh add foo bar → ./install.sh add foo bar
        exec "${REPO_ROOT}/install.sh" "$@"
      fi
      ;;
  esac
  # Fall through to standalone behavior for help etc.
fi

# ── Mode 2: standalone (curl|bash) ────────────────────────────────────
# We're not inside the repo. The skill files aren't here — they were
# never rsynced. We have two options:
#   a) Download the multi-skill installer and delegate to it
#   b) Download just this skill as a tarball and install directly
#
# (a) is simpler and uses the same code path as everyone else.
# (b) is faster but requires the repo to publish tarballs.

# Default behavior: download the multi-skill installer and delegate.
TEMP_INSTALLER="$(mktemp -t solana-superchargers-install.XXXXXX.sh)"

# Where to fetch the installer from. Override for forks/mirrors.
: "${SOLANA_SUPERCHARGERS_BASE_URL:=https://raw.githubusercontent.com/srivtx/solana-superchargers/main}"
INSTALLER_URL="${SOLANA_SUPERCHARGERS_BASE_URL}/install.sh"

# What the user actually wanted to do
cmd="${1:-add}"
shift || true

# Some commands we handle ourselves (no installer needed)
case "$cmd" in
  help|--help|-h)
    cat <<EOF
${SKILL_NAME} — per-skill installer

Curated one-liner for THIS skill:

  curl -fsSL ${BASE_URL:-${INSTALLER_URL%/*}}/solana-indexer-skill/install.sh | bash

That downloads this script and installs the ${SKILL_NAME} skill into
Claude Code and Codex. Equivalent to the multi-skill manager's
  ./install.sh add ${SKILL_NAME}

Commands (when running standalone):
  install.sh                Install this skill (default)
  install.sh add            (same, explicit)
  install.sh remove         Uninstall this skill
  install.sh help           Show this message
EOF
    exit 0
    ;;
esac

# Fetch the multi-skill installer
echo "→ fetching solana-superchargers installer from ${INSTALLER_URL}"
if ! curl -fsSL "$INSTALLER_URL" -o "$TEMP_INSTALLER"; then
  echo "✗ failed to download installer from $INSTALLER_URL" >&2
  exit 1
fi
chmod +x "$TEMP_INSTALLER"
trap 'rm -f "$TEMP_INSTALLER"' EXIT

# Delegate the actual install/uninstall to the real installer
echo "→ delegating to multi-skill installer"
exec "$TEMP_INSTALLER" "$cmd" "$SKILL_NAME" "$@"
