#!/usr/bin/env bash
# Tests for kit/scripts/fix-loop.sh (deterministic check → Claude fix → re-check loop).
set -u
source "$(dirname "$0")/lib.sh"

LOOP="$KIT/scripts/fix-loop.sh"
STATE="$(make_tmp)"

# Fake check: fails while $STATE/remaining > 0; exits $STATE/code_override if present.
FAKE_CHECK="$STATE/check.sh"
cat > "$FAKE_CHECK" <<EOF
#!/usr/bin/env bash
[ -f "$STATE/code_override" ] && exit "\$(cat "$STATE/code_override")"
remaining=\$(cat "$STATE/remaining")
if [ "\$remaining" -gt 0 ]; then echo "FAIL_MARKER \$remaining failing"; exit 1; fi
echo "all green"
EOF

# Fake claude: records its prompt; "fixes" one failure and edits a file unless told to idle.
FAKE_CLAUDE="$STATE/claude.sh"
cat > "$FAKE_CLAUDE" <<EOF
#!/usr/bin/env bash
echo call >> "$STATE/claude_calls"
printf '%s\n' "\$@" > "$STATE/claude_args"
[ -f "$STATE/idle" ] && exit 0
echo "edit \$RANDOM" >> "\$PWD/work.txt"
remaining=\$(cat "$STATE/remaining")
fixed=\$(cat "$STATE/fix_per_round")
echo \$((remaining - fixed)) > "$STATE/remaining"
EOF
chmod +x "$FAKE_CHECK" "$FAKE_CLAUDE"

setup() { # <remaining failures> <fixed per claude round>
  rm -f "$STATE/claude_calls" "$STATE/idle" "$STATE/code_override" "$STATE/claude_args"
  echo "$1" > "$STATE/remaining"
  echo "$2" > "$STATE/fix_per_round"
}
claude_calls() { [ -f "$STATE/claude_calls" ] && wc -l < "$STATE/claude_calls" | tr -d ' ' || echo 0; }

repo="$(make_repo)"
run_loop() {
  LOOP_OUT="$(cd "$repo" && env SDLC_CHECK_CMD="$FAKE_CHECK" SDLC_CLAUDE_CMD="$FAKE_CLAUDE" "$@" bash "$LOOP" 2>&1)"
  LOOP_EXIT=$?
}

echo "fix-loop: already green means Claude is never called"
setup 0 1; run_loop
assert_eq "exit 0" 0 "$LOOP_EXIT"
assert_eq "no Claude call" 0 "$(claude_calls)"

echo "fix-loop: red then fixed in one round"
setup 1 1; run_loop
assert_eq "exit 0 once green" 0 "$LOOP_EXIT"
assert_eq "one Claude call" 1 "$(claude_calls)"
assert_contains "prompt includes the real failure output" "FAIL_MARKER" "$(cat "$STATE/claude_args")"
assert_contains "prompt forbids weakening tests" "test" "$(cat "$STATE/claude_args")"

echo "fix-loop: gives up after the round limit"
setup 5 1; run_loop SDLC_FIX_ROUNDS=2
assert_eq "exit 1 when still red" 1 "$LOOP_EXIT"
assert_eq "exactly 2 Claude calls" 2 "$(claude_calls)"
assert_contains "reports it is still red" "still red" "$LOOP_OUT"

echo "fix-loop: stops when a round changes nothing"
setup 3 1; touch "$STATE/idle"; run_loop
assert_eq "exit 2 when stalled" 2 "$LOOP_EXIT"
assert_eq "stops after the idle round" 1 "$(claude_calls)"

echo "fix-loop: missing prerequisites fail clearly"
setup 1 1; echo 3 > "$STATE/code_override"; run_loop
assert_eq "exit 3 when checks are not configured" 3 "$LOOP_EXIT"
setup 1 1; run_loop SDLC_CLAUDE_CMD=/nonexistent/claude
assert_eq "exit 4 when the claude CLI is missing" 4 "$LOOP_EXIT"
plain="$(make_tmp)"
LOOP_OUT="$(cd "$plain" && SDLC_CHECK_CMD="$FAKE_CHECK" SDLC_CLAUDE_CMD="$FAKE_CLAUDE" bash "$LOOP" 2>&1)"
assert_eq "exit 4 outside a git repo" 4 $?

finish
