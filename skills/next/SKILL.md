---
name: next
description: Workflow router for a claude-projects workspace. Reads workspace state, determines the current lifecycle phase, and recommends (and routes to) the next action — grill-with-docs → to-prd → to-issues → tdd → PR. Use at session start or any time you ask "where am I / what's next?".
origin: claude-projects
---

# /next — the workflow router

`/next` removes the need to remember which skill to call next. It reads the
workspace's own state, figures out which **phase** the project is in, and tells
you the recommended next action — then routes you into the skill that handles it.

It is a **dispatcher, not an autopilot**, and it **complements** the phase skills
— every one of them (`grill-with-docs`, `to-prd`, `to-issues`, `tdd`) stays
directly invokable by hand. `/next` just spares you the routing decision.

> `/next` covers the full flow: phase detection (local **and Jira** mode),
> auto-dispatch with session seams, the acceptance-validator gate, acceptance
> loop-back, and stacked-worktree integration.

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
| **Pick** | tasks exist, none `active` | Pick the next unblocked task, then build it via the `tdd-implementer` sub-agent (HITL gets a planning gate first) — see selection + dispatch rules |
| **Build** | a task is `active` | Continue building it via the sub-agent |
| **Land** | a task is `done` but not yet PR'd | Open the PR (the PR-review gate runs at `gh pr create`) |
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
- **Prefer an `AFK` task** for the default recommendation; it can proceed without
  human gating.
- If the best candidate is `HITL`, **surface that** — say it needs the human's
  engagement (a design decision or review) before building, rather than silently
  starting it.
- Recommend one task in dependency order, but make clear the user can pick a
  different unblocked task — priority among unblocked peers is theirs to decide.

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

**Build arc — one task per fresh session.** When `/next` builds a task it runs the
work **as a sub-agent**, whatever the type — the orchestrator (you) stays lean and
the implementation context is disposable. For each build:

1. Flip the task `todo → active` and set up the worktree.
2. **HITL task** → do the human-facing planning gate yourself first (you're the
   orchestrator and *can* talk to the user): confirm the public interface and the
   prioritized behaviors. Then spawn the `tdd-implementer` (Agent tool,
   `subagent_type: tdd-implementer`) with that **cleared plan**.
   **AFK task** → derive the plan from the acceptance criteria (or leave it to the
   sub-agent) and spawn `tdd-implementer` directly — no human gate.
3. The sub-agent runs the red-green-refactor loop on a fresh context and returns a
   `COMPLETE | PARTIAL | BLOCKED` summary. Review it (re-run the tests; check the
   tests are behavioral, not implementation-coupled), flip `active → done` on a
   clean pass, and proceed to the PR gate.

A human who invokes `/tdd` by hand runs it **inline in the main agent** instead
(the skill's interactive main-agent mode) — that path does not spawn the sub-agent.

- **Pick**: propose the next unblocked task per the selection rules (id + title,
  type, and that other unblocked tasks exist if they do). On accept, build it as
  above (sub-agent either way; a HITL task gets the planning gate first); the user
  may name a different unblocked task instead.
- **Build**: a task is already `active` → continue building it — re-dispatch to the
  sub-agent with the prior summary and what's left. If it was reopened by a
  validator loop-back (it went `done → active` with a recent `blocker` journal
  entry), frame the work as *closing the flagged acceptance gaps* — read the gate's
  CRITICAL findings first and pass them to the sub-agent — not as starting fresh.

**Stacked work (when the task touches a code repo).** Create the worktree through
`scripts/repo.sh worktree <task> <repo>` — if the task's blocker is still in
review (its branch exists but isn't merged) it auto-stacks on that branch (or pass
`--onto <blocker>` to disambiguate), so dependent work doesn't stall waiting on
review. Before continuing on a stacked task, check `scripts/repo.sh status`: a
**BASE REOPENED** flag means the parent looped back to `active` (an acceptance
loop-back) — warn the user and reconcile deliberately; never auto-rebase.

For interactive phase *entry* (grill, or a hand-invoked `tdd`) dispatch immediately
once the user is clearly ready; an orchestrated build goes to the sub-agent (a HITL
task after its planning gate). For the cross-phase *commitments* above, take the
light confirm first.

## Boundaries

- Do **not** invent or store a `phase:` field — phase is always inferred from
  artifacts, every invocation.
- Do **not** auto-continue across the planning → build seam — hand off to a fresh
  session there.
- Phase *detection* is read-only — never modify an artifact just to "advance" a
  phase. The one exception is **Bootstrap**, which writes `PROJECT.md` from the
  user's answers — that captures the goal, it does not fake advancement. Task
  status flips are an action, not detection: `/next` flips a task `todo → active`
  then `active → done` around an orchestrated (sub-agent) build, since the
  sub-agent can't; a hand-invoked `tdd` flips its own status inside the skill.

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/next" ~/.claude/skills/next
```
