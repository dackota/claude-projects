---
name: next
description: Workflow router for a claude-projects workspace. Reads workspace state, determines the lifecycle phase, and routes to the next action. Use at session start or whenever you ask "where am I / what's next?".
origin: claude-projects
agents:
  - implementation-validator
  - correctness-reviewer
  - runtime-validator
  - integration-reviewer
---

# /next — the workflow router

A dispatcher, not an autopilot: it reads workspace state, determines the **phase**,
and routes into the skill that handles it. Every phase skill (`grill-with-docs`,
`to-prd`, `to-issues`, `tdd`) stays directly invokable by hand.

Re-derive the phase from artifacts **every** invocation — never trust a stored
cursor; work may have happened out of band since you last looked.

### 0. Preflight

Run `bash .claude/skills/next/next-preflight.sh` before routing. It verifies the
required scripts, gate/build agents, companion skills, and hooks are present — a
degraded install otherwise routes a barrier whose gates don't exist, shipping PRs
with no independent review, silently. If it reports anything missing, surface that
and stop — resolve it (`proj update-skills`, or re-scaffold) before routing.

### 1. Read the state signals

Read `project.yaml` first — `jira_key` empty → **local mode**; set → **Jira mode**.
Glance at `PROJECT.md`: Goals still the scaffold placeholder → **Bootstrap**, which
outranks every other signal.

**Local mode:** `project.yaml` `tasks[]` (`status`: todo/active/done/blocked,
`blocked_by`) · `docs/plans/*-prd.md` (an active PRD = grilling produced a plan) ·
`STATUS.md` (primary long-memory read; a synthesis, can be stale) · `journal.yaml`
**tail only** (the last ~15 entries) for momentum. Fallback: if `STATUS.md` is missing or
older than the newest journal entries, read the full journal instead.

**Jira mode:** query the tracker via the Atlassian MCP, reading the labels
`to-prd`/`to-issues` write: a `ready-for-agent` issue is the PRD (none → Grill);
slice issues carry `afk`/`hitl` (PRD with no slices → Slice); statuses map
To Do ≈ todo, In Progress ≈ active (→ Build), Done ≈ done (Done but un-PR'd →
Land); a slice's blockers are its "is blocked by" links — unblocked when all are
Done. Don't invent mappings beyond these; a non-standard board → say so and fall
back to the labels.

### 2. Determine the phase

First row that holds wins:

| Phase | Detected by | Next action |
|-------|-------------|-------------|
| **Bootstrap** | `PROJECT.md` Goals empty/placeholder | Interview the user for goal + context, write `PROJECT.md` (keep frontmatter), re-derive the phase. Never proceed silently or invent a goal |
| **Grill** | no active PRD in `docs/plans/` | `grill-with-docs`; at shared understanding → `to-prd` (no "grilling done" artifact exists — an active PRD is the only completion signal) |
| **Slice** | PRD exists, `tasks[]` empty | `to-issues` |
| **Pick** | tasks exist, none `active` | Pick the next unblocked task → build via `tdd-implementer` (HITL: gather its input first) |
| **Land** | a task is `done` but not PR'd | Open the PR; a release/deploy task also runs [RELEASE-VERIFY.md](./RELEASE-VERIFY.md) |
| **Build** | a task is `active` | Continue the build — including closing barrier-flagged gaps |
| **Done** | all tasks done and landed | Nothing to route |

Bootstrap is the one phase whose action edits an artifact — that artifact is the
prerequisite for everything after it.

### 3. Pick rules

Consider only tasks whose `blocked_by` are all `done` (the unblocked frontier).
Recommend one in dependency order — prefer **AFK** (no human input needed); the user
may pick any unblocked peer. If the best candidate is **HITL**, surface that: it
needs its flagged human input *before* the build; the loop runs non-interactively
once the input is in hand.

### 4. Report and dispatch

State the phase and the evidence that placed the user there ("PRD exists, 8 tasks,
none active → **Pick**"), then act:

**Planning arc — auto-chain in one session.** Grill, `to-prd`, and Slice compound
context; run them back-to-back with a light confirm at each boundary ("generate the
PRD? [y]", "slice it into issues? [y]"). A deep unknown mid-grill may take an
optional `codebase-researcher` detour — never a gate.

**Planning → build seam — fresh session.** After slices are approved, stop — tell
the user to start a fresh session; the next `/next` picks up the first task. A task
needs only its own acceptance criteria, not the planning history.

**Build arc — one task per fresh session**, via the Sonnet `tdd-implementer`
sub-agent (non-interactive loop; hand-invoked `/tdd` instead runs inline in the
main agent):

1. Flip the task `todo → active`; set up the worktree (`scripts/repo.sh worktree …`
   for a code repo).
2. **AFK** → spawn `tdd-implementer` directly (design settled upstream). **HITL** →
   gather the flagged human input first, fold it into the brief.
3. Brief the sub-agent with: acceptance criteria (+ any HITL input), `CONTEXT.md`
   vocabulary, relevant ADRs, the applicable coding standards (general +
   language-specific), the security-posture list from `STATUS.md`, the working
   directory, and the test command. If the slice is a pure transformation with a
   structural output invariant, or takes untrusted input, name the invariant and ask
   for a **property/invariant test** over generated + adversarial inputs up front
   (`rules/common/testing.md`) — catch the failure class in RED, not after a gate
   loop-back. The sub-agent returns `COMPLETE | PARTIAL | BLOCKED`.
   Review with a **cheap smoke, not a re-validation**: run the declared build/test
   command once and scan that tests are behavioral — the barrier's fresh gates do
   the rigorous, independent validation; duplicating them is spent tokens, not added
   assurance. Then spot-verify (don't re-run) the reported **Format & lint** result —
   the implementer runs the declared `validation.format_cmd`/`lint_cmd`/`test_cmd`
   when set, else the inferred toolchain, at close-out; if a
   spot-check shows it's actually dirty, record a `format-lint` `run` entry and
   re-spawn to clean it — no full BLOCK for formatting. On `BLOCKED` (a mid-build
   fork), gather what's needed and re-spawn. Don't flip `done` yet.
4. **Post-build barrier — [BARRIER.md](./BARRIER.md) (normative).** On a clean
   `COMPLETE` review, commit the slice, then run: acceptance + correctness always,
   runtime when the diff is runnable, observability for service tasks — **one
   parallel message**. Append a `run` journal entry per gate. **All PASS** (runtime
   SKIP counts as pass) → write the per-slice validation record, flip
   `active → done`, then Land. **Any BLOCK** → stay `active`, journal the findings,
   re-spawn `tdd-implementer` to close the gaps, re-run the failed gate(s) on the
   new `HEAD`.

**Build (resume):** re-dispatch with the prior summary and what's left. If the
latest `blocker` entry is a barrier-gate BLOCK, frame the work as closing those
findings — read them first and pass them to the sub-agent — then re-run the failed
gates on the new `HEAD`.

**Land:** open the PR with `scripts/repo.sh pr` — it self-enforces the recorded
barrier verdict (acceptance + correctness PASS for HEAD), the integration verdict
(when recorded), and the security verdict before it pushes; security itself runs at
`gh pr create`. A PR assembling **multiple slices** (a stack, or the last slice of a
PRD/epic) first runs the integration review per
[INTEGRATION-REVIEW.md](./INTEGRATION-REVIEW.md); a single-slice PR skips it. A
release/deploy task also runs **release-verify** per
[RELEASE-VERIFY.md](./RELEASE-VERIFY.md).

**Parallel fan-out (opt-in):** two or more mutually independent unblocked tasks and
the user asks ("build the next N in parallel") →
[PARALLEL-BUILDS.md](./PARALLEL-BUILDS.md). Single-task builds don't need it.

**Stacked work:** `scripts/repo.sh worktree <task> <repo>` auto-stacks on an
unmerged blocker branch (`--onto <blocker>` to disambiguate), so dependent work
doesn't stall in review. Before continuing a stacked task, check
`scripts/repo.sh status` — **BASE REOPENED** means the parent went back to `active`
after the child stacked on it: warn the user and reconcile deliberately; never
auto-rebase.

## Boundaries

- Never invent or store a `phase:` field — phase is inferred from artifacts, every
  invocation.
- Never auto-continue across the planning → build seam.
- Phase detection is read-only. Actions are not detection: Bootstrap writes
  `PROJECT.md` from the user's answers, and the orchestrator flips task status
  around the sub-agent build (the sub-agent can't touch status).

## Session hygiene

Keep the orchestrator thread lean: start fresh sessions at natural seams (a slice
landed/PR'd; the planning → build seam), delegate broad exploration to read-only
sub-agents keeping only conclusions + `file:line` pointers, and link to
`docs/validations/` + `journal.yaml` rather than restating gate detail into the
thread.
