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

## Reference

See skill: `golang-testing` for detailed Go testing patterns and helpers.
