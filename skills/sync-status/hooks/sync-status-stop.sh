#!/usr/bin/env bash
# Stop hook: fires when Claude is about to stop.
# Assumes CWD is the project root (where journal.yaml and STATUS.md live).
# Exits 2 to asyncRewake Claude if journal.yaml is newer than STATUS.md.

if [[ ! -f "STATUS.md" ]] || [[ "journal.yaml" -nt "STATUS.md" ]]; then
  echo "journal.yaml is newer than STATUS.md — run /sync-status to update the project status view."
  exit 2
fi

exit 0
