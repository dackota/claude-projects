---
title: Hook-enforced repo & worktree discipline (the `repo` skill)
created: 2026-06-19
last_updated: 2026-06-19
status: active
supersedes: []
superseded_by: null
related:
  - docs/adr/0002-hook-enforced-repo-discipline.md
jira: null
task: null
---

# Hook-enforced repo & worktree discipline

## Problem

Scaffolded workspaces ship a CLAUDE.md that already tells Claude to clone repos
into `repos/`, isolate task work in git worktrees, and update repos before use
(`scripts/proj.sh:280-285`). In practice:

1. **Claude bypasses the rules.** Prose is advisory. Claude reaches for raw
   `git clone`, `git worktree add`, and `git checkout` because they are the
   lowest-friction path, so repos land in arbitrary places and task work happens
   on branches inside a single clone instead of in worktrees.
2. **Worktrees go stale silently.** A worktree's base branch advances on the
   remote, but nothing tells Claude. It keeps building on old code and discovers
   the divergence only at merge-back time — the "redo it on back to main"
   rework.

The gap is not missing instructions; it is the absence of *enforcement* and a
*freshness signal*.

## Solution

Make the discipline mechanical via a new bundled `repo` skill:

- **`scripts/repo.sh`** — the single sanctioned, user-visible, user-runnable
  entry point for every repo/worktree operation. Verb-based command surface:

  ```
  repo.sh clone <url> [name]            # clone -> repos/<name>, register in project.yaml
  repo.sh worktree <task> <repo> [url]  # worktrees/<task>/<repo> on branch <task>; auto-clones if missing
  repo.sh sync <task> [repo]            # fetch; refuse if dirty; merge origin/<base>; stop+report on conflict
  repo.sh status [task]                 # live behind/ahead vs base + dirty + STALE flag (per worktree)
  repo.sh remove <task> [repo]          # remove worktree + delete local branch (safe by default)
  repo.sh list                          # registered repos
  ```

- **`hooks/git-guard.sh`** — PreToolUse(`Bash`) hook. Parses the command + cwd;
  blocks raw `git clone`, `git worktree add`, branch creation
  (`checkout -b` / `switch -c`), and branch switching
  (`git checkout <branch>` / `git switch <branch>`) when run under `repos/` or
  `worktrees/`. Exits 2 with a redirect to the equivalent `repo.sh` command.
  Read-only git and file-level `git checkout -- <path>` pass through.

- **`hooks/repo-stale.sh`** — PreToolUse(`Edit|Write`) hook. The first time
  Claude edits inside a given worktree each session, throttled-fetch + compute
  `behind` count vs base; if stale, exit 2 to warn before work proceeds. Deduped
  per session+worktree via a marker file (never per-edit).

- **`hooks/repo-stale-stop.sh`** — `Stop` hook summarizing stale worktrees as an
  end-of-session backstop. **Removed from the default wiring (2026-06-25):** it
  swept *all* worktrees on every stop regardless of whether one was in use (and,
  via `asyncRewake`, re-fired about already-resolved drift). Staleness is now
  checked point-of-use only through `repo-stale.sh`. The script is retained but
  unregistered; see ADR 0002's 2026-06-25 update.

**State model (hybrid):** repos are durable and declared in `project.yaml`
`repos` (`name`, `url`, `path`, `default_branch`). Worktrees are ephemeral and
NOT persisted — `status` derives them live from `git worktree list`, recovering
the task link from the `worktrees/<task-id>/<repo>` directory name.

**Distribution:** `proj.sh` special-cases the `repo` skill like
`journal`/`sync-status` — copies the skill, drops `repo.sh` into `scripts/`, and
merges the three hooks into `.claude/settings.json`. The merge is idempotent and
runs in both `proj <name> --skills` (new) and `proj update-skills` (existing),
so current workspaces are protected without re-scaffolding.

## Trade-offs

- **Enforcement friction vs. compliance.** The guard blocks a class of raw git
  commands. Accepted: the escape hatch is `repo.sh` or running outside
  `repos/`/`worktrees/`, and read-only git is never blocked.
- **Surface vs. simplicity.** A wrapper + three hooks + `proj.sh` merge logic is
  more than a lone script. Accepted: the wrapper alone (chosen decision #3 in the
  grilling) does not change behavior — only the guard does.
- **`yq` dependency.** Writing `project.yaml` robustly needs `yq` v4. Accepted
  over hand-rolled YAML appends (fragile) given `yq` is already on the dev box;
  scripts fail fast if it is absent.
- **Merge (not rebase) on sync.** Adds merge commits but never needs a
  force-push — safer for already-pushed branches (decision #9).

## Considerations

- Hooks follow existing conventions: read JSON on stdin
  (`jq -r '.tool_input.command'` / `.file_path`), exit 2 to block/rewake with a
  stdout message, assume CWD = project root.
- `default_branch` is detected on clone via
  `git symbolic-ref refs/remotes/origin/HEAD`.
- `worktree` resolves the clone URL from `project.yaml` when the repo is already
  registered; otherwise the `[url]` arg is required, and the repo is cloned +
  registered before the worktree is created.
- `remove` deletes only the *local* branch (origin/PR untouched) and **refuses
  if the branch has unpushed commits** unless `--force` — same no-lost-work
  principle as the dirty-tree refusal on `sync`.
- Staleness math: `git rev-list --count <branch>..origin/<base>` after a
  throttled fetch; dedupe marker keyed by `session_id` + worktree path.
- Branch name defaults to the bare `<task-id>` (no `feature/` prefix).

## Tasks

Each task is independently reviewable.

### Task 1 — `repo.sh`: clone, list, worktree, status (read + create paths)

`clone` (with `default_branch` detection + `project.yaml` registration via
`yq`), `list`, `worktree` (create `worktrees/<task>/<repo>`, branch `<task>`,
auto-clone if missing), `status` (live `git worktree list` + `rev-list` drift +
dirty + STALE flag). `yq`/`jq` presence check with fail-fast hint. No mutation
of existing worktrees yet.

### Task 2 — `repo.sh`: `sync` and `remove`

`sync`: fetch, refuse on dirty tree, `git merge origin/<base>`, stop-and-report
on conflict. `remove`: `git worktree remove` + delete local branch, refusing on
unpushed commits unless `--force`.

### Task 3 — `hooks/git-guard.sh` (PreToolUse Bash)

Parse `.tool_input.command` + cwd; implement the block matrix (clone /
worktree-add / branch create / branch switch under `repos/`+`worktrees/`); allow
read-only git and `git checkout -- <path>`. Exit 2 with a redirect message
naming the `repo.sh` equivalent.

### Task 4 — staleness hooks

`repo-stale.sh` (PreToolUse `Edit|Write`, per-session+worktree dedupe marker,
throttled fetch, behind-count warn) and `repo-stale-stop.sh` (Stop summary of
stale worktrees).

### Task 5 — `proj.sh` integration + CLAUDE.md template

Special-case the `repo` skill: copy skill, drop `repo.sh` into `scripts/`, and
**merge** the three hooks into `settings.json` (idempotent, dedupe by command
string) in both the scaffold and `update-skills` paths. Rewrite the CLAUDE.md
template's `repos/` and `worktrees/` sections to mandate `scripts/repo.sh` and
note the guard.

### Task 6 — tests + docs

Extend `scripts/test-proj.sh`: repo-skill install drops `scripts/repo.sh`,
`settings.json` merge is idempotent and preserves journal/sync-status hooks, and
`repo.sh` smoke tests run against a local throwaway git remote
(clone → worktree → status → sync → remove). Update `README.md` with the `repo`
skill and the `/repo` discipline.
