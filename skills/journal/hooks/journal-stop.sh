#!/usr/bin/env bash
# Stop hook: fires when Claude is about to stop.
# Resolves paths against the project root (CLAUDE_PROJECT_DIR, with a
# BASH_SOURCE-derived fallback) so it is independent of the hook's CWD —
# Stop hooks do NOT reliably run from the project root.
# Exits 2 (reason on stderr) to re-wake Claude if docs changed since the last
# journal entry.

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
journal="$root/journal.yaml"

# No journal yet → nothing to compare against; don't nag.
[[ -f "$journal" ]] || exit 0

newer=$(find "$root/docs" -name '*.md' -newer "$journal" 2>/dev/null | head -1)
if [[ -n "$newer" ]]; then
  echo "Docs modified since last journal entry ($(basename "$newer")). Write any missing /journal entries before stopping." >&2
  exit 2
fi

exit 0
