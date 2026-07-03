#!/usr/bin/env bash
# PostToolUse hook: fires when a Task (sub-agent) tool call returns — at completion
# for a foreground gate, at dispatch for a backgrounded one (the async launch
# returns immediately). For a review/gate agent it: (1) records a "gate ran" marker
# so the Stop hook can enforce that a `run` entry was actually written (barrier audit
# completeness — a missing entry is an error, not just a nudge), and (2) nudges Claude
# to append the entry once the gate's verdict is in. Exits 2 to re-wake Claude.

set -uo pipefail

input=$(cat)
agent=$(echo "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || echo "")

[[ -z "$agent" ]] && exit 0

case "$agent" in
  implementation-validator|correctness-reviewer|runtime-validator|security-reviewer|otel-observability-engineer|integration-reviewer)
    ;;
  *)
    exit 0
    ;;
esac

# Resolve the workspace root: CLAUDE_PROJECT_DIR, else the hook payload cwd, else PWD.
root="${CLAUDE_PROJECT_DIR:-}"
[[ -z "$root" ]] && root=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
[[ -z "$root" ]] && root="$PWD"

# Session-scope the pending/baseline markers so a crashed or interrupted session can't
# corrupt the NEXT session's audit accounting (each session only ever reads its own).
# When session_id is absent the suffix is empty — byte-identical to the old single-file
# name — and journal-stop.sh derives the identical name, so the pair stays consistent.
sid="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")"
sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')"
sfx=""; [[ -n "$sid" ]] && sfx=".$sid"

state="$root/.claude/state"
pending="$state/pending-gate-runs$sfx"
baseline="$state/pending-baseline$sfx"
journal="$root/journal.yaml"

mkdir -p "$state" 2>/dev/null || true
# Anchor the baseline run-entry count when this batch of gate runs begins, so the
# Stop hook can tell how many run entries have been written since.
if [[ ! -s "$pending" ]]; then
  if [[ -f "$journal" ]]; then
    n=$(grep -cE '^[[:space:]]+type:[[:space:]]*run[[:space:]]*$' "$journal" 2>/dev/null || true)
    echo "${n:-0}" > "$baseline"
  else
    echo 0 > "$baseline"
  fi
fi
printf '%s\n' "$agent" >> "$pending"

echo "Gate agent '${agent}' was dispatched — once it returns its VERDICT, append a /journal 'run' entry (type=run with structured fields: agent, task, verdict [PASS|BLOCK|SKIP], critical, high, rework, approver) so the audit trail and STATUS.md Pipeline health stay current. If it was spawned in the background, wait for its completion notification to read the verdict — do NOT fetch a still-running gate's output (that returns its raw transcript, not a verdict, and burns context). The Stop hook will refuse to stop until every gate run has a matching run entry."
exit 2
