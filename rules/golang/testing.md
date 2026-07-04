---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Testing

> This file extends [common/testing.md](../common/testing.md) with Go specific content.

## Framework

Use the standard `go test` with **table-driven tests**.

## Race Detection

Always run with the `-race` flag:

```bash
go test -race ./...
```

## Coverage

```bash
go test -cover ./...
```

## Property / invariant tests

For a pure function whose output has an invariant that must hold for every input (see
[common/testing.md](../common/testing.md)), assert the invariant over generated inputs
instead of only tabulating examples:

- **`testing/quick`** — `quick.Check(func(x T) bool { … }, nil)` runs a predicate against
  randomized inputs; the lightest way to assert "property P holds for all inputs".
- **Native fuzzing** — `func FuzzXxx(f *testing.F)` with `f.Add(seed)` corpus entries and
  `f.Fuzz(func(t *testing.T, in []byte) { … })`; run `go test -fuzz FuzzXxx -fuzztime=30s`
  locally / in CI, and commit the crashers it writes under `testdata/fuzz/` as permanent
  regression seeds.

One invariant test over adversarial inputs (empty, missing trailing newline, oversized)
catches the edge a `-race` example table misses.

### Lifecycle & concurrency invariants (not just pure functions)

The same doctrine applies to stateful/concurrent code — the class Go makes easy to get
subtly wrong (goroutines, semaphores, caches, temp dirs). Assert the *operational*
invariant, in RED, over the failure modes an example test skips:

- **Cleanup on every exit, including panic.** Inject a dependency (a fake satisfying the
  seam) that **panics**, and assert the function recovers to a classified error AND leaks
  nothing. Detect leaks deterministically by redirecting the temp base —
  `t.Setenv("TMPDIR", t.TempDir())` (Go's `os.MkdirTemp("", …)` honours `$TMPDIR`), then
  assert no stray entry remains. Table it across every code path that owns the resource
  (each side/branch), since a fix that moves cleanup can reopen a leak on one path only.
- **At most once / determinism under concurrency.** Use a **counting fake** and fire N
  concurrent callers for the same key; assert the guarded work ran at most once and every
  caller got the same result. Run these under `go test -race` (see above) — a passing
  example test under `-race` is not evidence the invariant holds for a *colliding* key.
- **Never panics / bound holds.** For any input (incl. adversarial repo/file content), the
  entry point returns a classified result, never panics, and any size/count/depth ceiling
  holds — assert with `testing/quick` or a fuzz target, not a hand-picked case.

## Reference

See skill: `golang-testing` for detailed Go testing patterns and helpers.
