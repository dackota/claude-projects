---
last_synced: 2026-06-04T00:00:00
---

# Status

## Goal
Provide a CLI (`proj`) and conventions that scaffold Claude Code project workspaces with a living current-state surface, append-only event log, lifecycle-frontmatted docs, and `/sync-status` + `/journal` skills to keep context current across sessions.

## Current state
The living-status-journal system is fully shipped. `proj.sh` scaffolds `STATUS.md` and `journal.yaml` stubs; the `CLAUDE.md` template documents lifecycle frontmatter, journal triggers, and both skills; `skills/sync-status` and `skills/journal` are versioned here and symlinked into `~/.claude/skills/`. All 27 smoke tests pass. DEVOPS-1511 was migrated as the validation case — 39 docs got lifecycle frontmatter, `journal.yaml` backfilled from project notes, and `STATUS.md` generated from scratch.

## Active work
None. The `living-status-journal` task is done.

## Blocked / open questions
None.

## Recent decisions
- 2026-06-04 — Full lifecycle frontmatter schema, journal trigger table, and `/sync-status` + `/journal` skills added to the scaffold. Skills versioned in `skills/` and symlinked globally.

## Key facts
- `proj.sh` is the canonical CLI; use `proj <name>` to scaffold a new workspace.
- Skills install: `ln -s "$(pwd)/skills/sync-status" ~/.claude/skills/sync-status` and same for `journal`.
- `proj.sh --show-claude-md` prints the embedded CLAUDE.md template.
- Smoke tests: `bash scripts/test-proj.sh` (27 assertions).

## Next moves
- Use `proj` to scaffold the next real project workspace and validate the end-to-end flow in anger.
