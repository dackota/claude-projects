---
title: Project Scaffold CLI
created: 2026-05-13
last_updated: 2026-06-04
status: superseded
supersedes: []
superseded_by: scripts/proj.sh
related: []
jira: null
task: null
---

# Project Scaffold CLI

> **Superseded 2026-06-04:** Implemented as `scripts/proj.sh` (renamed `proj`, not `new-project`). The CLI flags, scaffold structure, embedded CLAUDE.md heredoc, dry-run, and smoke tests described here are all present in `proj.sh` and `scripts/test-proj.sh`.



## Problem

Every new claude-projects workspace must be set up manually — creating the same directory structure, copying CLAUDE.md, and initializing `project.yaml` by hand. This is error-prone, slow, and drifts over time as the template evolves. There is no single canonical way to spin up a compliant project.

## Solution

A CLI tool (`new-project`) that accepts a project name and optional metadata, then scaffolds a fully-compliant project directory under a configurable base path. The tool copies the canonical CLAUDE.md from a built-in template, generates a starter `project.yaml`, initializes git, creates all required directories, and writes a minimal `PROJECT.md`.

The tool lives in `scripts/` as a self-contained Bash script (or Python if complexity warrants), installable via a symlink or PATH addition.

### Invocation

```bash
new-project <project-name> [--dir <base-path>] [--jira <PROJECT_KEY>]
```

Examples:

```bash
new-project my-feature-work
new-project aidp-migration --dir ~/Documents/repos --jira AIDP
```

### Scaffolded Output

```
<project-name>/
├── CLAUDE.md               # copied from embedded template
├── PROJECT.md              # generated stub (user fills in)
├── project.yaml            # generated stub with name, jira key, empty repos/tasks
├── .gitignore              # ignores repos/ and worktrees/
├── docs/
│   ├── plans/
│   ├── decisions/
│   ├── research/
│   └── validations/
├── scripts/
├── repos/
└── worktrees/
```

### `project.yaml` structure

```yaml
name: <project-name>
jira_key: <JIRA_KEY or "">
created: <ISO date>
repos: []
tasks: []
```

### `PROJECT.md` stub

```markdown
---
title: <project-name>
created: <ISO date>
---

# <project-name>

## Goals

<!-- Describe what this project is trying to accomplish -->

## Context

<!-- Background and motivation -->
```

## Trade-offs

| Option | Pro | Con |
|--------|-----|-----|
| Bash script | Zero dependencies, runs anywhere | Limited error handling, harder to test |
| Python script | Richer CLI (argparse), testable, readable | Requires Python in PATH |
| Node/TypeScript | Matches JS ecosystem tooling | Overkill, requires Node |

**Decision: Bash** — this repo has no runtime dependencies and the logic is straightforward (mkdir, cp, envsubst-style substitution). Python fallback if template rendering complexity grows.

## Considerations

- CLAUDE.md template is embedded in the script (heredoc) so the tool is self-contained and not coupled to this specific repo's location.
- The tool should fail fast with a clear error if the target directory already exists.
- `repos/` and `worktrees/` are `.gitignore`d by default — consistent with CLAUDE.md conventions.
- A `--dry-run` flag should print what would be created without writing anything.
- The script should be idempotent on a fresh directory (safe to re-run only if `--force` is passed).

---

## Tasks

### Task 1 — Core scaffold script

Write `scripts/new-project.sh`:

- Parse args: `<name>` (required), `--dir` (default: `~/Documents/repos/claude-projects`), `--jira` (optional), `--dry-run`, `--force`
- Validate: name is non-empty, target dir does not already exist (unless `--force`)
- Create directory tree: `docs/{plans,decisions,research,validations}`, `scripts/`, `repos/`, `worktrees/`
- Write `.gitignore` excluding `repos/` and `worktrees/`
- Write `project.yaml` from template with substituted values
- Write `PROJECT.md` stub
- Embed CLAUDE.md as a heredoc and write it into the new project

Acceptance: Running `./scripts/new-project.sh test-proj` produces the full directory tree with all files correctly populated.

---

### Task 2 — CLAUDE.md template embed

Extract the canonical CLAUDE.md content into the script as a heredoc constant. It must exactly match the current `CLAUDE.md` in this repo — no drift allowed.

Acceptance: `diff <(./scripts/new-project.sh test-proj --dry-run --show-claude-md) CLAUDE.md` produces no output.

---

### Task 3 — Dry-run and validation

- `--dry-run`: print all files/dirs that would be created, nothing written to disk
- `--show-claude-md`: print the embedded CLAUDE.md to stdout (used in acceptance test above)
- Exit codes: 0 = success, 1 = usage error, 2 = target already exists, 3 = write failure

Acceptance: `--dry-run` produces expected output, no files created. Exit codes verified with `echo $?`.

---

### Task 4 — Install / PATH setup

Add instructions to the script header comment for making it globally accessible:

```bash
# Option A: symlink
ln -s "$(pwd)/scripts/new-project.sh" /usr/local/bin/new-project

# Option B: add to PATH in .zshrc
export PATH="$PATH:/path/to/claude-projects/scripts"
```

Document in the script header. No separate installer — keep it simple.

Acceptance: After symlinking, `new-project --help` works from any directory.

---

### Task 5 — Smoke test

Write a Bash test script `scripts/test-new-project.sh` that:

1. Runs `new-project smoke-test-$$` in a temp dir
2. Asserts all expected files and directories exist
3. Asserts `project.yaml` contains the correct project name
4. Asserts `repos/` and `worktrees/` are in `.gitignore`
5. Cleans up the temp dir
6. Prints PASS/FAIL per assertion

Acceptance: `bash scripts/test-new-project.sh` exits 0 with all assertions passing.
