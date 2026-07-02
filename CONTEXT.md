# claude-projects

The scaffolder and conventions for Claude Code project workspaces. This glossary
pins the vocabulary the CLI, the bundled skills, and the workspace template all
share, so the language stays consistent as pieces are added over time.

## Language

**Project**:
The body of work and its goal — the *why*. A feature, migration, or investigation
worth tracking across multiple sessions. Described in `PROJECT.md`, configured in
`project.yaml`.
_Avoid_: using "project" for the directory (that is the Workspace) or for this repo
(that is the Scaffolder).

**Workspace**:
The directory Claude Code operates inside — the *where*. Holds exactly one project's
docs, journal, status synthesis, cloned repos, and worktrees.
_Avoid_: project, repo.

**Scaffolder**:
This repo (`claude-projects`) — the `proj` CLI plus the bundled skills it copies into
new workspaces. It is neither a project nor a workspace.
_Avoid_: bootstrap repo (informal only).

**Skill**:
A capability bundled in `skills/<name>/` and copied into a workspace's
`.claude/skills/`. Invoked as a slash command.

**Vertical slice**:
A thin unit of work that cuts end-to-end through every layer (schema, API, UI,
tests) and is demoable on its own. The unit `to-issues` produces and `/tdd`
implements one test at a time.
_Avoid_: horizontal slice (the anti-pattern: one layer across the whole feature).

**Task**:
A vertical slice tracked locally as an entry in `project.yaml` — the work the
journal and status synthesis follow as it moves through `todo → active → done`.
When a project uses Jira, the same slice is mirrored as a Jira issue.
_Avoid_: ticket; "issue" when you mean the local entry (an Issue lives in a tracker).

**Journal entry**:
A single append-only line in `journal.yaml` recording that a significant event
happened (a decision, plan, blocker, PR, etc.) with a date, type, and one-sentence
summary. The log of *what changed, when* — never the full reasoning.
_Avoid_: changelog, history.

**ADR**:
The single durable document recording a decision and the reasoning behind it. Written
only when the decision is hard to reverse, surprising without context, and the result
of a real trade-off. Lives in `docs/adr/`.
_Avoid_: decision record, decision doc.

**Status synthesis**:
The regenerated current-state view (`STATUS.md`) Claude reads first each session. A
*view* derived from the project's sources, never a source of truth itself.
_Avoid_: status report, summary.
