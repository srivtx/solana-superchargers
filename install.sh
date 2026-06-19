#!/usr/bin/env bash
#
# install.sh — solana-superchargers skill manager
#
# Multi-skill installer. Each subdirectory at the repo root is a self-contained
# skill. install.sh knows about all of them via SKILLS.md.
#
# Usage:
#   ./install.sh add <skill> [...]         Install one or more skills
#   ./install.sh add all                  Install every skill
#   ./install.sh add category:<cat>       Install every skill in a category
#   ./install.sh add preset:<preset>      Install a preset bundle
#   ./install.sh remove <skill> [...]     Uninstall one or more skills
#   ./install.sh remove --all             Uninstall every supercharger skill
#   ./install.sh list                     List all skills with install status
#   ./install.sh presets                  List all preset bundles
#   ./install.sh categories               List all categories
#   ./install.sh info <skill>             Show details for one skill
#   ./install.sh verify                   Check installed skills are valid
#   ./install.sh help                     Show usage
#
# Per the SKILL.md format used by Claude Code / Codex. Each skill gets
# installed to ~/.claude/skills/<name>/ and ~/.codex/skills/<name>/ (if
# codex is detected). Existing installs are overwritten.

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SKILLS_INDEX="${SCRIPT_DIR}/SKILLS.md"
BRANCH="${SUPERCHARGER_BRANCH:-main}"

# Where skills live. Override with CLAUDE_SKILLS_HOME=/path ./install.sh
: "${CLAUDE_SKILLS_HOME:=$HOME/.claude/skills}"
CODEX_SKILLS_HOME="${CODEX_SKILLS_HOME:-$HOME/.codex/skills}"
INSTALL_DIR="$CLAUDE_SKILLS_HOME"

# ── color helpers ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_GREEN=; C_YELLOW=; C_RED=; C_CYAN=; C_BLUE=
fi

ok()   { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn() { printf "  ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
err()  { printf "  ${C_RED}✗${C_RESET} %s\n" "$*" >&2; }
head() { printf "\n${C_BOLD}${C_CYAN}── %s ──${C_RESET}\n" "$*"; }

# ── SKILLS.md parser ──────────────────────────────────────────────────
# Parses our SKILLS.md index. Format:
#   ## <category>
#   - [name](path) — description
#   ## Presets
#   - <preset-name>: skill1, skill2, skill3
parse_skills_md() {
  python3 - "$SKILLS_INDEX" <<'PYEOF'
import sys, re
path = sys.argv[1]
try:
    content = open(path).read()
except FileNotFoundError:
    sys.exit(0)

# Strip code blocks (``` ... ```) and inline code (` ... `) so the example
# format at the top of SKILLS.md doesn't get parsed as a real entry.
content = re.sub(r'```[\s\S]*?```', '', content)
content = re.sub(r'`[^`\n]*`', '', content)

current_section = ""
presets = {}
skills = {}

for line in content.splitlines():
    s = line.strip()
    if s.startswith("## "):
        name = s[3:].strip()
        if name.lower() == "presets":
            current_section = "_preset"
        else:
            current_section = name
    elif current_section == "_preset" and s.startswith("- "):
        m = re.match(r"-\s+([\w-]+):\s*(.*)", s)
        if m:
            preset, list_ = m.group(1), m.group(2)
            presets[preset] = [x.strip() for x in list_.split(",") if x.strip()]
    elif s.startswith("- ") and current_section and current_section != "_preset":
        m = re.match(r"-\s+\[([\w-]+)\]\(([^)]+)\)\s*[—–-]\s*(.*)", s)
        if m:
            name, p, desc = m.group(1), m.group(2), m.group(3)
            skills[name] = {"path": p, "description": desc, "category": current_section}

for name, info in sorted(skills.items()):
    print(f"SKILL\t{name}\t{info['path']}\t{info['category']}\t{info['description']}")
for name, list_ in sorted(presets.items()):
    print(f"PRESET\t{name}\t{','.join(list_)}")
PYEOF
}

# ── core ops ──────────────────────────────────────────────────────────
discover_skills() {
  parse_skills_md
}

list_skills() {
  head "Available skills"
  local skills
  skills=$(discover_skills)
  if [[ -z "$skills" ]]; then
    warn "no skills found in SKILLS.md"
    return
  fi
  local current_cat=""
  while IFS= read -r line; do
    [[ "$line" =~ ^SKILL ]] || continue
    local name path cat desc
    name=$(echo "$line"  | cut -f2)
    path=$(echo "$line" | cut -f3)
    cat=$(echo "$line"  | cut -f4)
    desc=$(echo "$line" | cut -f5-)
    if [[ "$cat" != "$current_cat" ]]; then
      printf "\n  ${C_BOLD}%s${C_RESET}\n" "$cat"
      current_cat="$cat"
    fi
    local status
    if [[ -d "${INSTALL_DIR}/$name" ]] && [[ -f "${INSTALL_DIR}/$name/skill/SKILL.md" ]]; then
      status="${C_GREEN}installed${C_RESET}"
    else
      status="${C_DIM}not installed${C_RESET}"
    fi
    printf "    ${C_BOLD}%-22s${C_RESET}  %-50s  [%b]\n" "$name" "$desc" "$status"
  done <<< "$skills"
}

list_presets() {
  head "Presets"
  local presets
  presets=$(discover_skills | grep "^PRESET")
  if [[ -z "$presets" ]]; then
    warn "no presets defined"
    return
  fi
  while IFS=$'\t' read -r kind pname list_; do
    [[ "$kind" == "PRESET" ]] || continue
    IFS=',' read -ra arr <<< "$list_"
    printf "\n  ${C_BOLD}%s${C_RESET}  ${C_DIM}(%d skills)${C_RESET}\n" "$pname" "${#arr[@]}"
    for s in "${arr[@]}"; do
      printf "    · %s\n" "$s"
    done
  done <<< "$presets"
  printf "\n  ${C_DIM}install with: ./install.sh add preset:<name>${C_RESET}\n"
}

list_categories() {
  head "Categories"
  local cats
  cats=$(discover_skills | grep "^SKILL" | awk -F'\t' '{print $4}' | sort -u)
  if [[ -z "$cats" ]]; then
    warn "no skills found"
    return
  fi
  while read -r cat; do
    [[ -n "$cat" ]] || continue
    local count
    count=$(discover_skills | grep "^SKILL" | awk -F'\t' -v c="$cat" '$4==c' | wc -l | tr -d ' ')
    printf "  ${C_BOLD}%-20s${C_RESET}  %d skills\n" "$cat" "$count"
  done <<< "$cats"
}

show_info() {
  local target="$1"
  head "Info: $target"
  local found
  found=$(discover_skills | grep -E "^(SKILL|PRESET)\t$target\t")
  if [[ -z "$found" ]]; then
    err "not found: $target"
    return 1
  fi
  local kind name rest
  kind=$(echo "$found" | cut -f1)
  name=$(echo "$found" | cut -f2)
  if [[ "$kind" == "SKILL" ]]; then
    # Fields: SKILL\t<name>\t<path>\t<category>\t<description>
    local path cat desc
    IFS=$'\t' read -r kind p path cat desc <<< "$found"
    printf "  ${C_BOLD}name${C_RESET}        %s\n" "$name"
    printf "  ${C_BOLD}category${C_RESET}    %s\n" "$cat"
    printf "  ${C_BOLD}path${C_RESET}        %s\n" "$path"
    printf "  ${C_BOLD}description${C_RESET} %s\n" "$desc"
    if [[ -d "${SCRIPT_DIR}/$path" ]]; then
      local ref_count ex_count
      ref_count=$(find "${SCRIPT_DIR}/$path/skill/references" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
      ex_count=$(find "${SCRIPT_DIR}/$path/skill/examples" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      printf "  ${C_BOLD}references${C_RESET}   %s\n" "$ref_count"
      printf "  ${C_BOLD}examples${C_RESET}     %s\n" "$ex_count"
    fi
  else
    # Preset. Fields: PRESET\t<name>\t<list>
    local list_
    IFS=$'\t' read -r kind p list_ <<< "$found"
    printf "  ${C_BOLD}preset${C_RESET}       %s\n" "$name"
    printf "  ${C_BOLD}skills${C_RESET}       %s\n" "$list_"
  fi
}

install_skill() {
  local skill_name="$1"
  local found
  found=$(discover_skills | grep "^SKILL	${skill_name}	" || true)
  if [[ -z "$found" ]]; then
    err "unknown skill: $skill_name"
    return 1
  fi
  local path
  path=$(echo "$found" | cut -f3)
  local src="${SCRIPT_DIR}/$path"
  if [[ ! -d "$src" ]]; then
    err "source not found: $src"
    return 1
  fi
  if [[ ! -f "$src/skill/SKILL.md" ]]; then
    err "not a valid skill (no skill/SKILL.md): $path"
    return 1
  fi
  local dest="${INSTALL_DIR}/$skill_name"
  mkdir -p "$dest"
  rsync -a --delete \
    --exclude='install.sh' \
    --exclude='.git' \
    --exclude='**/node_modules' \
    --exclude='**/target' \
    --exclude='**/.DS_Store' \
    --exclude='**/dist' \
    "$src/" "$dest/"
  ok "installed $skill_name → $dest"
  if command -v codex &> /dev/null; then
    local codex_dest="${CODEX_SKILLS_HOME}/$skill_name"
    mkdir -p "$codex_dest"
    rsync -a --delete \
      --exclude='install.sh' \
      --exclude='.git' \
      --exclude='**/node_modules' \
      --exclude='**/target' \
      --exclude='**/.DS_Store' \
      --exclude='**/dist' \
      "$src/" "$codex_dest/"
    ok "mirrored to $codex_dest"
  fi
  return 0
}

remove_skill() {
  local skill_name="$1"
  if [[ ! -d "${INSTALL_DIR}/$skill_name" ]]; then
    warn "$skill_name is not installed"
    return 0
  fi
  rm -rf "${INSTALL_DIR}/$skill_name"
  ok "removed $skill_name"
  if [[ -d "${CODEX_SKILLS_HOME}/$skill_name" ]]; then
    rm -rf "${CODEX_SKILLS_HOME}/$skill_name"
    ok "removed from codex"
  fi
}

verify_install() {
  head "Verify"
  local skills
  skills=$(discover_skills | grep "^SKILL")
  if [[ -z "$skills" ]]; then
    warn "no skills found"
    return 1
  fi
  local total
  total=$(echo "$skills" | awk '/^SKILL/{c++} END{print c+0}')
  while read -r line; do
    [[ "$line" =~ ^SKILL ]] || continue
    local name
    name=$(echo "$line" | cut -f2)
    if [[ -d "${INSTALL_DIR}/$name" ]] && [[ -f "${INSTALL_DIR}/$name/skill/SKILL.md" ]]; then
      ok "$name"
    else
      warn "$name (not installed)"
    fi
  done <<< "$skills"
  local inst=0
  while read -r line; do
    [[ "$line" =~ ^SKILL ]] || continue
    local n
    n=$(echo "$line" | cut -f2)
    if [[ -d "${INSTALL_DIR}/$n" ]] && [[ -f "${INSTALL_DIR}/$n/skill/SKILL.md" ]]; then
      inst=$((inst + 1))
    fi
  done <<< "$skills"
  echo ""
  printf "  ${C_BOLD}%d / %d${C_RESET} skills installed at %s\n" "$inst" "$total" "$INSTALL_DIR"
}

cmd_add() {
  head "Add"
  local targets=("$@")
  if [[ ${#targets[@]} -eq 0 ]]; then
    err "no targets specified. use: add <skill|preset|category|all> [...]"
    return 1
  fi

  # Resolve "all" → every skill
  if [[ "${targets[*]}" == "all" ]]; then
    targets=($(discover_skills | grep "^SKILL" | cut -f2))
  fi

  local failed=0
  for target in "${targets[@]}"; do
    # preset:<name>
    if [[ "$target" == preset:* ]]; then
      local preset="${target#preset:}"
      local list_
      list_=$(discover_skills | grep "^PRESET	${preset}	" | cut -f3)
      if [[ -z "$list_" ]]; then
        err "unknown preset: $preset"
        failed=$((failed+1))
        continue
      fi
      IFS=',' read -ra arr <<< "$list_"
      for s in "${arr[@]}"; do
        install_skill "$s" || failed=$((failed+1))
      done
    # category:<name>
    elif [[ "$target" == category:* ]]; then
      local cat="${target#category:}"
      local skills_in_cat
      skills_in_cat=$(discover_skills | grep "^SKILL	" | awk -F'\t' -v c="$cat" '$4==c {print $2}')
      if [[ -z "$skills_in_cat" ]]; then
        err "unknown category: $cat"
        failed=$((failed+1))
        continue
      fi
      for s in $skills_in_cat; do
        install_skill "$s" || failed=$((failed+1))
      done
    else
      install_skill "$target" || failed=$((failed+1))
    fi
  done

  if [[ $failed -eq 0 ]]; then
    head "Done"
    printf "${C_GREEN}All installs succeeded.${C_RESET}\n"
    printf "Restart ${C_BOLD}Claude Code${C_RESET} or ${C_BOLD}Codex${C_RESET} to pick up the skills.\n"
  else
    return 1
  fi
}

cmd_remove() {
  head "Remove"
  local targets=("$@")
  if [[ ${#targets[@]} -eq 0 ]]; then
    err "no targets specified. use: remove <skill|--all> [...]"
    return 1
  fi
  if [[ "${targets[*]}" == "--all" ]]; then
    if [[ -d "$INSTALL_DIR" ]]; then
      local skills
      skills=$(discover_skills | grep "^SKILL" | cut -f2)
      for s in $skills; do
        if [[ -d "${INSTALL_DIR}/$s" ]]; then
          remove_skill "$s"
        fi
      done
    fi
  else
    for target in "${targets[@]}"; do
      remove_skill "$target"
    done
  fi
  head "Done"
  printf "Restart ${C_BOLD}Claude Code${C_RESET} or ${C_BOLD}Codex${C_RESET} to apply changes.\n"
}

cmd_help() {
  cat <<EOF
${C_BOLD}solana-superchargers installer${C_RESET}

${C_BOLD}Usage:${C_RESET}
  ./install.sh <command> [args]

${C_BOLD}Commands:${C_RESET}
  ${C_CYAN}add${C_RESET} <skill|category:<name>|preset:<name>|all> [...]
                       Install one or more skills
  ${C_CYAN}remove${C_RESET} <skill|--all>
                       Uninstall one or more skills
  ${C_CYAN}list${C_RESET}                Show all available skills with install status
  ${C_CYAN}categories${C_RESET}          Show all categories
  ${C_CYAN}presets${C_RESET}             Show all preset bundles
  ${C_CYAN}info${C_RESET} <skill|preset> Show details for one target
  ${C_CYAN}verify${C_RESET}              Check installed skills are valid
  ${C_CYAN}help${C_RESET}                Show this message

${C_BOLD}Examples:${C_RESET}
  ./install.sh add solana-indexer
  ./install.sh add all
  ./install.sh add preset:core
  ./install.sh add category:defi
  ./install.sh list
  ./install.sh info solana-indexer
  ./install.sh verify
  ./install.sh remove solana-indexer
  CLAUDE_SKILLS_HOME=~/my/skills ./install.sh add all

${C_BOLD}Environment:${C_RESET}
  CLAUDE_SKILLS_HOME       Where skills install (default: ~/.claude/skills)
  CODEX_SKILLS_HOME         Where skills mirror for codex (default: ~/.codex/skills)
  SUPERCHARGER_BRANCH       Which git ref (default: main)
EOF
}

# ── entry point ──────────────────────────────────────────────────────
cmd="${1:-help}"
shift || true

case "$cmd" in
  add)         cmd_add "$@" ;;
  remove|rm)   cmd_remove "$@" ;;
  list|ls)     list_skills ;;
  categories)  list_categories ;;
  presets)     list_presets ;;
  info)        show_info "${1:-}" ;;
  verify)      verify_install ;;
  help|--help|-h)  cmd_help ;;
  *)
    err "unknown command: $cmd"
    cmd_help
    exit 1
    ;;
esac
