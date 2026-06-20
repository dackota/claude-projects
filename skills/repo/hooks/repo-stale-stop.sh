#!/usr/bin/env bash
# Stop hook: end-of-session backstop. Summarize any worktrees that are behind
# their base branch. Cheap by design — uses already-fetched refs (the
# PreToolUse hook and repo.sh fetch during the session); does not fetch here.
# Assumes CWD is the project root.

[[ -f project.yaml ]] || exit 0
[[ -d worktrees ]] || exit 0

shopt -s nullglob

stale=""
for wt in worktrees/*/*; do
  [[ -e "$wt/.git" ]] || continue
  task="$(basename "$(dirname "$wt")")"
  repo="$(basename "$wt")"

  base="main"
  if command -v yq >/dev/null 2>&1; then
    b="$(yq e ".repos[] | select(.name == \"$repo\") | .default_branch" project.yaml 2>/dev/null || true)"
    [[ -n "$b" && "$b" != "null" ]] && base="$b"
  fi

  behind="$(git -C "$wt" rev-list --count "HEAD..origin/$base" 2>/dev/null || echo 0)"
  if [[ "${behind:-0}" -gt 0 ]]; then
    stale="${stale}
  - worktrees/$task/$repo: $behind behind origin/$base"
  fi
done

if [[ -n "$stale" ]]; then
  echo "⚠ Stale worktrees (behind base):${stale}"
  echo "Run ./scripts/repo.sh sync <task> [repo] to catch up before continuing next session."
  exit 2
fi

exit 0
