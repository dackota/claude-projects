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
#   --jira <KEY>       Jira project key (e.g. PROJ)  [scaffold only]
#   --skills [LIST]    Skills are bundled by default. Pass LIST (comma-separated,
#                      e.g. tdd,grill-with-docs) to restrict to a subset; bare
#                      --skills is the same as the default (all skills).
#   --no-skills        Opt out of bundling skills into the new project.
#   --lite             Scaffold the lightweight flow instead (grill → to-prd → to-issues
#                      → /build, where /build runs a build→check→iterate sub-agent loop).
#                      Delegates to the self-contained scripts/proj-lite.sh; all other
#                      flags except --dir/--jira/--otel/--dry-run/--force are ignored.
#                      [scaffold only]
#   --full             Also bundle the extras (code-review, codebase-researcher,
#                      diagnosing-bugs, improve-codebase-architecture, prototype).
#                      Excluded by default to keep per-session context lean; each
#                      is also individually installable via --skills.  [scaffold only]
#   --otel             Pre-set observability.enabled: true at scaffold, for a project
#                      already known to be a runtime service. The observability skill +
#                      otel agent are ALWAYS bundled (dormant unless enabled), so this
#                      only flips the flag on early; otherwise to-issues enables it the
#                      moment a request-serving path appears.  [scaffold only]
#   --bundle-rules     Copy the coding rules bundled with claude-projects into the
#                      project's .claude/rules/ so they travel with the repo. Off by
#                      default — only needed for repos used on machines without your global
#                      rules (teammates, CI, fresh clones); otherwise the global rules
#                      already load and bundling would just duplicate them.  [scaffold only]
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
SKILLS_LIST=""  # empty = the default bundle (core skills; extras need --full)
FULL=false      # --full also bundles the extras in EXTRA_SKILLS
OTEL=false      # --otel pre-sets observability.enabled: true (skill + agent are always bundled)
BUNDLE_RULES=false # coding rules are NOT bundled by default (global rules already load);
                   # opt in with --bundle-rules for repos used without your global config
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
# Coding rules are vendored in this repo (like skills/ and agents/) so --bundle-rules
# works on any machine — a project used without the user's global config still gets its
# standards. Keep this copy in sync with the canonical set in claude-config/rules.
RULES_SRC="${SCRIPT_DIR}/../rules"

# Extras: useful-but-occasional skills excluded from the default bundle so each
# workspace's per-session context stays lean (every bundled skill's description
# loads into every session). Bundle them with --full, or name one via --skills.
# NB: observability is NOT an extra — it ships in the default bundle (dormant unless
# project.yaml enables it) so the flag can flip on mid-project without a missing skill.
EXTRA_SKILLS="code-review codebase-researcher diagnosing-bugs improve-codebase-architecture prototype"

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
      # No per-write (Write|Edit) rewake: the Stop-time journal-stop.sh net below
      # catches unlogged doc changes before the session ends, without spending an
      # extra model turn on every mandated bookkeeping write.
      add_hook "$settings" Stop "" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/journal-stop.sh' true "Unlogged journal events detected"
      # After a review/gate sub-agent (Task) finishes, nudge a `run` audit entry.
      add_hook "$settings" PostToolUse "Task" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/run-check.sh' true "Gate run needs a journal entry"
      # Before re-spawning tdd-implementer, refuse if a gate has BLOCKed the active
      # task more than validation.max_rework times (barrier rework cap → escalate).
      add_hook "$settings" PreToolUse "Task" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/rework-cap.sh' true "Rework cap reached"
      # Gate `gh pr create` on the barrier's acceptance + correctness verdict, so the
      # "never reaches a PR until both PASS" promise is code, not just prose. (Security
      # is gated separately by pr-gate.sh; repo.sh pr self-enforces both internally.)
      add_hook "$settings" PreToolUse "Bash" 'bash "$CLAUDE_PROJECT_DIR"/.claude/skills/journal/hooks/barrier-gate.sh' false ""
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
  # yq is required to read a skill's `agents:` list. Fail LOUD when the skill
  # actually declares agents (else the gate agents silently never install and the
  # pipeline ships broken) — but stay silent for agent-less skills.
  if ! command -v yq >/dev/null 2>&1; then
    if grep -qE '^agents:' "$skill_md"; then
      die "Skill '${skill}' installs agents but yq is not available to read its 'agents:' list. Install: brew install yq"
    fi
    return 0
  fi
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
# `next` needs its planning/build companions AND its lifecycle infrastructure:
# `repo` (worktree ops in Pick/Build), `journal` (the `run` audit trail + rework-cap
# hook the barrier depends on), `sync-status` (Pipeline health in Learn), and
# `pr-security-review` (the "independent review before every PR" promise in Land).
# Without these a `--skills next` install is a legal-looking but silently broken
# pipeline. `security-review`/`cloud-infra-security` (read by the security-reviewer
# agent + pr-gate classifier) and `agent-controls` (read by the barrier) are listed
# directly on `next` because expand_skill_deps is one-level, not recursive.
# `observability` is a companion too: `to-issues` runs a flag-independent backstop that
# can enable it and read its `standard.md`, and the barrier spawns `otel-observability-engineer`
# for service tasks — so a `--skills next` install without it hits the same missing-skill
# break this bundle exists to prevent (its agent tags along via install_skill_agents).
# `codebase-researcher` is intentionally NOT a dep — it's an optional detour.
skill_deps() {
  case "$1" in
    next) echo "grill-with-docs to-prd to-issues tdd codebase-design repo journal sync-status pr-security-review security-review cloud-infra-security agent-controls observability" ;;
    pr-security-review) echo "security-review cloud-infra-security" ;;
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

# ── harness versioning + managed CLAUDE.md block ────────────────────────────
# The whole CLAUDE.md is harness-generated (project specifics live in PROJECT.md /
# CONTEXT.md), so it is wrapped in markers and treated as a managed block that
# `update-skills` can rewrite — closing the drift where `update-skills` refreshed
# skills but left CLAUDE.md stating retired rules. A `.harness-version` stamp
# records the source commit so a workspace's drift from the harness is visible.
HARNESS_BEGIN="<!-- BEGIN proj:harness (managed by proj update-skills; do not edit inside these markers) -->"
HARNESS_END="<!-- END proj:harness -->"

# Short commit SHA of the claude-projects source this proj was invoked from.
harness_sha() { git -C "${SCRIPT_DIR}/.." rev-parse --short HEAD 2>/dev/null || echo unknown; }

# The full managed CLAUDE.md document: markers wrapping the canonical template.
claude_md_document() {
  printf '%s\n' "$HARNESS_BEGIN"
  claude_md_content
  printf '%s\n' "$HARNESS_END"
}

# Rewrite the managed block in an existing CLAUDE.md, preserving any content the
# user added outside the markers. No-op (with a warning) when markers are absent,
# so a pre-managed-block workspace is never clobbered.
refresh_managed_claude_md() {
  local target="$1"
  local f="$target/CLAUDE.md"
  [[ -f "$f" ]] || return 0
  if ! grep -qF "$HARNESS_BEGIN" "$f" || ! grep -qF "$HARNESS_END" "$f"; then
    warn "CLAUDE.md has no proj:harness managed block — not refreshed (re-scaffold or add the markers to enable auto-refresh)."
    return 0
  fi
  local before after
  before="$(awk -v m="$HARNESS_BEGIN" 'index($0,m){exit} {print}' "$f")"
  after="$(awk  -v m="$HARNESS_END"   'p{print} index($0,m){p=1}' "$f")"
  {
    [[ -n "$before" ]] && printf '%s\n' "$before"
    claude_md_document
    [[ -n "$after" ]] && printf '%s\n' "$after"
    :
  } > "$f"
}

# ── embedded CLAUDE.md ───────────────────────────────────────────────────────
# This heredoc is the canonical CLAUDE.md for all scaffolded projects.
# Update this when the template changes; new-project is self-contained.
claude_md_content() {
cat << 'CLAUDE_MD_EOF'
# Workspace

`PROJECT.md` holds the goal (the *why*); this workspace directory holds the work.
`project.yaml` is the source of truth for repos, tasks, and config.

## Session start

1. Read `STATUS.md` — the current-state synthesis (absent → run `/sync-status`).
2. If `PROJECT.md`'s Goals section is still the scaffold placeholder, the project
   has no stated goal: ask the user and fill it in — **never invent one**.
3. Run `/next` — it reads workspace state and routes to the current lifecycle
   phase. Re-run any time to ask "where am I / what's next?".

## Map

| Path | What |
|------|------|
| `STATUS.md` | Read-first synthesis; regenerate with `/sync-status` after a significant change, at a natural pause |
| `project.yaml` | Repos, tasks (vertical slices — schema: `to-issues` skill), config |
| `CONTEXT.md` | Domain glossary — use its canonical terms in plans, ADRs, issues, tests, commits |
| `journal.yaml` | Append-only event log — never edit entries (schema: `journal` skill; manual: `/journal <type> "<summary>"`) |
| `docs/` | `plans/` · `adr/` · `research/` · `validations/` — conventions in `docs/README.md` |
| `repos/`, `worktrees/` | Clones + task worktrees, managed **only** via `scripts/repo.sh` (run it bare for the command list) |

Coding standards load automatically (global config, or `.claude/rules/` when
scaffolded with `--bundle-rules`); language rules apply to the files you touch.

## Hard rules

- **Journal immediately** when a decision lands, a plan is finalized, a task
  status flips, a blocker appears, research finalizes, a PR opens/merges, or a
  gate runs.
- **Read `docs/README.md` before writing any doc** — lifecycle frontmatter is
  mandatory and `status:` is the currency signal.
- **Never** run raw `git clone` / `git worktree` / branch ops under `repos/` or
  `worktrees/` — a hook blocks them; `scripts/repo.sh` wraps them (and `status` /
  `sync` catch worktree drift).
- **Write, then act:** PreToolUse gates inspect a command *before* it runs. Never
  chain a file write with a gated command in one Bash call
  (`… > verdict && gh pr create`) — the gate can't see the file yet and blocks.
  Write in one call; run the gated command in the next.
- The post-build barrier and PR security gate are normative in
  `.claude/skills/next/BARRIER.md` — point there; don't restate it.
CLAUDE_MD_EOF
}

# ── embedded docs/README.md ──────────────────────────────────────────────────
# Doc conventions live here (read on demand when writing a doc) rather than in
# CLAUDE.md (loaded every session) — the single canonical home for the lifecycle
# frontmatter schema and doc types. Skills reference this file by path.
docs_readme_content() {
cat << 'DOCS_README_EOF'
# docs/ conventions

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

## Doc types

| Type | Where | When / must include |
|------|-------|---------------------|
| **Plan** | `docs/plans/` | "create a plan", "plan it out". Detail Problem, Solution, Trade-offs, Considerations; break into human-reviewable Tasks. |
| **ADR** | `docs/adr/0001-slug.md` | A decision that is (1) hard to reverse, (2) surprising without context, (3) a real trade-off. If any bar is missing, skip it — a `decision` journal line suffices. |
| **Research** | `docs/research/` | "research how X works"; may be referenced by multiple plans. |
| **Validation** | `docs/validations/` | One per gated slice — the `/next` orchestrator writes it from the post-build gates' evidence (a section per gate: verdict · what · how · evidence like commands run, `path/to/file.ext:34`, test/boot output). Records the **final passing** state; mid-loop BLOCK history stays in `blocker`/`run` journal entries. The `done` journal entry references it. Hand-invoked `/tdd` writes its own at close-out. |
| **Script** | `scripts/` | Repeatable or logic-heavy work. Bash preferred, Python OK. |
DOCS_README_EOF
}

# ── arg parsing ───────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

# ── delegate to the lite scaffolder ────────────────────────────────────────────
# `proj <name> --lite [opts]` hands off to the self-contained proj-lite.sh (the lite
# flow can also be invoked directly as proj-lite). Strip --lite and forward the rest;
# proj-lite has its own arg parser and ignores flags it doesn't know.
for _a in "$@"; do
  if [[ "$_a" == "--lite" ]]; then
    LITE_ARGS=()
    for _b in "$@"; do [[ "$_b" == "--lite" ]] || LITE_ARGS+=("$_b"); done
    exec bash "${SCRIPT_DIR}/proj-lite.sh" ${LITE_ARGS[@]+"${LITE_ARGS[@]}"}
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)         usage ;;
    --show-claude-md)  claude_md_content; exit 0 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --force)           FORCE=true; shift ;;
    --dir)             [[ $# -lt 2 ]] && die "--dir requires an argument"; BASE_DIR="$2"; shift 2 ;;
    --jira)            [[ $# -lt 2 ]] && die "--jira requires an argument"; JIRA_KEY="$2"; shift 2 ;;
    --no-skills)       COPY_SKILLS=false; shift ;;
    --full)            FULL=true; shift ;;
    --otel)            OTEL=true; shift ;;
    --bundle-rules)    BUNDLE_RULES=true; shift ;;
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

  # Refresh the managed CLAUDE.md block + re-stamp the source SHA so the workspace
  # picks up harness changes to the template — not just the skills.
  if $DRY_RUN; then
    echo "  [update] CLAUDE.md managed block + .harness-version"
    [[ -f "$TARGET/docs/README.md" ]] || echo "  [file] docs/README.md (backfill)"
    [[ -n "$SKILLS_LIST" || -d "$SKILLS_DEST/observability" ]] || echo "  [skill] .claude/skills/observability/ (backfill)"
  else
    refresh_managed_claude_md "$TARGET"
    printf 'harness_sha: %s\nstamped: %s\n' "$(harness_sha)" "$TODAY" > "$TARGET/.harness-version"
    # Backfill doc conventions for pre-docs/README.md workspaces; never overwrite
    # an existing one (docs/ is user territory once scaffolded).
    if [[ ! -f "$TARGET/docs/README.md" ]]; then
      mkdir -p "$TARGET/docs"
      printf '%s\n' "$(docs_readme_content)" > "$TARGET/docs/README.md"
    fi
    # Backfill the now-always-bundled observability skill (+ its otel agent) for
    # pre-change workspaces, so the flag can flip on without a missing skill. Only on a
    # full update (an explicit --skills subset is honored verbatim); never clobbers an
    # existing copy (the loop above already refreshed it if installed).
    if [[ -z "$SKILLS_LIST" && ! -d "$SKILLS_DEST/observability" && -d "$SKILLS_SRC/observability" ]]; then
      mkdir -p "$SKILLS_DEST"
      cp -r "$SKILLS_SRC/observability" "$SKILLS_DEST/observability"
      post_install_skill "$TARGET" "observability"
    fi
  fi

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

# CLAUDE.md (wrapped in the managed-block markers so update-skills can refresh it)
write_file "$TARGET/CLAUDE.md" "$(claude_md_document)"

# docs/README.md — doc conventions, read on demand instead of loaded every session
write_file "$TARGET/docs/README.md" "$(docs_readme_content)"

# .harness-version — stamp the source commit so workspace/harness drift is visible
write_file "$TARGET/.harness-version" "$(printf 'harness_sha: %s\nstamped: %s' "$(harness_sha)" "$TODAY")"

# .gitignore
write_file "$TARGET/.gitignore" "$(cat << 'EOF'
repos/
worktrees/
EOF
)"

# project.yaml
# --otel pre-sets observability.enabled: true for a known-service project. The skill +
# agent are always bundled regardless; without --otel the flag starts false and to-issues
# flips it on (or records a waiver) the moment a request-serving path appears.
if $OTEL; then OBS_ENABLED=true; else OBS_ENABLED=false; fi
write_file "$TARGET/project.yaml" "$(cat << EOF
name: ${PROJECT_NAME}
jira_key: "${JIRA_KEY}"
created: ${TODAY}
repos: []
tasks: []
observability:
  enabled: ${OBS_ENABLED}       # true => service standard + otel gate active. --otel sets it; else
                        #   grill/to-prd/to-issues flip it when a request-serving path appears.
  waived: ""            # non-empty reason => explicit "no observability" decision; to-issues won't re-prompt
  otlp_endpoint: ""     # OTLP Collector endpoint (or OTEL_EXPORTER_OTLP_ENDPOINT)
  service_name: ""      # resource attribute; defaults to the project name
validation:
  run_cmd: ""           # optional: how the runtime gate boots/drives the artifact; inferred per project type when empty
  format_cmd: ""        # optional: formatter command (e.g. "gofmt -w ." / "ruff format"); inferred per language when empty
  lint_cmd: ""          # optional: linter/vet command (e.g. "go vet ./..." / "ruff check"); inferred per language when empty
  test_cmd: ""          # optional: full test command (e.g. "go test ./..." / "pytest"); inferred per language when empty
  max_rework: 3         # barrier rework cap: max BLOCKs at one gate before a slice escalates to blocked
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
    # Only real skill dirs (those with a SKILL.md); excludes grouping dirs like
    # lite/, whose forked variants ship via the separate proj-lite.sh, not this bundle.
    SKILLS_TO_COPY="$(for d in "$SKILLS_SRC"/*/; do [[ -f "${d}SKILL.md" ]] && basename "$d"; done | tr '\n' ' ')"
    # observability ships in the default bundle (dormant unless project.yaml enables it):
    # the flag can flip on mid-project, so its skill + otel agent must already be present
    # or to-issues/next would point at missing files. --otel only pre-sets the flag.
    # Extras are opt-in via --full (an explicit --skills list that names one is
    # honored — that path doesn't reach here).
    if ! $FULL; then
      for extra in $EXTRA_SKILLS; do
        SKILLS_TO_COPY="$(printf '%s' "$SKILLS_TO_COPY" | tr ' ' '\n' | grep -vx "$extra" | tr '\n' ' ')"
      done
    fi
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

# ── coding rules (opt-in via --bundle-rules) ────────────────────────────────────
# NOT bundled by default: your global ~/.claude/rules already loads for every project,
# so copying them here would just duplicate them in context. Opt in only for repos that
# run where the global rules aren't present (teammates, CI, fresh clones); native Claude
# Code loads project-level .claude/rules/ the same way.
if $BUNDLE_RULES; then
  if [[ -d "$RULES_SRC" ]]; then
    if $DRY_RUN; then
      echo "  [rules] .claude/rules/"
    else
      mkdir -p "${TARGET}/.claude/rules"
      cp -R "$RULES_SRC"/. "${TARGET}/.claude/rules/"
    fi
  else
    warn "--bundle-rules given but the bundled rules are missing at $RULES_SRC."
    warn "Your claude-projects checkout looks incomplete — restore rules/ and re-run."
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
