---
name: repo
description: Manage cloned repos and git worktrees in a claude-projects workspace through scripts/repo.sh. Use whenever you need to clone a repo, start work on a task, sync a worktree with its base branch, check for drift, or remove a worktree. Raw git clone / worktree add / branch create/switch under repos/ and worktrees/ are blocked by a guard hook — route them through repo.sh.
origin: claude-projects
---

# /repo

All repo and worktree operations in this workspace go through `scripts/repo.sh`.
A PreToolUse guard hook blocks raw `git clone`, `git worktree add`, and branch
create/switch inside `repos/` and `worktrees/`, redirecting you here. This keeps
base clones pinned to their default branch and isolates every task in a worktree,
so work never gets stranded by a `git checkout main` in a shared clone.

## Why this exists

- **Repos live in `repos/`, declared in `project.yaml`.** `repo.sh clone`
  records each repo (name, url, path, default_branch) so the workspace has a
  durable list of what it touches.
- **Task work lives in `worktrees/<task>/<repo>`** on a branch named `<task>`.
  One task can span multiple repos; each gets its own worktree under the same
  task directory.
- **Worktrees drift.** Their base branch advances on the remote while you work.
  `repo.sh` fetches on every invocation, `status` reports how far behind each
  worktree is, and a pre-edit hook warns you *before* you build on stale code.

## Commands

```
repo.sh clone <url> [name]             Clone into repos/<name>; register in project.yaml
repo.sh worktree <task> <repo> [url]   Create worktrees/<task>/<repo> on branch <task>
                                       (auto-clones the repo if missing)
repo.sh sync <task> [repo]             Fetch + merge origin/<base> into the worktree(s)
repo.sh status [task]                  Live behind/ahead vs base + dirty + STALE flag
repo.sh remove <task> [repo] [--force] Remove worktree(s) + delete local branch
repo.sh list                           List registered repos
```

## Behavior you can rely on

- **Fetch-always.** `worktree`, `sync`, `status`, and `remove` fetch first, so
  drift is measured against current remote state.
- **`sync` is the only working-tree mutation.** It refuses on a dirty tree
  (commit or stash first), merges `origin/<base>` (no force-push needed), and on
  conflict stops and lists the conflicted files — it never auto-resolves or
  silently aborts.
- **`remove` is safe by default.** It refuses if the worktree is dirty or the
  branch has unpushed commits; pass `--force` to override. It deletes only the
  local branch (origin / any PR are untouched).

## When a raw git command is blocked

The guard prints the `repo.sh` command to use instead. Read-only git
(`status`, `log`, `diff`, `fetch`, `show`) and file-level `git checkout -- <file>`
are always allowed.
