#!/usr/bin/env bash
# PostToolUse hook: fires after Write/Edit on significant files.
# Assumes CWD is the project root (where journal.yaml lives).
# Exits 2 to asyncRewake Claude with a journal reminder.

set -euo pipefail

input=$(cat)
fp=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

[[ -z "$fp" ]] && exit 0

case "$fp" in
  *project.yaml|*/docs/decisions/*|*/docs/plans/*|*/docs/research/*)
    ;;
  *)
    exit 0
    ;;
esac

if   [[ "$fp" == */docs/decisions/* ]]; then entry_type="decision"
elif [[ "$fp" == */docs/plans/*     ]]; then entry_type="plan"
elif [[ "$fp" == */docs/research/*  ]]; then entry_type="research"
else                                        entry_type="started/done/decision"
fi

echo "Wrote ${fp##*/} — write a /journal entry: type=${entry_type}, summary=\"<one sentence describing the change>\""
exit 2
