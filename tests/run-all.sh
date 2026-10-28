#!/usr/bin/env bash
# Runs every tests/*.test.sh file and fails if any of them fails.
set -u
cd "$(dirname "$0")" || exit 1

failed=()
for t in ./*.test.sh; do
  echo "== $t"
  bash "$t" || failed+=("$t")
done

echo
if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All test files passed."
