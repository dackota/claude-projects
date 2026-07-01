---
name: sync-status
description: Regenerate STATUS.md for a claude-projects workspace from its authoritative inputs. Use when a significant change has landed (plan/decision/task-status/blocker) AND you've reached a natural pause (handing back, finishing a work block) — the conjunction is deliberate.
origin: claude-projects
---

# /sync-status

Full regenerate of `STATUS.md` from authoritative inputs. Read-only on every source file; only `STATUS.md` is written.

## When to run

Run — or invoke automatically — when **both** conditions hold:

1. A significant change occurred: plan finalized or revised, decision committed, task status flipped in `project.yaml`, meaningful blocker recorded, doc superseded.
2. A natural pause has arrived: about to hand back to the user, or finishing a logical work block.

The conjunction is deliberate — do not sync after every individual doc edit, and do not skip sync at session handoff when meaningful work happened.

## Inputs read (in order)

1. `PROJECT.md` — one-sentence goal extracted from the Goals section.
2. `project.yaml` — repo list, Jira key, and `tasks` (status `active` → "Active work", `blocked` → "Blocked / open questions").
3. `journal.yaml` — all entries, most recent first for "Recent decisions"; the
   `type: run` entries feed the "Pipeline health" rollup.
4. Frontmatter of every doc in `docs/plans/`, `docs/research/`, and `docs/validations/` — to identify `status: active` docs. `docs/adr/` and `CONTEXT.md` are NOT scanned here; decisions surface via the journal.
5. Full body of every `status: active` doc — to synthesize current state and extract blockers/next moves.

Non-`active` docs (superseded, done, abandoned) are skipped unless explicitly referenced by an active doc's `related` field.

## Output format

Overwrite `STATUS.md` at the project root with:

```markdown
---
last_synced: <ISO-8601 timestamp>
---

# Status

## Goal
<one sentence from PROJECT.md Goals section>

## Current state
<2–4 sentences synthesizing where the project actually is right now>

## Active work
- <Jira key> — <summary>: <brief state> ([plan](docs/plans/foo.md))
- ... (only items with status: active or in-flight in project.yaml)

## Blocked / open questions
- <item> — <why blocked or unresolved>
- ...

## Recent decisions
- <YYYY-MM-DD> — <summary> ([adr](docs/adr/0001-foo.md))
- ... (last 3–5 from journal.yaml with type: decision)

## Key facts
- <load-bearing constraint or invariant learned through the project>
- ...

## Pipeline health
- Runs: <total> gate runs — block rate <pct>% (<blocks>/<total>)
- Rework: <avg> loop-backs per task; <n> task(s) looped back
- By gate: acceptance <blocks>/<runs>, security <blocks>/<runs>, observability <blocks>/<runs>
- <task-id> reworked <k>× — <the gate that keeps blocking it>

## Next moves
- <actionable next step>
- ...
```

Target size: ~350–500 tokens. Dense and link-heavy. Every active work item and next move should link to its plan or decision doc.

**Pipeline health** is the loop's "Learn" surface — a rollup of `journal.yaml`
`type: run` entries (block rate, rework rate, which gate blocks most, which tasks
rework most). Omit the whole section when there are no `run` entries yet; when there
are, keep it to a few rolled-up lines — never list every run.

## Bootstrap behavior

On first run (or when files are missing):

- If `STATUS.md` is absent: create it.
- If `journal.yaml` is absent: create it as `[]` (empty YAML list).
- If a doc's frontmatter is missing `status`: treat as `active` (safe default).

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/sync-status" ~/.claude/skills/sync-status
```
