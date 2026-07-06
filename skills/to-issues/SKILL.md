---
name: to-issues
description: Break a plan, spec, or PRD into tracer-bullet vertical-slice issues, published to Jira or local project.yaml tasks. Use when the user wants to convert a plan into issues, create implementation tickets, or break down work.
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
- **Prefactor first when the change is hard**: if existing structure makes a slice awkward, split off a behavior-preserving refactor slice ahead of it — *make the change easy, then make the easy change*. The prefactor is its own AFK slice with its own criteria (tests stay green, no behavior change).
- **Name the seam** each slice's tests attach at (from the PRD's testing decisions). `tdd` tests only at a named seam, so a slice with no named seam can't be built AFK — resolve the seam before publishing, not during the build.
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

### 5. Coverage map — assert every requirement is owned

Build a **coverage map** pairing each PRD **requirement ID** (the `R<n>` list in the
PRD's `## Requirements`) with the slice(s) that own it, and **record the owned IDs on
each slice** as a `covers:` list. Then **assert every requirement is owned by at least
one slice.** If any requirement has no owner, stop — add a slice that owns it, fold it
into an existing slice, or record it explicitly as out of scope with the user's
agreement. Never publish with an unowned requirement: a requirement no slice owns is the
failure class where a feature reaches production because nothing was responsible for
building it — it passes every build gate because there is no diff to review.

This is not eyeballed prose — it is **verified deterministically**. On the local path,
after writing the tasks in step 6, run:

```
bash .claude/skills/to-issues/coverage-check.sh <prd-path> project.yaml
```

It reads the PRD's `R<n>` IDs and each slice's `covers:` and exits non-zero, naming any
unowned requirement. Do not consider the breakdown published until it passes. (On the
Jira path there is no local `project.yaml` to check — present the `requirement → slice`
map for the user to confirm, and put the covered IDs in each issue body.)

### 6. Publish the approved slices

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

State each as a **behavioral** outcome — what the system does, observable through the named seam — not a procedure (steps to take). Behavioral criteria survive refactors and stay checkable by the post-build acceptance gate. Each criterion must be **independently testable**, and the criteria as a whole name the seam they're verified through (from the PRD's testing decisions). Avoid file paths and line numbers — they go stale.

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Covers

The PRD requirement IDs (`R<n>`) this slice owns — the coverage map's record on the
issue. Every requirement must appear on at least one slice.

## Out of scope

The adjacent behavior a reader might assume this slice covers but it does not. Keeps the slice's boundary explicit for the builder and the acceptance gate.

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
  covers: [R1, R4]                 # PRD requirement IDs this slice owns (coverage-check.sh verifies every R is owned)
  plan: docs/plans/<slug>-prd.md   # the source PRD/plan
  jira: null
  # release: true                  # optional — marks a release/deploy task so /next's
  #                                #   Land phase runs release-verify (see the next skill)
</task-schema>

Do NOT close or modify any parent issue.
