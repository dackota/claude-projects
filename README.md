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
| `--dir <path>` | Base directory (default: `~/Documents/repos/claude-projects`) |
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

## Install

```bash
# Symlink (recommended)
ln -s /path/to/claude-projects/scripts/proj.sh /usr/local/bin/proj

# Or add to PATH in ~/.zshrc
export PATH="$PATH:/path/to/claude-projects/scripts"
```

## Tests

```bash
bash scripts/test-proj.sh
```
