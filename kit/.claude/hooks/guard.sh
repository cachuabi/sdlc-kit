#!/usr/bin/env bash
# PreToolUse hook for Bash: blocks destructive or irreversible commands before they run.
# Exit 2 blocks the command and sends stderr back to Claude; exit 0 allows it.
# This is a speed bump against mistakes and prompt injection, not a sandbox:
# keep the deny list in settings.json and branch protection on the remote as well.
set -u

payload="$(cat)"

read_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -er '.tool_input.command // ""'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -I -c \
      'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))'
  else
    return 1
  fi
}

if ! cmd="$(read_command 2>/dev/null)"; then
  echo "guard: could not parse the hook payload (needs jq or python3) - blocking to stay safe." >&2
  exit 2
fi
[ -z "$cmd" ] && exit 0

block() {
  {
    echo "guard: BLOCKED - $1."
    echo "Command: $cmd"
    echo "Do not try to work around this. Stop and ask the user to run it themselves if it is really needed."
  } >&2
  exit 2
}

matches() { printf '%s' "$cmd" | grep -Eq -- "$1"; }
matches_any_case() { printf '%s' "$cmd" | grep -Eiq -- "$1"; }

# Patterns are extended regexes (case-sensitive unless noted); S = whitespace, E = end of a word.
S='[[:space:]]'
E='([[:space:];&|)]|$)'
PUSH="git$S+push($S.*)?"

matches "$PUSH$S(-f|--force|--force-with-lease)([=[:space:];&|]|$)" && block "force push rewrites shared history"
matches "$PUSH$S\+[^[:space:]]" && block "force push (+refspec) rewrites shared history"
matches "$PUSH($S--delete$E|$S:[^[:space:]])" && block "deleting a remote branch"
matches "$PUSH[[:space:]:](main|master)$E" && block "pushing to main/master - open a pull request instead"
matches "--no-verify" && block "skipping git hooks (--no-verify)"
matches "git$S+reset$S.*--hard" && block "git reset --hard discards work"
matches "git$S+clean$S+-[a-z]*f" && block "git clean deletes untracked files"
matches "git$S+(checkout$S+--$S+\.|restore$S+(--[a-z-]+$S+)*\.)$E" && block "discarding all local changes"
matches "git$S+branch$S+.*-D$E" && block "force-deleting a branch"

# rm with a recursive flag aimed at /, ~, \$HOME, .., * or . (rm -rf build stays allowed).
RM_FLAGS="(-{1,2}[a-zA-Z-]+$S+)*"
RM_RECURSIVE="(^|[;&|[:space:]])rm$S+$RM_FLAGS(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)$S+$RM_FLAGS"
DANGEROUS_TARGET='["'"'"']?(/|~|\$\{?HOME|\.\.|\*'"$E"'|\.'"$E"')'
matches "$RM_RECURSIVE(.*$S)?$DANGEROUS_TARGET" && block "recursive delete outside the project"

matches "(curl|wget)[^|]*\|$S*(sudo$S+)?(ba|z|da)?sh$E" && block "piping a download into a shell"
matches "(^|[;&|[:space:]])sudo$S" && block "running as root (sudo)"
matches "chmod$S+(-R$S+)?0?777" && block "making files world-writable"
matches "(npm|pnpm|yarn)$S+publish|cargo$S+publish|twine$S+upload|gh$S+release$S+create" && block "publishing a release"
matches "gh$S+pr$S+merge|gh$S+repo$S+delete" && block "merging or deleting on GitHub is a human decision"
matches_any_case "drop$S+(table|database|schema)$S|truncate$S+table$S" && block "destroying database data"

# Secrets: .env files (but not .env.example/.sample/.template), SSH keys, cloud credentials.
without_examples="$(printf '%s' "$cmd" | sed -E 's/\.env\.(example|sample|template)[A-Za-z0-9_.-]*//g')"
if printf '%s' "$without_examples" | grep -Eq '(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_-]+)?([^A-Za-z0-9_.-]|$)'; then
  block "reading secret .env files"
fi
matches "\.ssh/|id_rsa|id_ed25519|\.aws/credentials|\.netrc" && block "reading SSH keys or cloud credentials"

# Work on main/master goes through a branch and a pull request.
project_dir="${CLAUDE_PROJECT_DIR:-.}"
branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  if [ "${SDLC_ALLOW_MAIN:-0}" != "1" ] && matches "git$S+(commit|push)$E"; then
    block "committing or pushing directly on $branch - create a branch first: git switch -c feat/<task>"
  fi
fi

exit 0
