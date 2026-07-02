---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Coding Style

> This file extends [common/coding-style.md](../common/coding-style.md) with Go specific content.

## Formatting

- **gofmt** and **goimports** are mandatory — no style debates

## Design Principles

- Accept interfaces, return structs
- Keep interfaces small (1-3 methods)

## Mutation (overrides common's absolute rule)

`common/coding-style.md` frames immutability as "never mutate" — treat that as a
value-semantics *default*, not an absolute in Go. Idiomatic Go mutates: pointer
receivers, `append`, filling a struct's fields, `sync` primitives. That's fine. What
to actually avoid:

- **Shared mutable state across goroutines** without a mutex/channel — the real hazard.
- Mutating a caller's slice/map argument as a hidden side effect — document it or copy.
- Exported package-level mutable variables.

Prefer value semantics and returning new values where it's natural; reach for mutation
where it's the idiomatic, allocation-light choice.

## Error Handling

Always wrap errors with context:

```go
if err != nil {
    return fmt.Errorf("failed to create user: %w", err)
}
```

## Reference

See skill: `golang-patterns` for comprehensive Go idioms and patterns.
