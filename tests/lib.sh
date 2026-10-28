#!/usr/bin/env bash
# Shared helpers for the kit's shell tests. Source it; do not execute it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # read by the test files that source this one
KIT="$ROOT/kit"
PASS=0
FAIL=0

# Throwaway directories live under one root that is removed when the test file exits.
# (make_tmp runs inside $(...), so it cannot record paths in a parent-shell variable.)
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sdlc-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

make_tmp() { mktemp -d "$TEST_ROOT/t.XXXXXX"; }

# Creates a git repo with one commit on the given branch (default: feature/x).
make_repo() {
  local dir branch="${1:-feature/x}"
  dir="$(make_tmp)"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  printf 'seed\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "chore: seed"
  printf '%s' "$dir"
}

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# assert_eq <description> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

# assert_contains <description> <needle> <haystack>
assert_contains() {
  case "$3" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "missing [$2] in: $(printf '%s' "$3" | tail -n 5)" ;;
  esac
}

# assert_not_contains <description> <needle> <haystack>
assert_not_contains() {
  case "$3" in
    *"$2"*) fail "$1" "unexpected [$2]" ;;
    *) pass "$1" ;;
  esac
}

# Prints the summary and exits non-zero when any assertion failed.
finish() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
