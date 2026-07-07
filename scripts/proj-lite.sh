#!/usr/bin/env bash
# proj-lite — scaffold a lightweight ("lite") claude-projects workspace.
#
# The lite flow is a manual, low-ceremony pipeline:
#
#     /grill-with-docs  →  /to-prd  →  /to-issues  →  /build
#
# `/build` spawns a `lite-orchestrator` sub-agent that owns a build→check→iterate
# loop: `lite-builder` builds the slice, an independent `lite-checker` EXERCISES the
# change end-to-end and judges it against the acceptance criteria, and the loop
# repeats until the intent is met or the rework cap fires. The loop runs off the main
# session to keep it lean. No router, no barrier, no journal/audit machinery, no
# repo.sh — repos/ is read-only reference and all work happens in worktrees/.
#
# This script is deliberately SELF-CONTAINED (its own arg parsing, embedded CLAUDE.md,
# and helpers, no sourcing of proj.sh) so the lite flow can be lifted into its own
# repo. To extract it, take: this script, skills/lite/, the shared skills
# skills/{to-prd,codebase-design,observability}/, and
# agents/lite-{orchestrator,builder,checker}.md.
#
# Usage:
#   proj-lite <project-name> [options]
#
# Options:
#   --dir <path>     Base directory for the project (default: current directory)
#   --jira <KEY>     Jira key recorded in project.yaml (informational in the lite flow)
#   --otel           Pre-set observability.enabled: true (else /grill/to-issues flip it
#                    when a request-serving path appears)
#   --dry-run        Print what would be created; write nothing
#   --force          Overwrite if the target directory already exists
#   -h, --help       Show this help

set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────
BASE_DIR="$(pwd)"
JIRA_KEY=""
DRY_RUN=false
FORCE=false
OTEL=false
PROJECT_NAME=""

# Resolve the script's real directory (handles symlinks on macOS).
_SCRIPT="${BASH_SOURCE[0]}"
while [[ -L "$_SCRIPT" ]]; do
  _SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"
  _SCRIPT="$(readlink "$_SCRIPT")"
  [[ "$_SCRIPT" != /* ]] && _SCRIPT="${_SCRIPT_DIR}/${_SCRIPT}"
done
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/../skills"
LITE_SKILLS_SRC="${SKILLS_SRC}/lite"
AGENTS_SRC="${SCRIPT_DIR}/../agents"

# The lite bundle.
#   Forked variants (from skills/lite/, installed under their canonical command names):
LITE_FORKED_SKILLS="grill-with-docs to-issues build"
#   Shared skills (from skills/, used unchanged):
LITE_SHARED_SKILLS="to-prd codebase-design observability"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}[proj-lite]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[proj-lite]${RESET} $*"; }
error() { echo -e "${RED}[proj-lite]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── hook wiring (idempotent settings.json merge) ───────────────────────────────
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

# Wire the lite flow's one hook: keep repos/ read-only (build skill's guard).
wire_lite_hooks() {
  local target="$1" settings
  if $DRY_RUN; then
    echo "  [hooks] .claude/settings.json  <- repos-readonly (merge)"
    return 0
  fi
  command -v jq >/dev/null 2>&1 || die "jq is required to wire the read-only hook. Install: brew install jq"
  settings="$target/.claude/settings.json"
  mkdir -p "$target/.claude"
  [[ -f "$settings" ]] || echo '{}' > "$settings"
  add_hook "$settings" PreToolUse "Edit|Write" \
    'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/build/hooks/repos-readonly.sh' false ""
}

# Copy the agents a skill declares in its SKILL.md `agents:` frontmatter into the
# workspace's .claude/agents/ (auto-discovered there — no wiring needed).
install_skill_agents() {
  local target="$1" skill_md="$2" agent
  [[ -f "$skill_md" ]] || return 0
  if ! command -v yq >/dev/null 2>&1; then
    if grep -qE '^agents:' "$skill_md"; then
      die "A lite skill installs agents but yq is not available to read its 'agents:' list. Install: brew install yq"
    fi
    return 0
  fi
  local agents
  agents="$(yq --front-matter=extract '.agents // [] | .[]' "$skill_md" 2>/dev/null || true)"
  [[ -z "${agents// /}" ]] && return 0
  for agent in $agents; do
    local src="${AGENTS_SRC}/${agent}.md"
    if [[ ! -f "$src" ]]; then
      warn "Skill wants agent '${agent}' but ${src} is missing — skipping."
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

# ── embedded lite CLAUDE.md ────────────────────────────────────────────────────
claude_md_content() {
cat << 'CLAUDE_MD_EOF'
# Workspace (lite)

`PROJECT.md` holds the goal (the *why*); this workspace directory holds the work.
`project.yaml` is the source of truth for repos, tasks, and config.

This is a **lite** workspace — a manual, low-ceremony flow with no router, no audit
machinery, and no PR gates. You drive it by hand:

    /grill-with-docs   →   /to-prd   →   /to-issues   →   /build

- **`/grill-with-docs`** — stress-test the idea one question at a time; sharpen
  `CONTEXT.md`, offer ADRs.
- **`/to-prd`** — synthesize the conversation into a PRD in `docs/plans/`.
- **`/to-issues`** — break the PRD into **self-contained tasks** in `project.yaml`
  (acceptance criteria inline; each task names its target `repo`).
- **`/build [task-id]`** — build the next unblocked task. It spawns a
  `lite-orchestrator` sub-agent that runs a **build→check→iterate loop**:
  `lite-builder` builds the slice, then an independent `lite-checker` **exercises**
  the change end-to-end and judges it against the acceptance criteria; a BLOCK loops
  back with findings until the intent is met or the rework cap fires. The loop runs
  off this session to keep it lean. Build several independent tasks at once by asking
  to build them in parallel.

## Map

| Path | What |
|------|------|
| `PROJECT.md` | The goal + context |
| `project.yaml` | Repos, tasks (schema: `to-issues` skill), observability + validation config |
| `CONTEXT.md` | Domain glossary — use its canonical terms in plans, ADRs, issues, tests |
| `docs/` | `plans/` · `adr/` · `research/` — conventions in `docs/README.md` |
| `repos/` | **Read-only** base clones for reference (a hook blocks writes here) |
| `worktrees/` | Where **all** work happens — one worktree per task, cut by `/build` |

Coding standards load automatically (global config, or `.claude/rules/` when bundled);
language rules apply to the files you touch.

## Hard rules

- **All work happens in `worktrees/`.** `repos/` holds **read-only** base clones for
  reference; a PreToolUse hook blocks writes there. `/build` cuts a `git worktree` off
  the target repo's clone for each task.
- **Clone repos into `repos/`** with `git clone <url> repos/<name>` and record them in
  `project.yaml` `repos:`. Each task names the `repo` it builds in.
- **`/build` builds one unblocked task** (or several independent ones in parallel). On
  success the slice is built + validated but **uncommitted** — you review, commit, and
  open the PR by hand. Run `/security-review` first if the slice warrants it.
- **The build loop is bounded** by `validation.max_rework` (default 3): a slice that
  keeps failing the checker escalates to you, not another round.
- **GitHub via `gh-axi` (required).** This flow requires the agent-first `gh-axi` CLI
  (https://github.com/kunchenguid/gh-axi) installed and `gh` authenticated. For any GitHub
  operation — opening or reviewing PRs, issues, checking CI — use `gh-axi <command>` rather
  than raw `gh`; its output is token-efficient and each response suggests the next command.
  E.g. open a PR with `gh-axi pr create --title "…" --body-file <path>`.
CLAUDE_MD_EOF
}

# ── embedded lite docs/README.md ───────────────────────────────────────────────
docs_readme_content() {
cat << 'DOCS_README_EOF'
# docs/ conventions (lite)

All artifacts are Markdown with dash-separated file names. Every doc in `docs/plans/`
and `docs/research/` should carry lifecycle frontmatter (ADRs and `CONTEXT.md` are
exempt):

```yaml
---
title: <human-readable title>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []
superseded_by: null
related: []
---
```

`status` is the currency signal — skip non-`active` docs unless tracing history. Never
delete a superseded doc: flip `status: superseded`, set `superseded_by`, and note why.

## Doc types

| Type | Where | When |
|------|-------|------|
| **Plan / PRD** | `docs/plans/` | `/to-prd` writes it. Problem, Solution, Requirements (`R<n>`), Trade-offs. |
| **ADR** | `docs/adr/0001-slug.md` | A decision that is hard to reverse, surprising without context, and a real trade-off. Otherwise skip it. |
| **Research** | `docs/research/` | "research how X works"; may be referenced by multiple plans. |
| **Script** | `scripts/` | Repeatable or logic-heavy work. Bash preferred, Python OK. |
DOCS_README_EOF
}

# ── arg parsing ────────────────────────────────────────────────────────────────
usage() { grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --force)     FORCE=true; shift ;;
    --otel)      OTEL=true; shift ;;
    --dir)       [[ $# -lt 2 ]] && die "--dir requires an argument"; BASE_DIR="$2"; shift 2 ;;
    --jira)      [[ $# -lt 2 ]] && die "--jira requires an argument"; JIRA_KEY="$2"; shift 2 ;;
    -*)          die "Unknown option: $1" ;;
    *)           [[ -n "$PROJECT_NAME" ]] && die "Unexpected argument: $1 (project name already '${PROJECT_NAME}')"
                 PROJECT_NAME="$1"; shift ;;
  esac
done

[[ -z "$PROJECT_NAME" ]] && die "Usage: proj-lite <project-name> [options]\n       Run with --help for full usage."

TODAY=$(date +%Y-%m-%d)
TARGET="${BASE_DIR}/${PROJECT_NAME}"

# ── pre-flight ─────────────────────────────────────────────────────────────────
if [[ -e "$TARGET" ]]; then
  if $FORCE; then warn "Target exists — overwriting because --force was passed: $TARGET"
  else die "Target already exists: $TARGET\n       Use --force to overwrite."; fi
fi

# ── helpers ────────────────────────────────────────────────────────────────────
make_dir()   { if $DRY_RUN; then echo "  [dir]  $1"; else mkdir -p "$1"; fi; }
write_file() {
  local path="$1" content="$2"
  if $DRY_RUN; then echo "  [file] $path"
  else mkdir -p "$(dirname "$path")"; printf '%s\n' "$content" > "$path"; fi
}

if $DRY_RUN; then info "Dry run — nothing will be written."; echo ""; echo "Would create: $TARGET"; fi

# ── scaffold ───────────────────────────────────────────────────────────────────
make_dir "$TARGET"
make_dir "$TARGET/docs/plans"
make_dir "$TARGET/docs/adr"
make_dir "$TARGET/docs/research"
make_dir "$TARGET/scripts"
make_dir "$TARGET/repos"
make_dir "$TARGET/worktrees"

write_file "$TARGET/CLAUDE.md" "$(claude_md_content)"
write_file "$TARGET/docs/README.md" "$(docs_readme_content)"

write_file "$TARGET/.gitignore" "$(cat << 'EOF'
repos/
worktrees/
EOF
)"

if $OTEL; then OBS_ENABLED=true; else OBS_ENABLED=false; fi
write_file "$TARGET/project.yaml" "$(cat << EOF
name: ${PROJECT_NAME}
jira_key: "${JIRA_KEY}"
created: ${TODAY}
repos: []               # base clones under repos/ (read-only). Add: git clone <url> repos/<name>
#  - name: <repo>
#    url: <git-url>
tasks: []               # self-contained slices (schema: to-issues skill). Each names its target repo.
observability:
  enabled: ${OBS_ENABLED}       # true => to-issues folds concrete RED/log/span criteria into request-serving slices
  waived: ""            # non-empty reason => explicit "no observability" decision (the reason IS the audit trail)
  otlp_endpoint: ""
  service_name: ""
validation:
  run_cmd: ""           # how lite-checker boots/drives the artifact; inferred per project type when empty
  format_cmd: ""        # formatter (e.g. "gofmt -w ." / "ruff format"); inferred when empty
  lint_cmd: ""          # linter/vet (e.g. "go vet ./..." / "ruff check"); inferred when empty
  test_cmd: ""          # full test command (e.g. "go test ./..." / "pytest"); inferred when empty
  max_rework: 3         # build loop cap: max checker BLOCKs on one slice before it escalates to you
EOF
)"

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

# ── skills ─────────────────────────────────────────────────────────────────────
if [[ ! -d "$LITE_SKILLS_SRC" ]]; then
  warn "lite skills source not found: $LITE_SKILLS_SRC — skills will not be copied."
else
  # Forked lite variants install under their canonical command names.
  for skill in $LITE_FORKED_SKILLS; do
    src="${LITE_SKILLS_SRC}/${skill}"; dest="${TARGET}/.claude/skills/${skill}"
    [[ -d "$src" ]] || { warn "Lite skill not found, skipping: $skill ($src)"; continue; }
    if $DRY_RUN; then echo "  [skill] .claude/skills/${skill}/  (lite)"
    else mkdir -p "$(dirname "$dest")"; cp -r "$src" "$dest"; fi
    install_skill_agents "$TARGET" "${src}/SKILL.md"
  done
  # Shared skills, used unchanged. We do NOT install their declared agents: the lite
  # flow's only agents are the three the `build` skill declares (installed above). The
  # observability skill, in particular, declares otel-observability-engineer — a full-flow
  # barrier gate that nothing spawns in lite (the lite-checker validates observability
  # criteria itself). We bundle observability only for its standard.md.
  for skill in $LITE_SHARED_SKILLS; do
    src="${SKILLS_SRC}/${skill}"; dest="${TARGET}/.claude/skills/${skill}"
    [[ -d "$src" ]] || { warn "Shared skill not found, skipping: $skill ($src)"; continue; }
    if $DRY_RUN; then echo "  [skill] .claude/skills/${skill}/  (shared)"
    else mkdir -p "$(dirname "$dest")"; cp -r "$src" "$dest"; fi
  done
fi

# ── hook ───────────────────────────────────────────────────────────────────────
wire_lite_hooks "$TARGET"

# ── done ───────────────────────────────────────────────────────────────────────
if $DRY_RUN; then
  echo ""; info "Dry run complete. Re-run without --dry-run to create."
else
  echo ""
  info "Lite project scaffolded at: $TARGET"
  echo ""
  echo "  Next steps:"
  echo "    1. cd $TARGET"
  echo "    2. Clone the repos you'll work in:  git clone <url> repos/<name>  (add them to project.yaml repos:)"
  echo "    3. Edit PROJECT.md — describe your goals"
  echo "    4. Run /grill-with-docs → /to-prd → /to-issues → /build"
fi
