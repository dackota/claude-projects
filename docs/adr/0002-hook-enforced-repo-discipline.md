---
status: accepted
date: 2026-06-19
---

# Repo and worktree handling is enforced through `scripts/repo.sh` by a Bash guard hook

The scaffold's CLAUDE.md already mandated cloning into `repos/`, isolating task
work in worktrees, and "always update first" — yet Claude routinely bypassed
those prose rules with lower-friction raw `git clone` / `git worktree add` /
`git checkout`, and worktrees silently drifted behind their base branch until a
late merge back to main cost rework. The root cause is that prose instructions
are advisory. We make the discipline mechanical instead: a single sanctioned
entry point, `scripts/repo.sh` (a verb-based wrapper: `clone`, `worktree`,
`sync`, `status`, `remove`, `list`), and a **PreToolUse Bash guard hook** that
blocks raw branch-creating/switching/cloning/worktree-add git commands under
`repos/` and `worktrees/` and redirects Claude to the equivalent `repo.sh`
command. Freshness is handled non-destructively — every `repo.sh` invocation
fetches, `status` reports drift, and a **pre-first-edit staleness hook** warns
before Claude builds on stale code — while the only working-tree mutation
(`sync`) is an explicit `git merge origin/<base>` that refuses on a dirty tree
and stops to report conflicts rather than auto-resolving.

## Considered options

- **Keep prose instructions in CLAUDE.md only** (status quo) — rejected; this is
  the failing approach. Advisory rules get bypassed, which is the entire
  problem.
- **Ship a discoverable `/repo` skill with no guard** — rejected; invoking it
  stays optional, so raw git remains one keystroke away and the bypass persists.
- **Auto-rebase/auto-merge worktrees on every use** to keep them current —
  rejected; integrating the base mid-task can throw conflicts onto in-progress
  work, *causing* the very rework it aims to prevent. Freshness is surfaced, not
  forced; integration is an explicit, separate command.
- **Persist worktrees in `project.yaml`** alongside repos — rejected; worktrees
  are ephemeral (born and killed per task), so storing them invites
  yaml-vs-reality drift for no gain (YAGNI). Repos are durable and stay declared;
  worktrees are derived live from `git worktree list`, with the task link
  recovered from the `worktrees/<task-id>/<repo>` directory convention.

## Consequences

- A new `skills/repo/` bundle (`repo.sh` + `hooks/git-guard.sh` +
  `hooks/repo-stale.sh` + `hooks/repo-stale-stop.sh` + `SKILL.md`) is
  special-cased by `proj.sh` like `journal`/`sync-status`: it copies the skill,
  drops `repo.sh` into the project's `scripts/`, and wires three hooks
  (PreToolUse `Bash`, PreToolUse `Edit|Write`, `Stop`) into `settings.json`.
- `proj.sh` gains idempotent `settings.json` **merge** logic (jq, dedupe by
  command string) so the install path works on already-populated existing
  workspaces via `update-skills`, not just fresh scaffolds.
- A new dependency, `yq` (v4), is required for `project.yaml` writes alongside
  the existing `jq`; `repo.sh` and `proj.sh` fail fast with an install hint if
  either is missing.
- The CLAUDE.md template's `repos/` and `worktrees/` sections are rewritten to
  mandate `scripts/repo.sh` and state that a guard hook enforces it.
- Worktree layout is fixed at `worktrees/<task-id>/<repo>` with branch
  `<task-id>` off the repo's default branch; multi-repo tasks are first-class.
- The guard adds friction: raw branch-level git under `repos/`/`worktrees/` is
  blocked. The escape hatch is `repo.sh` itself, or running git outside those
  directories. Read-only git (`status`/`log`/`diff`/`fetch`/`show`) and
  file-level `git checkout -- <path>` remain unblocked.
