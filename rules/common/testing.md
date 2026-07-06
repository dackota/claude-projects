# Testing Requirements

## TDD (mandatory)

1. RED — write the test first; run it and watch it fail
2. GREEN — minimal implementation; watch it pass
3. REFACTOR — then confirm the behavior that matters is covered

Coverage is a guide, not a gate (~80% is a healthy signal, not a target). Test
observable behavior through public interfaces — never private methods or internal
collaborators. Fix the implementation, not the test (unless the test is wrong).

## Property / invariant tests

When a unit has an invariant that must hold for **every** input, assert the invariant
over generated + adversarial inputs (empty, boundary, oversized, malformed) instead of
only tabulating examples. Reach for one when:

- a pure transformation carries a structural contract (round-trip, sorted/deduped,
  valid encoding, counts match);
- the input is untrusted — the caller can hand it anything the type allows;
- the invariant is cheap to state but correct outputs are expensive to enumerate;
- the code is stateful/concurrent or owns a resource lifecycle — the real contract is
  operational ("cleanup runs exactly once on every exit path, including panic/cancel",
  "at most once per key", "never panics", "the resource ceiling holds"), which
  happy-path examples silently skip.

Write it in RED like any other test. The tell you need one: adding "…and also when the
input is empty / huge / malformed" as separate example cases. On the **first** violation
of an invariant, fix at the single chokepoint and add the property test covering the
whole class — don't patch the reported case and chase siblings across review rounds.

## Structure

AAA (Arrange-Act-Assert) with descriptive behavior names:
`returns empty array when no markets match query`.
