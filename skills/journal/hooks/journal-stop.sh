#!/usr/bin/env bash
# Stop hook: fires when Claude is about to stop.
# Assumes CWD is the project root (where journal.yaml lives).
# Exits 2 to asyncRewake Claude if docs have been modified since the last journal entry.

newer=$(find docs -name '*.md' -newer journal.yaml 2>/dev/null | head -1)
if [[ -n "$newer" ]]; then
  echo "Docs modified since last journal entry ($(basename "$newer")). Write any missing /journal entries before stopping."
  exit 2
fi

exit 0
