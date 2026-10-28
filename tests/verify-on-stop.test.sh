#!/usr/bin/env bash
# Tests for kit/.claude/hooks/verify-on-stop.sh (Stop hook that enforces the quality gate).
set -u
source "$(dirname "$0")/lib.sh"

HOOK="$KIT/.claude/hooks/verify-on-stop.sh"

# A fake check command: exits with the code stored in $STATE/result and logs each call.
STATE="$(make_tmp)"
FAKE_CHECK="$STATE/fake-check.sh"
cat > "$FAKE_CHECK" <<EOF
#!/usr/bin/env bash
echo call >> "$STATE/calls"
echo "FAIL_MARKER line from the check"
exit "\$(cat "$STATE/result")"
EOF
chmod +x "$FAKE_CHECK"

set_result() { printf '%s' "$1" > "$STATE/result"; }
calls() { [ -f "$STATE/calls" ] && wc -l < "$STATE/calls" | tr -d ' ' || echo 0; }
reset_calls() { rm -f "$STATE/calls"; }

# run_hook <repo> [extra env assignments...] → sets HOOK_EXIT, HOOK_OUT, HOOK_ERR
run_hook() {
  local repo="$1"; shift
  HOOK_ERR="$(printf '{"stop_hook_active": false}' \
    | env CLAUDE_PROJECT_DIR="$repo" SDLC_CHECK_CMD="$FAKE_CHECK" "$@" bash "$HOOK" 2>&1 >"$STATE/stdout")"
  HOOK_EXIT=$?
  HOOK_OUT="$(cat "$STATE/stdout")"
}

repo="$(make_repo)"

echo "verify-on-stop: a clean tree with no history is trusted without running checks"
set_result 1; reset_calls
run_hook "$repo"
assert_eq "exits 0 on clean tree" 0 "$HOOK_EXIT"
assert_eq "check not called" 0 "$(calls)"

echo "verify-on-stop: changes trigger the check; green lets Claude stop"
printf 'change\n' >> "$repo/README.md"
set_result 0; reset_calls
run_hook "$repo"
assert_eq "exits 0 when check passes" 0 "$HOOK_EXIT"
assert_eq "check called once" 1 "$(calls)"

echo "verify-on-stop: an already verified state is not re-checked"
reset_calls
run_hook "$repo"
assert_eq "exits 0" 0 "$HOOK_EXIT"
assert_eq "check not called again" 0 "$(calls)"

echo "verify-on-stop: a red check blocks stopping and feeds the output back"
printf 'broken\n' > "$repo/new-file.txt"
set_result 1; reset_calls
run_hook "$repo"
assert_eq "exits 2 to keep Claude working" 2 "$HOOK_EXIT"
assert_contains "failure output reaches Claude" "FAIL_MARKER" "$HOOK_ERR"

echo "verify-on-stop: after 3 blocked attempts Claude may stop, with a warning"
run_hook "$repo"; run_hook "$repo"
assert_eq "third attempt still blocks" 2 "$HOOK_EXIT"
run_hook "$repo"
assert_eq "fourth attempt lets Claude stop" 0 "$HOOK_EXIT"
assert_contains "warns the user the gate is red" "systemMessage" "$HOOK_OUT"
run_hook "$repo"
assert_eq "counter resets, next stop blocks again" 2 "$HOOK_EXIT"

echo "verify-on-stop: content edits to untracked files are detected"
set_result 0; run_hook "$repo"
printf 'edited\n' >> "$repo/new-file.txt"
set_result 1; reset_calls
run_hook "$repo"
assert_eq "edit to untracked file re-runs the check" 1 "$(calls)"

echo "verify-on-stop: a new commit counts as an unverified change"
set_result 0; run_hook "$repo"
git -C "$repo" add -A && git -C "$repo" commit -q -m "feat: change"
reset_calls; run_hook "$repo"
assert_eq "commit triggers the check" 1 "$(calls)"

echo "verify-on-stop: unconfigured checks warn but never block"
printf 'more\n' >> "$repo/README.md"
set_result 3
run_hook "$repo"
assert_eq "exit 3 from check does not block" 0 "$HOOK_EXIT"
assert_contains "warns about missing checks" "systemMessage" "$HOOK_OUT"

echo "verify-on-stop: a missing check script warns instead of blocking"
printf 'again\n' >> "$repo/README.md"
run_hook "$repo" SDLC_CHECK_CMD="$STATE/does-not-exist.sh"
assert_eq "missing check script does not block" 0 "$HOOK_EXIT"
assert_contains "warns that the gate is missing" "systemMessage" "$HOOK_OUT"

echo "verify-on-stop: opt-out and non-repo cases"
set_result 1; reset_calls
run_hook "$repo" SDLC_SKIP_VERIFY=1
assert_eq "SDLC_SKIP_VERIFY=1 skips the gate" 0 "$HOOK_EXIT"
assert_eq "check not called when skipped" 0 "$(calls)"
plain="$(make_tmp)"
run_hook "$plain"
assert_eq "outside a git repo the hook is a no-op" 0 "$HOOK_EXIT"

finish
