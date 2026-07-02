---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Code Review

> This file extends [common/code-review.md](../common/code-review.md) with Go specific content.

The **when-to-review**, **severity levels**, and **approval criteria** live in
[common/code-review.md](../common/code-review.md) — don't repeat them. This file adds only
the Go-specific findings to flag, plus the diagnostics that surface them. Style and security
rationale live in [coding-style.md](./coding-style.md) and [security.md](./security.md); here
they're the review *lens* — what to catch in a diff.

## Run these first

```bash
git diff -- '*.go'      # scope the review to changed Go files
go vet ./...            # suspicious constructs
staticcheck ./...       # idiom + correctness lint (if installed)
golangci-lint run       # aggregate linters (if configured)
go build -race ./...    # data-race instrumentation
go test -race ./...     # races under test
govulncheck ./...       # known-vulnerable dependencies
```

Findings from these tools are evidence — cite the file:line, don't just restate the tool.

## CRITICAL — block the merge

**Security** (see [security.md](./security.md)):
- SQL built by string concatenation instead of parameterized queries (`database/sql`)
- Unvalidated input reaching `os/exec` (command injection)
- User-controlled file paths without `filepath.Clean` + prefix containment check
- `unsafe` package used without a documented justification
- Hardcoded secrets — keys, passwords, tokens
- `tls.Config{InsecureSkipVerify: true}` outside a test

**Error handling:**
- Errors discarded with `_` (or ignored entirely) on a path that can fail
- `return err` bare where the caller loses context — wrap with `fmt.Errorf("...: %w", err)`
- `panic` used for a recoverable condition — return an error instead
- Sentinel comparison via `err == ErrX` instead of `errors.Is` / `errors.As`

**Concurrency (data races):**
- Shared state mutated from goroutines without a mutex, channel, or `sync/atomic`
- Loop variable captured by reference in a goroutine (pre-1.22 semantics / lingering pattern)

## HIGH — should fix before merge

**Concurrency:**
- Goroutine with no cancellation path — thread a `context.Context`
- Send on an unbuffered channel with no guaranteed receiver (deadlock risk)
- Goroutines spawned without `sync.WaitGroup` / errgroup coordination
- Mutex locked without `defer mu.Unlock()` where an early return can skip the unlock

**Code quality:**
- Functions > 50 lines or nesting > 4 levels — prefer early returns
- Mutable package-level variables (hidden global state)
- Interface defined at the producer with a single consumer (interface pollution) — "accept
  interfaces, return structs"
- `defer` inside a loop accumulating resources until the function returns

## MEDIUM — consider

- String concatenation in a loop — use `strings.Builder`
- Slice growth without `make([]T, 0, cap)` pre-allocation on a known size
- Database queries issued inside a loop (N+1)
- `ctx context.Context` not the first parameter
- Non–table-driven tests where cases obviously tabulate (see [testing.md](./testing.md))
- Error strings capitalized or punctuated (Go convention: lowercase, no trailing period)
- Package names with underscores / mixedCaps, or stutter (`http.HTTPServer`)

## Reference

Deeper Go idioms and anti-patterns: [coding-style.md](./coding-style.md),
[patterns.md](./patterns.md), [security.md](./security.md), [testing.md](./testing.md).
