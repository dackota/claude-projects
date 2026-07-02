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
