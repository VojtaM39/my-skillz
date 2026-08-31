#!/usr/bin/env bash
#
# Symlink skills from this repo into a Claude Code skills directory.
#
#   ./install.sh                     # all skills -> ~/.claude/skills
#   ./install.sh scope-creep         # one skill  -> ~/.claude/skills
#   ./install.sh --project           # all skills -> ./.claude/skills
#   ./install.sh --project ~/repo    # all skills -> ~/repo/.claude/skills
#   ./install.sh --list
#   ./install.sh --uninstall
#   ./install.sh --dry-run           # print what would happen
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_DIR/skills"

TARGET="$HOME/.claude/skills"
TARGET_LABEL="global"
DRY_RUN=false
UNINSTALL=false
SELECTED=()

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
run() { if $DRY_RUN; then printf '  would: %s\n' "$*"; else "$@"; fi; }

all_skills() {
    local dir
    for dir in "$SKILLS_DIR"/*/; do
        [ -f "$dir/SKILL.md" ] || continue
        basename "$dir"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --project|-p)
            # Optional path argument; defaults to cwd.
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ] && [ -d "$2" ]; then
                TARGET="$(cd "$2" && pwd)/.claude/skills"; shift
            else
                TARGET="$(pwd)/.claude/skills"
            fi
            TARGET_LABEL="project"
            ;;
        --list|-l)
            printf 'Skills in %s:\n' "$SKILLS_DIR"
            for skill in $(all_skills); do
                desc=$(sed -n 's/^description: //p' "$SKILLS_DIR/$skill/SKILL.md" | head -c 100)
                printf '  %-14s %s...\n' "$skill" "$desc"
            done
            exit 0
            ;;
        --uninstall|-u) UNINSTALL=true ;;
        --dry-run|-n)   DRY_RUN=true ;;
        --help|-h)      awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
        -*)             die "unknown flag: $1 (try --help)" ;;
        *)              SELECTED+=("$1") ;;
    esac
    shift
done

[ -d "$SKILLS_DIR" ] || die "no skills/ directory at $SKILLS_DIR"

if [ ${#SELECTED[@]} -eq 0 ]; then
    SELECTED=($(all_skills))
    [ ${#SELECTED[@]} -gt 0 ] || die "no skills found in $SKILLS_DIR"
else
    for skill in "${SELECTED[@]}"; do
        [ -f "$SKILLS_DIR/$skill/SKILL.md" ] || die "no such skill: $skill (try --list)"
    done
fi

if $UNINSTALL; then
    printf 'Removing from %s (%s)\n' "$TARGET" "$TARGET_LABEL"
    removed=0
    for skill in "${SELECTED[@]}"; do
        link="$TARGET/$skill"
        if [ ! -L "$link" ]; then
            [ -e "$link" ] && printf '  skip     %s (not a symlink — leaving it alone)\n' "$skill"
            continue
        fi
        # Only remove links that point back into this repo.
        case "$(cd "$(dirname "$link")" && cd "$(readlink "$link")" 2>/dev/null && pwd)" in
            "$SKILLS_DIR"/*) run rm "$link"; printf '  removed  %s\n' "$skill"; removed=$((removed+1)) ;;
            *) printf '  skip     %s (points outside this repo)\n' "$skill" ;;
        esac
    done
    printf '\n%d removed.\n' "$removed"
    exit 0
fi

printf 'Installing %d skill(s) into %s (%s)\n' "${#SELECTED[@]}" "$TARGET" "$TARGET_LABEL"
run mkdir -p "$TARGET"

for skill in "${SELECTED[@]}"; do
    link="$TARGET/$skill"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        printf '  SKIP     %s — a real directory already exists there, not overwriting\n' "$skill"
        continue
    fi
    run ln -sfn "$SKILLS_DIR/$skill" "$link"
    printf '  linked   %s\n' "$skill"
done

printf '\nDone. Invoke with /<skill-name> — restart Claude Code or open a new session to pick them up.\n'
printf 'Symlinked, so edits in %s take effect with no re-install.\n' "$SKILLS_DIR"
