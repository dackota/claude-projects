#!/usr/bin/env bash
# PreToolUse hook on Task: enforce the barrier rework cap.
#
# Before the orchestrator re-spawns `tdd-implementer`, refuse if any single gate has
# already BLOCKed the active task more than `validation.max_rework` times (default 3).
# A gate that keeps blocking the same slice signals a wrong seam, a flaky test, or an
# impossible criterion — not something another build loop will fix — so escalate to a
# human instead of looping unboundedly. Reads the A1-enforced structured run entries
# (task/agent/verdict as fields). Exits 2 (reason on stderr) to block the spawn and
# re-wake the orchestrator. Fails OPEN (exit 0) whenever state can't be determined
# (inline /tdd, non-/next contexts, no active task) — the cap only fires on a clear,
# counted breach. POSIX awk (must run under macOS BSD awk).

set -uo pipefail

input=$(cat)
agent=$(echo "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || echo "")
[[ "$agent" == "tdd-implementer" ]] || exit 0

root="${CLAUDE_PROJECT_DIR:-}"
[[ -z "$root" ]] && root=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
[[ -z "$root" ]] && root="$PWD"
project="$root/project.yaml"
journal="$root/journal.yaml"
[[ -f "$project" && -f "$journal" ]] || exit 0

# validation.max_rework (default 3)
cap=$(awk -F: '/^[[:space:]]*max_rework:/ { v=$2; sub(/#.*/,"",v); gsub(/[^0-9]/,"",v); if (v!="") { print v; exit } }' "$project")
[[ -z "$cap" ]] && cap=3

# active task id (first task with status: active)
active=$(awk '
  function flush() { if (st == "active" && id != "" && !seen) { print id; seen=1 } }
  /^  - id:/     { flush(); id=$0; sub(/^  - id:[[:space:]]*/,"",id); sub(/[[:space:]#].*$/,"",id); st="" }
  /^    status:/ { st=$0; sub(/^    status:[[:space:]]*/,"",st); sub(/[[:space:]#].*$/,"",st) }
  END { flush() }
' "$project")
[[ -z "$active" ]] && exit 0

# Max per-gate BLOCK count for the active task, counted over the CURRENT build episode
# only: a gate's own PASS entry ends its rework streak and resets its counter. So a task
# reopened long after it was done (a security reopen, a manual reopen) starts fresh
# rather than inheriting the BLOCK count from its earlier, already-passed episode.
# Entries are append-only and chronological, so processing them in file order makes the
# reset order-correct.
maxblk=$(awk -v task="$active" '
  function val(l,  v) { v=l; sub(/^  [a-z_]+:[[:space:]]*/,"",v); sub(/[[:space:]#].*$/,"",v); return v }
  function flush() {
    if (type=="run" && t==task && ag!="") {
      if (verdict=="BLOCK") c[ag]++
      else if (verdict=="PASS") c[ag]=0
    }
  }
  /^-[[:space:]]/ { flush(); type=""; ag=""; verdict=""; t="" }
  /^  type:/    { type=val($0) }
  /^  agent:/   { ag=val($0) }
  /^  verdict:/ { verdict=val($0) }
  /^  task:/    { t=val($0) }
  END { flush(); m=0; for (k in c) if (c[k] > m) m=c[k]; print m }
' "$journal")
[[ -z "$maxblk" ]] && maxblk=0

if [[ "$maxblk" -gt "$cap" ]]; then
  echo "Rework cap reached: task '${active}' has been BLOCKed ${maxblk} time(s) at a single gate (cap: ${cap}). Do NOT re-spawn tdd-implementer — a gate that keeps blocking the same slice signals a wrong seam, a flaky test, or an impossible criterion, not something another build loop will fix. Flip task '${active}' to status: blocked in project.yaml and write a /journal blocker entry requesting human input." >&2
  exit 2
fi
exit 0
