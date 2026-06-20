#!/usr/bin/env bash
# PreToolUse(Bash) hook: block raw git that bypasses repo.sh.
#
# Blocks (exit 2, message -> Claude):
#   - git clone                              -> repo.sh clone
#   - git worktree add                       -> repo.sh worktree
#   - branch create  (checkout -b / switch -c)  ] when run under repos/ or
#   - branch switch  (checkout <b> / switch <b>) ] worktrees/ (or via -C/cd there)
#
# Allows: read-only git (status/log/diff/fetch/show/branch -l/...), and
#         file-level restore (`git checkout -- <file>`, `git restore`).
#
# Reads the hook payload (JSON) on stdin; assumes the standard Claude Code
# PreToolUse shape with .tool_input.command and .cwd.

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"

[[ -z "$cmd" ]] && exit 0
case "$cmd" in *git*) ;; *) exit 0 ;; esac

block() {
  # $1 = what was blocked, $2 = the repo.sh redirect / guidance
  echo "🚫 repo guard: $1" >&2
  echo "$2" >&2
  echo "(Read-only git and 'git checkout -- <file>' are allowed. See ./scripts/repo.sh help.)" >&2
  exit 2
}

# Find the workspace root from cwd (dir containing project.yaml).
find_root() {
  local dir="$1"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    [[ -f "$dir/project.yaml" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

# Is this operation targeting repos/ or worktrees/?  True if cwd is under them,
# or the command references those paths (git -C repos/x, cd worktrees/x && ...).
in_managed() {
  local root; root="$(find_root "$cwd" 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    case "$cwd/" in
      "$root/repos/"*|"$root/worktrees/"*) return 0 ;;
    esac
  fi
  case "$cmd" in
    *repos/*|*worktrees/*) return 0 ;;
  esac
  return 1
}

# ── unconditional blocks (within the workspace) ───────────────────────────────
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:](])git[[:space:]]+clone([[:space:]]|$)'; then
  block "raw 'git clone' is disabled in this workspace." \
        "Use: ./scripts/repo.sh clone <url> [name]  — clones into repos/ and registers it in project.yaml."
fi

if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+worktree[[:space:]]+add'; then
  block "raw 'git worktree add' is disabled." \
        "Use: ./scripts/repo.sh worktree <task> <repo> [url]  — creates worktrees/<task>/<repo> on the right base branch."
fi

# ── branch create / switch — only when targeting repos/ or worktrees/ ─────────
if in_managed; then
  # branch creation
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+checkout[[:space:]]+([^&|;]*[[:space:]])?(-b|-B)([[:space:]]|=|$)' \
  || printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+switch[[:space:]]+([^&|;]*[[:space:]])?(-c|-C|--create)([[:space:]]|=|$)'; then
    block "creating a branch inside repos//worktrees/ is disabled — task work belongs in a worktree." \
          "Use: ./scripts/repo.sh worktree <task> <repo>  — isolates the branch in worktrees/<task>/<repo>."
  fi

  # branch switch (not a file-level checkout: no ' -- ')
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+switch([[:space:]]|$)'; then
    block "switching branches inside repos//worktrees/ is disabled — keep base clones pinned and use worktrees." \
          "Use: ./scripts/repo.sh worktree <task> <repo>  (new context) or  ./scripts/repo.sh status  (see what exists)."
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+checkout([[:space:]]|$)' \
     && ! printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+checkout[[:space:]]+([^&|;]*[[:space:]])?--([[:space:]]|$)'; then
    block "switching branches inside repos//worktrees/ is disabled — keep base clones pinned and use worktrees." \
          "Use: ./scripts/repo.sh worktree <task> <repo>  (new context), or 'git checkout -- <file>' to discard a file."
  fi
fi

exit 0
