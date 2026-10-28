#!/usr/bin/env bash
# The project's single quality gate. CI, the Stop hook and fix-loop all call this script,
# so "green" means the same thing everywhere. Customize the run_* functions for your stack.
#
# Usage: scripts/check.sh [run|deps]
#   run   (default) run lint / typecheck / test / build for every detected stack
#   deps  install dependencies for every detected stack (used by CI)
# Exit: 0 all passed · 1 a step failed · 3 nothing to check (configure this script) · 64 bad usage
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1

NO_CHECKS=3
USAGE=64
passed=()
failed=()

step() { # step <label> <command...>
  local label="$1"; shift
  echo "::group::$label"
  if "$@"; then passed+=("$label"); else failed+=("$label"); fi
  echo "::endgroup::"
}

has_make_target() { [ -f Makefile ] && grep -Eq "^$1:" Makefile; }

node_pm() {
  if [ -f pnpm-lock.yaml ]; then echo pnpm
  elif [ -f yarn.lock ]; then echo yarn
  else echo npm
  fi
}

has_npm_script() {
  node -e 'const s = require("./package.json").scripts || {}; process.exit(s[process.argv[1]] ? 0 : 1)' "$1"
}

# Prints "uv run" for uv projects; callers leave it unquoted so it splits into two words.
python_runner() { if [ -f uv.lock ]; then echo "uv run"; fi; }

run_checks() {
  local detected=0 pm script runner
  if has_make_target check; then
    step "make check" make check
    return 0
  fi
  if [ -f package.json ]; then
    detected=1; pm="$(node_pm)"
    for script in lint typecheck test build; do
      has_npm_script "$script" && step "$pm run $script" "$pm" run "$script"
    done
  fi
  if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
    detected=1; runner="$(python_runner)"
    # shellcheck disable=SC2086
    if [ -f ruff.toml ] || grep -q '^\[tool\.ruff' pyproject.toml 2>/dev/null; then
      step "ruff check" $runner ruff check .
    fi
    # shellcheck disable=SC2086
    step "pytest" $runner python -m pytest
  fi
  if [ -f go.mod ]; then
    detected=1
    step "go vet" go vet ./...
    step "go test" go test ./...
  fi
  if [ -f Cargo.toml ]; then
    detected=1
    step "cargo test" cargo test
  fi
  [ "$detected" -eq 1 ]
}

install_deps() {
  local detected=0
  if has_make_target deps; then make deps; return; fi
  if [ -f package.json ]; then
    detected=1
    case "$(node_pm)" in
      pnpm) pnpm install --frozen-lockfile ;;
      yarn) yarn install --frozen-lockfile ;;
      npm) if [ -f package-lock.json ]; then npm ci; else npm install; fi ;;
    esac || return 1
  fi
  if [ -f uv.lock ]; then detected=1; uv sync || return 1
  elif [ -f requirements.txt ]; then detected=1; python -m pip install -r requirements.txt || return 1
  elif [ -f pyproject.toml ]; then detected=1; python -m pip install -e '.[dev]' || python -m pip install -e . || return 1
  fi
  if [ -f go.mod ]; then detected=1; go mod download || return 1; fi
  if [ -f Cargo.toml ]; then detected=1; cargo fetch || return 1; fi
  [ "$detected" -eq 1 ] || return "$NO_CHECKS"
}

no_checks_message() {
  echo "check.sh: no stack detected. Add a 'check' target to the Makefile or edit scripts/check.sh" >&2
  echo "          so it runs your lint, typecheck, test and build commands." >&2
}

case "${1:-run}" in
  run)
    if ! run_checks; then no_checks_message; exit "$NO_CHECKS"; fi
    echo
    for s in ${passed[@]+"${passed[@]}"}; do echo "PASSED: $s"; done
    for s in ${failed[@]+"${failed[@]}"}; do echo "FAILED: $s"; done
    [ "${#failed[@]}" -eq 0 ]
    ;;
  deps)
    install_deps; code=$?
    [ "$code" -eq "$NO_CHECKS" ] && no_checks_message
    exit "$code"
    ;;
  *)
    echo "Usage: scripts/check.sh [run|deps]" >&2
    exit "$USAGE"
    ;;
esac
