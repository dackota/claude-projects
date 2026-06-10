#!/usr/bin/env bash
# proj — scaffold a new claude-projects workspace
#
# Usage:
#   proj <project-name> [options]
#
# Options:
#   --dir <path>       Base directory to create project in (default: current directory)
#   --jira <KEY>       Jira project key (e.g. AIDP)
#   --skills [LIST]    Copy skills into .claude/skills/ in the new project.
#                      LIST is an optional comma-separated subset (e.g. tdd,grill-me).
#                      Omit LIST to copy all bundled skills: grill-me, to-prd, to-issues, tdd.
#   --dry-run          Print what would be created; write nothing
#   --force            Overwrite if target directory already exists
#   --show-claude-md   Print the embedded CLAUDE.md to stdout and exit
#   -h, --help         Show this help
#
# Install (pick one):
#   ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj
#   export PATH="$PATH:/path/to/claude-projects/scripts"  # add to ~/.zshrc

set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────
BASE_DIR="$(pwd)"
JIRA_KEY=""
DRY_RUN=false
FORCE=false
PROJECT_NAME=""
COPY_SKILLS=false
SKILLS_LIST=""  # empty = all bundled skills

ALL_BUNDLED_SKILLS="grill-me to-prd to-issues tdd"

# Resolve script's real directory (handles symlinks on macOS)
_SCRIPT="${BASH_SOURCE[0]}"
while [[ -L "$_SCRIPT" ]]; do
  _SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"
  _SCRIPT="$(readlink "$_SCRIPT")"
  [[ "$_SCRIPT" != /* ]] && _SCRIPT="${_SCRIPT_DIR}/${_SCRIPT}"
done
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/../skills"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

info()  { echo -e "${GREEN}[proj]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[proj]${RESET} $*"; }
error() { echo -e "${RED}[proj]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── embedded CLAUDE.md ───────────────────────────────────────────────────────
# This heredoc is the canonical CLAUDE.md for all scaffolded projects.
# Update this when the template changes; new-project is self-contained.
claude_md_content() {
cat << 'CLAUDE_MD_EOF'
# Project Structure

See `PROJECT.md` for what this project is trying to accomplish.

## Session Start

Read `STATUS.md` first every session before opening any other file. It is a
~500-token synthesis of current project state. If it is absent, run
`/sync-status` to generate it.

## Project Structure

- `project.yaml` - source of truth: repos, tasks, Jira keys, and config
- `PROJECT.md` - project goals and context (read this for the why)
- `STATUS.md` - LLM-first current-state synthesis; READ THIS FIRST every session
- `journal.yaml` - append-only structured event log; never rewrite, only append
- `CLAUDE.md` - this file
- `docs/` - directory to store project documentation
- `docs/plans/` - directory to store planning documents
- `docs/decisions/` - directory to store decision records
- `docs/research/` - directory to store research and analysis documents
- `docs/validations/` - directory to store validation documents
- `scripts/` - directory to contain one-off scripts used in the project but not
  belonging to a specific repository
- `repos/` - directory containing cloned repos
- `worktrees/` - directory containing git worktrees associated with tasks

Code repos and worktrees are cloned inside the project directory but are
`.gitignored`-excluded; they are tracked via `project.yaml`, not committed here.
Read `project.yaml` to see what repos and tasks exist.

## Lifecycle Frontmatter

Every doc in `docs/plans/`, `docs/decisions/`, `docs/research/`, and
`docs/validations/` MUST carry this frontmatter:

```yaml
---
title: <human-readable title>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []            # paths to docs this replaces
superseded_by: null       # path to doc that replaced this
related:                  # cross-references for navigation
  - docs/decisions/foo.md
jira: null                # optional Jira issue key
task: null                # optional task id from project.yaml
---
```

`status` is the authoritative currency signal. Skip non-`active` docs unless
explicitly referenced or tracing history.

Superseded docs stay in place — never move or delete them. Flip
`status: superseded`, set `superseded_by`, and add a short block-quote at the
top of the body explaining when and why the doc was superseded.

## journal.yaml

Append-only event log. Never edit existing entries. Entry schema:

```yaml
- date: YYYY-MM-DD
  type: decision   # decision | plan | started | done | blocker | supersession | research | pr
  summary: <one or two sentences>
  refs:            # optional list of paths or external IDs
    - docs/decisions/foo.md
    - DEVOPS-1525
  jira: DEVOPS-1525  # optional
```

Append an entry immediately when:

| Event                                    | type          |
|------------------------------------------|---------------|
| Decision made or reversed                | `decision`    |
| Plan finalized or revised                | `plan`        |
| Task status flipped in `project.yaml`    | `started` / `done` |
| Blocker hit                              | `blocker`     |
| Doc superseded (frontmatter flipped)     | `supersession`|
| Research finalized                       | `research`    |
| PR opened, merged, or closed             | `pr`          |

Manual escape hatch: `/journal <type> "<summary>"`.

## /sync-status

Regenerates `STATUS.md` wholesale by reading `PROJECT.md`, `project.yaml`,
`journal.yaml`, frontmatter of all `docs/**.md`, and full content of
`status: active` docs. Run it — or Claude invokes it automatically — when
**both** conditions are true:

1. A significant change occurred (plan finalized, decision committed, task
   status flipped, meaningful blocker recorded).
2. A natural pause has arrived (handing back to the user, finishing a logical
   work block).

Do not sync after every individual doc edit.

First run bootstraps missing files: creates `STATUS.md` and `journal.yaml` if
absent; treats docs missing `status` frontmatter as `active`.

## /journal

Appends a single typed entry to `journal.yaml`. Usage:

```
/journal <type> "<summary>"
```

Valid types: `decision` | `plan` | `started` | `done` | `blocker` |
`supersession` | `research` | `pr`.

Refuses to run if no `journal.yaml` is present in the working directory tree.

## Artifact Types

All artifacts MUST BE written in Markdown unless otherwise mentioned during a
session. File names MUST use dash-separated words. For all Markdown files in
`docs/` you MUST include the lifecycle frontmatter described above.

- Plans are used to iterate on an idea and used as the source context for work
  to be done. Plans MUST detail the Problem, Solution, Trade-offs, and
  Considerations. Plans MUST BE broken down into Tasks. Each Task MUST BE a
  distinct body of work. A Task MUST BE able to be easily reviewable by a human.
  Store these in `docs/plans/`. Use this directory when I say things like:
  "create a plan", "let's plan out", "I want to plan a", "plan it out".

- Decision records are used to capture decisions made while building or
  executing a plan. These are lightweight decisions that will guide future tasks
  of the plan or project. Decisions may be turned into Architectural Decision
  Records (ADR) at some point in the future at my discretion. Store these in
  `docs/decisions/`.

- Research documents are used to store in-depth information about a topic or
  work item. The research may be referenced by multiple plans. Store these in
  `docs/research/`. Use this directory when I say things like: "Research how X
  works". This can also be used when a plan requires in-depth research.

- Validation documents are used to prove that a plan was successfully
  completed. When I ask you to validate that the plan was completed you will
  review the plan, gather evidence of completed work, and create a validation
  document. This MUST include tangible and auditable examples such as file paths
  and lines `path/to/file.ext:34` or the output summary of a successful test run.
  Store these documents in `docs/validations/`.

- Scripts for complex or repeatable work items. When you need to do something
  that is more complex due to the number of commands or the amount of logic
  (conditionals, loops, advanced scripting language features) or when you need to
  run the same command set over and over again you will create a script. Scripts
  will be put into `scripts/`. Scripts should be written in Bash but you can use
  Python as well.

- Repos is a directory that stores repositories needed by this project. These
  repositories may be needed for research or changes in order to complete the
  project. Clone the required repos here. Every time a repo is used for any 
  task it must be updated first so its always the latest.

- Worktrees is a directory that stores git worktrees needed by this project.
  Worktrees MUST be used when working on Tasks.
CLAUDE_MD_EOF
}

# ── arg parsing ───────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)         usage ;;
    --show-claude-md)  claude_md_content; exit 0 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --force)           FORCE=true; shift ;;
    --dir)             [[ $# -lt 2 ]] && die "--dir requires an argument"; BASE_DIR="$2"; shift 2 ;;
    --jira)            [[ $# -lt 2 ]] && die "--jira requires an argument"; JIRA_KEY="$2"; shift 2 ;;
    --skills)
      COPY_SKILLS=true
      # optional next arg: comma-separated skill names (not starting with -)
      if [[ $# -gt 1 && "$2" != -* ]]; then
        SKILLS_LIST="${2//,/ }"  # normalise commas to spaces
        shift
      fi
      shift ;;
    -*)                die "Unknown option: $1" ;;
    *)
      [[ -n "$PROJECT_NAME" ]] && die "Unexpected argument: $1 (project name already set to '${PROJECT_NAME}')"
      PROJECT_NAME="$1"; shift ;;
  esac
done

[[ -z "$PROJECT_NAME" ]] && die "Usage: proj <project-name> [options]\n       Run with --help for full usage."

TODAY=$(date +%Y-%m-%d)
TARGET="${BASE_DIR}/${PROJECT_NAME}"

# ── pre-flight ────────────────────────────────────────────────────────────────
if [[ -e "$TARGET" ]]; then
  if $FORCE; then
    warn "Target exists — overwriting because --force was passed: $TARGET"
  else
    die "Target already exists: $TARGET\n       Use --force to overwrite."
  fi
fi

# ── helpers ───────────────────────────────────────────────────────────────────
make_dir() {
  if $DRY_RUN; then
    echo "  [dir]  $1"
  else
    mkdir -p "$1"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  if $DRY_RUN; then
    echo "  [file] $path"
  else
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
  fi
}

# ── dry-run header ────────────────────────────────────────────────────────────
if $DRY_RUN; then
  info "Dry run — nothing will be written."
  echo ""
  echo "Would create: $TARGET"
fi

# ── scaffold ──────────────────────────────────────────────────────────────────
make_dir "$TARGET"
make_dir "$TARGET/docs/plans"
make_dir "$TARGET/docs/decisions"
make_dir "$TARGET/docs/research"
make_dir "$TARGET/docs/validations"
make_dir "$TARGET/scripts"
make_dir "$TARGET/repos"
make_dir "$TARGET/worktrees"

# CLAUDE.md
write_file "$TARGET/CLAUDE.md" "$(claude_md_content)"

# .gitignore
write_file "$TARGET/.gitignore" "$(cat << 'EOF'
repos/
worktrees/
EOF
)"

# project.yaml
write_file "$TARGET/project.yaml" "$(cat << EOF
name: ${PROJECT_NAME}
jira_key: "${JIRA_KEY}"
created: ${TODAY}
repos: []
tasks: []
EOF
)"

# PROJECT.md
write_file "$TARGET/PROJECT.md" "$(cat << EOF
---
title: ${PROJECT_NAME}
created: ${TODAY}
---

# ${PROJECT_NAME}

## Goals

<!-- Describe what this project is trying to accomplish -->

## Context

<!-- Background and motivation -->
EOF
)"

# STATUS.md
write_file "$TARGET/STATUS.md" "$(cat << 'EOF'
---
last_synced: null
---

# Status

_Not yet synced. Run `/sync-status` once meaningful work begins, or Claude will invoke it after the first significant change + natural pause._
EOF
)"

# journal.yaml
write_file "$TARGET/journal.yaml" "[]"

# ── skills ───────────────────────────────────────────────────────────────────
if $COPY_SKILLS; then
  SKILLS_TO_COPY="${SKILLS_LIST:-$ALL_BUNDLED_SKILLS}"

  if [[ ! -d "$SKILLS_SRC" ]]; then
    warn "--skills requested but skills directory not found: $SKILLS_SRC"
    warn "Skills will not be copied. Check your installation."
  else
    for skill in $SKILLS_TO_COPY; do
      SRC="${SKILLS_SRC}/${skill}"
      DEST="${TARGET}/.claude/skills/${skill}"
      if [[ ! -d "$SRC" ]]; then
        warn "Skill not found, skipping: $skill ($SRC)"
        continue
      fi
      if $DRY_RUN; then
        echo "  [skill] .claude/skills/${skill}/"
      else
        mkdir -p "$(dirname "$DEST")"
        cp -r "$SRC" "$DEST"
      fi
    done
  fi
fi

# ── done ─────────────────────────────────────────────────────────────────────
if $DRY_RUN; then
  echo ""
  info "Dry run complete. Re-run without --dry-run to create."
else
  echo ""
  info "Project scaffolded at: $TARGET"
  echo ""
  echo "  Next steps:"
  echo "    1. cd $TARGET"
  echo "    2. Edit PROJECT.md — describe your goals"
  echo "    3. Edit project.yaml — add repos and tasks as you work"
  echo "    4. Run /sync-status after your first significant change"
fi
