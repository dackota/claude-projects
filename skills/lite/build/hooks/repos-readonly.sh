#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook — keep repos/ read-only in a lite workspace.
#
# In the lite flow, repos/ holds read-only base clones for reference and ALL work
# happens in worktrees/. This blocks any Write/Edit whose target path is under the
# workspace's repos/ (exit 2, message -> Claude), so an agent can't work directly in
# a clone. Reads (Read/Grep/Glob) and git ops via Bash (git worktree add, fetch) are
# unaffected — that's why this is a hook, not a filesystem chmod.
#
# Reads the hook payload (JSON) on stdin; assumes the standard Claude Code
# PreToolUse shape with .tool_input.file_path and .cwd.

input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
cwd="$(printf '%s'  "$input" | jq -r '.cwd // ""'              2>/dev/null || true)"

[[ -z "$path" ]] && exit 0

# Find the workspace root (dir containing project.yaml) walking up from cwd.
find_root() {
  local dir="$1"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    [[ -f "$dir/project.yaml" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

root="$(find_root "$cwd" 2>/dev/null || true)"
[[ -z "$root" ]] && exit 0   # not inside a workspace — nothing to guard

# Write/Edit paths are absolute, but resolve a relative one against cwd to be safe.
case "$path" in
  /*) abs="$path" ;;
  *)  abs="$cwd/$path" ;;
esac

# Trailing slash so `<root>/repos` and `<root>/repos/x` match, but a sibling like
# `<root>/repositories` does not.
case "$abs/" in
  "$root/repos/"*)
    echo "🚫 repos/ is read-only in a lite workspace." >&2
    echo "repos/ holds read-only base clones for reference; all work happens in worktrees/." >&2
    echo "Write to the task worktree under worktrees/<task>/ instead." >&2
    exit 2
    ;;
esac

exit 0
