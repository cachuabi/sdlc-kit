#!/usr/bin/env bash
# Deterministic fix loop: run the quality gate, hand the real failure output to Claude,
# re-run the gate. The exit code of scripts/check.sh decides "green", never Claude's report.
#
# Usage: scripts/fix-loop.sh            (SDLC_FIX_ROUNDS=3 by default)
# Exit: 0 green · 1 still red after the round limit · 2 stalled (a round changed nothing)
#       3 no checks configured · 4 missing prerequisite (git repo, claude CLI)
set -u

ROUNDS="${SDLC_FIX_ROUNDS:-3}"
MAX_TURNS_PER_ROUND=40
OUTPUT_TAIL_LINES=120
NO_CHECKS=3
MISSING_PREREQ=4

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "fix-loop: run this inside a git repository." >&2
  exit "$MISSING_PREREQ"
}
cd "$root" || exit "$MISSING_PREREQ"
# shellcheck source=lib/git-state.sh
source "$(dirname "$0")/lib/git-state.sh"

check_cmd="${SDLC_CHECK_CMD:-$root/scripts/check.sh}"
claude_cmd="${SDLC_CLAUDE_CMD:-claude}"

run_check() {
  check_output="$(bash "$check_cmd" 2>&1)"
  check_code=$?
}

fix_prompt() {
  cat <<EOF
The project's quality gate (scripts/check.sh) is failing. Its output (last $OUTPUT_TAIL_LINES lines):

$(printf '%s\n' "$check_output" | tail -n "$OUTPUT_TAIL_LINES")

Fix the root causes in the code under test.
- Do not skip, delete or weaken tests to make them pass. If a test itself is wrong, fix it and say why.
- Touch only what the failures require. Do not commit, push or change unrelated files.
- Run ./scripts/check.sh yourself before you finish and report what you changed.
EOF
}

run_check
[ "$check_code" -eq 0 ] && { echo "fix-loop: already green."; exit 0; }
[ "$check_code" -eq "$NO_CHECKS" ] && { printf '%s\n' "$check_output" >&2; exit "$NO_CHECKS"; }

if ! command -v "$claude_cmd" >/dev/null 2>&1; then
  echo "fix-loop: '$claude_cmd' not found. Install Claude Code: https://code.claude.com" >&2
  exit "$MISSING_PREREQ"
fi

for round in $(seq 1 "$ROUNDS"); do
  echo "fix-loop: round $round/$ROUNDS - gate is red, asking Claude to fix."
  before="$(worktree_fingerprint)"
  # The outer loop verifies, so the Stop hook inside this session would only duplicate work.
  SDLC_SKIP_VERIFY=1 "$claude_cmd" -p "$(fix_prompt)" \
    --permission-mode acceptEdits --max-turns "$MAX_TURNS_PER_ROUND"

  if [ "$(worktree_fingerprint)" = "$before" ]; then
    echo "fix-loop: round $round changed nothing - stopping. A human needs to look." >&2
    exit 2
  fi
  run_check
  [ "$check_code" -eq 0 ] && { echo "fix-loop: green after $round round(s). Review the diff before committing."; exit 0; }
done

echo "fix-loop: still red after $ROUNDS round(s). Last failures:" >&2
printf '%s\n' "$check_output" | tail -n 30 >&2
exit 1
