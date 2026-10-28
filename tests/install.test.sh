#!/usr/bin/env bash
# Tests for install.sh (copies the kit into a target repo without clobbering user files).
set -u
source "$(dirname "$0")/lib.sh"

INSTALL="$ROOT/install.sh"

run_install() {
  INSTALL_OUT="$(bash "$INSTALL" "$@" 2>&1)"
  INSTALL_EXIT=$?
}

echo "install: rejects bad targets"
run_install
assert_eq "no argument prints usage" 64 "$INSTALL_EXIT"
run_install /nonexistent/path
assert_eq "missing directory fails" 1 "$INSTALL_EXIT"
plain="$(make_tmp)"
run_install "$plain"
assert_eq "non-git directory fails" 1 "$INSTALL_EXIT"
assert_contains "explains git is required" "git" "$INSTALL_OUT"

echo "install: fresh repo receives the whole kit"
repo="$(make_repo)"
run_install "$repo"
assert_eq "exit 0" 0 "$INSTALL_EXIT"
missing=""
while IFS= read -r -d '' src; do
  rel="${src#"$KIT"/}"
  [ -f "$repo/$rel" ] || missing="$missing $rel"
done < <(find "$KIT" -type f -print0)
assert_eq "every kit file is installed" "" "$missing"
[ -x "$repo/.claude/hooks/guard.sh" ] && [ -x "$repo/scripts/check.sh" ]
assert_eq "scripts are executable" 0 $?
assert_contains ".gitignore ignores backups" ".sdlc-backup/" "$(cat "$repo/.gitignore")"
assert_contains ".gitattributes keeps LF for scripts" "*.sh text eol=lf" "$(cat "$repo/.gitattributes")"

echo "install: existing .gitignore lines are kept and not duplicated"
repo_gi="$(make_repo)"
printf 'node_modules/\n.env' > "$repo_gi/.gitignore"
run_install "$repo_gi"
gi="$(cat "$repo_gi/.gitignore")"
assert_contains "user line kept" "node_modules/" "$gi"
assert_eq "shared line not duplicated" 1 "$(grep -cx '.env' "$repo_gi/.gitignore")"
assert_contains "missing kit line appended" ".sdlc-backup/" "$gi"
jq -e . "$repo/.claude/settings.json" >/dev/null
assert_eq "settings.json is valid JSON" 0 $?

echo "install: re-running is idempotent"
snapshot="$(cd "$repo" && find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)"
run_install "$repo"
assert_eq "second run exits 0" 0 "$INSTALL_EXIT"
assert_eq "second run changes nothing" "$snapshot" \
  "$(cd "$repo" && find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)"

echo "install: an existing CLAUDE.md is kept and imports the rules once"
repo2="$(make_repo)"
printf '# My project\n\nOwn notes.\n' > "$repo2/CLAUDE.md"
run_install "$repo2"; run_install "$repo2"
assert_contains "user content kept" "Own notes." "$(cat "$repo2/CLAUDE.md")"
assert_eq "rules import appended exactly once" 1 "$(grep -c '^@.claude/sdlc/RULES.md$' "$repo2/CLAUDE.md")"

echo "install: an existing settings.json is merged, user entries win"
mkdir -p "$repo2/.claude"
cat > "$repo2/.claude/settings.json" <<'EOF'
{
  "model": "custom-model",
  "permissions": { "allow": ["Bash(make:*)"], "deny": ["Bash(git push --force:*)"] },
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo mine" } ] } ] }
}
EOF
run_install "$repo2"; run_install "$repo2"
merged="$repo2/.claude/settings.json"
assert_eq "user key kept" "custom-model" "$(jq -r .model "$merged")"
assert_eq "user allow kept" "true" "$(jq '.permissions.allow | index("Bash(make:*)") != null' "$merged")"
assert_eq "kit allow added" "true" "$(jq '.permissions.allow | index("Bash(./scripts/check.sh:*)") != null' "$merged")"
assert_eq "deny entries not duplicated" 1 "$(jq '[.permissions.deny[] | select(. == "Bash(git push --force:*)")] | length' "$merged")"
assert_eq "user Stop hook kept" "true" "$(jq '[.hooks.Stop[].hooks[].command] | index("echo mine") != null' "$merged")"
assert_eq "kit Stop hook added once" 1 "$(jq '[.hooks.Stop[].hooks[].command | select(test("verify-on-stop"))] | length' "$merged")"
assert_eq "kit PreToolUse hook added" 1 "$(jq '[.hooks.PreToolUse[].hooks[].command | select(test("guard"))] | length' "$merged")"

sleep 1; run_install "$repo2"  # a later run gets a new backup timestamp
assert_eq "merge backed up the original settings once" 1 \
  "$(find "$repo2/.sdlc-backup" -name settings.json -type f | wc -l | tr -d ' ')"

echo "install: differing files are kept unless --force, which backs them up"
repo3="$(make_repo)"
mkdir -p "$repo3/scripts"
printf '#!/usr/bin/env bash\necho custom\n' > "$repo3/scripts/check.sh"
run_install "$repo3"
assert_contains "custom check.sh kept" "echo custom" "$(cat "$repo3/scripts/check.sh")"
assert_contains "reports the kept file" "scripts/check.sh" "$INSTALL_OUT"
run_install "$repo3" --force
assert_not_contains "--force replaces the file" "echo custom" "$(cat "$repo3/scripts/check.sh")"
backup="$(find "$repo3/.sdlc-backup" -name check.sh -type f | head -n 1)"
assert_contains "--force keeps a backup" "echo custom" "$(cat "$backup" 2>/dev/null)"

finish
