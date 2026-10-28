#!/usr/bin/env bash
# Shared helper: a fingerprint of the working tree (HEAD + staged/unstaged diff + untracked
# file contents). Two equal fingerprints mean nothing changed in between.
# Source it from bash; requires the current directory to be inside a git work tree.

worktree_fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null || echo "no-head"
    git diff HEAD 2>/dev/null || git diff --cached
    git ls-files --others --exclude-standard -z | while IFS= read -r -d '' file; do
      printf '%s ' "$file"
      git hash-object -- "$file"
    done
  } | git hash-object --stdin
}
