---
name: build
description: Lite-flow build command. Picks an unblocked task from project.yaml and builds it by spawning a lite-orchestrator sub-agent that owns the build→check→iterate loop (lite-builder builds, lite-checker exercises the change, loops until the intent is met or the cap fires). Keeps the loop off the main session. Use in a lite workspace to build a slice after /to-issues; supports building several independent slices in parallel.
origin: claude-projects
agents:
  - lite-orchestrator
  - lite-builder
  - lite-checker
---

# /build — the lite build loop

`/build` is the lite flow's build step (the counterpart to `/next`'s Build phase, without
the router, barrier, worktree apparatus, or audit machinery). You — the main session —
stay thin: **pick the task, spawn the loop, collect the result, report.** The actual
build→check→iterate loop runs inside a `lite-orchestrator` sub-agent on a fresh context,
so this session never carries it.

## 1. Pick the task

Read `project.yaml`. Tasks are local (`tasks:` list). Then:

- **`/build <task-id>`** → build that task.
- **`/build`** (no arg) → pick the next unblocked `todo` task in dependency order (all
  its `blocked_by` are `done`). If none is unblocked, say so and stop.
- **HITL task** → it needs its flagged human input first; you're in the session, so gather
  it and fold it into the brief before spawning. AFK tasks build straight through.

Confirm the task's **target repo** (`repo:` field) is cloned under `repos/`. If it isn't,
tell the user to clone it there and add it to `project.yaml` `repos:` — don't invent one.

Read the task's inline **acceptance criteria**, **what**, **seam**, and **repo** (the lite
`to-issues` writes these into the task; the `plan:` is context if you need it).

## 2. Flip status, cut the worktree, spawn the loop

Flip the task `todo → active` in `project.yaml` (you own status; the sub-agent can't touch
it). Then **cut the worktree yourself** (plain `git worktree`, so parallel builds on one
repo don't race on git's lock — the orchestrators never create worktrees):

```
git -C repos/<repo> worktree add "$PWD/worktrees/<task-id>" -b lite/<task-id>
```

Reuse the branch if it already exists (a resumed task). Then spawn **`lite-orchestrator`**
(Agent tool, `subagent_type: lite-orchestrator`) **in the foreground**
(`run_in_background: false`) so its `FINAL:` result comes back in the tool result. Brief it
with:

- the task id, its acceptance criteria + "what to build", and the **worktree path**
  (`worktrees/<task-id>`);
- the test/run commands (`project.yaml` `validation.test_cmd` / `run_cmd`) and the cap
  (`validation.max_rework`);
- the `CONTEXT.md` vocabulary.

The orchestrator runs the loop and returns
`FINAL: DONE | BLOCKED-CAP | CANT-VALIDATE | BUILD-BLOCKED`.

## 3. Parallel (opt-in)

When the user asks to build several at once ("build the next 3 in parallel"), pick that
many **mutually independent** unblocked tasks (none `blocked_by` another in the set) and
flip each `todo → active`. **Create every worktree first, serially** (the `git worktree
add` above, one at a time — concurrent adds on the same base clone can race on git's lock),
then spawn **one `lite-orchestrator` per task in a single message** (multiple Agent calls,
all foreground) so the *build loops* run concurrently, each in its ready worktree. Collect
every `FINAL:` before reporting. Don't parallelize dependent tasks — a blocker must land
first.

## 4. Report

Per task, act on the orchestrator's `FINAL:`:

- **DONE** → flip the task `active → done`. Tell the user the **worktree path**; the slice
  is built + validated but **uncommitted** (the lite flow has no auto-commit or PR gate).
  Review, then commit and open the PR. Use **`gh-axi`** for the GitHub side (agent-first,
  token-efficient output) rather than raw `gh` — `gh-axi pr create --title "…" --body-file
  <path>`, or `npx -y gh-axi pr create …` if it isn't installed globally (needs `gh`
  authenticated). Run `/security-review` by hand first if the slice warrants it.
- **BLOCKED-CAP** → leave the task `active` (or set `blocked` if it clearly can't proceed).
  Surface the recurring finding: a gate that keeps blocking the same slice usually means a
  wrong seam, a flaky test, or an impossible criterion — a human call, not another round.
- **CANT-VALIDATE** → leave the task `active`. Surface exactly what the checker couldn't
  run (missing dependency / no runnable surface) so the user can validate another way.
- **BUILD-BLOCKED** → leave the task `active`. Surface the design fork the builder hit and
  resolve it with the user, then re-run `/build <task-id>`.

For a parallel run, report a short per-task summary (task · FINAL · worktree · one-line
note) rather than restating each loop.

## Boundaries

- You **spawn and collect** — you don't build or grade. The orchestrator owns the loop; the
  independent `lite-checker` owns the verdict.
- You flip task status (the sub-agent can't); you never commit or open PRs for the user.
- All work lands in `worktrees/`; `repos/` stays read-only (a hook enforces it).
- Any GitHub interaction (PRs, issues, CI checks) goes through **`gh-axi`** (`gh-axi
  <command>`, or `npx -y gh-axi <command>` if not installed globally), not raw `gh` — the
  agent-first path with token-efficient output.
