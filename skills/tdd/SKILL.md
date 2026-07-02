---
name: tdd
description: Test-driven development with red-green-refactor loop. Never requires interaction (the design was settled in grilling / to-prd / to-issues). Runs two ways by caller — hand-invoked, the main agent (Opus) runs the loop inline for an ad-hoc request; via /next, the Sonnet tdd-implementer sub-agent builds the slice autonomously. Use when building a slice from its acceptance criteria, or for an ad-hoc test-first request.
origin: claude-projects
agents:
  - tdd-implementer
---

# Test-Driven Development

## How this runs

`/tdd` builds **one slice via the red-green-refactor loop, and the loop itself
never requires interaction** — an AFK task's design was settled upstream (grilling,
confirmed in `to-prd` and `to-issues`), so its acceptance criteria are a complete
contract. A **HITL task is the exception**: it was flagged HITL precisely *because
it needs human input* (a decision or answer that couldn't be settled upstream), so
that input is gathered **before** the loop runs — then the loop runs
non-interactively like any other. There are two ways it runs, decided by **who
invoked it**:

- **Hand-invoked → main-agent mode.** You ran `/tdd` directly. The main agent
  (Opus) runs the loop **inline, in this session** — the path for an ad-hoc request
  where you want the main model doing the implementation itself, with you watching.
  Derive the plan from the task's acceptance criteria (or, for an ad-hoc request
  with no task, from what you were asked) and run — no planning gate. The user is
  right here, so if the task is HITL or a question genuinely arises, just ask, then
  continue; the skill never *requires* it. The rest of this file describes this mode.
- **`/next` build → subagent mode.** `/next` (the orchestrator) builds the task by
  spawning the Sonnet **`tdd-implementer`** sub-agent on a fresh context — the
  autonomous pipeline path. For a HITL task `/next` gathers the needed human input
  first (it can talk to the user; the sub-agent can't), then hands it to the
  sub-agent. The orchestrator flips the task `active`, spawns the sub-agent, reviews
  its `COMPLETE | PARTIAL | BLOCKED` summary, then runs the **post-build barrier**:
  it commits the slice and spawns, in parallel, a fresh `implementation-validator`
  (acceptance criteria) and a fresh `correctness-reviewer` (diff-introduced
  correctness bugs) *before* marking the task done, then writes the slice's
  validation record. A `BLOCK` from either — a promised behavior undelivered or a
  real bug introduced — loops straight back to this sub-agent with the findings; the
  task never reaches `done` (or a PR) until both pass. Only on `PASS` does the
  orchestrator close out. This keeps the orchestrator lean and the implementation
  tokens on the cheaper model. The sub-agent follows the same discipline below.

No mode gates the *loop* on a confirmation prompt. If a genuine design fork the
criteria didn't settle comes up mid-build, surface it (inline mode) or return
`BLOCKED` (subagent mode) rather than guessing — that's reactive, not a routine gate.

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Anti-Pattern: Tautological Tests

A **tautological test** computes its expected value the same way the code under test does, so it asserts the implementation against itself and can never fail for the reason that matters. If the test reuses the production formula, calls the same function to build the expected value, or shares the same constant, it stays green no matter how wrong the behavior is.

```
WRONG (tautological):
  expect(discount(order)).toBe(order.total * 0.1)   // mirrors the impl's own formula
RIGHT (independent):
  expect(discount({ total: 200 })).toBe(20)         // a hand-computed expected value
```

Assert against **independently known** expected values — hand-computed, taken from the spec, or a fixed literal. See [tests.md](tests.md).

## Workflow (main-agent / inline mode)

### 1. Plan the slice (no gate)

Use the vocabulary from `CONTEXT.md` (the project's domain glossary) so test names and interface vocabulary match the project's language, and respect any ADRs in `docs/adr/`.

If you're implementing a `project.yaml` task, pick one whose `blocked_by` are all
`done`, flip its `status` `todo → active` (the journal's `started` signal), and
read its acceptance criteria from the source plan (`plan:`) or the Jira issue. For
an ad-hoc request with no task, the request itself is the spec.

If the task is **HITL**, it needs human input before you build — the user is in the
session with you, so get the decision or answer it flagged now, then proceed.

Derive the plan — don't confirm it:

- [ ] Identify opportunities for **deep modules** (small interface, deep implementation) — vocabulary and heuristics in the `codebase-design` skill (`.claude/skills/codebase-design/SKILL.md`)
- [ ] Design interfaces for **testability** (`.claude/skills/codebase-design/INTERFACE-DESIGN.md`)
- [ ] List the prioritized **behaviors to test** (not implementation steps) — critical paths and complex logic first; you can't test everything

**Seams gate.** Test only at a seam the acceptance criteria name — `to-prd` sketched
the seams (highest seam, ideal number is one) and `to-issues` recorded them per slice.
Do not invent a seam mid-build. If the criteria name no seam, or building reveals the
promised behavior can only be reached through a seam the criteria didn't name, that's a
design fork the criteria didn't settle: in inline mode surface it and get agreement; in
subagent mode return `BLOCKED` with the seam question. **No test is written at an
unconfirmed seam.**

### 2. Tracer bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet — it proves the path works end-to-end.

### 3. Incremental loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass the current test
- Don't anticipate future tests
- Keep tests focused on observable behavior
- Observable by default (every slice): structured single-line logs to stdout at
  correct levels, and errors are never swallowed — propagate/handle with context.
- If a criterion calls for **service** observability (RED metrics, trace-correlated
  logs, spans), build it and its tests in the same loop, to the Service standard in
  `.claude/skills/observability/standard.md`.

### 4. Close out

The red-green loop is done when the task's behaviors are all GREEN. **Refactoring is
not part of the loop** — it happens here at close-out, once nothing is RED.

**Refactor pass.** With everything GREEN, look for refactor candidates — deepen
shallow modules (`.claude/skills/codebase-design/DEEPENING.md`); the fuller
standards/spec pass is the `code-review` skill — before declaring the slice done:

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what the new code reveals about existing code
- [ ] Run tests after each refactor step

Never restructure while RED — get to GREEN first. In **subagent mode** this pass is
enforced independently: the post-build `implementation-validator` gate checks it, so a
slice that skipped a needed refactor can loop back. In **inline mode** it's your own
close-out check.

Then:

- Flip the `project.yaml` task `status` to `done` — the journal's `done` signal (skip for an ad-hoc request with no task).
- Write the **validation record** to `docs/validations/<task>.md` (workspace lifecycle frontmatter) with the evidence — commands run, `path:line`, test output — and reference it from the `done` journal entry. In inline mode you are the reviewer, so this is your own close-out evidence; in `/next` subagent mode the orchestrator writes it from the gates' output instead (see below).

In subagent mode (`/next`), an **independent post-build barrier** runs immediately
after this loop — `/next` commits the slice and spawns, in parallel, a fresh
`implementation-validator` (acceptance criteria, including the refactor pass above)
and a fresh `correctness-reviewer` (diff-introduced correctness bugs) before the
task is marked done, then writes the slice's validation record from their evidence;
a `BLOCK` from either loops straight back here. In inline mode there is no auto-gate
(you're watching live) — close-out here is your own confidence that the slice is
done; run `/pr-security-review` by hand if you want an independent pass. Either way,
security is reviewed later at the PR gate.

## Checklist Per Cycle

The same discipline binds the `tdd-implementer` sub-agent in subagent mode:

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
