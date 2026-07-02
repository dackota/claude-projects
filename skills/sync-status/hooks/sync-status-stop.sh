#!/usr/bin/env bash
# Stop hook: fires when Claude is about to stop.
# Resolves files against the project root (CLAUDE_PROJECT_DIR, with a
# BASH_SOURCE-derived fallback) so it is independent of the hook's CWD —
# Stop hooks do NOT reliably run from the project root.
# Exits 2 (reason on stderr, where the harness reads it) to re-wake Claude if
# journal.yaml is newer than STATUS.md.

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
status="$root/STATUS.md"
journal="$root/journal.yaml"

# No journal yet → nothing to track against; don't nag.
[[ -f "$journal" ]] || exit 0

if [[ ! -f "$status" ]] || [[ "$journal" -nt "$status" ]]; then
  echo "journal.yaml is newer than STATUS.md — run /sync-status to update the project status view." >&2
  exit 2
fi

exit 0
