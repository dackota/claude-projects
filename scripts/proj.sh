#!/usr/bin/env bash
# proj — scaffold a new claude-projects workspace
#
# Usage:
#   proj <project-name> [options]
#   proj update-skills [<project-name>] [options]
#
# Subcommands:
#   update-skills      Sync already-installed skills from the source to pick up
#                      latest changes. <project-name> is optional; when omitted,
#                      the current directory (or --dir) is treated as the project root.
#                      Only skills already present in .claude/skills/ are updated.
#                      Pass --skills LIST to restrict which skills are updated.
#
# Options:
#   --dir <path>       Base directory for the project (default: current directory)
#   --jira <KEY>       Jira project key (e.g. AIDP)  [scaffold only]
#   --skills [LIST]    Copy skills into .claude/skills/ in the new project.
#                      LIST is an optional comma-separated subset (e.g. tdd,grill-with-docs).
#                      Omit LIST to copy all skills found in the skills/ directory.
#   --dry-run          Print what would be created/updated; write nothing
#   --force            Overwrite if target directory already exists  [scaffold only]
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
SUBCOMMAND=""

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

# ── skill hook wiring (idempotent settings.json merge) ─────────────────────────
# Merge one hook into a settings.json, adding it only if a hook with the same
# command isn't already present in the matching event+matcher group. Safe to
# re-run; safe against existing journal/sync-status/repo wiring.
# add_hook <settings_file> <event> <matcher> <command> <async true|false> <summary>
add_hook() {
  local file="$1" event="$2" matcher="$3" command="$4" async="$5" summary="$6" tmp
  tmp="$(mktemp)"
  jq \
    --arg event "$event" --arg matcher "$matcher" --arg command "$command" \
    --argjson async "$async" --arg summary "$summary" '
    .hooks //= {} | .hooks[$event] //= []
    | (.hooks[$event] | map(.matcher == $matcher) | index(true)) as $gi
    | if $gi == null then .hooks[$event] += [{matcher: $matcher, hooks: []}] else . end
    | (.hooks[$event] | map(.matcher == $matcher) | index(true)) as $g
    | if (.hooks[$event][$g].hooks | map(.command) | index($command)) == null
      then .hooks[$event][$g].hooks +=
        [ ({type: "command", command: $command}
           + (if $async then {asyncRewake: true, rewakeSummary: $summary} else {} end)) ]
      else . end
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Wire the hooks a given skill needs into the target's settings.json.
# wire_skill_hooks <target> <skill>
wire_skill_hooks() {
  local target="$1" skill="$2" settings
  case "$skill" in journal|sync-status|repo) ;; *) return 0 ;; esac
  if $DRY_RUN; then
    echo "  [hooks] .claude/settings.json  <- ${skill} hooks (merge)"
    return 0
  fi
  command -v jq >/dev/null 2>&1 || die "jq is required to wire skill hooks. Install: brew install jq"
  settings="$target/.claude/settings.json"
  mkdir -p "$target/.claude"
  [[ -f "$settings" ]] || echo '{}' > "$settings"
  case "$skill" in
    journal)
      add_hook "$settings" PostToolUse "Write|Edit" "bash .claude/skills/journal/hooks/journal-check.sh" true "Journal entry may be needed"
      add_hook "$settings" Stop "" "bash .claude/skills/journal/hooks/journal-stop.sh" true "Unlogged journal events detected"
      ;;
    sync-status)
      add_hook "$settings" Stop "" "bash .claude/skills/sync-status/hooks/sync-status-stop.sh" true "STATUS.md is out of date"
      ;;
    repo)
      add_hook "$settings" PreToolUse "Bash"       "bash .claude/skills/repo/hooks/git-guard.sh"   false ""
      add_hook "$settings" PreToolUse "Edit|Write" "bash .claude/skills/repo/hooks/repo-stale.sh"  false ""
      add_hook "$settings" Stop       ""           "bash .claude/skills/repo/hooks/repo-stale-stop.sh" true "Stale worktrees detected"
      ;;
  esac
}

# The repo skill also drops a first-class, user-visible scripts/repo.sh.
# install_repo_script <target>
install_repo_script() {
  local target="$1" src="${SKILLS_SRC}/repo/repo.sh"
  if $DRY_RUN; then
    echo "  [file] scripts/repo.sh"
    return 0
  fi
  [[ -f "$src" ]] || { warn "repo skill copied but repo.sh missing at $src"; return 0; }
  mkdir -p "$target/scripts"
  cp "$src" "$target/scripts/repo.sh"
  chmod +x "$target/scripts/repo.sh"
}

# Run after a skill is copied: wire its hooks and install any companion files.
# post_install_skill <target> <skill>
post_install_skill() {
  local target="$1" skill="$2"
  wire_skill_hooks "$target" "$skill"
  [[ "$skill" == "repo" ]] && install_repo_script "$target"
  return 0
}

# ── embedded CLAUDE.md ───────────────────────────────────────────────────────
# This heredoc is the canonical CLAUDE.md for all scaffolded projects.
# Update this when the template changes; new-project is self-contained.
claude_md_content() {
cat << 'CLAUDE_MD_EOF'
# Project Structure

See `PROJECT.md` for what this project is trying to accomplish. A **project** is
the body of work and its goal (the *why*); this **workspace** is the directory
that holds it (the *where*).

## Session Start

Read `STATUS.md` first every session before opening any other file. It is a
~500-token synthesis of current project state. If it is absent, run
`/sync-status` to generate it.

## Project Structure

- `project.yaml` - source of truth: repos, tasks, Jira key, and config
- `PROJECT.md` - project goals and context (read this for the why)
- `STATUS.md` - LLM-first current-state synthesis; READ THIS FIRST every session
- `CONTEXT.md` - domain glossary; the canonical term for each concept
- `journal.yaml` - append-only structured event log; never rewrite, only append
- `CLAUDE.md` - this file
- `docs/` - directory to store project documentation
- `docs/plans/` - planning documents (and local PRDs when not using a tracker)
- `docs/adr/` - architectural decision records (the why behind hard decisions)
- `docs/research/` - directory to store research and analysis documents
- `docs/validations/` - directory to store validation documents
- `scripts/` - directory to contain one-off scripts used in the project but not
  belonging to a specific repository
- `repos/` - cloned repos; managed via `scripts/repo.sh` — never clone by hand
- `worktrees/` - git worktrees for tasks, laid out `worktrees/<task-id>/<repo>`;
  managed via `scripts/repo.sh`

Code repos and worktrees are cloned inside the workspace but are
`.gitignore`-excluded; repos are tracked via `project.yaml`, worktrees are
derived live. Read `project.yaml` to see what repos and tasks exist.

## repos/ and worktrees/ — always via `scripts/repo.sh`

When the `repo` skill is installed (`proj --skills`), all repo and worktree
operations MUST go through `scripts/repo.sh`. A PreToolUse guard hook blocks raw
`git clone`, `git worktree add`, and branch create/switch inside `repos/` and
`worktrees/`; read-only git and `git checkout -- <file>` stay allowed.

```
scripts/repo.sh clone <url> [name]             # clone into repos/, register in project.yaml
scripts/repo.sh worktree <task> <repo> [url]   # start work: worktrees/<task>/<repo> on branch <task>
scripts/repo.sh sync <task> [repo]             # merge origin/<base> in (worktrees drift while you work)
scripts/repo.sh status [task]                  # see how far behind/ahead each worktree is
scripts/repo.sh remove <task> [repo]           # remove worktree + delete local branch (safe by default)
scripts/repo.sh list                           # registered repos
```

Worktrees go stale as their base branch advances. Run `scripts/repo.sh status`
before relying on one, and `scripts/repo.sh sync` to catch it up — the guard's
staleness hook also warns before the first edit in a stale worktree.

## CONTEXT.md — domain glossary

`CONTEXT.md` is the project's glossary: the canonical name for each domain
concept, with synonyms to steer away from. Use its vocabulary in plans, ADRs,
issues, tests, and commits so language stays consistent across sessions. It is a
glossary and nothing else — no implementation details, no general programming
concepts. `/grill-with-docs` maintains it as terms are resolved.

## docs/adr/ — Architectural Decision Records

An ADR records a decision and the reasoning behind it. Write one only when all
three hold:

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will wonder "why this way?"
3. **The result of a real trade-off** — there were genuine alternatives.

If any is missing, skip the ADR — the journal `decision` line already records
that the decision happened. ADRs use sequential numbering (`0001-slug.md`) and
can be a single paragraph. ADRs and `CONTEXT.md` are exempt from the lifecycle
frontmatter below and from the `/sync-status` active-doc scan.

## Lifecycle Frontmatter

Every doc in `docs/plans/`, `docs/research/`, and `docs/validations/` MUST carry
this frontmatter (ADRs and `CONTEXT.md` are exempt — see above):

```yaml
---
title: <human-readable title>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []            # paths to docs this replaces
superseded_by: null       # path to doc that replaced this
related:                  # cross-references for navigation
  - docs/adr/0001-foo.md
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
    - docs/adr/0001-foo.md
    - DEVOPS-1525
  jira: DEVOPS-1525  # optional
```

Append an entry immediately when:

| Event                                    | type          |
|------------------------------------------|---------------|
| Decision made or reversed                | `decision` (link the ADR if one was written) |
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

## Issue tracker and tasks

Where PRDs and vertical-slice issues go is driven by `project.yaml`:

- **`jira_key` is set** → publish to Jira. PRDs get the `ready-for-agent` label.
  Each issue gets an `afk` or `hitl` label mirroring its type, and
  `ready-for-agent` is added to AFK issues only — never HITL.
- **`jira_key` is empty** → keep work local. A PRD becomes
  `docs/plans/<slug>-prd.md`; vertical-slice issues become `tasks` in
  `project.yaml`.
- Use GitHub Issues only when explicitly asked to.

A **task** is a vertical slice tracked in `project.yaml`:

```yaml
tasks:
  - id: extract-gateway-subchart   # stable kebab-case id (used in blocked_by)
    title: Extract aidp-gateway subchart
    type: AFK                      # AFK | HITL
    status: todo                   # todo | active | done | blocked
    blocked_by: []                 # list of task ids
    plan: docs/plans/chart-split-prd.md   # source PRD/plan
    jira: null                     # set when mirrored to a Jira issue
```

Status transitions drive the journal: `todo → active` writes a `started` entry,
`active → done` writes a `done` entry, any → `blocked` writes a `blocker` entry.
`/sync-status` reads `active` tasks for "Active work" and `blocked` for "Blocked
/ open questions."

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

- Architectural Decision Records (ADRs) capture the reasoning behind a decision
  that is hard to reverse, surprising without context, and the result of a real
  trade-off. Store these in `docs/adr/` using sequential numbering
  (`0001-slug.md`). A lightweight decision that does not clear all three bars
  needs only a `decision` line in `journal.yaml` — not a document.

- Research documents are used to store in-depth information about a topic or
  work item. The research may be referenced by multiple plans. Store these in
  `docs/research/`. Use this directory when I say things like: "Research how X
  works". This can also be used when a plan requires in-depth research.

- Validation documents prove that a plan was successfully completed. Produce one
  when a meaningful plan or milestone finishes (not every task) — or whenever I
  ask you to validate — and reference it from the corresponding `done` entry in
  `journal.yaml`. Review the plan, gather evidence of completed work, and create
  the document. This MUST include tangible and auditable examples such as
  commands run, file paths and lines `path/to/file.ext:34`, or the output summary
  of a successful test run. Store these documents in `docs/validations/`.

- Scripts for complex or repeatable work items. When you need to do something
  that is more complex due to the number of commands or the amount of logic
  (conditionals, loops, advanced scripting language features) or when you need to
  run the same command set over and over again you will create a script. Scripts
  will be put into `scripts/`. Scripts should be written in Bash but you can use
  Python as well.

- Repos (`repos/`) stores repositories this project needs for research or
  changes. NEVER run `git clone` directly — use
  `scripts/repo.sh clone <url> [name]`, which clones into `repos/` and registers
  the repo in `project.yaml`. `repo.sh` fetches automatically before every use,
  so clones stay current.

- Worktrees (`worktrees/`) stores git worktrees for task work, laid out as
  `worktrees/<task-id>/<repo>` (one task can span multiple repos). Worktrees MUST
  be used when working on Tasks — never create branches inside a base clone.
  Use `scripts/repo.sh worktree <task> <repo>` to start, `scripts/repo.sh sync`
  to catch a worktree up to its base branch, and `scripts/repo.sh status` to
  check for drift. Remove with `scripts/repo.sh remove <task> [repo]`.
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
    update-skills)
      [[ -n "$SUBCOMMAND" ]] && die "Unexpected argument: $1"
      SUBCOMMAND="update-skills"; shift ;;
    *)
      [[ -n "$PROJECT_NAME" ]] && die "Unexpected argument: $1 (project name already set to '${PROJECT_NAME}')"
      PROJECT_NAME="$1"; shift ;;
  esac
done

TODAY=$(date +%Y-%m-%d)

# ── subcommand: update-skills ─────────────────────────────────────────────────
if [[ "$SUBCOMMAND" == "update-skills" ]]; then
  if [[ -n "$PROJECT_NAME" ]]; then
    TARGET="${BASE_DIR}/${PROJECT_NAME}"
  else
    TARGET="$BASE_DIR"
  fi

  SKILLS_DEST="${TARGET}/.claude/skills"

  [[ ! -d "$TARGET"      ]] && die "Project directory not found: $TARGET"
  [[ ! -d "$SKILLS_DEST" ]] && die "No .claude/skills/ found in: $TARGET\n       Run 'proj <name> --skills' first to install skills."
  [[ ! -d "$SKILLS_SRC"  ]] && die "Skills source directory not found: $SKILLS_SRC\n       Check your installation."

  # Default: update every skill already installed in the project
  if [[ -n "$SKILLS_LIST" ]]; then
    SKILLS_TO_UPDATE="$SKILLS_LIST"
  else
    SKILLS_TO_UPDATE="$(ls -1 "$SKILLS_DEST" 2>/dev/null | tr '\n' ' ')"
  fi

  if [[ -z "${SKILLS_TO_UPDATE// /}" ]]; then
    warn "No skills found in: $SKILLS_DEST"
    exit 0
  fi

  if $DRY_RUN; then
    info "Dry run — nothing will be written."
    echo ""
    echo "Would update skills in: $TARGET"
  fi

  UPDATED=0
  SKIPPED=0
  for skill in $SKILLS_TO_UPDATE; do
    SRC="${SKILLS_SRC}/${skill}"
    DEST="${SKILLS_DEST}/${skill}"

    if [[ ! -d "$SRC" ]]; then
      warn "Not in source, skipping: ${skill}"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if [[ ! -d "$DEST" ]]; then
      warn "Not installed in project, skipping: ${skill}  (use --skills ${skill} to install)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    if $DRY_RUN; then
      echo "  [update] .claude/skills/${skill}/"
    else
      rm -rf "$DEST"
      cp -r "$SRC" "$DEST"
      UPDATED=$((UPDATED + 1))
    fi
    # Re-wire hooks and (re)install companion files; idempotent, so safe to
    # run against an already-populated existing workspace.
    post_install_skill "$TARGET" "$skill"
  done

  echo ""
  if $DRY_RUN; then
    info "Dry run complete. Re-run without --dry-run to update."
  else
    info "Updated ${UPDATED} skill(s) in: $TARGET"
    [[ $SKIPPED -gt 0 ]] && warn "Skipped ${SKIPPED} skill(s) — see warnings above."
  fi
  exit 0
fi

# ── scaffold (default subcommand) ─────────────────────────────────────────────
[[ -z "$PROJECT_NAME" ]] && die "Usage: proj <project-name> [options]\n       Run with --help for full usage."

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
make_dir "$TARGET/docs/adr"
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

# CONTEXT.md
write_file "$TARGET/CONTEXT.md" "$(cat << EOF
# ${PROJECT_NAME}

<!-- One or two sentences: what this project's domain is and why it exists. -->

## Language

<!--
Domain glossary. /grill-with-docs maintains this as terminology is resolved.
Pick one canonical term per concept and list synonyms under _Avoid_.
Glossary only — no implementation details, no general programming concepts.

**Term**:
One or two sentence definition of what it IS, not what it does.
_Avoid_: synonyms to steer away from.
-->
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
  if [[ -n "$SKILLS_LIST" ]]; then
    SKILLS_TO_COPY="$SKILLS_LIST"
  else
    SKILLS_TO_COPY="$(ls -1 "$SKILLS_SRC" 2>/dev/null | tr '\n' ' ')"
  fi

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
      # Wire hooks + install companion files for hook-bearing skills.
      # Idempotent merge, so it composes cleanly when several are copied.
      post_install_skill "$TARGET" "$skill"
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
