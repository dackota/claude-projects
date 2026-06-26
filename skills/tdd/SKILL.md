---
name: tdd
description: Test-driven development with red-green-refactor loop. When a human invokes /tdd directly it runs inline in the main agent (interactive — plan + drive the loop yourself). When /next builds a task it instead spawns the Sonnet tdd-implementer sub-agent to complete it (both AFK and HITL). Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
origin: claude-projects
agents:
  - tdd-implementer
---

# Test-Driven Development

## How this skill runs

`/tdd` runs in one of two modes, decided by **who invoked it**:

- **Main-agent mode (interactive)** — a human invoked `/tdd` directly, ad hoc. You
  run the whole cycle **in this session**: plan the slice (confirming the interface
  and behaviors with the user), drive RED→GREEN→refactor yourself so they can watch
  and steer, and close it out. This is what the workflow below describes.
- **Subagent mode (orchestrated)** — `/next` is building a task. It does **not**
  run this skill inline; it spawns the Sonnet **`tdd-implementer`** sub-agent on a
  fresh context to run the loop, then reviews the structured summary it returns.
  This applies to **both AFK and HITL** tasks — for a HITL task the orchestrator
  gathers the user's input at the planning gate first, then hands the cleared plan
  to the sub-agent. (See `/next`'s Build arc for how it dispatches.)

If you are reading this in the main session because a human invoked `/tdd`, you are
in **main-agent mode** — run the loop here. The sub-agent path is `/next`'s to
drive, and the `tdd-implementer` holds itself to the same discipline below.

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

## Workflow (main-agent mode)

### 1. Plan the slice

When exploring the codebase, use the vocabulary from `CONTEXT.md` (the project's domain glossary) so test names and interface vocabulary match the project's language, and respect any ADRs in `docs/adr/`.

You are usually implementing one `project.yaml` task. Pick a task whose
`blocked_by` are all `done`, and flip its `status` from `todo` to `active` when
you start — that is the journal's `started` signal. Read the task's acceptance
criteria and "what to build" from its source plan (`plan:`), or — in Jira mode —
from the issue body.

Design the slice:

- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the prioritized **behaviors to test** (not implementation steps)

**You can't test everything.** Focus the behavior list on critical paths and
complex logic, not every edge case.

A human is present in this mode, so **confirm the plan before writing tests** —
ask *"What should the public interface look like? Which behaviors are most
important to test?"* and get agreement on the interface and the prioritized
behavior list.

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

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what the new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

### 5. Close out

When the task's behaviors are all GREEN and refactored:

- Flip the `project.yaml` task `status` to `done` — the journal's `done` signal.
- For a meaningful plan or milestone (not every task), write a validation doc to `docs/validations/` with the evidence (commands run, `path:line`, test output) and reference it from the `done` journal entry.

The independent acceptance check happens later, at the PR gate
(`pr-security-review` spawns `implementation-validator`) — close-out here is your
own confidence that the slice is done, not the final word.

## Checklist Per Cycle

The same discipline binds the `tdd-implementer` sub-agent in orchestrated mode:

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
