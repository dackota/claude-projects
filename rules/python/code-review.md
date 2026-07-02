---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Code Review

> This file extends [common/code-review.md](../common/code-review.md) with Python specific content.

The **when-to-review**, **severity levels**, and **approval criteria** live in
[common/code-review.md](../common/code-review.md) — don't repeat them. This file adds only
the Python-specific findings to flag, plus the diagnostics that surface them. Style and
security rationale live in [coding-style.md](./coding-style.md) and [security.md](./security.md);
here they're the review *lens* — what to catch in a diff.

## Run these first

```bash
git diff -- '*.py'                          # scope the review to changed Python files
ruff check .                                # fast lint (idioms, bugs, imports)
mypy .                                       # static type checking
bandit -r .                                  # security scan
pytest --cov=. --cov-report=term-missing     # tests + coverage gaps
```

Findings from these tools are evidence — cite the file:line, don't just restate the tool.

## CRITICAL — block the merge

**Security** (see [security.md](./security.md)):
- f-strings / `%` / `.format` building SQL instead of parameterized queries
- Unvalidated input in `subprocess`/`os.system` with `shell=True` — use a list of args
- User-controlled paths without normalization + `..` rejection (path traversal)
- `eval` / `exec` on untrusted input; `pickle` / `yaml.load` on untrusted data
  (use `yaml.safe_load`)
- Hardcoded secrets — keys, passwords, tokens
- MD5 / SHA1 used for a security purpose

**Error handling:**
- Bare `except:` or `except Exception: pass` — catch specific types, don't swallow
- Exceptions logged-and-lost with no handling or re-raise
- Manual file/resource open without a `with` context manager

## HIGH — should fix before merge

**Type hints:**
- Public functions without annotations
- `Any` where a concrete type is knowable
- Nullable parameter missing `Optional[...]` / `| None`

**Pythonic patterns:**
- Mutable default argument (`def f(x=[])`) — use `None` and initialize inside
- C-style index loops where a comprehension or iteration reads clearer
- `type(x) == T` instead of `isinstance(x, T)`
- `==`/`!=` against `None` instead of `is` / `is not`
- Magic numbers instead of `Enum` / named constants

**Code quality:**
- Functions > 50 lines or > 5 parameters (pass a dataclass), nesting > 4 levels
- Duplicated logic that should be extracted

**Concurrency:**
- Shared mutable state across threads without a lock
- Blocking (sync) call inside an `async def`
- Query issued inside a loop (N+1) — batch it

## MEDIUM — consider

- PEP 8 drift: import ordering, naming, spacing
- Missing docstrings on public functions/classes
- `print()` where `logging` belongs
- `from module import *` (namespace pollution)
- Shadowing builtins (`list`, `dict`, `id`, `type`, ...)

## Framework spot-checks

- **Django** — missing `select_related`/`prefetch_related` (N+1); multi-step writes not
  wrapped in `transaction.atomic()`; model changes without a migration
- **FastAPI** — missing Pydantic validation / response models; blocking I/O in an async
  route; permissive CORS
- **Flask** — missing error handlers; CSRF protection absent on state-changing forms

## Reference

Deeper Python patterns and security examples: [coding-style.md](./coding-style.md),
[patterns.md](./patterns.md), [security.md](./security.md), [testing.md](./testing.md).
