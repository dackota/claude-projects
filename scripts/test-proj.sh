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
assert "project.yaml has observability block" "$(grep -q '^observability:' "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml observability disabled"  "$(grep -q 'enabled: false' "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml has validation block"    "$(grep -q '^validation:' "$TARGET/project.yaml" && echo true || echo false)"
assert ".gitignore excludes repos/"           "$(grep -q 'repos/' "$TARGET/.gitignore" && echo true || echo false)"
assert ".gitignore excludes worktrees/"       "$(grep -q 'worktrees/' "$TARGET/.gitignore" && echo true || echo false)"
assert "PROJECT.md has frontmatter title"     "$(grep -q "title: ${PROJECT_NAME}" "$TARGET/PROJECT.md" && echo true || echo false)"
assert "CLAUDE.md contains Project Structure" "$(grep -q '# Project Structure' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md references docs/adr/"       "$(grep -q 'docs/adr/' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md nudges PROJECT.md bootstrap" "$(grep -q 'Before anything else, check .PROJECT.md' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md drops docs/decisions"       "$(! grep -q 'docs/decisions' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: every-gated-slice validation" "$(grep -q 'Every gated slice' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: supersession type retired"    "$(! grep -q 'supersession' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: points to canonical BARRIER.md" "$(grep -q 'BARRIER.md' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: write-then-act gate rule"  "$(grep -q 'write, then act' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CONTEXT.md has Language heading"      "$(grep -q '## Language' "$TARGET/CONTEXT.md" && echo true || echo false)"
assert "STATUS.md exists"                     "$([[ -f $TARGET/STATUS.md ]] && echo true || echo false)"
assert "STATUS.md has last_synced: null"      "$(grep -q 'last_synced: null' "$TARGET/STATUS.md" && echo true || echo false)"
assert "journal.yaml exists"                  "$([[ -f $TARGET/journal.yaml ]] && echo true || echo false)"
assert "journal.yaml is an empty YAML list"   "$(grep -qx '\[\]' "$TARGET/journal.yaml" && echo true || echo false)"
assert "default: skills bundled (repo)"       "$([[ -d $TARGET/.claude/skills/repo ]] && echo true || echo false)"
assert "default: hooks wired (settings.json)" "$([[ -f $TARGET/.claude/settings.json ]] && echo true || echo false)"
assert "default: observability NOT bundled (opt-in)" "$([[ ! -d $TARGET/.claude/skills/observability ]] && echo true || echo false)"
assert "default: no otel agent (opt-in)"      "$([[ ! -f $TARGET/.claude/agents/otel-observability-engineer.md ]] && echo true || echo false)"
assert "default: codebase-design bundled"     "$([[ -d $TARGET/.claude/skills/codebase-design ]] && echo true || echo false)"
assert "default: code-review bundled"         "$([[ -d $TARGET/.claude/skills/code-review ]] && echo true || echo false)"
assert "default: diagnosing-bugs bundled"     "$([[ -d $TARGET/.claude/skills/diagnosing-bugs ]] && echo true || echo false)"
assert "default: diagnosing-bugs hitl tmpl"   "$([[ -f $TARGET/.claude/skills/diagnosing-bugs/scripts/hitl-loop.template.sh ]] && echo true || echo false)"
assert "default: prototype bundled"           "$([[ -d $TARGET/.claude/skills/prototype ]] && echo true || echo false)"
assert "default: improve-codebase-arch bundled" "$([[ -d $TARGET/.claude/skills/improve-codebase-architecture ]] && echo true || echo false)"
assert "default: tdd baseline is unconditional" "$(grep -q 'Observable by default (baseline' "$TARGET/.claude/agents/tdd-implementer.md" && echo true || echo false)"

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

# ── --no-skills opts out of the default skill bundling ────────────────────────
NS="${TMPDIR_BASE}/no-skills-test"
bash "$PROJ" "no-skills-test" --dir "$TMPDIR_BASE" --no-skills >/dev/null 2>&1
assert "--no-skills: workspace still created"  "$([[ -f $NS/CLAUDE.md ]] && echo true || echo false)"
assert "--no-skills: skills not installed"     "$([[ ! -d $NS/.claude/skills/repo ]] && echo true || echo false)"
assert "--no-skills: no observability skill"   "$([[ ! -d $NS/.claude/skills/observability ]] && echo true || echo false)"
assert "--no-skills: no otel agent"            "$([[ ! -f $NS/.claude/agents/otel-observability-engineer.md ]] && echo true || echo false)"

# ── --otel opts into observability (skill + otel agent + enabled flag) ─────────
OT2="${TMPDIR_BASE}/otel-test"
bash "$PROJ" "otel-test" --dir "$TMPDIR_BASE" --otel >/dev/null 2>&1
assert "--otel: observability skill bundled"   "$([[ -d $OT2/.claude/skills/observability ]] && echo true || echo false)"
assert "--otel: otel agent installed"          "$([[ -f $OT2/.claude/agents/otel-observability-engineer.md ]] && echo true || echo false)"
assert "--otel: observability enabled in yaml" "$(grep -q 'enabled: true' "$OT2/project.yaml" && echo true || echo false)"
assert "--otel: other skills still bundled"    "$([[ -d $OT2/.claude/skills/repo ]] && echo true || echo false)"

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
assert "settings: Stop repo-stale-stop NOT wired"   "$([[ "$(count_cmd repo-stale-stop)" == "0" ]] && echo true || echo false)"
assert "settings: journal-check per-write dropped"  "$([[ "$(count_cmd journal-check)" == "0" ]] && echo true || echo false)"
assert "settings: journal-stop net wired"           "$([[ "$(count_cmd journal-stop)" == "1" ]] && echo true || echo false)"
assert "settings: run-check Task hook wired"         "$([[ "$(count_cmd run-check)" == "1" ]] && echo true || echo false)"
assert "settings: sync-status hook preserved"       "$([[ "$(count_cmd sync-status-stop)" == "1" ]] && echo true || echo false)"
# All Stop hooks (journal, sync-status) share one matcher group
STOP_GROUPS="$(jq '[.hooks.Stop[] | select(.matcher=="")] | length' "$SETTINGS")"
assert "settings: single Stop matcher group"        "$([[ "$STOP_GROUPS" == "1" ]] && echo true || echo false)"

# ── merge idempotency: update-skills must not duplicate hooks ──────────────────
bash "$PROJ" update-skills --dir "$RT" >/dev/null
bash "$PROJ" update-skills --dir "$RT" >/dev/null
assert "idempotent: git-guard still single"         "$([[ "$(count_cmd git-guard)" == "1" ]] && echo true || echo false)"
assert "idempotent: journal-stop still single"      "$([[ "$(count_cmd journal-stop)" == "1" ]] && echo true || echo false)"
assert "idempotent: no per-write journal-check"     "$([[ "$(count_cmd journal-check)" == "0" ]] && echo true || echo false)"
# sync-status enforces the STATUS.md 500-token cap (Slice B, decision 8)
assert "sync-status: 500-token cap enforced"        "$(grep -q '500 tokens' "$RT/.claude/skills/sync-status/SKILL.md" && echo true || echo false)"
# update-skills must not nest a skill inside itself (.claude/skills/<x>/<x>/)
NESTED=""
for d in "$RT"/.claude/skills/*/; do
  s="$(basename "$d")"
  if [[ -d "${d}${s}" ]]; then NESTED+="$s "; fi
done
assert "idempotent: no nested skill doubling"       "$([[ -z "${NESTED// /}" ]] && echo true || echo false)"
# run-check.sh must audit every post-build gate agent (the barrier's full set)
RUNCHECK="$RT/.claude/skills/journal/hooks/run-check.sh"
assert "run-check: correctness-reviewer in cases"   "$(grep -q 'correctness-reviewer' "$RUNCHECK" && echo true || echo false)"
assert "run-check: runtime-validator in cases"      "$(grep -q 'runtime-validator' "$RUNCHECK" && echo true || echo false)"
# supersession retired from the journal type enum table (kept only as a note)
assert "journal skill: supersession off enum table" "$(! grep -qE '^\|[[:space:]]*.supersession. ' "$RT/.claude/skills/journal/SKILL.md" && echo true || echo false)"

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

  # ── stacked worktrees ───────────────────────────────────────────────────────
  wt_commit() { # wt_commit <worktree> <file> <content> <msg>
    echo "$3" > "$1/$2"
    git -C "$1" add -A
    git -C "$1" -c user.email=t@t.test -c user.name=T -c commit.gpgsign=false commit -qm "$4"
  }
  # Seed a parent task (in review = done) and a child that depends on it.
  yq e -i '.tasks = [
    {"id":"slice-1","title":"parent","type":"AFK","status":"done","blocked_by":[]},
    {"id":"slice-2","title":"child","type":"AFK","status":"todo","blocked_by":["slice-1"]}
  ]' "$RT/project.yaml"

  repo worktree slice-1 remote >/dev/null 2>&1
  wt_commit "$RT/worktrees/slice-1/remote" p.txt "parent-work" "parent work"

  # Child stacked on the in-review parent via --onto.
  repo worktree slice-2 remote --onto slice-1 >/dev/null 2>&1
  CHILD="$RT/worktrees/slice-2/remote"
  assert "stack: child worktree created"            "$([[ -d $CHILD ]] && echo true || echo false)"
  assert "stack: child upstream is parent branch"   "$([[ "$(git -C "$CHILD" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" == "slice-1" ]] && echo true || echo false)"
  assert "stack: child built on parent work"        "$(git -C "$CHILD" merge-base --is-ancestor slice-1 HEAD 2>/dev/null && echo true || echo false)"

  # sync cascades the parent's new review-fix commits into the child.
  wt_commit "$RT/worktrees/slice-1/remote" p2.txt "more" "parent work 2"
  P2="$(git -C "$RT/worktrees/slice-1/remote" rev-parse HEAD)"
  repo sync slice-2 >/dev/null 2>&1
  assert "stack: sync cascades parent commits"      "$(git -C "$CHILD" merge-base --is-ancestor "$P2" HEAD 2>/dev/null && echo true || echo false)"

  # Auto-derive: a task with exactly one unmerged blocker (live branch) stacks.
  yq e -i '.tasks += [{"id":"slice-3","title":"auto","type":"AFK","status":"todo","blocked_by":["slice-1"]}]' "$RT/project.yaml"
  repo worktree slice-3 remote >/dev/null 2>&1
  C3="$RT/worktrees/slice-3/remote"
  assert "stack: auto-derive single blocker"        "$([[ "$(git -C "$C3" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" == "slice-1" ]] && echo true || echo false)"

  # No blockers -> ordinary worktree off base, not stacked.
  yq e -i '.tasks += [{"id":"slice-free","title":"free","type":"AFK","status":"todo","blocked_by":[]}]' "$RT/project.yaml"
  repo worktree slice-free remote >/dev/null 2>&1
  CF="$RT/worktrees/slice-free/remote"
  assert "stack: no blockers -> not stacked"        "$([[ "$(git -C "$CF" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo none)" != "slice-1" ]] && echo true || echo false)"

  # Base reopened: parent task flips done -> active; status flags the stacked child.
  yq e -i '(.tasks[] | select(.id=="slice-1") | .status) = "active"' "$RT/project.yaml"
  STK_STATUS="$(repo status 2>/dev/null)"
  assert "stack: status flags BASE REOPENED"        "$(echo "$STK_STATUS" | grep -q 'BASE REOPENED' && echo true || echo false)"

  # Parent merges into base on the remote; child sync re-points upstream to base.
  git -C "$RT/repos/remote" push -q origin slice-1
  git -C "$SEED" fetch -q origin
  git -C "$SEED" -c user.email=t@t.test -c user.name=T -c commit.gpgsign=false merge -q --no-edit origin/slice-1
  git -C "$SEED" push -q origin main
  repo sync slice-2 >/dev/null 2>&1
  assert "stack: re-points to base after merge"     "$([[ "$(git -C "$CHILD" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" == "origin/main" ]] && echo true || echo false)"
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

# ── pr-security-review: install + agent + hook wiring ─────────────────────────
assert "pr-review: skill dir copied"                "$([[ -d $RT/.claude/skills/pr-security-review ]] && echo true || echo false)"
assert "pr-review: classify.sh installed"           "$([[ -f $RT/.claude/skills/pr-security-review/classify.sh ]] && echo true || echo false)"
assert "pr-review: gate hook installed"             "$([[ -f $RT/.claude/skills/pr-security-review/hooks/pr-gate.sh ]] && echo true || echo false)"
assert "pr-review: bundled security-review skill"   "$([[ -d $RT/.claude/skills/security-review ]] && echo true || echo false)"
assert "pr-review: bundled cloud-infra skill"       "$([[ -d $RT/.claude/skills/cloud-infra-security ]] && echo true || echo false)"
assert "pr-review: agent copied to .claude/agents"  "$([[ -f $RT/.claude/agents/security-reviewer.md ]] && echo true || echo false)"
assert "pr-review: pr-gate hook wired in settings"  "$([[ "$(count_cmd pr-gate)" == "1" ]] && echo true || echo false)"
assert "pr-review: SKILL warns record-then-create"  "$(grep -q 'two separate Bash calls' "$RT/.claude/skills/pr-security-review/SKILL.md" && echo true || echo false)"
assert "pr-review: SKILL documents surface-skip"    "$(grep -q 'trust-boundary surface' "$RT/.claude/skills/pr-security-review/SKILL.md" && echo true || echo false)"

CLASSIFY="$RT/.claude/skills/pr-security-review/classify.sh"
PR_GATE="$RT/.claude/skills/pr-security-review/hooks/pr-gate.sh"

# ── classify.sh: path-based dimension detection ───────────────────────────────
CLS="${TMPDIR_BASE}/cls"
git init -q "$CLS"
git -C "$CLS" config user.email t@t.test
git -C "$CLS" config user.name "Test"
git -C "$CLS" config commit.gpgsign false
echo "base" > "$CLS/README.md"; git -C "$CLS" add -A; git -C "$CLS" commit -qm base
git -C "$CLS" branch -M main
classify() { ( cd "$CLS" && bash "$CLASSIFY" main ); }

git -C "$CLS" checkout -q -b code-only main
echo "print('x')" > "$CLS/app.py"; git -C "$CLS" add -A; git -C "$CLS" commit -qm code
assert "classify: code only -> code"                "$([[ "$(classify)" == "code" ]] && echo true || echo false)"

git -C "$CLS" checkout -q -b infra-only main
printf 'resource "aws_s3_bucket" "b" {}\n' > "$CLS/main.tf"; git -C "$CLS" add -A; git -C "$CLS" commit -qm infra
assert "classify: terraform only -> infra"          "$([[ "$(classify)" == "infra" ]] && echo true || echo false)"

git -C "$CLS" checkout -q -b both main
echo "print('x')" > "$CLS/app.py"; printf 'a: b\n' > "$CLS/values.yaml"
git -C "$CLS" add -A; git -C "$CLS" commit -qm both
assert "classify: code+yaml -> code infra"          "$([[ "$(classify)" == "code infra" ]] && echo true || echo false)"

git -C "$CLS" checkout -q -b docs-only main
echo "notes" > "$CLS/NOTES.md"; git -C "$CLS" add -A; git -C "$CLS" commit -qm docs
assert "classify: docs only -> none"                "$([[ -z "$(classify)" ]] && echo true || echo false)"

git -C "$CLS" checkout -q -b surface-code main
printf 'import requests\ndef f(u):\n    return requests.get(u)\n' > "$CLS/net.py"
git -C "$CLS" add -A; git -C "$CLS" commit -qm net
assert "classify: trust-boundary code -> surface"   "$(case " $(classify) " in *" surface "*) echo true ;; *) echo false ;; esac)"
assert "classify: pure code has no surface"         "$(git -C "$CLS" checkout -q code-only; case " $(classify) " in *" surface "*) echo false ;; *) echo true ;; esac)"

# ── pr-gate.sh: gates gh pr create (surface-aware + verdict-honoring) ─────────
# Give the local repo an origin/main ref so the hook can resolve a base.
git -C "$CLS" update-ref refs/remotes/origin/main "$(git -C "$CLS" rev-parse main)"
git -C "$CLS" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
VERDICT_DIR="$CLS/.git/pr-security-review"
prgate() { # prgate <command> -> exit code (cwd = current branch in $CLS)
  local rc=0
  echo "{\"tool_input\":{\"command\":\"$1\"},\"cwd\":\"$CLS\"}" | bash "$PR_GATE" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
sha_of() { git -C "$CLS" rev-parse HEAD; }

# Branches off main. Decision 4: the security skip keys on the trust boundary the diff
# touches ("surface"), not size — a pure-logic module skips at any size, a code diff
# touching I/O/exec/env/secrets is reviewed at any size, and infra is always reviewed.
git -C "$CLS" checkout -q -b small-code main
printf 'print(1)\nprint(2)\n' > "$CLS/tiny.py"; git -C "$CLS" add -A; git -C "$CLS" commit -qm tiny
git -C "$CLS" checkout -q -b big-code main
{ for i in $(seq 1 40); do echo "value_$i = $i"; done; } > "$CLS/big.py"; git -C "$CLS" add -A; git -C "$CLS" commit -qm big
git -C "$CLS" checkout -q -b surface-gate main
printf 'import requests\ndef f(u):\n    return requests.get(u)\n' > "$CLS/call.py"; git -C "$CLS" add -A; git -C "$CLS" commit -qm surf
git -C "$CLS" checkout -q -b tiny-infra main
printf 'x = 1\n' > "$CLS/one.tf"; git -C "$CLS" add -A; git -C "$CLS" commit -qm onetf

rm -rf "$VERDICT_DIR"
git -C "$CLS" checkout -q small-code
assert "gate: skips small pure-code diff"           "$([[ "$(prgate 'gh pr create -t x')" == "0" ]] && echo true || echo false)"
git -C "$CLS" checkout -q big-code
assert "gate: skips large PURE code diff (dec 4)"   "$([[ "$(prgate 'gh pr create -t x')" == "0" ]] && echo true || echo false)"
git -C "$CLS" checkout -q surface-gate
assert "gate: blocks code touching trust boundary"  "$([[ "$(prgate 'gh pr create -t x')" == "2" ]] && echo true || echo false)"
git -C "$CLS" checkout -q tiny-infra
assert "gate: blocks tiny infra diff (no verdict)"  "$([[ "$(prgate 'gh pr create -t x')" == "2" ]] && echo true || echo false)"
git -C "$CLS" checkout -q docs-only
assert "gate: skips docs-only diff"                 "$([[ "$(prgate 'gh pr create -t x')" == "0" ]] && echo true || echo false)"

# A recorded verdict is honored regardless of dimension.
mkdir -p "$VERDICT_DIR"
git -C "$CLS" checkout -q surface-gate
printf 'PASS\nCRITICAL:0 HIGH:1\n' > "$VERDICT_DIR/$(sha_of)"
assert "gate: PASS verdict allows surface diff"     "$([[ "$(prgate 'gh pr create -t x')" == "0" ]] && echo true || echo false)"
git -C "$CLS" checkout -q small-code
printf 'BLOCK\nCRITICAL:1\n' > "$VERDICT_DIR/$(sha_of)"
assert "gate: BLOCK verdict blocks pure diff"       "$([[ "$(prgate 'gh pr create -t x')" == "2" ]] && echo true || echo false)"

# Marker override: force a pure diff to register a surface -> reviewed.
git -C "$CLS" checkout -q big-code; rm -f "$VERDICT_DIR/$(sha_of)"
export PR_SECURITY_SURFACE_MARKERS='value_'
assert "gate: PR_SECURITY_SURFACE_MARKERS override" "$([[ "$(prgate 'gh pr create -t x')" == "2" ]] && echo true || echo false)"
unset PR_SECURITY_SURFACE_MARKERS

assert "gate: ignores non-create gh (pr list)"      "$([[ "$(prgate 'gh pr list')" == "0" ]] && echo true || echo false)"
assert "gate: ignores non-gh commands"              "$([[ "$(prgate 'git status')" == "0" ]] && echo true || echo false)"

# ── PR gate is security-only: a task branch is no longer force-reviewed ───────
# Acceptance moved to /next's post-build gate, so the PR hook applies security
# rules only — a slice-task branch with a non-security diff now skips (the old
# "branch is a task -> require review" acceptance trigger is gone).
if command -v yq >/dev/null 2>&1 && [[ -d "$RT/worktrees/slice-2/remote" ]]; then
  WT2="$RT/worktrees/slice-2/remote"
  WT2_GITDIR="$(git -C "$WT2" rev-parse --absolute-git-dir)"
  prg() { # prg <command> <cwd> -> exit code
    local rc=0
    echo "{\"tool_input\":{\"command\":\"$1\"},\"cwd\":\"$2\"}" | bash "$PR_GATE" >/dev/null 2>&1 || rc=$?
    echo "$rc"
  }
  # slice-2 is a task in project.yaml with a docs/.txt-only diff -> security rules
  # only -> no review required (the old acceptance trigger would have blocked it).
  rm -rf "$WT2_GITDIR/pr-security-review"
  assert "gate: task branch not force-reviewed"      "$([[ "$(prg 'gh pr create -t x' "$WT2")" == "0" ]] && echo true || echo false)"
fi

# ── next skill: orchestrator install + dependency resolution ──────────────────
NT="${TMPDIR_BASE}/next-test"
bash "$PROJ" "next-test" --dir "$TMPDIR_BASE" --skills next >/dev/null
assert "next: skill dir copied"                     "$([[ -d $NT/.claude/skills/next ]] && echo true || echo false)"
assert "next: companion grill-with-docs pulled"     "$([[ -d $NT/.claude/skills/grill-with-docs ]] && echo true || echo false)"
assert "next: companion to-prd pulled"              "$([[ -d $NT/.claude/skills/to-prd ]] && echo true || echo false)"
assert "next: companion to-issues pulled"           "$([[ -d $NT/.claude/skills/to-issues ]] && echo true || echo false)"
assert "next: companion tdd pulled"                 "$([[ -d $NT/.claude/skills/tdd ]] && echo true || echo false)"
assert "next: companion codebase-design pulled"     "$([[ -d $NT/.claude/skills/codebase-design ]] && echo true || echo false)"
assert "next: tdd-implementer agent wired"          "$([[ -f $NT/.claude/agents/tdd-implementer.md ]] && echo true || echo false)"
assert "next: implementation-validator agent wired" "$([[ -f $NT/.claude/agents/implementation-validator.md ]] && echo true || echo false)"
assert "next: correctness-reviewer agent wired"     "$([[ -f $NT/.claude/agents/correctness-reviewer.md ]] && echo true || echo false)"
assert "correctness: security-obligations ledger"   "$(grep -q 'Security obligations for future callers' "$NT/.claude/agents/correctness-reviewer.md" && echo true || echo false)"
assert "next: runtime-validator agent wired"        "$([[ -f $NT/.claude/agents/runtime-validator.md ]] && echo true || echo false)"
assert "next: BARRIER.md reference doc installed"   "$([[ -f $NT/.claude/skills/next/BARRIER.md ]] && echo true || echo false)"
assert "next: SKILL points to canonical BARRIER"    "$(grep -q 'BARRIER.md' "$NT/.claude/skills/next/SKILL.md" && echo true || echo false)"
assert "next: SKILL reads journal tail (dec 6)"     "$(grep -q 'last ~15 entries' "$NT/.claude/skills/next/SKILL.md" && echo true || echo false)"
assert "tdd-implementer: hardening baseline (dec 9)" "$(grep -q 'Harden by default' "$NT/.claude/agents/tdd-implementer.md" && echo true || echo false)"
assert "next: passes security-posture (dec 9)"      "$(grep -q 'security-posture' "$NT/.claude/skills/next/SKILL.md" && echo true || echo false)"
assert "next: formatter spot-verify (dec 9)"        "$(grep -q 'spot-verify' "$NT/.claude/skills/next/SKILL.md" && echo true || echo false)"
assert "to-issues: coverage-map ownership (dec 10)" "$(grep -q 'Coverage map' "$NT/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "next: CLAUDE.md has /next session-start"    "$(grep -q '/next' "$NT/CLAUDE.md" && echo true || echo false)"
# Scoping guard: dependency resolution is additive, not "install everything".
assert "next: does NOT pull unrelated journal"      "$([[ ! -d $NT/.claude/skills/journal ]] && echo true || echo false)"
assert "next: does NOT pull unrelated repo"         "$([[ ! -d $NT/.claude/skills/repo ]] && echo true || echo false)"
# observability is NOT a companion of next — it is service-scoped, not part of the flow.
assert "next: does NOT pull observability"          "$([[ ! -d $NT/.claude/skills/observability ]] && echo true || echo false)"

# ── observability skill: install + agent wiring ───────────────────────────────
OT="${TMPDIR_BASE}/obs-test"
bash "$PROJ" "obs-test" --dir "$TMPDIR_BASE" --skills observability >/dev/null
assert "obs: skill dir copied"                      "$([[ -d $OT/.claude/skills/observability ]] && echo true || echo false)"
assert "obs: standard.md present"                   "$([[ -f $OT/.claude/skills/observability/standard.md ]] && echo true || echo false)"
assert "obs: otel agent wired from frontmatter"     "$([[ -f $OT/.claude/agents/otel-observability-engineer.md ]] && echo true || echo false)"
assert "obs: standard defines RED (service layer)"  "$(grep -q 'RED is the floor' "$OT/.claude/skills/observability/standard.md" && echo true || echo false)"
assert "obs: standard has universal Baseline layer"  "$(grep -q '## Baseline' "$OT/.claude/skills/observability/standard.md" && echo true || echo false)"
assert "obs: standard has Service standard layer"    "$(grep -q '## Service standard' "$OT/.claude/skills/observability/standard.md" && echo true || echo false)"
assert "obs: subset does NOT pull unrelated tdd"    "$([[ ! -d $OT/.claude/skills/tdd ]] && echo true || echo false)"

# ── agent-controls: skill bundling + operating contracts on every agent ───────
assert "agent-controls: skill dir bundled"          "$([[ -d $RT/.claude/skills/agent-controls ]] && echo true || echo false)"
assert "agent-controls: standard.md bundled"        "$([[ -f $RT/.claude/skills/agent-controls/standard.md ]] && echo true || echo false)"
assert "agent-controls: standard defines contract"  "$(grep -q 'operating contract' "$RT/.claude/skills/agent-controls/standard.md" && echo true || echo false)"
assert "agent-controls: not hook-bearing"           "$([[ "$(count_cmd agent-controls)" == "0" ]] && echo true || echo false)"

# Every agent definition must carry a complete operating contract (the inward
# application of the agent-controls standard), and a read-only agent must not hold
# write tools. This is a repo invariant, so check the source agents directly.
AGENTS_DIR="${SCRIPT_DIR}/../agents"
if command -v yq >/dev/null 2>&1; then
  CONTRACT_KEYS="actor approval-rule blocked-actions fallback permitted-evidence required-check tool-scope"
  contracts_ok=true
  readonly_ok=true
  for f in "$AGENTS_DIR"/*.md; do
    keys="$(yq --front-matter=extract '.contract | keys | sort | join(" ")' "$f" 2>/dev/null || echo "")"
    [[ "$keys" == "$CONTRACT_KEYS" ]] || { contracts_ok=false; echo "    (contract keys off in ${f##*/}: [$keys])"; }
    scope="$(yq --front-matter=extract '.contract.tool-scope' "$f" 2>/dev/null || echo "")"
    if [[ "$scope" == "read-only" ]]; then
      wr="$(yq --front-matter=extract '[.tools[] | select(. == "Write" or . == "Edit")] | length' "$f" 2>/dev/null || echo "1")"
      [[ "$wr" == "0" ]] || { readonly_ok=false; echo "    (read-only ${f##*/} holds Write/Edit)"; }
    fi
  done
  assert "agent-controls: every agent has 7 contract keys" "$([[ "$contracts_ok" == "true" ]] && echo true || echo false)"
  assert "agent-controls: read-only agents lack Write/Edit" "$([[ "$readonly_ok" == "true" ]] && echo true || echo false)"
else
  echo "  (skipping agent-controls contract checks — yq not installed)"
fi

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
