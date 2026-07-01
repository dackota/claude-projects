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
#   --skills [LIST]    Skills are bundled by default. Pass LIST (comma-separated,
#                      e.g. tdd,grill-with-docs) to restrict to a subset; bare
#                      --skills is the same as the default (all skills).
#   --no-skills        Opt out of bundling skills into the new project.
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
COPY_SKILLS=true   # skills are bundled by default; opt out with --no-skills
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
AGENTS_SRC="${SCRIPT_DIR}/../agents"

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
  case "$skill" in journal|sync-status|repo|pr-security-review) ;; *) return 0 ;; esac
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
      add_hook "$settings" PostToolUse "Write|Edit" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/journal-check.sh' true "Journal entry may be needed"
      add_hook "$settings" Stop "" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/journal-stop.sh' true "Unlogged journal events detected"
      ;;
    sync-status)
      # Synchronous (no asyncRewake): block once at the real stop when STATUS.md
      # is staler than journal.yaml, so the fix happens before the session ends.
      # asyncRewake re-woke about already-resolved state (stale/duplicate fires).
      add_hook "$settings" Stop "" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/sync-status/hooks/sync-status-stop.sh' false ""
      ;;
    repo)
      add_hook "$settings" PreToolUse "Bash"       'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/repo/hooks/git-guard.sh'   false ""
      # Staleness is checked point-of-use only: the PreToolUse(Edit|Write) hook
      # warns when a worktree is about to be edited (scoped to that worktree).
      # No blanket Stop-time sweep of all worktrees — that fired on every stop
      # regardless of whether a worktree was being used, which was too noisy.
      add_hook "$settings" PreToolUse "Edit|Write" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/repo/hooks/repo-stale.sh'  false ""
      ;;
    pr-security-review)
      add_hook "$settings" PreToolUse "Bash" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/hooks/pr-gate.sh' false ""
      ;;
  esac
}

# Skills may declare `agents:` in their SKILL.md frontmatter. Copy each named
# agent definition from the repo's agents/ dir into the workspace's
# .claude/agents/ (auto-discovered there — no wiring needed).
# install_skill_agents <target> <skill>
install_skill_agents() {
  local target="$1" skill="$2" agent
  local skill_md="${SKILLS_SRC}/${skill}/SKILL.md"
  [[ -f "$skill_md" ]] || return 0
  command -v yq >/dev/null 2>&1 || return 0
  local agents
  agents="$(yq --front-matter=extract '.agents // [] | .[]' "$skill_md" 2>/dev/null || true)"
  [[ -z "${agents// /}" ]] && return 0
  for agent in $agents; do
    local src="${AGENTS_SRC}/${agent}.md"
    if [[ ! -f "$src" ]]; then
      warn "Skill '${skill}' wants agent '${agent}' but ${src} is missing — skipping."
      continue
    fi
    if $DRY_RUN; then
      echo "  [agent] .claude/agents/${agent}.md"
    else
      mkdir -p "$target/.claude/agents"
      cp "$src" "$target/.claude/agents/${agent}.md"
    fi
  done
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
  install_skill_agents "$target" "$skill"
  [[ "$skill" == "repo" ]] && install_repo_script "$target"
  return 0
}

# Companion skills a skill orchestrates and cannot function without.
# skill_deps <skill> -> echoes space-separated dependency skill names
# Note: `codebase-researcher` is intentionally NOT a dep of `next` — it's an
# optional detour, never pulled in as a dep of next (it's bundled by default with
# all skills, but an explicit `--skills` subset must name it).
skill_deps() {
  case "$1" in
    next) echo "grill-with-docs to-prd to-issues tdd" ;;
    *) ;;
  esac
}

# Expand a skill list to include each skill's dependencies, deduped and
# order-preserving. expand_skill_deps <skill...> -> echoes the expanded list.
expand_skill_deps() {
  local s d
  for s in "$@"; do
    echo "$s"
    for d in $(skill_deps "$s"); do echo "$d"; done
  done | awk '!seen[$0]++' | tr '\n' ' '
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

1. Read `STATUS.md` first — a ~500-token synthesis of current project state. If
   it is absent, run `/sync-status` to generate it.
2. **Before anything else, check `PROJECT.md`.** If its Goals section is still the
   scaffold placeholder (empty, or just the `<!-- … -->` comment), the project has
   no stated goal yet — do **not** proceed or invent one. Ask the user what the
   project is trying to accomplish, fill `PROJECT.md` in with their answers (keep
   the frontmatter), then continue. `/next` treats this as the **Bootstrap** phase.
3. Run `/next` (bundled by default). It reads workspace state, determines the
   current lifecycle phase, and routes to the next action — so you never have to
   recall the `grill-with-docs → to-prd → to-issues → tdd` sequence. Run it any
   time mid-session to ask "where am I / what's next?".

## Files & directories

- `project.yaml` — source of truth: repos, tasks, Jira key, config
- `PROJECT.md` — goals and context (read this for the why)
- `STATUS.md` — current-state synthesis; READ FIRST every session
- `CONTEXT.md` — domain glossary: the canonical term for each concept, with
  synonyms to steer away from. Use its vocabulary in plans, ADRs, issues, tests,
  and commits. Glossary only — no implementation detail. `/grill-with-docs`
  maintains it.
- `journal.yaml` — append-only event log; never rewrite, only append (see below)
- `docs/plans/` — planning documents (and local PRDs when not using a tracker)
- `docs/adr/` — architectural decision records (see Documentation rules)
- `docs/research/`, `docs/validations/` — research, and completion evidence
- `scripts/` — one-off scripts not belonging to a specific repo
- `repos/`, `worktrees/` — cloned repos and task worktrees, **managed only via
  `scripts/repo.sh`** (see below). Both are `.gitignore`-excluded; repos are
  tracked in `project.yaml`, worktrees derived live — read it to see what exists.

## repos/ & worktrees/ — always via `scripts/repo.sh`

With the `repo` skill installed (default), every repo/worktree operation goes
through `scripts/repo.sh`; a PreToolUse hook blocks raw `git clone`,
`git worktree add`, and branch create/switch under `repos/`/`worktrees/`
(read-only git and `git checkout -- <file>` stay allowed). Run `scripts/repo.sh`
with no args for the command list, or see the `repo` skill.

Key habits: worktrees drift as their base advances — run `scripts/repo.sh status`
before relying on one, `sync` to catch it up. When a task depends on another still
in review, **stack** on that branch (`repo.sh worktree <task> <repo> --onto
<parent>`, or auto-derived from a single unmerged `blocked_by`) instead of
waiting; `sync` re-points to the base once the parent merges.

## Independent review

Two reviews guard each slice, each by a fresh agent that never saw the build
conversation, run at different moments:

- **Acceptance — right after the build.** When `/next` builds a task it commits
  the slice and runs `implementation-validator` against the acceptance criteria.
  A CRITICAL gap **loops back to `tdd`**; the task stays `active` (never `done`,
  let alone a PR) until acceptance passes.
- **Security — at the PR gate.** With `pr-security-review` installed (default),
  CLI `gh pr create` is gated by `security-reviewer`. A CRITICAL blocks until
  fixed (each fix commit re-reviews); HIGH/MEDIUM/LOW are noted in the PR body but
  pass. A review is required when the diff touches infra (any size) or is code
  over ~25 lines; small code-only and docs-only diffs skip. `--web`/GitHub UI
  bypass the gate.

## Documentation rules

All artifacts are Markdown with dash-separated file names. Every doc in
`docs/plans/`, `docs/research/`, and `docs/validations/` MUST carry lifecycle
frontmatter (ADRs and `CONTEXT.md` are exempt):

```yaml
---
title: <human-readable title>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []            # paths this replaces
superseded_by: null       # path to doc that replaced this
related: []               # cross-references for navigation
jira: null                # optional Jira issue key
task: null                # optional task id from project.yaml
---
```

`status` is the authoritative currency signal — skip non-`active` docs unless
tracing history. Never move or delete a superseded doc: flip `status: superseded`,
set `superseded_by`, and add a short block-quote at the top saying when/why.

Doc types:

| Type | Where | When / must include |
|------|-------|---------------------|
| **Plan** | `docs/plans/` | "create a plan", "plan it out". Detail Problem, Solution, Trade-offs, Considerations; break into human-reviewable Tasks. |
| **ADR** | `docs/adr/0001-slug.md` | A decision that is (1) hard to reverse, (2) surprising without context, (3) a real trade-off. If any bar is missing, skip it — a `decision` journal line suffices. |
| **Research** | `docs/research/` | "research how X works"; may be referenced by multiple plans. |
| **Validation** | `docs/validations/` | When a meaningful plan/milestone finishes (not every task). Auditable evidence: commands run, `path/to/file.ext:34`, test output. Reference it from the `done` journal entry. |
| **Script** | `scripts/` | Repeatable or logic-heavy work. Bash preferred, Python OK. |

## journal.yaml

Append-only; never edit existing entries. Manual escape hatch:
`/journal <type> "<summary>"`. Entry schema:

```yaml
- date: YYYY-MM-DD
  type: decision   # decision | plan | started | done | blocker | supersession | research | pr
  summary: <one or two sentences>
  refs: []         # optional paths or external IDs
  jira: DEVOPS-1525  # optional
```

Append immediately when: a decision is made/reversed (`decision` — link the ADR
if one was written) · a plan is finalized/revised (`plan`) · a task status flips
(`started`/`done`) · a blocker is hit (`blocker`) · a doc is superseded
(`supersession`) · research is finalized (`research`) · a PR is opened/merged/
closed (`pr`).

## /sync-status

Regenerates `STATUS.md` wholesale from `PROJECT.md`, `project.yaml`,
`journal.yaml`, and doc frontmatter/active-doc content. Run it (or Claude runs it
automatically) when **both** hold: (1) a significant change occurred (plan
finalized, decision committed, task status flipped, meaningful blocker); and
(2) a natural pause has arrived (handing back, finishing a work block). Not after
every doc edit.

## Issue tracker & tasks

Where PRDs and vertical-slice issues go is driven by `project.yaml`:

- **`jira_key` set** → publish to Jira. PRDs get `ready-for-agent`; each issue
  gets an `afk`/`hitl` label mirroring its type, and `ready-for-agent` is added to
  AFK issues only — never HITL.
- **`jira_key` empty** → keep local. PRD → `docs/plans/<slug>-prd.md`;
  vertical-slice issues → `tasks` in `project.yaml`.
- Use GitHub Issues only when explicitly asked.

A **task** is a vertical slice in `project.yaml`:

```yaml
tasks:
  - id: extract-gateway-subchart   # stable kebab-case id (used in blocked_by)
    title: Extract aidp-gateway subchart
    type: AFK                      # AFK | HITL
    status: todo                   # todo | active | done | blocked
    blocked_by: []                 # list of task ids
    plan: docs/plans/chart-split-prd.md
    jira: null                     # set when mirrored to a Jira issue
```

Status transitions drive the journal: `todo → active` → `started`,
`active → done` → `done`, any → `blocked` → `blocker`.
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
    --no-skills)       COPY_SKILLS=false; shift ;;
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

  # Pull in companion skills an orchestrator skill depends on (e.g. `next`).
  # (Install-time only — `update-skills` deliberately updates just what's asked,
  # not transitive deps, so an explicit skill list there is honored verbatim.)
  SKILLS_TO_COPY="$(expand_skill_deps $SKILLS_TO_COPY)"

  if [[ ! -d "$SKILLS_SRC" ]]; then
    warn "skills bundling is on but skills directory not found: $SKILLS_SRC"
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
