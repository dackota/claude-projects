# Coding Style

- **Immutability (CRITICAL):** never mutate existing objects — return new copies with
  the change applied.
- **KISS / DRY / YAGNI:** simplest solution that works; extract real (not speculative)
  repetition; build nothing before it's needed; clarity over cleverness.
- **Files & functions:** many small files > few large — organize by feature/domain;
  ~200–400 lines typical, 800 max; functions <50 lines; no >4-level nesting (prefer
  early returns).
- **Errors:** handle explicitly at every level; never silently swallow; user-friendly
  messages UI-side, detailed context in server logs.
- **Validation:** validate all external input at system boundaries (schema-based where
  available); fail fast; never trust API responses, user input, or file content.
- **Naming:** `camelCase` vars/functions (`is`/`has`/`should`/`can` for booleans),
  `PascalCase` types/components, `UPPER_SNAKE_CASE` constants, `use`-prefixed hooks;
  named constants over magic numbers.
