#!/usr/bin/env bash
# test-proj.sh — smoke tests for proj.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ="${SCRIPT_DIR}/proj.sh"
TMPDIR_BASE="$(mktemp -d)"
PROJECT_NAME="smoke-test-$$"
TARGET="${TMPDIR_BASE}/${PROJECT_NAME}"

PASS=0
FAIL=0

GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"

assert() {
  local desc="$1"
  local result="$2"
  if [[ "$result" == "true" ]]; then
    echo -e "  ${GREEN}PASS${RESET}  $desc"
    ((PASS++)) || true
  else
    echo -e "  ${RED}FAIL${RESET}  $desc"
    ((FAIL++)) || true
  fi
}

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

echo "Running proj smoke tests..."
echo ""

# ── basic scaffold ────────────────────────────────────────────────────────────
bash "$PROJ" "$PROJECT_NAME" --dir "$TMPDIR_BASE" --jira "TEST"

assert "target directory created"             "$([[ -d $TARGET ]] && echo true || echo false)"
assert "CLAUDE.md exists"                     "$([[ -f $TARGET/CLAUDE.md ]] && echo true || echo false)"
assert "PROJECT.md exists"                    "$([[ -f $TARGET/PROJECT.md ]] && echo true || echo false)"
assert "CONTEXT.md exists"                    "$([[ -f $TARGET/CONTEXT.md ]] && echo true || echo false)"
assert "project.yaml exists"                  "$([[ -f $TARGET/project.yaml ]] && echo true || echo false)"
assert ".gitignore exists"                    "$([[ -f $TARGET/.gitignore ]] && echo true || echo false)"
assert "docs/plans/ exists"                   "$([[ -d $TARGET/docs/plans ]] && echo true || echo false)"
assert "docs/adr/ exists"                     "$([[ -d $TARGET/docs/adr ]] && echo true || echo false)"
assert "docs/research/ exists"                "$([[ -d $TARGET/docs/research ]] && echo true || echo false)"
assert "docs/validations/ exists"             "$([[ -d $TARGET/docs/validations ]] && echo true || echo false)"
assert "scripts/ exists"                      "$([[ -d $TARGET/scripts ]] && echo true || echo false)"
assert "repos/ exists"                        "$([[ -d $TARGET/repos ]] && echo true || echo false)"
assert "worktrees/ exists"                    "$([[ -d $TARGET/worktrees ]] && echo true || echo false)"

# ── content checks ────────────────────────────────────────────────────────────
assert "project.yaml has correct name"        "$(grep -q "name: ${PROJECT_NAME}" "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml has jira_key TEST"       "$(grep -q 'jira_key: "TEST"' "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml has repos list"          "$(grep -q 'repos: \[\]' "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml has tasks list"          "$(grep -q 'tasks: \[\]' "$TARGET/project.yaml" && echo true || echo false)"
assert ".gitignore excludes repos/"           "$(grep -q 'repos/' "$TARGET/.gitignore" && echo true || echo false)"
assert ".gitignore excludes worktrees/"       "$(grep -q 'worktrees/' "$TARGET/.gitignore" && echo true || echo false)"
assert "PROJECT.md has frontmatter title"     "$(grep -q "title: ${PROJECT_NAME}" "$TARGET/PROJECT.md" && echo true || echo false)"
assert "CLAUDE.md contains Project Structure" "$(grep -q '# Project Structure' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md references docs/adr/"       "$(grep -q 'docs/adr/' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md drops docs/decisions"       "$(! grep -q 'docs/decisions' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CONTEXT.md has Language heading"      "$(grep -q '## Language' "$TARGET/CONTEXT.md" && echo true || echo false)"
assert "STATUS.md exists"                     "$([[ -f $TARGET/STATUS.md ]] && echo true || echo false)"
assert "STATUS.md has last_synced: null"      "$(grep -q 'last_synced: null' "$TARGET/STATUS.md" && echo true || echo false)"
assert "journal.yaml exists"                  "$([[ -f $TARGET/journal.yaml ]] && echo true || echo false)"
assert "journal.yaml is an empty YAML list"   "$(grep -qx '\[\]' "$TARGET/journal.yaml" && echo true || echo false)"

# ── dry-run creates nothing ───────────────────────────────────────────────────
DRY_TARGET="${TMPDIR_BASE}/dry-run-test"
bash "$PROJ" "dry-run-test" --dir "$TMPDIR_BASE" --dry-run
assert "dry-run does not create target dir"   "$([[ ! -d $DRY_TARGET ]] && echo true || echo false)"

# ── already-exists guard ─────────────────────────────────────────────────────
exit_code=0
bash "$PROJ" "$PROJECT_NAME" --dir "$TMPDIR_BASE" 2>/dev/null || exit_code=$?
assert "exits non-zero when target exists"    "$([[ $exit_code -ne 0 ]] && echo true || echo false)"

# ── --force overwrites ────────────────────────────────────────────────────────
bash "$PROJ" "$PROJECT_NAME" --dir "$TMPDIR_BASE" --force
assert "--force succeeds on existing target"  "$([[ -f $TARGET/CLAUDE.md ]] && echo true || echo false)"

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
