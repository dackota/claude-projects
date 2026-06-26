---
name: tdd
description: Test-driven development with red-green-refactor loop. The main session orchestrates — it plans the slice, then spawns a Sonnet tdd-implementer sub-agent to run the implementation loop, and reviews the result. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
origin: claude-projects
agents:
  - tdd-implementer
---

# Test-Driven Development

## Orchestration model

In a project workspace this skill runs as a **two-role split**:

- **You (the main session) orchestrate.** You pick the task, design the slice's
  interface and behavior list, hold the planning gate with the user where needed,
  then **delegate the red-green-refactor loop to a Sonnet `tdd-implementer`
  sub-agent**, review what it returns, and close the task out. You own the
  lifecycle (status flips, refactor judgment, the validation doc).
- **The `tdd-implementer` (Sonnet) implements.** Spawned fresh per slice, it gets
  the agreed plan and the task's acceptance criteria, runs the TDD loop one
  behavior at a time, and returns a structured summary. It does not talk to the
  user or touch task status.

This keeps human-facing planning and orchestration on the main model while the
mechanical implementation tokens go to Sonnet. The standards below are the
contract the implementer follows **and** the bar you review its output against.

> For a quick, throwaway TDD cycle outside a project workspace you can run the
> loop yourself — but inside a workspace, delegate it so each slice gets a fresh,
> cheap implementation context.

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

## Workflow

### 1. Plan the slice (orchestrator)

When exploring the codebase, use the vocabulary from `CONTEXT.md` (the project's domain glossary) so test names and interface vocabulary match the project's language, and respect any ADRs in `docs/adr/`.

You are usually implementing one `project.yaml` task. Pick a task whose
`blocked_by` are all `done`, and flip its `status` from `todo` to `active` when
you start — that is the journal's `started` signal. Read the task's acceptance
criteria and "what to build" from its source plan (`plan:`), or — in Jira mode —
from the issue body.

Produce the plan you will hand to the implementer:

- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the prioritized **behaviors to test** (not implementation steps)

**You can't test everything.** Focus the behavior list on critical paths and
complex logic, not every edge case.

**Planning gate — by task type:**

- **HITL task** (`type: HITL`, or the `hitl` label in Jira mode): confirm the plan
  with the user before delegating. Ask: *"What should the public interface look
  like? Which behaviors are most important to test?"* Get approval on the
  interface and the prioritized behavior list.
- **AFK task** (`type: AFK` / `afk`): derive the interface and behavior list from
  the acceptance criteria and proceed without a confirmation gate — these are
  meant to run without human gating. State the plan you derived as you dispatch.

### 2. Delegate the loop to the implementer (orchestrator)

Spawn the `tdd-implementer` agent (Agent tool, `subagent_type: tdd-implementer`)
with a fresh context. Give it:

- **The plan** — the public interface to build and the prioritized behavior list.
- **The task context** — the acceptance criteria and "what to build" description,
  the `CONTEXT.md` vocabulary, and any relevant ADRs.
- **The working directory** — the worktree the slice is being built in (see
  *Stacked work* in `/next`; create it with `scripts/repo.sh worktree` when the
  task touches a code repo).
- **The test command** — how to run this project's tests, if you know it.

The implementer runs RED→GREEN→refactor one behavior at a time and returns a
summary with `STATUS: COMPLETE | PARTIAL | BLOCKED`, the final test output,
behaviors implemented (`path:line`), files changed, refactors, assumptions, and
anything left undone or blocked.

### 3. Review what it returned (orchestrator)

Do not rubber-stamp the summary — verify it:

- **Re-run the tests yourself** to confirm the reported GREEN state is real.
- **Spot-check the tests against the discipline above** — are they behavioral
  (public interface, would survive a refactor), or did the implementer drift into
  shape-testing or horizontal slicing? If the tests are coupled to implementation,
  send it back with specific guidance.
- **Handle the status:**
  - `COMPLETE` → proceed to refactor judgment and close-out.
  - `PARTIAL` → decide whether to re-spawn the implementer to finish the remaining
    behaviors (pass it the summary + what's left), or close a narrower slice.
  - `BLOCKED` → resolve the fork it surfaced (a design decision, an undone
    dependency). If it needs the user, raise it; then re-spawn with the resolution.
- **Refactor judgment.** The implementer does in-loop refactoring, but you own the
  cross-cutting call: look for [refactor candidates](refactoring.md) the slice
  reveals about existing code (extract duplication, deepen modules, SOLID where
  natural). Apply or re-delegate as appropriate. **Never leave the tree RED.**

### 4. Close out (orchestrator)

When the task's behaviors are all GREEN and refactored:

- Flip the `project.yaml` task `status` to `done` — the journal's `done` signal.
- For a meaningful plan or milestone (not every task), write a validation doc to `docs/validations/` with the evidence (commands run, `path:line`, test output) and reference it from the `done` journal entry.

The independent acceptance check happens later, at the PR gate
(`pr-security-review` spawns `implementation-validator`) — close-out here is your
own confidence that the slice is done, not the final word.

## Checklist Per Cycle

The implementer holds itself to this each RED→GREEN; you verify it on review:

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
