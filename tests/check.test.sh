#!/usr/bin/env bash
# Tests for kit/scripts/check.sh (the single quality gate used by hooks, CI and fix-loop).
set -u
source "$(dirname "$0")/lib.sh"

CHECK="$KIT/scripts/check.sh"

# run_check <dir> [args...] → sets CHECK_EXIT and CHECK_OUT
run_check() {
  local dir="$1"; shift
  CHECK_OUT="$(cd "$dir" && bash "$CHECK" "$@" 2>&1)"
  CHECK_EXIT=$?
}

write_package_json() {
  # $1 dir, $2 lint script, $3 test script
  cat > "$1/package.json" <<EOF
{ "name": "fixture", "version": "1.0.0", "private": true,
  "scripts": { "lint": "$2", "test": "$3" } }
EOF
}

echo "check: a repo with nothing to check fails loud with code 3"
empty="$(make_tmp)"
run_check "$empty"
assert_eq "exit code 3 when no checks are detected" 3 "$CHECK_EXIT"
assert_contains "tells the user to configure checks" "scripts/check.sh" "$CHECK_OUT"

echo "check: node project runs every defined script and reports failures"
node_red="$(make_tmp)"
write_package_json "$node_red" "exit 0" "exit 1"
run_check "$node_red"
assert_eq "exit code 1 when a step fails" 1 "$CHECK_EXIT"
assert_contains "names the failing step" "FAILED: npm run test" "$CHECK_OUT"
assert_contains "still runs the passing step" "PASSED: npm run lint" "$CHECK_OUT"

node_green="$(make_tmp)"
write_package_json "$node_green" "exit 0" "exit 0"
run_check "$node_green"
assert_eq "exit code 0 when every step passes" 0 "$CHECK_EXIT"
assert_not_contains "skips scripts that are not defined" "npm run build" "$CHECK_OUT"

echo "check: a Makefile check target takes precedence"
make_red="$(make_tmp)"
printf 'check:\n\t@echo running make check; exit 1\n' > "$make_red/Makefile"
write_package_json "$make_red" "exit 0" "exit 0"
run_check "$make_red"
assert_eq "make check failure is reported" 1 "$CHECK_EXIT"
assert_contains "runs make check" "running make check" "$CHECK_OUT"
assert_not_contains "does not also run npm scripts" "npm run lint" "$CHECK_OUT"

make_green="$(make_tmp)"
printf 'check:\n\t@echo ok\n' > "$make_green/Makefile"
run_check "$make_green"
assert_eq "make check success passes" 0 "$CHECK_EXIT"

echo "check: argument handling"
run_check "$empty" deps
assert_eq "deps with nothing detected exits 3" 3 "$CHECK_EXIT"
run_check "$empty" bogus
assert_eq "unknown subcommand exits 64" 64 "$CHECK_EXIT"
assert_contains "prints usage" "Usage" "$CHECK_OUT"

finish
