#!/usr/bin/env bash
# test-proj-lite.sh — smoke tests for proj-lite.sh (the lite scaffold flow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_LITE="${SCRIPT_DIR}/proj-lite.sh"
PROJ="${SCRIPT_DIR}/proj.sh"
TMPDIR_BASE="$(mktemp -d)"
NAME="lite-smoke-$$"
T="${TMPDIR_BASE}/${NAME}"

PASS=0; FAIL=0
GREEN="\033[0;32m"; RED="\033[0;31m"; RESET="\033[0m"
assert() {
  if [[ "$2" == "true" ]]; then echo -e "  ${GREEN}PASS${RESET}  $1"; ((PASS++)) || true
  else echo -e "  ${RED}FAIL${RESET}  $1"; ((FAIL++)) || true; fi
}
cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

echo "Running proj-lite smoke tests..."
echo ""

# ── basic scaffold ────────────────────────────────────────────────────────────
bash "$PROJ_LITE" "$NAME" --dir "$TMPDIR_BASE" --jira "TEST" >/dev/null

assert "target created"                 "$([[ -d $T ]] && echo true || echo false)"
assert "CLAUDE.md exists"               "$([[ -f $T/CLAUDE.md ]] && echo true || echo false)"
assert "PROJECT.md exists"              "$([[ -f $T/PROJECT.md ]] && echo true || echo false)"
assert "CONTEXT.md exists"              "$([[ -f $T/CONTEXT.md ]] && echo true || echo false)"
assert "project.yaml exists"            "$([[ -f $T/project.yaml ]] && echo true || echo false)"
assert "docs/README.md exists"          "$([[ -f $T/docs/README.md ]] && echo true || echo false)"
assert "docs/plans/ exists"             "$([[ -d $T/docs/plans ]] && echo true || echo false)"
assert "docs/adr/ exists"               "$([[ -d $T/docs/adr ]] && echo true || echo false)"
assert "docs/research/ exists"          "$([[ -d $T/docs/research ]] && echo true || echo false)"
assert "repos/ exists"                  "$([[ -d $T/repos ]] && echo true || echo false)"
assert "worktrees/ exists"              "$([[ -d $T/worktrees ]] && echo true || echo false)"
# lite drops the full flow's audit machinery
assert "no STATUS.md (audit dropped)"   "$([[ ! -f $T/STATUS.md ]] && echo true || echo false)"
assert "no journal.yaml (audit dropped)" "$([[ ! -f $T/journal.yaml ]] && echo true || echo false)"
assert "no docs/validations/ (audit dropped)" "$([[ ! -d $T/docs/validations ]] && echo true || echo false)"

# ── project.yaml content ──────────────────────────────────────────────────────
assert "project.yaml: name"             "$(grep -q "name: ${NAME}" "$T/project.yaml" && echo true || echo false)"
assert "project.yaml: repos list"       "$(grep -q 'repos: \[\]' "$T/project.yaml" && echo true || echo false)"
assert "project.yaml: tasks list"       "$(grep -q 'tasks: \[\]' "$T/project.yaml" && echo true || echo false)"
assert "project.yaml: observability"    "$(grep -q '^observability:' "$T/project.yaml" && echo true || echo false)"
assert "project.yaml: obs disabled"     "$(grep -q 'enabled: false' "$T/project.yaml" && echo true || echo false)"
assert "project.yaml: declares max_rework" "$(grep -qE '^[[:space:]]*max_rework:' "$T/project.yaml" && echo true || echo false)"

# ── lite CLAUDE.md (not the /next router) ─────────────────────────────────────
assert "CLAUDE.md: mentions /build"     "$(grep -q '/build' "$T/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: work in worktrees"   "$(grep -qi 'worktrees' "$T/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: repos/ read-only"    "$(grep -qi 'read-only' "$T/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: NOT the /next router" "$(! grep -q '/next' "$T/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: GitHub via gh-axi"   "$(grep -q 'gh-axi' "$T/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: npx -y gh-axi fallback" "$(grep -q 'npx -y gh-axi' "$T/CLAUDE.md" && echo true || echo false)"

# ── bundled skills (exactly the 6 lite-flow skills) ───────────────────────────
assert "skill: build bundled"           "$([[ -d $T/.claude/skills/build ]] && echo true || echo false)"
assert "build (lite): PRs via gh-axi"   "$(grep -q 'gh-axi' "$T/.claude/skills/build/SKILL.md" && echo true || echo false)"
assert "skill: grill-with-docs bundled" "$([[ -d $T/.claude/skills/grill-with-docs ]] && echo true || echo false)"
assert "skill: to-prd bundled"          "$([[ -d $T/.claude/skills/to-prd ]] && echo true || echo false)"
assert "skill: to-issues bundled"       "$([[ -d $T/.claude/skills/to-issues ]] && echo true || echo false)"
assert "skill: codebase-design bundled" "$([[ -d $T/.claude/skills/codebase-design ]] && echo true || echo false)"
assert "skill: observability bundled"   "$([[ -d $T/.claude/skills/observability ]] && echo true || echo false)"
assert "skill: next NOT bundled"        "$([[ ! -d $T/.claude/skills/next ]] && echo true || echo false)"
assert "skill: repo NOT bundled"        "$([[ ! -d $T/.claude/skills/repo ]] && echo true || echo false)"
assert "skill: journal NOT bundled"     "$([[ ! -d $T/.claude/skills/journal ]] && echo true || echo false)"
assert "no lite/ grouping dir bundled"  "$([[ ! -d $T/.claude/skills/lite ]] && echo true || echo false)"
LITE_COUNT=$(ls -1 "$T/.claude/skills" | wc -l | tr -d ' ')
assert "lite bundle is exactly 6 skills" "$([[ "$LITE_COUNT" == "6" ]] && echo true || echo false)"

# ── forked skill content ──────────────────────────────────────────────────────
assert "to-issues (lite): inline acceptance schema" "$(grep -q 'acceptance:' "$T/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "to-issues (lite): task names target repo"   "$(grep -qE 'repo: <repo-name>' "$T/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "to-issues (lite): no journal coupling"      "$(! grep -qi 'journal entry' "$T/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "to-issues (lite): no /next coupling"        "$(! grep -q '/next' "$T/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "to-issues (lite): coverage-check present"   "$([[ -f $T/.claude/skills/to-issues/coverage-check.sh ]] && echo true || echo false)"
assert "grill (lite): references /build not /next"  "$(grep -q '/build' "$T/.claude/skills/grill-with-docs/SKILL.md" && ! grep -q '/next' "$T/.claude/skills/grill-with-docs/SKILL.md" && echo true || echo false)"

# ── agents (exactly the 3 lite agents) ────────────────────────────────────────
assert "agent: lite-orchestrator"       "$([[ -f $T/.claude/agents/lite-orchestrator.md ]] && echo true || echo false)"
assert "agent: lite-builder"            "$([[ -f $T/.claude/agents/lite-builder.md ]] && echo true || echo false)"
assert "agent: lite-checker"            "$([[ -f $T/.claude/agents/lite-checker.md ]] && echo true || echo false)"
assert "agent: otel NOT installed"      "$([[ ! -f $T/.claude/agents/otel-observability-engineer.md ]] && echo true || echo false)"
assert "agent: tdd-implementer NOT installed" "$([[ ! -f $T/.claude/agents/tdd-implementer.md ]] && echo true || echo false)"
AG_COUNT=$(ls -1 "$T/.claude/agents" | wc -l | tr -d ' ')
assert "exactly 3 lite agents installed" "$([[ "$AG_COUNT" == "3" ]] && echo true || echo false)"

# ── read-only hook: wiring + behavior ─────────────────────────────────────────
assert "hook: script installed"         "$([[ -f $T/.claude/skills/build/hooks/repos-readonly.sh ]] && echo true || echo false)"
assert "hook: script executable"        "$([[ -x $T/.claude/skills/build/hooks/repos-readonly.sh ]] && echo true || echo false)"
assert "hook: settings.json exists"     "$([[ -f $T/.claude/settings.json ]] && echo true || echo false)"
if command -v jq >/dev/null 2>&1; then
  assert "hook: wired PreToolUse Edit|Write" \
    "$([[ "$(jq '[.hooks.PreToolUse[]? | select(.matcher=="Edit|Write") | .hooks[] | select(.command|test("repos-readonly"))] | length' "$T/.claude/settings.json")" == "1" ]] && echo true || echo false)"
  HOOK="$T/.claude/skills/build/hooks/repos-readonly.sh"
  hookrc() { local rc=0; echo "{\"tool_input\":{\"file_path\":\"$1\"},\"cwd\":\"$T\"}" | bash "$HOOK" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
  assert "hook: BLOCKS write under repos/"     "$([[ "$(hookrc "$T/repos/foo/main.go")" == "2" ]] && echo true || echo false)"
  assert "hook: ALLOWS write under worktrees/" "$([[ "$(hookrc "$T/worktrees/t1/main.go")" == "0" ]] && echo true || echo false)"
  assert "hook: ALLOWS write under docs/"      "$([[ "$(hookrc "$T/docs/plans/prd.md")" == "0" ]] && echo true || echo false)"
  assert "hook: no false-match on repositories/" "$([[ "$(hookrc "$T/repositories/x")" == "0" ]] && echo true || echo false)"
else
  echo "  (skipping hook-wiring/behavior checks — jq not installed)"
fi

# ── delegation: proj <name> --lite produces a lite workspace ──────────────────
DEL="${TMPDIR_BASE}/via-proj"
bash "$PROJ" "via-proj" --dir "$TMPDIR_BASE" --lite >/dev/null 2>&1
assert "delegation: proj --lite scaffolds lite"  "$([[ -d $DEL/.claude/skills/build && ! -d $DEL/.claude/skills/next ]] && echo true || echo false)"

# ── --otel pre-sets observability.enabled: true ───────────────────────────────
OT="${TMPDIR_BASE}/otel"
bash "$PROJ_LITE" "otel" --dir "$TMPDIR_BASE" --otel >/dev/null 2>&1
assert "--otel: observability enabled in yaml"   "$(grep -q 'enabled: true' "$OT/project.yaml" && echo true || echo false)"

# ── dry-run / exists guard / force ────────────────────────────────────────────
DR="${TMPDIR_BASE}/dry"
bash "$PROJ_LITE" "dry" --dir "$TMPDIR_BASE" --dry-run >/dev/null
assert "dry-run creates nothing"        "$([[ ! -d $DR ]] && echo true || echo false)"
rc=0; bash "$PROJ_LITE" "$NAME" --dir "$TMPDIR_BASE" 2>/dev/null || rc=$?
assert "exits non-zero when target exists" "$([[ $rc -ne 0 ]] && echo true || echo false)"
bash "$PROJ_LITE" "$NAME" --dir "$TMPDIR_BASE" --force >/dev/null 2>&1
assert "--force overwrites existing"    "$([[ -f $T/CLAUDE.md ]] && echo true || echo false)"

echo ""
echo -e "Results: ${GREEN}${PASS} passed${RESET}, $([[ $FAIL -gt 0 ]] && echo -e "${RED}${FAIL} failed${RESET}" || echo "0 failed")"
[[ $FAIL -eq 0 ]] || exit 1
