#!/usr/bin/env bash
# Stop hook: before Claude ends a turn with unverified changes, run scripts/check.sh.
# Red → exit 2, so Claude keeps working and sees the failure output.
# After MAX_ATTEMPTS blocked stops in a row Claude may stop, and the user is warned.
# Set SDLC_SKIP_VERIFY=1 to turn the gate off for one session.
set -u

MAX_ATTEMPTS=3
NO_CHECKS=3
OUTPUT_TAIL_LINES=60

cat >/dev/null  # the payload is not needed; the git state is the source of truth
[ "${SDLC_SKIP_VERIFY:-0}" = "1" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-.}"
cd "$project_dir" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 0

# shellcheck source=../../scripts/lib/git-state.sh
source "$root/scripts/lib/git-state.sh" 2>/dev/null \
  || source "$(dirname "$0")/../../scripts/lib/git-state.sh"

state_dir="$(git rev-parse --absolute-git-dir)/sdlc"
mkdir -p "$state_dir"
verified_file="$state_dir/verified"
attempts_file="$state_dir/stop-attempts"

warn_user() { # prints a JSON systemMessage, which Claude Code shows to the user
  local text="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$text" '{systemMessage: $m}'
  else
    printf '{"systemMessage": "%s"}\n' "$(printf '%s' "$text" | tr -d '"\\')"
  fi
}

current="$(worktree_fingerprint)"
last_verified="$(cat "$verified_file" 2>/dev/null || true)"

if [ -z "$last_verified" ] && [ -z "$(git status --porcelain)" ]; then
  echo "$current" > "$verified_file"   # first run on a clean tree: trust the committed state
  exit 0
fi
[ "$current" = "$last_verified" ] && exit 0

check_cmd="${SDLC_CHECK_CMD:-$root/scripts/check.sh}"
if [ ! -f "$check_cmd" ]; then
  warn_user "Quality gate is missing: $check_cmd does not exist. Changes are unverified."
  exit 0
fi
output="$(bash "$check_cmd" 2>&1)"
code=$?

if [ "$code" -eq 0 ]; then
  echo "$current" > "$verified_file"
  rm -f "$attempts_file"
  exit 0
fi

if [ "$code" -eq "$NO_CHECKS" ]; then
  warn_user "Quality gate is not configured: scripts/check.sh found nothing to run. Changes are unverified."
  exit 0
fi

attempts=$(( $(cat "$attempts_file" 2>/dev/null || echo 0) + 1 ))
if [ "$attempts" -gt "$MAX_ATTEMPTS" ]; then
  rm -f "$attempts_file"
  warn_user "Quality gate is still RED after $MAX_ATTEMPTS fix attempts. Do not merge; run scripts/check.sh to see the failures."
  exit 0
fi
echo "$attempts" > "$attempts_file"

{
  echo "Quality gate failed (scripts/check.sh exit $code), attempt $attempts of $MAX_ATTEMPTS."
  echo "Fix the root cause. Do not skip, delete or weaken tests to make them pass."
  echo "--- last $OUTPUT_TAIL_LINES lines ---"
  printf '%s\n' "$output" | tail -n "$OUTPUT_TAIL_LINES"
} >&2
exit 2
