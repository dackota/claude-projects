---
name: codebase-researcher
description: Read-only codebase mapper. Trace execution paths, map architecture layers, and surface dependencies and risks for a subsystem or feature area, then capture the findings as a research doc. Use to understand existing code before deciding how to change it, or when a grilling session hits a deep unknown worth researching.
origin: claude-projects
---

# /codebase-researcher

Map a codebase — or one feature area within it — so a plan can be made on solid
ground. This is a **read-only** investigation: it traces how the code actually
works and writes up what it found. It never edits code.

Research is **not** a forced phase. `grill-with-docs` already explores the
codebase while sharpening a plan; reach for this skill when a question needs more
depth than the grill should carry inline — a gnarly subsystem, an unfamiliar
integration, a "how does X actually work?" that would derail the interview.

## What to investigate

Scope to the subsystem or feature area in question — do not boil the ocean.

- **Execution paths** — trace the real flow for the behavior in question, entry
  point to effect (request → handler → service → store, or CLI → command →
  side effect). Cite `path:line` for each hop.
- **Architecture layers** — the modules involved and their boundaries; which are
  deep (small interface, lots behind it) and which are shallow.
- **Dependencies** — what this area depends on and what depends on it (the blast
  radius of a change), including external libraries and services.
- **Risks & landmines** — implicit invariants, shared mutable state, missing
  tests, surprising couplings, anything that would make a change dangerous.
- **Prior art** — existing patterns to follow so new work matches the codebase.

Use the vocabulary from `CONTEXT.md` (the project's domain glossary) for the
concepts you describe, and note any contradiction you find between the code and a
documented decision in `docs/adr/`.

## Output

Write a research doc to `docs/research/<topic>.md` with the workspace's lifecycle
frontmatter (`status: active`). Structure it around the sections above, lead with
a short summary of what the area does and how, and end with the open questions or
risks a plan must address. After finalizing it, record a `research` entry in
`journal.yaml` (or via `/journal research "<summary>"`).

For a quick, in-conversation map that doesn't warrant a doc, you may answer
inline instead — but if the findings will inform a plan or PRD, write the doc so
the next session inherits it.

## Boundaries

- **Read-only.** No `Write`/`Edit` to code — only the research doc (and journal)
  is written. If the investigation suggests a change, that belongs in a plan, not
  here.
- **Scoped.** Map the area asked about, not the whole repo.
- **Grounded.** Cite `path:line`; trace real code rather than assuming behavior
  from names.

## Install (one-time per machine)

```bash
ln -s "$(pwd)/skills/codebase-researcher" ~/.claude/skills/codebase-researcher
```
