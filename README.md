# claude-projects

Scaffolding and conventions for Claude Code project workspaces.

## What this is

Each project workspace is a directory that Claude Code uses as context for a focused body of work — a feature, migration, investigation, etc. This repo defines the structure those workspaces follow and provides a CLI to create them.

## Usage

```bash
proj <project-name> [options]
```

**Options**

| Flag | Description |
|------|-------------|
| `--dir <path>` | Base directory (default: current directory) |
| `--jira <KEY>` | Jira project key, e.g. `AIDP` |
| `--dry-run` | Print what would be created without writing anything |
| `--force` | Overwrite if target directory already exists |
| `--show-claude-md` | Print the embedded CLAUDE.md template to stdout |
| `-h, --help` | Show help |

**Examples**

```bash
proj my-feature-work
proj aidp-migration --dir ~/Documents/repos --jira AIDP
proj big-refactor --dry-run
```

## Scaffolded structure

```
<project-name>/
├── CLAUDE.md                  # project conventions for Claude Code
├── PROJECT.md                 # goals and context (fill this in)
├── STATUS.md                  # LLM-first current-state synthesis (read first each session)
├── journal.yaml               # append-only structured event log
├── project.yaml               # source of truth: repos, tasks, Jira keys
├── .gitignore                 # excludes repos/ and worktrees/
├── docs/
│   ├── plans/                 # implementation plans
│   ├── decisions/             # lightweight decision records
│   ├── research/              # in-depth research docs
│   └── validations/           # proof of completion
├── scripts/                   # one-off and repeatable scripts
├── repos/                     # cloned repos (gitignored)
└── worktrees/                 # git worktrees (gitignored)
```

## Living status system

Each workspace carries two control files that keep Claude oriented across sessions.

### STATUS.md

Regenerated wholesale by `/sync-status`. The first file Claude reads each session — a ~500-token synthesis of current project state under these sections:

- **Goal** — one sentence from `PROJECT.md`
- **Current state** — 2–4 sentences
- **Active work** — bullet list with doc links
- **Blocked / open questions**
- **Recent decisions** — dated, linked
- **Key facts** — load-bearing constraints
- **Next moves**

`STATUS.md` is a *view*, not a source of truth. If a fact needs to persist, put it in a plan or decision doc.

### journal.yaml

Append-only event log. Never rewritten — only appended. Entry schema:

```yaml
- date: YYYY-MM-DD
  type: decision   # decision | plan | started | done | blocker | supersession | research | pr
  summary: One or two sentences.
  refs:            # optional
    - docs/decisions/foo.md
  jira: DEVOPS-1234  # optional
```

Claude appends an entry immediately when: a decision is made, a plan is finalized, a task status flips, a blocker is hit, a doc is superseded, research is finalized, or a PR is opened/merged/closed.

## Doc lifecycle frontmatter

Every doc in `docs/` carries:

```yaml
---
title: Human-readable title
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []
superseded_by: null
related:
  - docs/decisions/foo.md
jira: null
task: null
---
```

`status` is the currency signal. Claude skips non-`active` docs unless explicitly referenced. Superseded docs stay in place — never moved or deleted — with `status: superseded` and a block-quote at the top explaining the supersession.

## Skills

Two project skills live in `skills/` and must be symlinked into `~/.claude/skills/` once per machine.

### /sync-status

Regenerates `STATUS.md` from all authoritative inputs. Claude invokes it automatically when a significant change occurs AND a natural pause arrives (handing back to the user, finishing a work block). You can also invoke it manually.

### /journal

Appends a single typed entry to `journal.yaml`.

```
/journal <type> "<summary>"
/journal decision "Switched mas to consumer-subchart pattern."
/journal done "DEVOPS-1521 PR #829 merged and sbx-validated."
```

## Install

**CLI**

```bash
# Symlink (recommended)
ln -s /path/to/claude-projects/scripts/proj.sh /usr/local/bin/proj

# Or add to PATH in ~/.zshrc
export PATH="$PATH:/path/to/claude-projects/scripts"
```

**Skills (one-time per machine)**

```bash
cd /path/to/claude-projects
ln -s "$(pwd)/skills/sync-status" ~/.claude/skills/sync-status
ln -s "$(pwd)/skills/journal"     ~/.claude/skills/journal
```

## Tests

```bash
bash scripts/test-proj.sh
```
