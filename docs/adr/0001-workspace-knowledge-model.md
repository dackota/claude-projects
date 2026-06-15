---
status: accepted
date: 2026-06-15
---

# Workspace records knowledge as a glossary + ADRs, and work as `project.yaml` tasks

Scaffolded workspaces carried two unconnected documentation systems: a
living-status layer (plans, journal, `STATUS.md`) and a domain-knowledge layer
that several skills assumed but the scaffold never created (`CONTEXT.md` glossary
+ `docs/adr/`). We adopted the domain layer into the scaffold, collapsed
"decision records" into a journal line (the log) plus an ADR (the only decision
*document*, gated by the three-part test), and routed tracker-less work into
`project.yaml` tasks rather than loose docs — so every artifact has exactly one
home, wired into the status synthesis.

## Considered options

- **Strip the glossary/ADR references out of the skills** instead of adopting
  them — rejected; it discards the more capable skills to match the weaker
  scaffold.
- **Keep `docs/decisions/` as a middle tier** between the journal line and the
  ADR — rejected; the three-gate test already discriminates what deserves a
  document, so a middle tier is speculative generality (YAGNI).
- **Save tracker-less issues as loose `docs/plans/*.md`** — rejected; they would
  be invisible to the journal and `/sync-status`, which key off `project.yaml`
  tasks.

## Consequences

- `docs/decisions/` is removed; `/sync-status` and the journal hook point at
  `docs/adr/`, and "Recent decisions" is sourced from the journal, not by
  scanning ADRs.
- `grill-me` is removed in favor of `grill-with-docs` as the single grilling
  skill.
- `project.yaml.tasks` gains a defined schema (`id`, `title`, `type`, `status`,
  `blocked_by`, `plan`, `jira`) that the journal, `/sync-status`, and `/tdd` all
  key off.
- ADRs and `CONTEXT.md` are exempt from the living-status lifecycle frontmatter
  and from `/sync-status`'s active-doc scan; they follow their own minimal
  formats.
