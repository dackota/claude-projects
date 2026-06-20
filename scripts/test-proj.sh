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

# ── repo skill: install + hook wiring ─────────────────────────────────────────
RT="${TMPDIR_BASE}/repo-test"
bash "$PROJ" "repo-test" --dir "$TMPDIR_BASE" --skills >/dev/null

assert "repo skill: scripts/repo.sh installed"      "$([[ -f $RT/scripts/repo.sh ]] && echo true || echo false)"
assert "repo skill: scripts/repo.sh executable"     "$([[ -x $RT/scripts/repo.sh ]] && echo true || echo false)"
assert "repo skill: skill dir copied"               "$([[ -d $RT/.claude/skills/repo ]] && echo true || echo false)"
assert "repo skill: settings.json created"          "$([[ -f $RT/.claude/settings.json ]] && echo true || echo false)"

SETTINGS="$RT/.claude/settings.json"
count_cmd() { jq "[.. | objects | select(has(\"command\")) | select(.command|test(\"$1\"))] | length" "$SETTINGS"; }

assert "settings: PreToolUse git-guard wired"       "$([[ "$(count_cmd git-guard)" == "1" ]] && echo true || echo false)"
assert "settings: PreToolUse repo-stale wired"      "$([[ "$(count_cmd 'repo-stale\\.sh')" == "1" ]] && echo true || echo false)"
assert "settings: Stop repo-stale-stop wired"       "$([[ "$(count_cmd repo-stale-stop)" == "1" ]] && echo true || echo false)"
assert "settings: journal hooks preserved"          "$([[ "$(count_cmd journal-check)" == "1" ]] && echo true || echo false)"
assert "settings: sync-status hook preserved"       "$([[ "$(count_cmd sync-status-stop)" == "1" ]] && echo true || echo false)"
# All Stop hooks (journal, sync-status, repo) share one matcher group
STOP_GROUPS="$(jq '[.hooks.Stop[] | select(.matcher=="")] | length' "$SETTINGS")"
assert "settings: single Stop matcher group"        "$([[ "$STOP_GROUPS" == "1" ]] && echo true || echo false)"

# ── merge idempotency: update-skills must not duplicate hooks ──────────────────
bash "$PROJ" update-skills --dir "$RT" >/dev/null
bash "$PROJ" update-skills --dir "$RT" >/dev/null
assert "idempotent: git-guard still single"         "$([[ "$(count_cmd git-guard)" == "1" ]] && echo true || echo false)"
assert "idempotent: journal-check still single"     "$([[ "$(count_cmd journal-check)" == "1" ]] && echo true || echo false)"

# ── repo.sh lifecycle against a throwaway remote ──────────────────────────────
if command -v yq >/dev/null 2>&1; then
  REMOTE="${TMPDIR_BASE}/remote.git"
  SEED="${TMPDIR_BASE}/seed"
  git init -q "$SEED"
  git -C "$SEED" config user.email t@t.test
  git -C "$SEED" config user.name "Test"
  git -C "$SEED" config commit.gpgsign false
  echo "v1" > "$SEED/README.md"
  git -C "$SEED" add -A
  git -C "$SEED" commit -qm "init"
  git -C "$SEED" branch -M main
  git init -q --bare "$REMOTE"
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  git -C "$SEED" remote add origin "$REMOTE"
  git -C "$SEED" push -q origin main

  repo() { ( cd "$RT" && bash scripts/repo.sh "$@" ); }

  repo clone "$REMOTE" >/dev/null 2>&1
  assert "repo.sh clone: repos/remote created"      "$([[ -d $RT/repos/remote/.git ]] && echo true || echo false)"
  assert "repo.sh clone: registered in yaml"        "$([[ "$(yq e '.repos[0].name' "$RT/project.yaml")" == "remote" ]] && echo true || echo false)"
  assert "repo.sh clone: default_branch detected"   "$([[ "$(yq e '.repos[0].default_branch' "$RT/project.yaml")" == "main" ]] && echo true || echo false)"

  repo worktree TASK-1 remote >/dev/null 2>&1
  assert "repo.sh worktree: dir created"            "$([[ -d $RT/worktrees/TASK-1/remote ]] && echo true || echo false)"
  assert "repo.sh worktree: on branch TASK-1"       "$([[ "$(git -C "$RT/worktrees/TASK-1/remote" rev-parse --abbrev-ref HEAD)" == "TASK-1" ]] && echo true || echo false)"

  # Advance base branch on the remote so the worktree goes stale.
  echo "v2" > "$SEED/README.md"
  git -C "$SEED" commit -qam "v2"
  git -C "$SEED" push -q origin main

  STATUS_OUT="$(repo status 2>/dev/null)"
  assert "repo.sh status: flags STALE worktree"     "$(echo "$STATUS_OUT" | grep -q 'STALE' && echo true || echo false)"

  repo sync TASK-1 >/dev/null 2>&1
  BEHIND="$(git -C "$RT/worktrees/TASK-1/remote" rev-list --count HEAD..origin/main 2>/dev/null)"
  assert "repo.sh sync: worktree no longer behind"  "$([[ "$BEHIND" == "0" ]] && echo true || echo false)"

  repo remove TASK-1 >/dev/null 2>&1
  assert "repo.sh remove: worktree gone"            "$([[ ! -d $RT/worktrees/TASK-1 ]] && echo true || echo false)"
  assert "repo.sh remove: local branch deleted"     "$(! git -C "$RT/repos/remote" show-ref --verify --quiet refs/heads/TASK-1 && echo true || echo false)"
else
  echo "  (skipping repo.sh lifecycle tests — yq not installed)"
fi

# ── git-guard hook: blocks bypass, allows read-only ───────────────────────────
GUARD="$RT/.claude/skills/repo/hooks/git-guard.sh"
guard() { # guard <command> <cwd> -> echoes exit code
  local rc=0
  echo "{\"tool_input\":{\"command\":\"$1\"},\"cwd\":\"$2\"}" | bash "$GUARD" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
assert "guard: blocks raw git clone"                "$([[ "$(guard 'git clone https://x/y.git' "$RT")" == "2" ]] && echo true || echo false)"
assert "guard: blocks git worktree add"             "$([[ "$(guard 'git worktree add ../wt' "$RT/repos/remote")" == "2" ]] && echo true || echo false)"
assert "guard: blocks checkout -b in repos/"        "$([[ "$(guard 'git checkout -b feature' "$RT/repos/remote")" == "2" ]] && echo true || echo false)"
assert "guard: blocks branch switch in worktrees/"  "$([[ "$(guard 'git checkout main' "$RT/worktrees/x/remote")" == "2" ]] && echo true || echo false)"
assert "guard: allows git status"                   "$([[ "$(guard 'git status' "$RT/repos/remote")" == "0" ]] && echo true || echo false)"
assert "guard: allows git checkout -- file"         "$([[ "$(guard 'git checkout -- README.md' "$RT/repos/remote")" == "0" ]] && echo true || echo false)"
assert "guard: ignores non-git commands"            "$([[ "$(guard 'ls -la repos/' "$RT")" == "0" ]] && echo true || echo false)"

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
