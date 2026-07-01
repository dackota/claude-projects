---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable tracer-bullet vertical slices, published as Jira issues or local project.yaml tasks (routed by project.yaml jira_key). Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
origin: claude-projects
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the vocabulary from `CONTEXT.md` (the project's domain glossary), and respect any ADRs in `docs/adr/` that touch the area you're working in.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

**Observability (service projects only).** If `project.yaml` has
`observability.enabled: true`, then for any slice that adds a **request-serving
path** (HTTP/gRPC handler, message consumer, background/cron job), fold the
observability baseline into that slice's **acceptance criteria** — read
`.claude/skills/observability/standard.md` and add concrete criteria: RED metrics
(rate/errors/duration) on the new path, structured JSON logs with `trace_id`/`span_id`,
and spans around downstream calls. This is what makes observability designed-in: the
build satisfies it and the post-build gate verifies it. Slices with no request path
(and all slices when the flag is off) get no observability criteria.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the approved slices

Where the slices land is driven by `project.yaml`:

**`jira_key` is set → Jira.** Publish each slice as a Jira issue using the body template below. Label each issue `afk` or `hitl` to mirror its type, and add `ready-for-agent` to AFK issues **only** — never HITL, since a human must engage first. Publish in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

**`jira_key` is empty → local `project.yaml` tasks.** Append each slice to the `tasks` list using the task schema below. Keep the full "What to build" and acceptance criteria in the source plan/PRD doc — the task entry stays a thin pointer (`type` is the AFK/HITL marker; no labels needed locally).

Use GitHub Issues only when explicitly asked to.

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

For the local path, append a thin task entry per slice:

<task-schema>
- id: <stable-kebab-id>            # referenced by other tasks' blocked_by
  title: <slice title>
  type: AFK                        # AFK | HITL
  status: todo                     # todo | active | done | blocked
  blocked_by: []                   # task ids that must finish first
  plan: docs/plans/<slug>-prd.md   # the source PRD/plan
  jira: null
</task-schema>

Do NOT close or modify any parent issue.
