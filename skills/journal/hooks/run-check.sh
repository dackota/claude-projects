#!/usr/bin/env bash
# PostToolUse hook: fires after a Task (sub-agent) tool call.
# When a review/gate agent finishes, nudge Claude to record a `run` entry in
# journal.yaml (the pipeline audit trail — the loop's "Audit" step). Assumes CWD
# is the project root (where journal.yaml lives). Exits 2 to asyncRewake Claude.

set -euo pipefail

input=$(cat)
agent=$(echo "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null)

[[ -z "$agent" ]] && exit 0

case "$agent" in
  implementation-validator|security-reviewer|otel-observability-engineer)
    ;;
  *)
    exit 0
    ;;
esac

echo "Gate agent '${agent}' finished — append a /journal 'run' entry (type=run; agent, task, verdict, critical/high counts, rework, approver) to journal.yaml so the pipeline audit trail and STATUS.md Pipeline health stay current."
exit 2
