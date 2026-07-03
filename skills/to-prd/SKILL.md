---
name: to-prd
description: Turn the current conversation context into a PRD, then publish it to Jira or save it as a local plan doc (routed by project.yaml jira_key). Use when user wants to create a PRD from the current context.
origin: claude-projects
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT run a fresh interview — synthesize what you already know. The only check-ins are the two module confirmations in step 2.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the vocabulary from `CONTEXT.md` (the project's domain glossary) throughout the PRD, and respect any ADRs in `docs/adr/` that touch the area you're working in.

   **Observability (service projects).** If `project.yaml` has
   `observability.enabled: true` (or the design clearly ships a runtime service but
   the flag wasn't set in grilling — set it now), capture the observability intent
   in the PRD: the critical paths, any SLOs, and the RED/structured-logging baseline
   from `.claude/skills/observability/standard.md`. Put it in **Implementation
   Decisions** and **Testing Decisions** so `to-issues` can turn it into per-slice
   acceptance criteria. Skip entirely for non-service projects.

2. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Then sketch the **seams** at which you'll test — the interfaces where tests attach to exercise behavior. Prefer an existing seam over inventing one, use the **highest seam** that still exercises the behavior (test through the widest public entry point, not the internals beneath it), and keep the count small — the **ideal number is one**. A deep module's interface is a natural seam. These seams are the contract `to-issues` records per slice and `tdd` tests at, so name them precisely.

Check with the user that these modules and seams match their expectations. Check with the user which modules they want tests written for.

3. Write the PRD using the template below, then route it per `project.yaml`:

   - **`jira_key` is set** → publish the PRD to the Jira project and apply the `ready-for-agent` label. No further triage needed.
   - **`jira_key` is empty** → save the PRD as `docs/plans/<slug>-prd.md` with the workspace's lifecycle frontmatter (`status: active`).
   - Use GitHub Issues only when explicitly asked to.

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Requirements

The enumerated, checkable list of what this feature must do — the universe
`to-issues` maps to slices and `coverage-check.sh` verifies is fully owned. Each is a
stable-ID behavioral requirement:

- R1: <what the system must do>
- R2: <...>

Derive them from the user stories **and** — critically — from the *implied behavior of
every schema field, config option, and external input* in the Implementation Decisions
below. A data field almost always implies a behavior that produces or consumes it (a
`FileGlob` field implies "glob patterns are expanded"); that implied behavior is the
class that escapes to production when no slice owns it, because no build gate reviews a
diff that was never written. Give each such behavior its own `R<n>`, not just the field.
IDs are stable and never reused; keep numbering monotonic even across revisions.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- **The seams tests will attach at** (from step 2 — prefer existing, highest seam, ideal number is one). `to-issues` carries these into each slice's acceptance criteria.
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>
