---
name: observability
description: The project's observability standard (RED metrics, structured JSON logging, OpenTelemetry); dormant unless project.yaml sets observability.enabled. Use when auditing or planning observability for a runtime service.
origin: claude-projects
agents:
  - otel-observability-engineer
---

# Observability

Makes software observable by design rather than reviewed after the fact. The
canonical bar lives in [standard.md](./standard.md), which has **two layers**:

- **Baseline** — logging/error hygiene (structured logs, correct levels, no
  swallowed errors) that `tdd` applies to **every** build, service or not,
  regardless of the flag below. It's build discipline, not gated.
- **Service standard** — RED metrics, OTLP export, tracing, SDK lifecycle. This is
  what the flag gates.

## Activation — the project.yaml flag (gates the service standard)

The **Service standard** is **dormant** unless `project.yaml` carries:

```yaml
observability:
  enabled: true
  otlp_endpoint: ""     # OTLP Collector endpoint (or OTEL_EXPORTER_OTLP_ENDPOINT)
  service_name: ""      # resource attribute; defaults to the project name
```

`enabled` is set during design (`grill-with-docs` / `to-prd`) once the project is
known to ship a runtime service. A non-service project (CLI, IaC, docs, library)
leaves it `false` — it still gets the baseline, but none of the service standard
below activates. Even when enabled, RED applies only to tasks that add
request-serving paths — a task with no handler has nothing to enforce.

## How each layer reaches the phases

The **baseline** rides in `tdd`'s build discipline on every task — no flag, no file
lookup required. The **service standard** activates only when the flag is on, and
those phases load `standard.md` on demand (DRY, one source, off the always-on
context path).

| Phase | Layer | Behavior |
|-------|-------|----------|
| **tdd / tdd-implementer** | baseline | Always: structured logs, correct levels, no swallowed errors |
| **grill-with-docs / to-prd** | service | Surface SLOs and critical paths; set the flag |
| **to-issues** | service | Add observability acceptance criteria to service tasks (RED, trace-correlated logs, spans) |
| **tdd / tdd-implementer** | service | Build the instrumentation + its tests when a criterion calls for it |
| **/next post-build gate** | service | Run `otel-observability-engineer` to verify the diff |

## The gate

For a **service task**, `/next` spawns `otel-observability-engineer` right after the
build, **in parallel with** `implementation-validator` (both review-only). It
returns a machine-readable verdict; a **BLOCKER** (missing RED, unstructured
logging) loops the task back to `tdd` exactly like an acceptance gap, while
HIGH/MEDIUM/LOW are recorded but pass. The agent definition holds the verdict
format `/next` parses.

## Hand-invoked

Run this skill by hand to audit or plan instrumentation for a service outside the
`/next` flow — the agent maps boundaries, checks the RED baseline, and reports gaps
(with concrete fixes) against `standard.md`.
