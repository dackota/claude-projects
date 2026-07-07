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

## Always bundled, dormant by flag

This skill and the `otel-observability-engineer` agent ship in **every** scaffold, so
the machinery is present the instant a project turns out to ship a service — the flag
can flip on mid-project without a missing skill. Nothing about the **Service standard**
activates, though, until `project.yaml` carries:

```yaml
observability:
  enabled: true         # gates the service standard below
  waived: ""            # non-empty reason ⇒ explicit "no observability" decision (no re-prompt)
  otlp_endpoint: ""     # OTLP Collector endpoint (or OTEL_EXPORTER_OTLP_ENDPOINT)
  service_name: ""      # resource attribute; defaults to the project name
```

`enabled` is set the moment the project is known to ship a runtime service — early at
design (`grill-with-docs` / `to-prd`), or at the latest by `to-issues`, which runs a
**backstop**: if a slice authors a request-serving path while `enabled: false` and
`waived` is absent or empty, it stops and forces an explicit decision — enable (the default), or
record a `waived` reason (no silent off). A non-service project (CLI, IaC,
Helm/Terraform, docs, library) leaves it `false` with `waived: ""` and is **never
prompted** — it still gets the baseline, but none of the service standard activates.
Even when enabled, RED applies only to tasks that add request-serving paths — a task
with no handler has nothing to enforce. `--otel` at scaffold just pre-sets
`enabled: true` for a project already known to be a service.

## How each layer reaches the phases

The **baseline** rides in `tdd`'s build discipline on every task — no flag, no file
lookup required. The **service standard** activates only when the flag is on, and
those phases load `standard.md` on demand (DRY, one source, off the always-on
context path).

| Phase | Layer | Behavior |
|-------|-------|----------|
| **tdd / tdd-implementer** | baseline | Always: structured logs, correct levels, no swallowed errors |
| **grill-with-docs / to-prd** | service | Surface SLOs and critical paths; set the flag |
| **to-issues** | service | Backstop: detect a request-serving slice **regardless of the flag** — add observability acceptance criteria (RED, trace-correlated logs, spans) when enabled, else force an enable/`waived` decision |
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
