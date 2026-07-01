---
name: agent-controls
description: The standard for human-agent systems under control, expressed as a per-agent operating contract (permitted evidence, tool scope, approval, verification, audit, recovery, ownership). Governs this workspace's own pipeline agents now (checked by test-proj.sh). Use to audit an agent definition or design one that touches money/prod/security.
origin: claude-projects
---

# Agent controls

Makes human-agent systems safe **by design** rather than reviewed after an incident.
The canonical bar lives in [standard.md](./standard.md): seven control dimensions
(context rules, tool boundaries, approval gates, verification paths, audit trails,
secret handling, recovery/rollback), the per-agent **operating contract**, and a
production-readiness checklist.

This standard has **two applications** — one active, one deferred.

## Inward — governs this workspace's own agents (active)

Every agent this workspace ships (`.claude/agents/*.md`) is itself a human-agent
system, so each carries an **operating contract** in its frontmatter:

```yaml
contract:
  actor: implementation-validator
  permitted-evidence: [diff range (base...HEAD), changed files, acceptance criteria]
  blocked-actions: [modify files, see implementation rationale, mutating git, network push]
  tool-scope: read-only          # read-only | write | deploy
  approval-rule: none            # none for review-only agents
  required-check: "emits VERDICT block; BLOCK iff CRITICAL>0"
  fallback: "flag rather than pass on ambiguity"
```

`test-proj.sh` asserts every agent carries all seven contract fields and that no
`tool-scope: read-only` agent holds `Write`/`Edit`. The pipeline already satisfies
the control dimensions — this makes them **declared and checkable** rather than
implicit:

| Dimension | How the pipeline satisfies it |
|-----------|-------------------------------|
| Context rules | `/next` hands each gate a diff **range** it fetches itself — never pasted file contents |
| Tool boundaries | reviewers are `tool-scope: read-only`; only `tdd-implementer` is `write` |
| Verification | independent `implementation-validator` / `security-reviewer` gates that never saw the build |
| Audit trails | `run` journal entries record each gate (agent, verdict, rework, approver) |
| Secret handling | ranges-not-contents keeps secrets out of prompts; `security-reviewer` catches secrets in code |
| Recovery | a gate BLOCK loops the slice back to `tdd`; the task never reaches `done` |

## Deliverable-facing — for agent systems a project ships (deferred)

When a scaffolded project *ships* its own human-agent system (e.g. an agent that
inspects infrastructure and drafts a rollback plan but must not execute an
irreversible action without approval), this standard becomes a **gated standard
parallel to `observability`**:

- a `project.yaml` `agent_systems.enabled` flag, dormant otherwise;
- controls surfaced in `grill-with-docs` / `to-prd`, folded into `to-issues`
  acceptance criteria, and built in `tdd`;
- a post-build `agent-controls-reviewer` agent gate (review-only) that BLOCKs a
  slice whose agent violates a BLOCKER-level control, loop-back like the
  observability gate.

**This layer is not wired yet** — build it the day a project actually ships an agent
system, exactly as `observability` stayed dormant until a service project appeared.

## Hand-invoked

Run this skill by hand to audit an agent definition or a proposed human-agent design
against `standard.md` — walk the operating contract and the seven dimensions, and
report gaps (with concrete fixes) and the residual blast radius.
