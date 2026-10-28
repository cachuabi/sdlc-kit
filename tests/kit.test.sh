#!/usr/bin/env bash
# Static checks over the kit: syntax, permissions and machine-readable config.
set -u
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

echo "kit: every shell script parses and has a bash shebang"
while IFS= read -r -d '' f; do
  rel="${f#"$ROOT"/}"
  bash -n "$f" 2>/dev/null
  assert_eq "syntax ok: $rel" 0 $?
  assert_eq "shebang: $rel" "#!/usr/bin/env bash" "$(head -n 1 "$f")"
done < <(find "$ROOT/kit" "$ROOT/install.sh" -name '*.sh' -type f -print0)

echo "kit: JSON config is valid"
jq -e . "$KIT/.claude/settings.json" >/dev/null
assert_eq "settings.json parses" 0 $?
assert_eq "hooks use the project dir variable" 0 \
  "$(jq '[.hooks[][].hooks[].command | select(test("CLAUDE_PROJECT_DIR") | not)] | length' "$KIT/.claude/settings.json")"

echo "kit: YAML config is valid"
if python3 -c 'import yaml' 2>/dev/null; then
  while IFS= read -r -d '' f; do
    python3 -I -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>/dev/null
    assert_eq "yaml parses: ${f#"$ROOT"/}" 0 $?
  done < <(find "$KIT/.github" -name '*.yml' -type f -print0)
else
  echo "  skip YAML parse (python3 yaml module not installed)"
fi

echo "kit: GitHub workflows pin the Claude action and avoid broad tokens"
for wf in claude.yml claude-review.yml; do
  body="$(cat "$KIT/.github/workflows/$wf")"
  assert_contains "$wf uses claude-code-action@v1" "anthropics/claude-code-action@v1" "$body"
  assert_contains "$wf has a timeout" "timeout-minutes" "$body"
  assert_not_contains "$wf never sets allowed_non_write_users" "allowed_non_write_users" "$body"
done

finish
