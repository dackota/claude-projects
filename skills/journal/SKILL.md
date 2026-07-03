---
name: journal
description: Append one typed entry to journal.yaml in a claude-projects workspace. Use when recording a significant project event — a decision, plan, task started/done, blocker, research, pr, or gate run.
origin: claude-projects
---

# /journal

Append one structured entry to `journal.yaml`. Never edits existing entries.

## Usage

```
/journal <type> "<summary>"
```

Optional additional args (add as YAML fields if provided):

```
/journal <type> "<summary>" --jira PROJ-123
/journal <type> "<summary>" --refs docs/plans/foo.md,PROJ-123
```

## Type enum

| Type | When to use |
|------|-------------|
| `decision` | A decision was made or reversed |
| `plan` | A plan was finalized or revised |
| `started` | A task's status flipped to in-progress in `project.yaml` |
| `done` | A task's status flipped to done in `project.yaml` |
| `blocker` | A blocker was hit |
| `research` | A research doc was finalized |
| `pr` | A PR was opened, merged, or closed |
| `run` | A review/gate agent finished a run — the audit record for a `/next` pipeline gate (see below) |

Rejects unknown types with a clear error listing the valid enum values.

## Entry schema written

```yaml
- date: YYYY-MM-DD        # today's date (UTC)
  type: <type>
  summary: <summary text>
  refs:                   # omit if not provided
    - docs/adr/0001-foo.md
    - PROJ-123
  jira: PROJ-123       # omit if not provided
```

Entries are appended to the end of the list in `journal.yaml`. The file grows chronologically; never reorder or compact it.

## `run` entries — pipeline audit records

A `run` entry is the durable audit trail for one gate run in the `/next` pipeline
(the loop's "Audit" step). Alongside the common fields it carries structured fields
the `/sync-status` **Pipeline health** surface rolls up:

```yaml
- date: YYYY-MM-DD
  type: run
  agent: implementation-validator   # which review/gate agent ran
  task: add-login-endpoint          # the task id under review
  verdict: PASS | BLOCK | SKIP      # SKIP is the runtime gate's no-runnable-surface verdict
  critical: 0                       # counts as the agent reported them (BLOCKER for otel; observed runtime failures for runtime-validator)
  high: 0
  rework: 2                         # times this task looped back through this gate so far
  approver: null                    # named human who approved a gated action, else null
  gate: release-verify              # optional: only when it differs from the agent's default (e.g. a runtime-validator run in release mode)
  escape: true                      # optional: set when this records a defect that passed the build gates and was caught live
  summary: implementation-validator BLOCK (1 CRITICAL) on add-login-endpoint
  refs: [add-login-endpoint]
```

`agent`, `task`, `verdict` (∈ `PASS`/`BLOCK`/`SKIP`), `critical`, `high`, and `rework`
are **required structured fields** — the prose `summary` is kept for the narrative but
does **not** substitute for them. They are enforced: the `Stop` hook rejects a `run`
entry that carries them only in prose, and the rework cap and cross-workspace rollup
read them directly. `gate` and `escape` are optional (see comments above).

`/next` appends one complete `run` entry after each gate returns — it never edits a
prior entry (append-only holds). A `PostToolUse` hook (`run-check.sh`) records that a
gate ran and nudges for the entry; the `Stop` hook then refuses to stop until every
recorded gate run has a matching, well-formed `run` entry (a missing entry is an error,
not just a nudge).

## Safety checks

- Refuses to run if no `journal.yaml` is found in the current working directory or any of its parent directories (prevents accidental writes outside a workspace).
- Validates `type` before writing; fails fast with a clear error on unknown types.
- Does not call `/sync-status` automatically — that is a separate concern.

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/journal" ~/.claude/skills/journal
```
