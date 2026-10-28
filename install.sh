#!/usr/bin/env bash
# Installs the SDLC kit into a target git repository.
#
# Usage: ./install.sh <target-repo> [--force]
#   Files that already exist and differ are kept, unless --force (then backed up first).
#   CLAUDE.md gets one import line; .claude/settings.json is merged (your entries win);
#   .gitignore and .gitattributes get the missing lines appended. Safe to re-run.
set -u

USAGE=64
KIT="$(cd "$(dirname "$0")" && pwd)/kit"
RULES_IMPORT="@.claude/sdlc/RULES.md"

target="${1:-}"
force=0
[ "${2:-}" = "--force" ] && force=1
if [ -z "$target" ] || [ "$target" = "-h" ] || [ "$target" = "--help" ]; then
  echo "Usage: ./install.sh <target-repo> [--force]" >&2
  exit "$USAGE"
fi
[ -d "$target" ] || { echo "install: '$target' is not a directory." >&2; exit 1; }
target="$(cd "$target" && pwd)"
git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "install: '$target' is not a git repository. Run 'git init' there first." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 \
  || { echo "install: python3 is required to merge .claude/settings.json." >&2; exit 1; }

backup_root="$target/.sdlc-backup/$(date +%Y%m%d-%H%M%S)"
written=(); kept=(); merged=()

backup() { # backup <relative path>
  mkdir -p "$(dirname "$backup_root/$1")"
  cp -p "$target/$1" "$backup_root/$1"
}

install_file() { # install_file <relative path>
  local rel="$1" src="$KIT/$1" dst="$target/$1"
  if [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"; written+=("$rel")
  elif cmp -s "$src" "$dst"; then
    :
  elif [ "$force" -eq 1 ]; then
    backup "$rel"; cp -p "$src" "$dst"; written+=("$rel (old copy in .sdlc-backup/)")
  else
    kept+=("$rel")
  fi
}

merge_claude_md() {
  local dst="$target/CLAUDE.md"
  if [ ! -e "$dst" ]; then install_file CLAUDE.md; return; fi
  grep -qxF "$RULES_IMPORT" "$dst" && return
  backup CLAUDE.md
  printf '\n## Quy trình làm việc\n%s\n' "$RULES_IMPORT" >> "$dst"
  merged+=("CLAUDE.md (added $RULES_IMPORT)")
}

merge_lines() { # merge_lines <relative path>: append the kit's lines that are missing
  local rel="$1" dst="$target/$1" line added=0
  touch "$dst"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if ! grep -qxF "$line" "$dst"; then
      [ -s "$dst" ] && [ -n "$(tail -c 1 "$dst")" ] && printf '\n' >> "$dst"
      printf '%s\n' "$line" >> "$dst"; added=1
    fi
  done < "$KIT/$rel"
  [ "$added" -eq 1 ] && merged+=("$rel")
}

merge_settings() {
  local rel=".claude/settings.json"
  if [ ! -e "$target/$rel" ]; then install_file "$rel"; return; fi
  local result
  result="$(python3 -I -c "$MERGE_SETTINGS_PY" "$KIT/$rel" "$target/$rel")" \
    || { echo "install: could not merge $rel (is it valid JSON?)." >&2; exit 1; }
  [ -z "$result" ] && return
  backup "$rel"
  printf '%s\n' "$result" > "$target/$rel"
  merged+=("$rel (your entries kept)")
}

# Prints the merged settings (user entries win, kit entries added), or nothing if unchanged.
MERGE_SETTINGS_PY="$(cat <<'PY'
import json, sys

kit_path, user_path = sys.argv[1], sys.argv[2]
kit = json.load(open(kit_path))
user = json.load(open(user_path))
merged = json.loads(json.dumps(user))

for key, value in kit.items():
    if key not in ("permissions", "hooks", "enabledPlugins"):
        merged.setdefault(key, value)

for key in ("enabledPlugins",):
    target = merged.setdefault(key, {})
    for name, enabled in kit.get(key, {}).items():
        target.setdefault(name, enabled)

perms = merged.setdefault("permissions", {})
for kind, rules in kit.get("permissions", {}).items():
    existing = perms.setdefault(kind, [])
    existing.extend(rule for rule in rules if rule not in existing)

def commands(groups):
    return {h.get("command") for g in groups for h in g.get("hooks", [])}

hooks = merged.setdefault("hooks", {})
for event, groups in kit.get("hooks", {}).items():
    existing = hooks.setdefault(event, [])
    present = commands(existing)
    existing.extend(g for g in groups if not commands([g]) <= present)

if merged != user:
    print(json.dumps(merged, indent=2, ensure_ascii=False))
PY
)"

while IFS= read -r -d '' src; do
  rel="${src#"$KIT"/}"
  case "$rel" in
    CLAUDE.md) merge_claude_md ;;
    .gitignore|.gitattributes) merge_lines "$rel" ;;
    .claude/settings.json) merge_settings ;;
    *) install_file "$rel" ;;
  esac
done < <(find "$KIT" -type f -print0 | sort -z)

find "$target/.claude/hooks" "$target/scripts" -name '*.sh' -type f -exec chmod +x {} + 2>/dev/null

# Drop the backup folder if this run did not need it.
rmdir "$backup_root" 2>/dev/null; rmdir "$target/.sdlc-backup" 2>/dev/null

echo "SDLC kit -> $target"
for f in ${written[@]+"${written[@]}"}; do echo "  + $f"; done
for f in ${merged[@]+"${merged[@]}"}; do echo "  ~ $f"; done
for f in ${kept[@]+"${kept[@]}"}; do echo "  = kept your $f (differs from the kit; re-run with --force to replace)"; done
[ "${#written[@]}" -eq 0 ] && [ "${#merged[@]}" -eq 0 ] && echo "  (nothing to change)"

cat <<'EOF'

Next steps:
  1. Fill in the project section of CLAUDE.md.
  2. Make ./scripts/check.sh run your lint/typecheck/test/build, then run it once.
  3. Review and commit on a branch: git switch -c chore/sdlc-kit && git add -A && git commit
  4. On GitHub: add the ANTHROPIC_API_KEY secret (or run /install-github-app in Claude Code),
     create a "claude" label, and protect main (require PR + the CI "check" status).
EOF
