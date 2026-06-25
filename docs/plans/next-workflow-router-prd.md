---
title: "/next — the workflow router (software-factory orchestrator)"
created: 2026-06-25
last_updated: 2026-06-25
status: active
supersedes: []
superseded_by: null
related:
  - docs/adr/0002-hook-enforced-repo-discipline.md
jira: null
task: null
---

# /next — the workflow router

## Problem Statement

The `claude-projects` workflow has a phase sequence the user relies on:
`grill-with-docs` → `to-prd` → `to-issues` → `tdd`. It works well, but the user
has to **remember which skill to call next** and manually drive each handoff.
Mapped against the "software factory" five-layer model (Context, Knowledge,
Agent, Workflow, Delivery), the project is strong on every layer *except*
**Workflow**: there is no orchestrator that chains the phases together. Today the
human *is* the router. New or returning sessions also pay a re-orientation tax —
the user must inspect `STATUS.md`, `project.yaml`, and `journal.yaml` and then
decide, by hand, what the next action is.

Two secondary gaps surface from the same article:

1. **No acceptance gate.** A slice is reviewed for *security* at PR time
   (`pr-security-review`) but nothing independently checks that the built code
   actually satisfies the slice's *acceptance criteria*. The article's
   "implementation-validator" role is absent.
2. **Work stalls on review.** Worktrees always branch off the repo's base
   branch, so a slice that depends on an in-review (unmerged) slice cannot be
   started — the dependent work has nowhere to build. The article's
   "continue on" / stacked-work pattern isn't supported.

## Solution

Introduce **`/next`**, a state-aware **workflow router** bundled as a skill. The
user types one command (or it runs automatically at session start) and `/next`
determines the current phase from workspace artifacts and dispatches to the right
skill — removing the need to know the sequence. It is a *dispatcher that
complements* the existing skills, not an autopilot and not a rewrite: every
phase skill stays independently invokable.

Alongside the router, close the two secondary gaps so the orchestrated flow is
complete end-to-end:

- An independent **`implementation-validator`** agent checks each slice against
  its acceptance criteria at the PR gate, sequenced ahead of the existing
  security review under one **unified PR-review gate**.
- **`repo.sh`** gains **stacked worktrees** so a dependent slice can build on an
  in-review slice's branch and work never has to stop.

From the user's perspective: *open a session, and the workspace tells you where
you are and takes you to the next step; approve at the points where your judgment
matters; never manually route again.*

## User Stories

1. As a developer in a workspace, I want a single command that tells me what
   phase the project is in, so that I don't have to inspect `project.yaml`,
   `STATUS.md`, and `journal.yaml` myself.
2. As a developer, I want the workspace to orient me automatically at session
   start, so that I don't even have to remember to ask "what's next?".
3. As a developer, I want `/next` to dispatch me straight into the correct phase
   skill, so that I never have to recall the `grill → prd → issues → tdd`
   sequence.
4. As a developer starting a brand-new workspace, I want `/next` to recognize
   there is no PRD yet and take me into grilling, so that the first step is
   obvious.
5. As a developer who just finished grilling, I want `/next` to offer to
   synthesize a PRD (and roll into it on approval), so that the planning arc
   flows without a manual handoff.
6. As a developer with an approved PRD, I want `/next` to roll into slicing the
   PRD into vertical-slice issues, so that the breakdown happens without me
   re-invoking a skill.
7. As a developer with a sliced backlog, I want `/next` to propose the next
   unblocked task in dependency order, so that I can start work with one
   keystroke.
8. As a developer, I want to be able to override the proposed task by naming
   another, so that I keep control of priority among unblocked peers.
9. As a developer, I want `/next` to prefer AFK tasks for its default proposal
   and to flag HITL tasks as needing my engagement first, so that autonomous
   work proceeds and human-gated work pauses appropriately.
10. As a developer, I want `/next` to start each task's `tdd` in a fresh session
    with only that slice's acceptance criteria, so that I avoid the context
    drift of dragging the whole planning history along.
11. As a developer, I want the planning arc (grill → prd → issues) to run in one
    continuous session, so that each phase benefits from the prior phase's live
    context.
12. As a developer, I want a light confirmation at each phase transition, so that
    I approve meaningful commitments without being nagged on every step.
13. As a developer in a Jira-backed workspace, I want `/next` to detect the PRD
    and issues from the tracker (via labels) rather than reporting "nothing
    here", so that routing is correct in Jira mode.
14. As a developer in a local (no-Jira) workspace, I want `/next` to detect the
    PRD and tasks from `docs/plans/` and `project.yaml`, so that routing works
    without a tracker.
15. As a developer, I want `/next` to re-derive the phase from artifacts every
    time it runs, so that routing stays correct even when work happened out of
    band or files changed.
16. As a developer finishing a slice, I want an independent agent to verify the
    code actually meets the slice's acceptance criteria before the PR opens, so
    that "done" means done.
17. As a developer, I want the acceptance check to run automatically at
    `gh pr create` (not only when I remember to ask), so that the gate can't be
    silently skipped.
18. As a developer, I want acceptance validation to run *before* security review
    and short-circuit on a critical acceptance gap, so that I don't spend a
    security pass on a slice that doesn't even do what it promised.
19. As a developer, I want a critical acceptance gap to reopen the task
    (`done → active`), record a blocker, and route me back into `tdd`, so that
    recovery is a defined loop, not an ad-hoc scramble.
20. As a developer, I want non-critical acceptance findings folded into the PR
    body rather than blocking, so that minor gaps are visible but don't halt
    delivery.
21. As a developer, I want the validator and security reviewer to share one PR
    gate and one verdict cache keyed by commit, so that re-pushing a fix
    re-reviews automatically without redundant runs.
22. As a developer whose branch doesn't follow the worktree naming convention, I
    want the gate to warn and fall back to security-only (rather than block), so
    that off-convention work isn't dead-ended.
23. As a developer, I want to start a slice that depends on an in-review,
    unmerged slice by building on that slice's branch, so that work doesn't stop
    while review is pending.
24. As a developer, I want stacking to be inferred automatically when a task has
    exactly one unmerged blocker with a live branch, so that I don't have to wire
    it up by hand.
25. As a developer with a task that has multiple unmerged blockers, I want to
    name the stack target explicitly, so that ambiguous stacks are unambiguous.
26. As a developer, I want a stacked slice's PR to target its parent slice's
    branch, so that its diff stays clean and reviewable.
27. As a developer, I want `repo.sh sync` on a stacked worktree to pull in the
    parent slice's review-fix commits, so that the stack stays current.
28. As a developer, I want a stacked branch to re-point to the base branch once
    its parent merges, so that the PR retargets to the base automatically.
29. As a developer, I want `repo.sh status` to flag a stacked worktree whose base
    was reopened, and `/next` to warn me, so that I don't keep building on
    shifting ground.
30. As a developer, I want an optional, invokable codebase-research skill
    available, so that I can map the codebase on demand without research becoming
    a forced phase.
31. As a workspace creator, I want `proj --skills next` to also pull in the
    skills `/next` orchestrates, so that the router isn't useless on its own.
32. As a workspace creator, I want the scaffolded `CLAUDE.md` to document the
    `/next` ritual, the unified PR-review gate, and stacked worktrees, so that
    every new workspace explains its own workflow.
33. As a maintainer, I want every phase skill to remain independently invokable,
    so that `/next` is a convenience layer and nothing that exists today breaks.

## Implementation Decisions

### Router shape and trigger

- `/next` is a **state-aware router**, not an autopilot. It detects the current
  phase and dispatches to the matching phase skill. It **complements** the
  existing skills — all remain invokable by hand.
- `/next` ships as a **single bundled skill**. All phase-detection and routing
  logic lives in that one skill (deep module / single source of truth). No
  separate state-detection script that could drift from the skill's logic.
- The router is triggered two ways: a **soft session-start instruction** added to
  the scaffolded `CLAUDE.md` (after the existing "read `STATUS.md` first" line),
  and **by hand** any time. Session-start orientation is convenience, not a
  safety invariant, so it is a soft instruction — not a hook.

### State detection

- Phase is **inferred from artifacts on every invocation**; there is no stored
  `phase:` cursor. Artifacts are the source of truth.
- The state machine:

  | State | Detected by | Dispatches to | Advances when |
  |-------|-------------|---------------|----------------|
  | Grill | no PRD anywhere | `grill-with-docs` | a PRD appears |
  | (transition) | — | `to-prd` | PRD approved |
  | Slice | PRD exists, no tasks | `to-issues` | tasks/issues appear |
  | Pick | tasks exist, none active | propose next unblocked task | a task flips active |
  | Build | a task is active | `tdd` | task flips done |
  | Validate | task done, not PR'd | `implementation-validator` | validation passes |
  | Land | — | unified PR gate (validator → security) | PR merged |

- **Grill and "shared understanding" collapse into one state**: there is no clean
  "grilling is done" artifact, so *"a PRD exists"* is the signal that grilling
  finished. Absence of a PRD means "(continue) grilling".
- `to-prd` is modeled as a **transition action** fired at the Grill→Slice
  boundary, not a standalone state.
- **Within a live session**, transitions are conversational (the human signals
  "understanding reached"); **across sessions**, the phase is re-derived from
  artifacts. These are two different triggers for the same boundary.
- **Jira and local parity.** The router reads `project.yaml`'s `jira_key` first.
  Local mode → file detection (`docs/plans/` lifecycle frontmatter, `project.yaml`
  tasks). Jira mode → query the tracker via MCP, mapping the existing
  `ready-for-agent` / `afk` / `hitl` labels plus standard To Do / In Progress /
  Done statuses to phases. No custom universal status mapping is invented.

### Session seams

- **Planning arc = one continuous session**: `grill-with-docs` → `to-prd` →
  `to-issues`, auto-chained inline with a **light confirm at each gate**. These
  phases compound context productively (`to-prd` explicitly synthesizes the live
  grill context; `to-issues` slices the live PRD).
- **Session seam at planning → build**: after the breakdown is approved, the
  router hands off and recommends starting a fresh session.
- **Build arc = one fresh session per task**: `tdd` runs with only that slice's
  acceptance criteria as context; on done, the Land gate fires at PR. The next
  task is the next fresh session.

### Pick behavior

- The router **auto-proposes** the next unblocked task in dependency order; one
  keystroke accepts, or the user names another (the router can't infer business
  priority among unblocked peers, but shouldn't reintroduce the "what do I do
  next" friction either).
- **AFK-preferred default**; **HITL surfaced** as needing human engagement before
  building.

### Validator and the unified PR-review gate

- A new independent **`implementation-validator`** agent (read-only; cloned from
  the existing `security-reviewer` agent's shape) compares a slice's diff against
  its acceptance criteria. It is **per-task**, firing at the Build→Land boundary.
- The validator and security reviewer are **two distinct agents** (different
  prompts, different failure modes, separate verdicts), **sequenced
  validator → security** at **one unified PR-review gate**. There is no point
  security-reviewing a slice that fails acceptance.
- The gate is **hook-enforced** at `gh pr create` (defense in depth — the router
  is convenience, the hook is the guarantee). It derives the task from the
  worktree/branch layout (`worktrees/<task-id>/<repo>`), looks up the task's
  source PRD/issue, and validates against its acceptance criteria.
- Severity model **mirrors `pr-security-review` exactly**: shared
  CRITICAL/HIGH/MEDIUM/LOW vocabulary, one **sha-keyed verdict cache** under
  `.git/`, findings folded into the PR body. **CRITICAL blocks**; HIGH/MEDIUM/LOW
  are noted (block threshold is CRITICAL-only, matching security).
- **Loop-back** on a CRITICAL acceptance gap: the router flips the task
  `done → active` (writing a `blocker` journal entry) and re-enters `tdd`. New
  commits re-validate via the sha-keyed cache.
- If the task can't be derived from the branch/worktree (off-convention work),
  the gate **warns and falls back** to security-only rather than blocking.
- This **rescopes `pr-security-review` into the unified PR-review gate** — its
  scope note broadens from security-only to "PR review (acceptance + security)".
  The *plumbing* is unified (one hook, one cache, one short-circuit); the two
  *agents* stay distinct.

### Stacked worktrees in `repo.sh`

- `repo.sh worktree` gains **stacking**: a dependent slice can branch off an
  in-review (unmerged) slice's branch instead of the base branch.
- The stack relationship is recorded as the **branch's git upstream** — not a new
  `project.yaml` field. `blocked_by` already encodes the dependency; duplicating
  it would drift. Default worktrees track `origin/<base>`; stacked worktrees track
  the parent branch.
- Stacking is **auto-derived** when a task has exactly **one unmerged blocker with
  a live branch**; an explicit **`--onto <task>`** disambiguates multiple
  blockers or non-`blocked_by` stacks (hybrid trigger).
- `sync` merges the worktree's upstream — so a stacked worktree pulls in the
  parent's review-fix commits. When the parent **merges to base**, the child's
  upstream is **re-pointed to the base branch** and the PR retargets.
- A stacked slice's **PR targets its parent's branch** (a stacked PR); the diff
  stays clean.
- **Base-reopen handling**: if a stacked parent reopens (`done → active` via
  validator loop-back), `repo.sh status` **flags** the child as "base reopened"
  and `/next` **warns** before further work. **No automatic rebasing** of a
  disturbed stack — warn, don't auto-magic.

### Optional research skill

- A new optional, invokable **`codebase-researcher`** skill (read-only codebase
  mapper) is bundled. Research is **not** a forced phase; `grill-with-docs`
  already explores before decisions are made. `/next` may offer a research detour
  mid-grill when a deep unknown surfaces, but never gates on it.

### Packaging

- New: `skills/next/`, `agents/implementation-validator.md`,
  `skills/codebase-researcher/`.
- The validator agent is declared via the PR-review skill's `agents:` frontmatter
  so the existing agent-install path copies it (as `pr-security-review` already
  pulls `security-reviewer`).
- `proj.sh` wiring: add the session-start line to the scaffolded `CLAUDE.md`
  heredoc; treat `/next`'s companion skills (`grill-with-docs`, `to-prd`,
  `to-issues`, `tdd`) as **dependencies** of `--skills next`; wire the new
  hook/agent-bearing skills into the settings-merge path.

## Testing Decisions

A good test verifies **observable behavior through the public interface**, not
implementation details — for these bash modules, the public interface is the CLI
command and its effects on git/filesystem/`project.yaml`. Tests should survive
internal refactors of the scripts.

Tested modules (bash; the markdown skills/agents are model-driven prompts and are
**not** unit-tested — they're validated by dogfooding the flow on a real
workspace):

1. **`repo.sh` stacking** — highest bug risk (real branching logic). Prior art:
   the existing `repo.sh` smoke-test style. Cover, via observable git/FS state:
   - `worktree --onto <task>` branches the child off the parent branch and sets
     the parent as the child's upstream.
   - Auto-derive stacks when exactly one unmerged blocker with a live branch
     exists; do **not** auto-stack with zero or multiple such blockers.
   - `sync` on a stacked worktree merges the parent branch's new commits.
   - On parent merge to base, the child's upstream re-points to base.
   - `status` flags a stacked worktree whose base was reopened.
2. **`proj.sh` wiring** — extend `scripts/test-proj.sh`. Cover:
   - The scaffolded `CLAUDE.md` contains the session-start `/next` line.
   - `--skills next` also installs the companion skills (dependency resolution).
   - New hook/agent-bearing skills merge correctly into the workspace
     `.claude/settings.json` (idempotent).
3. **Unified PR-gate hook** — cover, by invoking the hook script directly:
   - Task derivation from a `worktrees/<task-id>/<repo>` branch.
   - Validator runs before security; a CRITICAL acceptance verdict
     short-circuits before security runs.
   - Warn-and-fall-back to security-only when the task can't be derived.
   - Sha-keyed cache prevents redundant re-runs on an unchanged commit.

## Out of Scope

- **Full autopilot** that runs all phases end-to-end without session breaks —
  explicitly rejected in favor of the hybrid router (fights the interactive
  nature of grill/tdd and invites context drift).
- **A mandatory research phase** — `codebase-researcher` is optional and
  invokable only.
- **Automatic rebasing** of a disturbed stack when a parent reopens — warn only.
- **A custom universal Jira status mapping** — rely on existing label
  conventions plus standard statuses.
- **Unit-testing the markdown skills/agents** — validated by dogfooding instead.
- **Mid-grill progress detection** — the router cannot sense how far along a
  grilling session is; it only knows "PRD exists or not".
- **Agent-generated milestone validation docs** — the per-task validator is the
  automated gate; the `docs/validations/` milestone doc stays a human/close-out
  artifact.

## Further Notes

- This design supplies the **Workflow layer** the project was missing; the
  Knowledge (`CLAUDE.md`/`STATUS.md`/`journal.yaml`/`CONTEXT.md`), Agent
  (reviewer agents), and Delivery (`pr-security-review`, `repo.sh`) layers already
  exist.
- The work is captured here as a local PRD because this bootstrap repo has no
  `jira_key`. Vertical slices will be produced by `to-issues` into `project.yaml`
  tasks / `docs/plans/` (or, when the repo gains a tracker, Jira).
- Likely a good candidate for an **ADR** on rescoping `pr-security-review` into a
  unified PR-review gate (hard to reverse, surprising without context, a real
  trade-off vs. a separate sibling skill) — to be offered during issue breakdown
  or implementation.
- Dogfooding note: this PRD was itself produced by walking the very flow being
  automated (grill → to-prd), which is the intended validation pattern for the
  markdown modules.
