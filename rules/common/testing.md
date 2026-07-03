# Testing Requirements

## Coverage is a guide, not a gate

Cover the behavior that matters — critical paths, complex logic, and the edge cases a
caller can actually hit — rather than a fixed line-coverage number. ~80% is a healthy
signal, **not** a target to chase; the last stretch is usually where tests turn into
implementation-coupled noise.

Test through **public interfaces / observable behavior**, not internal units:
1. **Behavior / integration tests** — exercise real code paths through the public API
   (the default; they survive refactors).
2. **Unit tests** — for genuinely standalone pure logic (parsers, calculators), tested
   through their public surface — not private methods or internal collaborators.
3. **E2E tests** — critical user flows (framework chosen per language).

Avoid the anti-patterns: testing private methods, mocking internal collaborators, and
tautological tests (asserting the implementation against its own formula).

## Property / invariant tests (don't just tabulate examples)

Example-based tests prove the cases you thought of. When a unit has an **invariant that
must hold for _every_ input** — not just the handful you tabulated — assert that invariant
directly over generated and adversarial inputs. For the right shape of code this is the
single highest-leverage test you can write: it finds the input you *didn't* think of,
before a reviewer (or production) does.

Reach for a property/invariant test when the smell fits:

- a **pure transformation** (data in → data out, no I/O) whose output carries a
  **structural contract** — e.g. "every line of the diff starts with `+`/`-`/space", "the
  summary counts equal the rendered counts", "`decode(encode(x)) == x`", "output is
  sorted / deduplicated / valid UTF-8";
- the input is **untrusted or unvalidated** — the caller can hand it anything the type
  allows (empty, huge, malformed, missing a trailing newline);
- the correct output is **expensive to hand-write** across many cases, but the *invariant*
  is cheap to state once.

Write it in the RED phase like any other test: state the invariant as a predicate, feed it
generated inputs including the adversarial edges (empty, boundary, oversized, malformed),
and let it search. One such test typically subsumes a whole family of example cases and
catches the family member that would otherwise slip through. The tell that you need one:
you catch yourself adding "…and also when the input is empty / huge / malformed" as
separate example cases. Keep the example tests too, for specific behaviors and as readable
documentation — the property test complements them, it doesn't replace them.

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Confirm the behavior that matters is covered (coverage is a guide, not a gate)

## Troubleshooting Test Failures

1. Check test isolation
2. Verify mocks are correct (and that you're not mocking internal collaborators)
3. Fix implementation, not tests (unless the tests are wrong)

## Agent support

Use whatever test-first agent your workflow provides. In a claude-projects workspace
that's the `tdd` skill / `tdd-implementer` sub-agent (behavior-driven, one test at a
time), invoked by `/next`. There is no standalone `tdd-guide` agent in this config —
don't rely on one.

## Test Structure (AAA Pattern)

Prefer Arrange-Act-Assert structure for tests:

```typescript
test('calculates similarity correctly', () => {
  // Arrange
  const vector1 = [1, 0, 0]
  const vector2 = [0, 1, 0]

  // Act
  const similarity = calculateCosineSimilarity(vector1, vector2)

  // Assert
  expect(similarity).toBe(0)
})
```

### Test Naming

Use descriptive names that explain the behavior under test:

```typescript
test('returns empty array when no markets match query', () => {})
test('throws error when API key is missing', () => {})
test('falls back to substring search when Redis is unavailable', () => {})
```
