---
name: next
description: Workflow router for a claude-projects workspace. Reads workspace state, determines the current lifecycle phase, and recommends (and routes to) the next action — grill-with-docs → to-prd → to-issues → tdd → PR. Use at session start or any time you ask "where am I / what's next?".
origin: claude-projects
agents:
  - implementation-validator
---

# /next — the workflow router

`/next` removes the need to remember which skill to call next. It reads the
workspace's own state, figures out which **phase** the project is in, and tells
you the recommended next action — then routes you into the skill that handles it.

It is a **dispatcher, not an autopilot**, and it **complements** the phase skills
— every one of them (`grill-with-docs`, `to-prd`, `to-issues`, `tdd`) stays
directly invokable by hand. `/next` just spares you the routing decision.

> `/next` covers the full flow: phase detection (local **and Jira** mode),
> auto-dispatch with session seams, the **post-build acceptance-validator gate**
> (run right after the build, before the task is marked done, in parallel with an
> **observability gate** for service tasks), acceptance loop-back, parallel build
> fan-out, and stacked-worktree integration.

## How to run

Re-derive the phase from artifacts **every** invocation — never trust a stored
cursor. The artifacts are the source of truth; work may have happened out of band
since you last looked.

### 1. Read the state signals

Always read `project.yaml` first — its `jira_key` selects the routing mode:
**empty → local mode**, **set → Jira mode**. Then read only what you need to
determine the phase.

Also glance at `PROJECT.md`: if its **Goals** section is still the scaffold
placeholder (empty, or just the `<!-- … -->` comment), the project has no stated
goal yet — that is the **Bootstrap** phase below, and it takes priority over every
other signal.

**Local mode** (`jira_key` empty):

1. `project.yaml` — `tasks[]` (each task's `status`: `todo` / `active` / `done` /
   `blocked`, and `blocked_by`).
2. `docs/plans/*-prd.md` — a PRD with lifecycle `status: active` is the signal
   that grilling produced a plan.
3. `STATUS.md` — the synthesized current-state surface, for a richer summary
   (a convenience, not authority; it can be stale).
4. `journal.yaml` — recent events, to describe momentum.

**Jira mode** (`jira_key` set): the PRD and tasks live in the tracker, so query it
via the Atlassian MCP instead of local files, reading the same label conventions
`to-prd` / `to-issues` write:

- **PRD signal** — an issue carrying the `ready-for-agent` label is the PRD.
  None → Grill.
- **Tasks** — the slice issues, labeled `afk` / `hitl`. A PRD with no child slice
  issues → Slice.
- **Status** — map the board's standard statuses: *To Do* ≈ `todo`,
  *In Progress* ≈ `active`, *Done* ≈ `done`. An issue In Progress → Build; slice
  issues exist but none In Progress → Pick; an issue Done but not yet PR'd → Land.
- **Dependencies** — a slice's blockers are its "is blocked by" issue links; an
  issue is unblocked when all its blockers are Done. `hitl` issues are HITL tasks;
  `afk` are AFK.

Do **not** invent a custom status mapping beyond those labels plus the standard
To Do / In Progress / Done. If a board uses non-standard statuses, say so and fall
back to the labels.

### 2. Determine the phase

Apply the state machine. The first row whose detection holds is the phase:

| Phase | Detected by | Recommended next action |
|-------|-------------|--------------------------|
| **Bootstrap** | `PROJECT.md` Goals still empty / placeholder | Help the user fill in `PROJECT.md` — interview them for the goal and context, write it, then re-derive the phase |
| **Grill** | no active PRD in `docs/plans/` | Run `grill-with-docs`; on shared understanding, `to-prd` (the Grill→Slice transition) |
| **Slice** | a PRD exists, but `tasks[]` is empty | Run `to-issues` to break the PRD into vertical slices |
| **Pick** | tasks exist, none `active` | Pick the next unblocked task, then build it via the `tdd-implementer` sub-agent (a HITL task gathers human input first) — see selection + dispatch rules |
| **Build** | a task is `active` | Continue building it via the sub-agent — including closing any gaps the post-build acceptance gate flagged |
| **Land** | a task is `done` but not yet PR'd | Open the PR (acceptance is already validated; the security review runs at `gh pr create`) |
| **Done** | all tasks `done` and landed | Project complete — nothing to route |

Notes:

- **Bootstrap comes first.** Without a stated goal in `PROJECT.md`, grilling has
  nothing to sharpen. Don't proceed silently or invent a goal — ask the user what
  the project should accomplish and the context behind it, write `PROJECT.md` with
  their answers (preserve the frontmatter), then re-derive the phase. This is the
  one phase whose action edits an artifact, because that artifact is the
  prerequisite for every phase after it. (A `PROJECT.md` with real Goals → fall
  through to Grill.)
- **Grill and "shared understanding" collapse.** There is no clean "grilling is
  done" artifact, so *"an active PRD exists"* is the only signal that grilling
  finished. No active PRD → (continue) grilling.
- `to-prd` is the **transition action** fired when grilling reaches shared
  understanding — it is not a phase you sit in. In this orientation version, if
  you judge grilling is complete, recommend `to-prd`.

### 3. Pick-state selection rules

When the phase is **Pick**, choose what to recommend:

- Consider only tasks whose `blocked_by` are **all `done`** (the unblocked
  frontier).
- Recommend one task in dependency order, but make clear the user can pick a
  different unblocked task — priority among unblocked peers is theirs to decide.
- **Prefer an `AFK` task** for the default recommendation; it builds with no human
  input needed.
- If the best candidate is `HITL`, **surface that** — it needs human input
  (a design decision or answer the task flagged) *before* the build. You gather
  that input first; the build loop itself still runs non-interactively once you
  have it. Don't silently start a HITL task without resolving its input.

### 4. Report and dispatch

Always state the **phase** and the evidence that placed the user there (e.g.
"PRD exists, 8 tasks, none active → **Pick**"). Then act on it — how you dispatch
depends on the phase.

**Planning arc — auto-chain in one session.** Grill, the `to-prd` transition, and
Slice compound context, so run them back-to-back in the *current* session,
pausing only for a light confirmation at each phase boundary:

- **Grill**: run `grill-with-docs`. When shared understanding is reached, ask one
  confirm — *"Understanding looks complete — generate the PRD? [y]"* — and on yes
  run `to-prd`. If grilling surfaces a deep unknown that would derail the
  interview, you may offer a `codebase-researcher` detour (optional — never a
  gate); fold its findings back into the grill.
- **After the PRD**: confirm — *"PRD approved — slice it into issues? [y]"* — and
  on yes run `to-issues`.

**Planning → build seam — hand off to a fresh session.** After the slice
breakdown is approved, do **not** continue into implementation in this session.
Tell the user to start a fresh session; the next `/next` there picks up the first
task. A task needs only its own acceptance criteria as context, not the whole
planning history — a fresh session resists the drift that sinks long sessions.

**Build arc — one task per fresh session.** `/next` builds a task by spawning the
Sonnet `tdd-implementer` sub-agent on a fresh context — the build **loop** is
non-interactive. The task type decides whether a human-input step comes *first*;
either way the orchestrator (you) stays lean and the implementation context stays
disposable. For each build:

1. Flip the task `todo → active` and set up the worktree (`scripts/repo.sh worktree …`
   for a code repo).
2. **AFK task** → its design is fully settled upstream (grilling → `to-prd` →
   `to-issues`), so spawn the `tdd-implementer` (Agent tool,
   `subagent_type: tdd-implementer`) directly.
   **HITL task** → it was flagged HITL *because it needs human input* — a design
   decision or answer that couldn't be settled upstream. You're the orchestrator
   and can talk to the user, so **gather that input first**, then spawn the
   sub-agent with it folded into the criteria you pass. The build loop runs
   non-interactively once the input is in hand.
3. Give the sub-agent the task's acceptance criteria (plus any gathered HITL input),
   `CONTEXT.md` vocabulary, relevant ADRs, the working directory, and the test
   command. It derives the plan and runs the red-green-refactor loop, returning a
   `COMPLETE | PARTIAL | BLOCKED` summary. Review it (re-run the tests; check the
   tests are behavioral, not implementation-coupled). On `BLOCKED` — a fork that
   surfaced mid-build — gather any further input the user needs to settle it and
   re-spawn. Do **not** flip the task `done` yet — the acceptance gate runs first.
4. **Post-build acceptance gate (don't wait for the PR).** Once your own review of
   a `COMPLETE` summary is clean, **commit the slice** in the worktree, then spawn
   the `implementation-validator` (Agent tool, `subagent_type: implementation-validator`)
   on a **fresh context** to verify the slice against its contract *before* it is
   marked done. Give it only the diff range (`<base>...HEAD`) + changed files and
   the task's acceptance criteria / "what to build" — **not** the implementation
   rationale; independence is the point. It returns `VERDICT: PASS | BLOCK`
   (`BLOCK` iff `CRITICAL > 0`).

   **Observability gate (service tasks only — run in parallel).** If `project.yaml`
   has `observability.enabled: true`, the agent `otel-observability-engineer` is
   installed, **and** the diff adds a request-serving path, spawn that agent on the
   same diff **in the same message** as `implementation-validator` so both
   review-only gates run concurrently (no added latency). It returns its own
   `VERDICT: PASS | BLOCK` (`BLOCK` iff `BLOCKER > 0`) against
   `.claude/skills/observability/standard.md`. Skip it silently when the flag is
   off, the agent isn't installed, or the diff adds no request path.

   Treat the two gates as one barrier — the slice advances only if **both** PASS:
   - **Both PASS** → flip the task `active → done` and proceed to **Land** (the PR's
     security review still runs at `gh pr create`; acceptance is already done).
   - **Either BLOCK** → the slice isn't ready. Leave the task `active`, write a
     `blocker` journal entry with the failing gate's findings (the validator's
     CRITICAL acceptance gaps and/or the observability BLOCKERs), and **re-spawn the
     `tdd-implementer`** framed as *closing those specific gaps* — pass it the
     findings, not a fresh build. Its fixes are new commits → re-run the failed
     gate(s) on the new `HEAD`. Loop until both PASS. This keeps the loop-back cheap
     and local — the task never reaches a PR (or even `done`) until it passes.

Invoking `/tdd` by hand is different: it runs the loop **inline in the main agent**
(Opus) for an ad-hoc build — see the `tdd` skill's main-agent mode. `/next` always
takes the sub-agent path.

- **Pick**: propose the next unblocked task per the selection rules (id + title,
  marker, and that other unblocked tasks exist if they do). On accept, build it as
  above; the user may name a different unblocked task instead.
- **Build**: a task is already `active` → continue building it — re-dispatch to the
  sub-agent with the prior summary and what's left. If the most recent `blocker`
  journal entry is a **post-build gate** failure (the acceptance validator and/or
  the observability gate returned `BLOCK`; the task stayed `active`), frame the work
  as *closing the flagged gaps* — read the gate's CRITICAL/BLOCKER findings first and
  pass them to the sub-agent — not as starting fresh. Re-run the failed gate(s)
  (step 4) on the new `HEAD` before the task can move on.

**Parallel build fan-out (opt-in — when several tasks are unblocked at once).**
When the Pick frontier holds **two or more mutually independent** unblocked tasks
(none is in another's `blocked_by`, transitively) and the user opts in ("build the
next N in parallel"), build them concurrently instead of one-per-session.
Isolation is what makes this safe — each task gets its **own worktree**, so builds
never touch each other's files. Only ever fan out the **frontier**: never
parallelize two tasks with a dependency between them (a blocked task waits for its
blocker to land).

1. **Prefer AFK.** AFK tasks fan out directly. A HITL task needs human input
   first — gather every HITL task's input up front, or leave it out of the batch;
   the build loops themselves stay non-interactive.
2. **Set up per task**: `scripts/repo.sh worktree <task> <repo>` for each, and flip
   each `todo → active` (a `started` journal entry each).
3. **Fan out**: spawn one `tdd-implementer` per task **concurrently — all Agent
   calls in a single message** so they run in parallel. Give each ONLY its own
   task's acceptance criteria, its worktree as the working directory, plus
   `CONTEXT.md`/ADRs/test command. No task sees another's context.
4. **Land each independently as it returns** (pipeline, not barrier): review +
   re-run its tests → commit its slice → run the post-build gate(s) on its diff —
   `implementation-validator`, plus `otel-observability-engineer` in parallel for a
   service task that added a request path — → `active → done` only if all PASS, or
   loop that one task back to `tdd` on a CRITICAL/BLOCKER gap. One task looping back
   never holds up the others.
5. **Keep batches modest** (a few at a time) so reviews and acceptance gates stay
   tractable; a large frontier builds in waves.

**Orchestrator hygiene under fan-out (this is where parallel work breaks).** N
worktrees share **one** shell working directory and **one** set of workspace
files, so the ambient cwd drifts between tasks:

- Write `project.yaml` / `journal.yaml` / `STATUS.md` by **absolute path** — never
  rely on the shell's cwd (a drifted cwd silently writes a stray file into a
  worktree).
- Use `git -C <worktree> …` for every git op; don't `cd` to mutate the shared cwd.
- Open each PR with `scripts/repo.sh pr <task>` — its `cd` is internal, so it is
  cwd-safe and self-enforces the recorded review verdict. **This is the path to use
  under fan-out.** A **direct** `gh pr create` keys the PR gate on the *session's
  current directory* — the gate deliberately does **not** parse a leading `cd`
  (that repeatedly proved exploitable) — so run it only from **inside** the target
  worktree; a drifted cwd makes the gate block. In short: prefer `repo.sh pr`.

**Stacked work (when the task touches a code repo).** Create the worktree through
`scripts/repo.sh worktree <task> <repo>` — if the task's blocker is still in
review (its branch exists but isn't merged) it auto-stacks on that branch (or pass
`--onto <blocker>` to disambiguate), so dependent work doesn't stall waiting on
review. Before continuing on a stacked task, check `scripts/repo.sh status`: a
**BASE REOPENED** flag means the parent went back to `active` after the child
stacked on it (a security-review reopen, or a manual reopen — acceptance is settled
pre-`done`, so it won't be that) — warn the user and reconcile deliberately; never
auto-rebase.

For interactive phase *entry* (grill, and the human-input step of a HITL build)
engage once the user is ready; an AFK build runs straight through the sub-agent,
and a hand-invoked build runs inline in the main agent. For the cross-phase
*commitments* above, take the light confirm
first.

## Boundaries

- Do **not** invent or store a `phase:` field — phase is always inferred from
  artifacts, every invocation.
- Do **not** auto-continue across the planning → build seam — hand off to a fresh
  session there.
- Phase *detection* is read-only — never modify an artifact just to "advance" a
  phase. The one exception is **Bootstrap**, which writes `PROJECT.md` from the
  user's answers — that captures the goal, it does not fake advancement. Task
  status flips are an action, not detection: the invoking orchestrator (you, or
  `/next`) flips a task `todo → active` then `active → done` around the sub-agent
  build, since the sub-agent can't touch status.

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/next" ~/.claude/skills/next
```
