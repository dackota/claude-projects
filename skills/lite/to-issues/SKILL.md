---
name: to-issues
description: Break a plan, spec, or PRD into tracer-bullet vertical-slice issues, written as self-contained tasks in the local project.yaml. Use when the user wants to convert a plan into issues or break down work. (Lite-flow variant — local tasks only, criteria inline, no journal/Jira/router coupling.)
origin: claude-projects
---

# To Issues (lite)

Break a plan into independently-grabbable **tracer-bullet vertical slices**, written as
self-contained tasks in `project.yaml`. This is the lite-flow variant: tasks are **local
only**, each task carries its own **acceptance criteria inline** (so `/build` needs
nothing else), and there is no journal, Jira, or full-flow router coupling.

## Process

### 1. Gather context

Work from the conversation context and the active PRD in `docs/plans/`. Read `CONTEXT.md`
(the domain glossary) and any ADRs in `docs/adr/` that touch the area.

### 2. Draft vertical slices

Each slice is a thin vertical slice that cuts through ALL integration layers end-to-end —
NOT a horizontal slice of one layer.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests).
- A completed slice is demoable or verifiable on its own.
- Prefer many thin slices over few thick ones.
- **Prefactor first when the change is hard**: if existing structure makes a slice awkward,
  split off a behavior-preserving refactor slice ahead of it — *make the change easy, then
  make the easy change*. The prefactor is its own AFK slice (tests stay green, no behavior
  change).
- **Name the seam** each slice's tests attach at. The lite builder tests only at the named
  seam, so a slice with no seam can't be built AFK — resolve it before publishing.
- **One target repo per slice.** Each slice names the `repo` (under `repos/`) it builds in.
  If a change genuinely needs two repos, that's two slices with a `blocked_by` between them.
</vertical-slice-rules>

**Observability — shift it left into concrete criteria.** For each slice, decide whether it
**authors a request-serving path**: application code that *handles* requests — an HTTP/gRPC
handler, a message/queue consumer, or a background/cron worker loop. (This is about
request-handling *code in the slice*, not infrastructure that provisions or fronts a
service — a k8s `Service`, a Helm/Terraform change, a CI step carry no observability
criteria.) Then act on `project.yaml`'s `observability` block:

- **`enabled: true`** — for each request-serving slice, **read
  `.claude/skills/observability/standard.md` yourself and translate its bar into
  concrete, buildable acceptance criteria** on that slice. Not "meets the observability
  standard" — the builder never reads the standard, so spell it out, e.g.:
  - *Exposes RED metrics: a request counter and a latency histogram labeled by route and
    status; errors counted.*
  - *Emits structured JSON logs on the path, each carrying `trace_id` and `span_id`.*
  - *Wraps each downstream call (DB, outbound HTTP) in a span.*

  This is the whole point of shifting left: the planner reads the standard once and bakes
  specifics into the criteria; the builder just builds what the criteria say.
- **`enabled: false`, `waived` empty, but a slice authors a request-serving path** — the
  **backstop**. Don't silently publish a service with zero observability criteria. Raise it
  in step 4 (default: enable).
- **`waived` non-empty** — already decided; add no observability criteria, don't re-prompt.
- **No request-serving path anywhere** (CLI, library, IaC, docs) — nothing fires; leave the
  `observability` block untouched. The common non-service case.

### 3. Quiz the user

Present the breakdown as a numbered list. Per slice show: **Title**, **Type** (HITL/AFK),
**Repo**, **Blocked by**, and the **user stories/requirements** it covers. Ask:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked HITL vs AFK?
- **If the observability backstop fired**: *"Slice N adds a request-serving path but
  observability is off. Enable it for this project?"*
  - **[Y — recommended, default]**: set `observability.enabled: true` in `project.yaml`, then
    add concrete RED / trace-log / span criteria to every request-serving slice.
  - **[n]**: record a non-empty reason in `observability.waived` (lite has no journal, so the
    reason lives as an inline comment on the `waived:` line — that is the audit trail). No
    silent off: a reason is mandatory.

Iterate until the user approves.

### 4. Coverage map — assert every requirement is owned

Pair each PRD **requirement ID** (`R<n>` in the PRD's `## Requirements`) with the slice(s)
that own it, recorded as each slice's `covers:` list. Assert **every** requirement is owned
by at least one slice — an unowned requirement is the failure class where a feature never
gets built because nothing was responsible for it. If any is unowned: add a slice, fold it
in, or record it out of scope with the user's agreement.

Verify deterministically after writing the tasks:

```
bash .claude/skills/to-issues/coverage-check.sh <prd-path> project.yaml
```

It reads the PRD's `R<n>` IDs and each task's `covers:` and exits non-zero naming any
unowned requirement. Not published until it passes.

### 5. Publish — append self-contained tasks to project.yaml

Append each approved slice to `project.yaml` `tasks:` using the schema below. Unlike the
full flow, the lite task is **self-contained**: the acceptance criteria live **inline** so
`/build` reads nothing but the task. The PRD stays as narrative/requirements context.

<task-schema>
- id: <stable-kebab-id>            # referenced by other tasks' blocked_by
  title: <slice title>
  type: AFK                        # AFK | HITL
  status: todo                     # todo | active | done | blocked
  blocked_by: []                   # task ids that must finish first
  repo: <repo-name>                # target repo under repos/ this slice builds in
  seam: <the public entry point its tests attach at>
  covers: [R1, R4]                 # PRD requirement IDs this slice owns
  plan: docs/plans/<slug>-prd.md   # source PRD for context
  what: >                          # concise end-to-end behavior — not layer-by-layer steps
    <what this slice does>
  acceptance:                      # the build contract: behavioral, independently testable,
    - <criterion 1>                #   checkable through the named seam. Observability folded
    - <criterion 2>                #   in as concrete criteria when the slice serves requests.
  out_of_scope:                    # adjacent behavior a reader might assume but this slice omits
    - <boundary note>
</task-schema>

Write **behavioral** acceptance criteria — what the system does, observable through the
seam — not procedures. They must survive refactors and be independently checkable by the
`lite-checker`. Avoid file paths / line numbers (they go stale).
