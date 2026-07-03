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
assert "CLAUDE.md: surface-based security skip" "$(grep -q 'trust-boundary' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "CLAUDE.md: size-based skip retired"   "$(! grep -q '25 lines' "$TARGET/CLAUDE.md" && echo true || echo false)"
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
assert "default: barrier-gate hook present"    "$([[ -f $TARGET/.claude/skills/journal/hooks/barrier-gate.sh ]] && echo true || echo false)"
assert "default: barrier-gate hook wired"      "$(grep -q 'barrier-gate.sh' "$TARGET/.claude/settings.json" && echo true || echo false)"
assert "default: preflight checks barrier-gate" "$(grep -q 'barrier-gate' "$TARGET/.claude/skills/next/next-preflight.sh" && echo true || echo false)"

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
assert "repo skill: unwired stale-stop removed"     "$([[ ! -f $RT/.claude/skills/repo/hooks/repo-stale-stop.sh ]] && echo true || echo false)"

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

# ── A1: run-entry schema + barrier-audit enforcement (journal hooks) ──────────
STOP_HOOK="$RT/.claude/skills/journal/hooks/journal-stop.sh"
RUN_HOOK="$RT/.claude/skills/journal/hooks/run-check.sh"

# stopcheck <workspace-dir> -> exit code of the Stop hook for that workspace
stopcheck() {
  local rc=0
  CLAUDE_PROJECT_DIR="$1" bash "$STOP_HOOK" </dev/null >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
# gaterun <workspace-dir> <agent> -> simulate a gate sub-agent finishing
gaterun() {
  echo "{\"tool_input\":{\"subagent_type\":\"$2\"},\"cwd\":\"$1\"}" \
    | CLAUDE_PROJECT_DIR="$1" bash "$RUN_HOOK" >/dev/null 2>&1 || true
}

# schema doc must admit SKIP (the runtime gate's verdict)
assert "journal skill: verdict enum includes SKIP" \
  "$(grep -qE 'verdict:.*\bSKIP\b' "$RT/.claude/skills/journal/SKILL.md" && echo true || echo false)"

# a well-formed run entry (all required fields) passes the Stop gate
FX_OK="${TMPDIR_BASE}/a1-ok"; mkdir -p "$FX_OK"
cat > "$FX_OK/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: correctness-reviewer
  task: add-login-endpoint
  verdict: PASS
  critical: 0
  high: 0
  rework: 0
  summary: correctness-reviewer PASS on add-login-endpoint
  refs: [add-login-endpoint]
EOF
assert "stop: well-formed run entry passes"        "$([[ "$(stopcheck "$FX_OK")" == "0" ]] && echo true || echo false)"

# verdict SKIP is valid (runtime gate emits it)
FX_SKIP="${TMPDIR_BASE}/a1-skip"; mkdir -p "$FX_SKIP"
cat > "$FX_SKIP/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: runtime-validator
  task: pure-lib
  verdict: SKIP
  critical: 0
  high: 0
  rework: 0
  summary: runtime SKIP — no runnable surface
  refs: [pure-lib]
EOF
assert "stop: verdict SKIP accepted"               "$([[ "$(stopcheck "$FX_SKIP")" == "0" ]] && echo true || echo false)"

# a prose-only run entry (the drift we found) is rejected
FX_PROSE="${TMPDIR_BASE}/a1-prose"; mkdir -p "$FX_PROSE"
cat > "$FX_PROSE/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  summary: >-
    correctness-reviewer BLOCK with 2 CRITICAL on manifestdiff; looping back.
  refs: [manifestdiff-module]
EOF
assert "stop: prose-only run entry blocked"        "$([[ "$(stopcheck "$FX_PROSE")" == "2" ]] && echo true || echo false)"

# an invalid verdict value is rejected
FX_BADV="${TMPDIR_BASE}/a1-badv"; mkdir -p "$FX_BADV"
cat > "$FX_BADV/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: implementation-validator
  task: t
  verdict: MAYBE
  critical: 0
  high: 0
  rework: 0
  summary: bad verdict
EOF
assert "stop: invalid verdict blocked"             "$([[ "$(stopcheck "$FX_BADV")" == "2" ]] && echo true || echo false)"

# non-run entries are exempt from the run schema
FX_NONRUN="${TMPDIR_BASE}/a1-nonrun"; mkdir -p "$FX_NONRUN"
cat > "$FX_NONRUN/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: done
  summary: slice built and gated
  refs: [x]
- date: 2026-07-03
  type: decision
  summary: chose approach A
EOF
assert "stop: non-run entries exempt"              "$([[ "$(stopcheck "$FX_NONRUN")" == "0" ]] && echo true || echo false)"

# run-check.sh drops a pending marker for a gate agent, none for others
FX_MARK="${TMPDIR_BASE}/a1-mark"; mkdir -p "$FX_MARK"; printf '[]\n' > "$FX_MARK/journal.yaml"
gaterun "$FX_MARK" correctness-reviewer
assert "run-check: gate run drops marker"          "$([[ -s "$FX_MARK/.claude/state/pending-gate-runs" ]] && echo true || echo false)"

FX_NOMARK="${TMPDIR_BASE}/a1-nomark"; mkdir -p "$FX_NOMARK"; printf '[]\n' > "$FX_NOMARK/journal.yaml"
gaterun "$FX_NOMARK" tdd-implementer
assert "run-check: non-gate agent drops no marker" "$([[ ! -s "$FX_NOMARK/.claude/state/pending-gate-runs" ]] && echo true || echo false)"

# barrier-audit completeness: a recorded gate run with no run entry blocks Stop
assert "stop: gate ran but no entry blocks"        "$([[ "$(stopcheck "$FX_MARK")" == "2" ]] && echo true || echo false)"

# once the matching run entry exists, Stop reconciles and clears the markers
cat > "$FX_MARK/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: correctness-reviewer
  task: t
  verdict: BLOCK
  critical: 1
  high: 0
  rework: 0
  summary: correctness BLOCK (1 CRITICAL)
EOF
assert "stop: entry written reconciles audit"      "$([[ "$(stopcheck "$FX_MARK")" == "0" ]] && echo true || echo false)"
assert "stop: reconcile clears pending markers"    "$([[ ! -s "$FX_MARK/.claude/state/pending-gate-runs" ]] && echo true || echo false)"

# Fix 4: session-scoped markers isolate a crashed session from a healthy one. Session
# AAA runs a gate then "crashes" (never writes its entry, never stops), leaving an
# orphaned marker; session BBB runs a gate, logs it, and stops — and must be clean
# despite AAA's orphan (pre-fix, the single shared marker blocked any session's Stop).
FX_ISO="${TMPDIR_BASE}/a1-iso"; mkdir -p "$FX_ISO"; printf '[]\n' > "$FX_ISO/journal.yaml"
echo "{\"tool_input\":{\"subagent_type\":\"implementation-validator\"},\"session_id\":\"AAA\",\"cwd\":\"$FX_ISO\"}" \
  | CLAUDE_PROJECT_DIR="$FX_ISO" bash "$RUN_HOOK" >/dev/null 2>&1 || true
assert "run-check: marker is session-scoped"        "$([[ -s "$FX_ISO/.claude/state/pending-gate-runs.AAA" ]] && echo true || echo false)"
echo "{\"tool_input\":{\"subagent_type\":\"correctness-reviewer\"},\"session_id\":\"BBB\",\"cwd\":\"$FX_ISO\"}" \
  | CLAUDE_PROJECT_DIR="$FX_ISO" bash "$RUN_HOOK" >/dev/null 2>&1 || true
cat > "$FX_ISO/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: correctness-reviewer
  task: t
  verdict: PASS
  critical: 0
  high: 0
  rework: 0
EOF
ISO_RC=0; echo '{"session_id":"BBB"}' | CLAUDE_PROJECT_DIR="$FX_ISO" bash "$STOP_HOOK" >/dev/null 2>&1 || ISO_RC=$?
assert "stop: crashed session's orphan doesn't block a healthy one" "$([[ "$ISO_RC" == "0" ]] && echo true || echo false)"

# adversarial: a malformed run entry among well-formed ones is still caught
FX_MULTI="${TMPDIR_BASE}/a1-multi"; mkdir -p "$FX_MULTI"
cat > "$FX_MULTI/journal.yaml" <<'EOF'
- date: 2026-07-03
  type: run
  agent: implementation-validator
  task: a
  verdict: PASS
  critical: 0
  high: 0
  rework: 0
  summary: ok
- date: 2026-07-03
  type: run
  summary: prose only, no structured fields
EOF
assert "stop: malformed entry among valid caught"  "$([[ "$(stopcheck "$FX_MULTI")" == "2" ]] && echo true || echo false)"

# adversarial: malformed final entry with NO trailing newline (END-flush path)
FX_NONL="${TMPDIR_BASE}/a1-nonl"; mkdir -p "$FX_NONL"
printf -- '- date: 2026-07-03\n  type: run\n  summary: prose only, no trailing newline' > "$FX_NONL/journal.yaml"
assert "stop: malformed no-trailing-newline caught" "$([[ "$(stopcheck "$FX_NONL")" == "2" ]] && echo true || echo false)"

# ── A2: rework cap (rework-cap.sh) — PreToolUse on Task ───────────────────────
CAP_HOOK="$RT/.claude/skills/journal/hooks/rework-cap.sh"
assert "rework-cap: hook installed"                "$([[ -f $CAP_HOOK ]] && echo true || echo false)"
assert "rework-cap: PreToolUse Task hook wired"    "$([[ "$(count_cmd rework-cap)" == "1" ]] && echo true || echo false)"

# capcheck <dir> <subagent_type> -> exit code
capcheck() {
  local rc=0
  echo "{\"tool_input\":{\"subagent_type\":\"$2\"},\"cwd\":\"$1\"}" | CLAUDE_PROJECT_DIR="$1" bash "$CAP_HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
# mk_proj <file> <active-id> <max_rework>
mk_proj() { cat > "$1" <<EOF
name: fx
tasks:
  - id: $2
    title: T
    type: AFK
    status: active
    blocked_by: []
validation:
  run_cmd: ""
  max_rework: $3
EOF
}
# mk_runs <file> <task> <agent> <verdict> <count>  (append run entries)
mk_runs() {
  local f=$1 task=$2 agent=$3 verdict=$4 n=$5 i
  for ((i=0;i<n;i++)); do cat >> "$f" <<EOF
- date: 2026-07-03
  type: run
  agent: $agent
  task: $task
  verdict: $verdict
  critical: 1
  high: 0
  rework: $i
  summary: $agent $verdict on $task
EOF
  done
}

# at the cap (3 BLOCKs, cap 3) the 3rd rework is allowed — the manifestdiff converge case
CAP1="${TMPDIR_BASE}/cap-atcap"; mkdir -p "$CAP1"; mk_proj "$CAP1/project.yaml" t1 3
: > "$CAP1/journal.yaml"; mk_runs "$CAP1/journal.yaml" t1 correctness-reviewer BLOCK 3
assert "cap: 3 BLOCKs at cap 3 still allowed"      "$([[ "$(capcheck "$CAP1" tdd-implementer)" == "0" ]] && echo true || echo false)"

# over the cap (4 BLOCKs, cap 3) the re-spawn is refused
CAP2="${TMPDIR_BASE}/cap-over"; mkdir -p "$CAP2"; mk_proj "$CAP2/project.yaml" t1 3
: > "$CAP2/journal.yaml"; mk_runs "$CAP2/journal.yaml" t1 correctness-reviewer BLOCK 4
assert "cap: 4th BLOCK at a gate escalates"        "$([[ "$(capcheck "$CAP2" tdd-implementer)" == "2" ]] && echo true || echo false)"

# the cap only gates tdd-implementer spawns, not other agents
assert "cap: only gates tdd-implementer"           "$([[ "$(capcheck "$CAP2" correctness-reviewer)" == "0" ]] && echo true || echo false)"

# per-GATE, not per-task total: 3 correctness + 3 acceptance (max 3/gate) at cap 3 → allowed
CAP3="${TMPDIR_BASE}/cap-pergate"; mkdir -p "$CAP3"; mk_proj "$CAP3/project.yaml" t1 3
: > "$CAP3/journal.yaml"
mk_runs "$CAP3/journal.yaml" t1 correctness-reviewer BLOCK 3
mk_runs "$CAP3/journal.yaml" t1 implementation-validator BLOCK 3
assert "cap: per-gate, not per-task total"         "$([[ "$(capcheck "$CAP3" tdd-implementer)" == "0" ]] && echo true || echo false)"

# cap is configurable: max_rework 2, 3 BLOCKs → refused
CAP4="${TMPDIR_BASE}/cap-config"; mkdir -p "$CAP4"; mk_proj "$CAP4/project.yaml" t1 2
: > "$CAP4/journal.yaml"; mk_runs "$CAP4/journal.yaml" t1 correctness-reviewer BLOCK 3
assert "cap: max_rework configurable (2)"          "$([[ "$(capcheck "$CAP4" tdd-implementer)" == "2" ]] && echo true || echo false)"

# BLOCKs for a DIFFERENT task don't count against the active task
CAP5="${TMPDIR_BASE}/cap-otask"; mkdir -p "$CAP5"; mk_proj "$CAP5/project.yaml" t1 3
: > "$CAP5/journal.yaml"; mk_runs "$CAP5/journal.yaml" t2 correctness-reviewer BLOCK 5
assert "cap: counts only the active task"          "$([[ "$(capcheck "$CAP5" tdd-implementer)" == "0" ]] && echo true || echo false)"

# Fix 5: a gate's PASS ends its rework streak, so a task reopened after it passed
# starts fresh instead of inheriting the earlier episode's BLOCK count. 5 old BLOCKs
# (way over cap 3) + a PASS + 1 new BLOCK → streak is 1 → allowed.
CAP6="${TMPDIR_BASE}/cap-episode"; mkdir -p "$CAP6"; mk_proj "$CAP6/project.yaml" t1 3
: > "$CAP6/journal.yaml"
mk_runs "$CAP6/journal.yaml" t1 correctness-reviewer BLOCK 5
mk_runs "$CAP6/journal.yaml" t1 correctness-reviewer PASS  1
mk_runs "$CAP6/journal.yaml" t1 correctness-reviewer BLOCK 1
assert "cap: PASS resets the rework streak (reopen)" "$([[ "$(capcheck "$CAP6" tdd-implementer)" == "0" ]] && echo true || echo false)"

# scaffolded project.yaml declares the cap (not a magic number)
assert "project.yaml: declares max_rework"         "$(grep -qE '^[[:space:]]*max_rework:' "$TARGET/project.yaml" && echo true || echo false)"

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

  # Removing a stacked parent must refuse while children point at its branch.
  RM_RC=0
  repo remove slice-1 >/dev/null 2>&1 || RM_RC=$?
  assert "stack: remove parent refused (children)"  "$([[ $RM_RC -ne 0 ]] && echo true || echo false)"
  assert "stack: parent branch survives refusal"    "$(git -C "$RT/repos/remote" show-ref --verify --quiet refs/heads/slice-1 && echo true || echo false)"
  assert "stack: parent worktree survives refusal"  "$([[ -d $RT/worktrees/slice-1/remote ]] && echo true || echo false)"

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

  # Orphaned admin entries (a worktree dir removed by hand) are pruned by status.
  repo worktree prune-probe remote >/dev/null 2>&1
  rm -rf "$RT/worktrees/prune-probe"
  repo status >/dev/null 2>&1
  assert "status: prunes orphaned worktree entry"   "$(! git -C "$RT/repos/remote" worktree list | grep -q '/prune-probe/' && echo true || echo false)"
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

git -C "$CLS" checkout -q -b sql-mig main
printf 'ALTER TABLE users ADD COLUMN email text;\n' > "$CLS/001_add_email.sql"
git -C "$CLS" add -A; git -C "$CLS" commit -qm sql
assert "classify: sql migration -> surface"         "$(case " $(classify) " in *" surface "*) echo true ;; *) echo false ;; esac)"

git -C "$CLS" checkout -q -b env-file main
printf 'API_KEY=abc123\n' > "$CLS/.env"
git -C "$CLS" add -A; git -C "$CLS" commit -qm env
assert "classify: env file -> surface"              "$(case " $(classify) " in *" surface "*) echo true ;; *) echo false ;; esac)"

git -C "$CLS" checkout -q -b json-infra main
printf '{"AWSTemplateFormatVersion":"2010-09-09","Resources":{}}\n' > "$CLS/stack.json"
git -C "$CLS" add -A; git -C "$CLS" commit -qm cfn
assert "classify: CloudFormation json -> infra"     "$(case " $(classify) " in *" infra "*) echo true ;; *) echo false ;; esac)"

git -C "$CLS" checkout -q -b json-fixture main
printf '{"name":"fixture","items":[1,2,3]}\n' > "$CLS/fixture.json"
git -C "$CLS" add -A; git -C "$CLS" commit -qm fixture
assert "classify: plain json fixture -> none"       "$([[ -z "$(classify)" ]] && echo true || echo false)"

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

# ── barrier-gate.sh: acceptance+correctness PR gate (worktree + next scoped) ──
BARRIER_GATE="$RT/.claude/skills/journal/hooks/barrier-gate.sh"
# A git repo whose path is under worktrees/ — the pipeline task-worktree shape.
BG_WT="${TMPDIR_BASE}/bg/worktrees/slice-1/remote"
mkdir -p "$BG_WT"
git init -q "$BG_WT"
git -C "$BG_WT" config user.email t@t.test
git -C "$BG_WT" config user.name "Test"
git -C "$BG_WT" config commit.gpgsign false
echo base > "$BG_WT/f.txt"; git -C "$BG_WT" add -A; git -C "$BG_WT" commit -qm base
BG_SHA="$(git -C "$BG_WT" rev-parse HEAD)"
BG_VDIR="$(git -C "$BG_WT" rev-parse --absolute-git-dir)/barrier-review"
bgate() { # bgate <workspace-root> <cwd> -> exit code
  local rc=0
  echo "{\"tool_input\":{\"command\":\"gh pr create -t x\"},\"cwd\":\"$2\"}" \
    | CLAUDE_PROJECT_DIR="$1" bash "$BARRIER_GATE" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
# Workspaces distinguished only by which barrier pieces they carry.
BG_NONEXT="${TMPDIR_BASE}/bg-nonext"; mkdir -p "$BG_NONEXT/.claude/skills/journal"
BG_FULL="${TMPDIR_BASE}/bg-full"; mkdir -p "$BG_FULL/.claude/skills/next" "$BG_FULL/.claude/agents"
BG_DEGRADED="${TMPDIR_BASE}/bg-degraded"; mkdir -p "$BG_DEGRADED/.claude/skills/next" "$BG_DEGRADED/.claude/agents"
: > "$BG_FULL/.claude/agents/implementation-validator.md"
: > "$BG_FULL/.claude/agents/correctness-reviewer.md"

rm -rf "$BG_VDIR"
# The fix: without the barrier workflow (`next`) installed, the journal-shipped hook
# stays inert — a supported `--skills journal,repo` subset can't be permanently blocked.
assert "barrier-gate: inert without next skill"      "$([[ "$(bgate "$BG_NONEXT" "$BG_WT")" == "0" ]] && echo true || echo false)"
# `next` present but gate agents missing -> degraded install -> fail closed.
assert "barrier-gate: fail-closed on degraded next"  "$([[ "$(bgate "$BG_DEGRADED" "$BG_WT")" == "2" ]] && echo true || echo false)"
# `next` + both agents present, no recorded verdict -> a built slice must carry one.
assert "barrier-gate: blocks worktree PR w/o verdict" "$([[ "$(bgate "$BG_FULL" "$BG_WT")" == "2" ]] && echo true || echo false)"
# A recorded verdict is honored ahead of every other check (independent of next).
mkdir -p "$BG_VDIR"
printf 'acceptance PASS\ncorrectness PASS\n' > "$BG_VDIR/$BG_SHA"
assert "barrier-gate: honors PASS/PASS verdict"      "$([[ "$(bgate "$BG_NONEXT" "$BG_WT")" == "0" ]] && echo true || echo false)"
printf 'acceptance PASS\ncorrectness BLOCK\n' > "$BG_VDIR/$BG_SHA"
assert "barrier-gate: blocks recorded non-PASS"      "$([[ "$(bgate "$BG_FULL" "$BG_WT")" == "2" ]] && echo true || echo false)"
rm -rf "$BG_VDIR"
# Inline / ad-hoc PR (cwd not under worktrees/) is allowed even with next installed.
BG_INLINE="${TMPDIR_BASE}/bg-inline"
git init -q "$BG_INLINE"
git -C "$BG_INLINE" config user.email t@t.test
git -C "$BG_INLINE" config user.name "Test"
git -C "$BG_INLINE" config commit.gpgsign false
echo base > "$BG_INLINE/f.txt"; git -C "$BG_INLINE" add -A; git -C "$BG_INLINE" commit -qm base
assert "barrier-gate: allows inline non-worktree"    "$([[ "$(bgate "$BG_FULL" "$BG_INLINE")" == "0" ]] && echo true || echo false)"

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
# Slice E — release-verify (Land-phase live verification, decision 2)
assert "next: RELEASE-VERIFY.md installed"          "$([[ -f $NT/.claude/skills/next/RELEASE-VERIFY.md ]] && echo true || echo false)"
assert "next: Land references release-verify"       "$(grep -q 'RELEASE-VERIFY.md' "$NT/.claude/skills/next/SKILL.md" && echo true || echo false)"
assert "runtime-validator: release mode"            "$(grep -q 'Release mode' "$NT/.claude/agents/runtime-validator.md" && echo true || echo false)"
assert "runtime-validator: verdict carries CRITICAL" "$(grep -q 'CRITICAL: <n>' "$NT/.claude/agents/runtime-validator.md" && echo true || echo false)"
assert "runtime-validator: live read-only, no deploy" "$(grep -q 'mutate any live/shared environment' "$NT/.claude/agents/runtime-validator.md" && echo true || echo false)"
assert "next: CLAUDE.md has /next session-start"    "$(grep -q '/next' "$NT/CLAUDE.md" && echo true || echo false)"
# Scoping guard: dependency resolution is additive, not "install everything".
# A3: next now pulls its lifecycle infrastructure as hard deps (previously excluded,
# which yielded a legal-looking but silently broken `--skills next` install).
assert "next: pulls journal companion"              "$([[ -d $NT/.claude/skills/journal ]] && echo true || echo false)"
assert "next: pulls repo companion"                 "$([[ -d $NT/.claude/skills/repo ]] && echo true || echo false)"
assert "next: pulls sync-status companion"          "$([[ -d $NT/.claude/skills/sync-status ]] && echo true || echo false)"
assert "next: pulls pr-security-review companion"   "$([[ -d $NT/.claude/skills/pr-security-review ]] && echo true || echo false)"
assert "next: repo.sh script installed"             "$([[ -f $NT/scripts/repo.sh ]] && echo true || echo false)"
assert "next: security-reviewer agent installed"    "$([[ -f $NT/.claude/agents/security-reviewer.md ]] && echo true || echo false)"
NX_SETTINGS="$NT/.claude/settings.json"
nx_cmd() { jq "[.. | objects | select(has(\"command\")) | select(.command|test(\"$1\"))] | length" "$NX_SETTINGS"; }
assert "next: pr-gate hook wired"                   "$([[ "$(nx_cmd pr-gate)" == "1" ]] && echo true || echo false)"
assert "next: rework-cap hook wired"                "$([[ "$(nx_cmd rework-cap)" == "1" ]] && echo true || echo false)"
# A3: /next preflight self-check exists, passes on a whole install, fails when degraded
assert "next: preflight script installed"           "$([[ -f $NT/.claude/skills/next/next-preflight.sh ]] && echo true || echo false)"
preflight() { local rc=0; CLAUDE_PROJECT_DIR="$1" bash "$NT/.claude/skills/next/next-preflight.sh" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
assert "next: preflight passes on full install"     "$([[ "$(preflight "$NT")" == "0" ]] && echo true || echo false)"
NX_EMPTY="${TMPDIR_BASE}/nx-empty"; mkdir -p "$NX_EMPTY"
assert "next: preflight fails on empty workspace"   "$([[ "$(preflight "$NX_EMPTY")" == "1" ]] && echo true || echo false)"
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
assert "agents: tool-scope enum includes execute"   "$(! grep -l '# read-only | write | deploy' "$AGENTS_DIR"/*.md >/dev/null 2>&1 && echo true || echo false)"
assert "agents: no stray </content> tags"           "$(! grep -q '</content>' "$AGENTS_DIR"/*.md && echo true || echo false)"
assert "REFERENCE: size-skip knob retired"          "$(! grep -q 'PR_SECURITY_MAX_SMALL_LINES' "${SCRIPT_DIR}/../docs/REFERENCE.md" && echo true || echo false)"
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

# ── B1/B2: cross-workspace outcome rollup (scripts/rollup.sh) ─────────────────
ROLLUP="${SCRIPT_DIR}/rollup.sh"
assert "rollup: script exists"                     "$([[ -f $ROLLUP ]] && echo true || echo false)"

# workspace with a representative spread of gate runs (post-A1 structured schema)
WS1="${TMPDIR_BASE}/rollup-ws1"; mkdir -p "$WS1"
cat > "$WS1/journal.yaml" <<'EOF'
- date: 2026-07-01
  type: run
  agent: implementation-validator
  task: t1
  verdict: PASS
  critical: 0
  high: 0
  rework: 0
  summary: acceptance PASS
- date: 2026-07-01
  type: run
  agent: correctness-reviewer
  task: t1
  verdict: BLOCK
  critical: 2
  high: 0
  rework: 0
  summary: correctness BLOCK (2 CRITICAL)
- date: 2026-07-01
  type: run
  agent: correctness-reviewer
  task: t1
  verdict: PASS
  critical: 0
  high: 0
  rework: 1
  summary: correctness PASS after rework
- date: 2026-07-01
  type: run
  agent: runtime-validator
  task: t1
  verdict: SKIP
  critical: 0
  high: 0
  rework: 0
  summary: runtime SKIP — pure library
- date: 2026-07-02
  type: run
  agent: runtime-validator
  task: t2
  verdict: BLOCK
  critical: 1
  high: 0
  rework: 0
  gate: release-verify
  escape: true
  summary: glob fan-out escape caught at deploy verify
- date: 2026-07-02
  type: run
  agent: security-reviewer
  task: t1
  verdict: PASS
  critical: 0
  high: 0
  rework: 0
  approver: alice
  summary: security PASS, human-approved
- date: 2026-07-02
  type: blocker
  summary: blocked on missing sandbox credential
EOF

# workspace with no gate runs (older harness) — counted, contributes nothing
WS2="${TMPDIR_BASE}/rollup-ws2"; mkdir -p "$WS2"
cat > "$WS2/journal.yaml" <<'EOF'
- date: 2026-06-01
  type: done
  summary: shipped
- date: 2026-06-01
  type: decision
  summary: chose approach A
EOF

OUT="$(bash "$ROLLUP" "$WS1" "$WS2" 2>/dev/null || true)"
assert "rollup: counts workspaces + gate-run coverage" "$(echo "$OUT" | grep -qF '2 workspace(s) scanned, 1 with gate runs' && echo true || echo false)"
assert "rollup: verdict tally PASS/BLOCK/SKIP"      "$(echo "$OUT" | grep -qF 'PASS 3 / BLOCK 2 / SKIP 1' && echo true || echo false)"
assert "rollup: block rate excludes SKIP"          "$(echo "$OUT" | grep -qF 'block rate 40% (2/5 decided)' && echo true || echo false)"
assert "rollup: by-gate correctness 1/2"           "$(echo "$OUT" | grep -qF 'correctness 1/2' && echo true || echo false)"
assert "rollup: by-gate runtime 1/2"               "$(echo "$OUT" | grep -qF 'runtime 1/2' && echo true || echo false)"
assert "rollup: rework loop-backs + tasks"         "$(echo "$OUT" | grep -qF '2 loop-back(s) across 2 task(s)' && echo true || echo false)"
assert "rollup: runtime SKIP rate (B2)"            "$(echo "$OUT" | grep -qF 'Runtime SKIP: 1/2' && echo true || echo false)"
assert "rollup: escapes-found-live counted"        "$(echo "$OUT" | grep -qF 'Escapes (found live): 1' && echo true || echo false)"
assert "rollup: human interventions"               "$(echo "$OUT" | grep -qF '1 blocker(s) + 1 approval(s)' && echo true || echo false)"

# empty / no-run corpus must not divide by zero or crash
OUT2="$(bash "$ROLLUP" "$WS2" 2>/dev/null || echo CRASH)"
assert "rollup: no-run corpus degrades gracefully" "$([[ "$OUT2" != "CRASH" ]] && echo "$OUT2" | grep -qF '0 with gate runs' && echo true || echo false)"

# ── A3/A4/A5/A6: Phase-A integrity fixes ──────────────────────────────────────

# A3.4: yq fails loud (die) when an agent-bearing skill would install, not silent-skip
assert "proj: yq-loud guard for agent skills"       "$(grep -q 'installs agents but yq is not available' "$PROJ" && echo true || echo false)"

# A4: Pipeline health surfaces correctness + runtime by-gate + runtime-SKIP dormancy
SS="$RT/.claude/skills/sync-status/SKILL.md"
assert "sync-status: by-gate includes correctness"  "$(grep -qE 'By gate:.*correctness' "$SS" && echo true || echo false)"
assert "sync-status: by-gate includes runtime"      "$(grep -qE 'By gate:.*runtime'     "$SS" && echo true || echo false)"
assert "sync-status: surfaces runtime SKIP dormancy" "$(grep -q 'Runtime gate:' "$SS" && grep -q 'SKIP' "$SS" && echo true || echo false)"

# A5: gate rules have a single normative home — no restatement outside BARRIER.md
A5_LEAK=$(grep -rlF -e 'the 3rd rework is allowed' -e 'advances only if **all** PASS' "$RT/.claude/skills" 2>/dev/null | grep -v '/next/BARRIER.md' || true)
assert "single-home: gate rules only in BARRIER.md" "$([[ -z "$A5_LEAK" ]] && echo true || echo false)"

# A6: managed CLAUDE.md block + harness SHA stamp
assert "scaffold: CLAUDE.md has managed BEGIN marker" "$(grep -qF 'BEGIN proj:harness' "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "scaffold: CLAUDE.md has managed END marker"   "$(grep -qF 'END proj:harness'   "$TARGET/CLAUDE.md" && echo true || echo false)"
assert "scaffold: .harness-version stamped"           "$(grep -qE '^harness_sha:' "$TARGET/.harness-version" && echo true || echo false)"

# A6: update-skills refreshes the managed block (drift removed) + preserves outside content + re-stamps
printf '\n<!-- USER NOTE: keep me -->\n' >> "$RT/CLAUDE.md"
awk '{print} /BEGIN proj:harness/ && !d {print "STALE RETIRED RULE LINE"; d=1}' "$RT/CLAUDE.md" > "$RT/CLAUDE.md.tmp" && mv "$RT/CLAUDE.md.tmp" "$RT/CLAUDE.md"
bash "$PROJ" update-skills --dir "$RT" >/dev/null 2>&1
assert "update-skills: refreshes managed block"      "$(! grep -qF 'STALE RETIRED RULE LINE' "$RT/CLAUDE.md" && echo true || echo false)"
assert "update-skills: preserves content outside"    "$(grep -qF 'USER NOTE: keep me' "$RT/CLAUDE.md" && echo true || echo false)"
assert "update-skills: re-stamps .harness-version"   "$(grep -qE '^harness_sha:' "$RT/.harness-version" && echo true || echo false)"

# ADR-0004: declarative toolchain — project.yaml declares format/lint/test commands,
# and the runner + spot-verify prefer them (declared-then-inferred, not hardcoded).
assert "project.yaml: declares format_cmd"          "$(grep -qE '^[[:space:]]*format_cmd:' "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml: declares lint_cmd"            "$(grep -qE '^[[:space:]]*lint_cmd:'   "$TARGET/project.yaml" && echo true || echo false)"
assert "project.yaml: declares test_cmd"            "$(grep -qE '^[[:space:]]*test_cmd:'   "$TARGET/project.yaml" && echo true || echo false)"
assert "tdd-implementer: prefers declared toolchain" "$(grep -q 'validation.format_cmd' "$RT/.claude/agents/tdd-implementer.md" && echo true || echo false)"
assert "next: spot-verify reads declared cmds"       "$(grep -q 'validation.format_cmd' "$RT/.claude/skills/next/SKILL.md" && echo true || echo false)"

# ── Layer 1: coverage map — every PRD requirement owned by a slice ────────────
COV="$RT/.claude/skills/to-issues/coverage-check.sh"
assert "coverage: check script installed"            "$([[ -f $COV ]] && echo true || echo false)"
assert "to-prd: PRD template has Requirements"       "$(grep -q '## Requirements' "$RT/.claude/skills/to-prd/SKILL.md" && echo true || echo false)"
assert "to-issues: slices persist covers"            "$(grep -q 'covers:' "$RT/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "to-issues: runs coverage-check"              "$(grep -q 'coverage-check' "$RT/.claude/skills/to-issues/SKILL.md" && echo true || echo false)"
assert "CLAUDE.md: task schema has covers"           "$(grep -q 'covers:' "$TARGET/CLAUDE.md" && echo true || echo false)"

if command -v yq >/dev/null 2>&1; then
  covcheck() { local rc=0; bash "$COV" "$1" "$2" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
  COVWS="${TMPDIR_BASE}/cov"; mkdir -p "$COVWS"
  cat > "$COVWS/feature-a-prd.md" <<'EOF'
## Requirements
- R1: the poller expands glob patterns
- R2: config rejects oversized files
- R3: the filter validates facet names
EOF
  cat > "$COVWS/ok.yaml" <<'EOF'
tasks:
  - id: s1
    plan: docs/plans/feature-a-prd.md
    covers: [R1, R2]
  - id: s2
    plan: docs/plans/feature-a-prd.md
    covers: [R3]
EOF
  assert "coverage: all requirements owned -> pass"  "$([[ "$(covcheck "$COVWS/feature-a-prd.md" "$COVWS/ok.yaml")" == "0" ]] && echo true || echo false)"

  cat > "$COVWS/gap.yaml" <<'EOF'
tasks:
  - id: s1
    plan: docs/plans/feature-a-prd.md
    covers: [R1, R2]
EOF
  assert "coverage: unowned requirement -> fail"     "$([[ "$(covcheck "$COVWS/feature-a-prd.md" "$COVWS/gap.yaml")" == "1" ]] && echo true || echo false)"
  COV_OUT="$(bash "$COV" "$COVWS/feature-a-prd.md" "$COVWS/gap.yaml" 2>&1 || true)"
  assert "coverage: names the unowned id (R3)"       "$(echo "$COV_OUT" | grep -q 'R3' && echo true || echo false)"

  # covers under a DIFFERENT plan must not count toward this PRD (plan filter)
  cat > "$COVWS/otherplan.yaml" <<'EOF'
tasks:
  - id: s1
    plan: docs/plans/feature-b-prd.md
    covers: [R1, R2, R3]
EOF
  assert "coverage: other-plan covers don't count"   "$([[ "$(covcheck "$COVWS/feature-a-prd.md" "$COVWS/otherplan.yaml")" == "1" ]] && echo true || echo false)"
else
  echo "  (skipping coverage-check behavior — yq not installed)"
fi

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
