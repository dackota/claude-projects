#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook: warn before building on a stale worktree.
#
# The first time Claude edits inside a given worktree this session, fetch and
# check whether the branch is behind its base. If so, exit 2 once to surface the
# drift (the marker is set first, so a retry of the same edit proceeds — this is
# a one-time speed bump per worktree per session, not a hard block).

input="$(cat)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null || true)"

[[ -z "$fp" ]] && exit 0

# Workspace root = nearest ancestor of the edited file containing project.yaml.
dir="$(dirname "$fp")"
root=""
while [[ -n "$dir" && "$dir" != "/" ]]; do
  [[ -f "$dir/project.yaml" ]] && { root="$dir"; break; }
  dir="$(dirname "$dir")"
done
[[ -z "$root" ]] && exit 0

# Only care about edits under worktrees/<task>/<repo>/...
case "$fp" in
  "$root/worktrees/"*) ;;
  *) exit 0 ;;
esac
rel="${fp#"$root"/worktrees/}"
task="${rel%%/*}"
rest="${rel#*/}"
repo="${rest%%/*}"
wt="$root/worktrees/$task/$repo"
[[ -e "$wt/.git" ]] || exit 0

# Dedupe: one check per session per worktree.
marker="${TMPDIR:-/tmp}/repo-stale.${session}.$(printf '%s' "$task/$repo" | tr '/ ' '__')"
[[ -f "$marker" ]] && exit 0
: > "$marker" 2>/dev/null || true

# Base branch from project.yaml (default main); needs git (yq optional).
base="main"
if command -v yq >/dev/null 2>&1; then
  b="$(yq e ".repos[] | select(.name == \"$repo\") | .default_branch" "$root/project.yaml" 2>/dev/null || true)"
  [[ -n "$b" && "$b" != "null" ]] && base="$b"
fi

git -C "$wt" fetch -q --all --prune 2>/dev/null || exit 0
behind="$(git -C "$wt" rev-list --count "HEAD..origin/$base" 2>/dev/null || echo 0)"

if [[ "${behind:-0}" -gt 0 ]]; then
  echo "⚠ worktrees/$task/$repo is STALE: $behind commit(s) behind origin/$base." >&2
  echo "Run ./scripts/repo.sh sync $task $repo before building on it, or you'll rework at merge time." >&2
  echo "(This is a one-time per-session notice — re-issue the edit to proceed if you've decided not to sync.)" >&2
  exit 2
fi

exit 0
