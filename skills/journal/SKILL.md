---
name: journal
description: Append a single typed entry to journal.yaml in the current claude-projects workspace. Use when recording a significant event (decision, plan, started, done, blocker, supersession, research, pr) explicitly, or when the user invokes /journal directly.
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
/journal <type> "<summary>" --jira DEVOPS-1234
/journal <type> "<summary>" --refs docs/plans/foo.md,DEVOPS-1234
```

## Type enum

| Type | When to use |
|------|-------------|
| `decision` | A decision was made or reversed |
| `plan` | A plan was finalized or revised |
| `started` | A task's status flipped to in-progress in `project.yaml` |
| `done` | A task's status flipped to done in `project.yaml` |
| `blocker` | A blocker was hit |
| `supersession` | A doc's status was flipped to superseded |
| `research` | A research doc was finalized |
| `pr` | A PR was opened, merged, or closed |

Rejects unknown types with a clear error listing the valid enum values.

## Entry schema written

```yaml
- date: YYYY-MM-DD        # today's date (UTC)
  type: <type>
  summary: <summary text>
  refs:                   # omit if not provided
    - docs/decisions/foo.md
    - DEVOPS-1234
  jira: DEVOPS-1234       # omit if not provided
```

Entries are appended to the end of the list in `journal.yaml`. The file grows chronologically; never reorder or compact it.

## Safety checks

- Refuses to run if no `journal.yaml` is found in the current working directory or any of its parent directories (prevents accidental writes outside a workspace).
- Validates `type` before writing; fails fast with a clear error on unknown types.
- Does not call `/sync-status` automatically — that is a separate concern.

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/journal" ~/.claude/skills/journal
```
