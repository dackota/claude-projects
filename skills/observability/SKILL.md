---
name: observability
description: The project's observability standard (RED metrics, structured JSON logging, OpenTelemetry) and its post-build gate. Dormant unless project.yaml sets observability.enabled — then planning, building, and the /next gate enforce it for runtime services. Use to audit or plan observability for a service, or when the user mentions RED metrics, OTel, tracing, or structured logging.
origin: claude-projects
agents:
  - otel-observability-engineer
---

# Observability

Makes scaffolded **services** observable by design rather than reviewed after the
fact. The canonical bar lives in [standard.md](./standard.md); this file is the
contract the lifecycle phases and the gate follow.

## Activation — the project.yaml flag

Everything here is **dormant** unless `project.yaml` carries:

```yaml
observability:
  enabled: true
  otlp_endpoint: ""     # OTLP Collector endpoint (or OTEL_EXPORTER_OTLP_ENDPOINT)
  service_name: ""      # resource attribute; defaults to the project name
```

`enabled` is set during design (`grill-with-docs` / `to-prd`) once the project is
known to ship a runtime service. A non-service project (CLI, IaC, docs, library)
leaves it `false` and nothing below activates. Even when enabled, RED applies only
to tasks that add request-serving paths — a task with no handler has nothing to
enforce.

## How the standard reaches each phase (when enabled)

Each phase skill loads `standard.md` **only when the flag is on** — the standard
stays DRY (one source) and off the always-on context path.

| Phase | Reads standard.md to… |
|-------|------------------------|
| **grill-with-docs / to-prd** | surface SLOs and critical paths as design intent; set the flag |
| **to-issues** | add observability acceptance criteria to service tasks (RED on new paths, structured logs w/ trace correlation, spans on downstream calls) |
| **tdd / tdd-implementer** | build the instrumentation + its tests alongside the feature |
| **/next post-build gate** | run `otel-observability-engineer` to verify the diff |

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
