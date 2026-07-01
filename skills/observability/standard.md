# Observability standard

Two layers, both language- and backend-agnostic (apply them with the project's own
logger, metrics, and OTel SDK):

- **Baseline** — logging and error hygiene **every project** follows, service or
  not. Applied by the build discipline (`tdd`) on every task, regardless of the
  flag. Failures should be diagnosable from the logs alone.
- **Service standard** — the full instrumentation bar for **runtime services**,
  gated by `project.yaml` `observability.enabled: true` (see [SKILL.md](./SKILL.md)).

## Baseline — every project

Good even in a CLI, library, or batch job:

- **Structured logs.** Emit logs as single-line JSON to **stdout** via a structured
  logger (slog, zap, pino, winston, structlog, Serilog, …) — never
  printf/console.log/println. Include at least `timestamp` (ISO8601 UTC), `level`,
  and `message`.
- **Correct levels.** Errors at ERROR, not INFO; don't log at a level that hides a
  real problem or cries wolf.
- **Never swallow errors.** Every caught error is handled or propagated, with enough
  context (which operation, which inputs) to diagnose it. No empty catch, no bare
  `except: pass`.
- **No secrets or PII in logs.**

## Service standard — runtime services only

Applies when `observability.enabled: true` and the code serves requests
(HTTP/gRPC/messages) or runs as a long-lived process. Everything below is **in
addition to** the baseline.

### RED is the floor

Every request-serving path (HTTP, gRPC, message consumer, background/cron job)
emits, at minimum:

- **Rate** — a counter of requests/operations handled.
- **Errors** — a count (or a labeled subset of the rate counter) of failures,
  distinguishing client (4xx) from server (5xx) where applicable.
- **Duration** — a histogram of request latency.

A request-serving path missing any of the three is a **BLOCKER**.

### OpenTelemetry is the instrumentation standard

- Instrument with the OTel API/SDK, not vendor-specific or ad-hoc code.
- Export **OTLP to a Collector** — never couple the app to a specific backend. The
  concrete endpoint comes from `project.yaml` `observability.otlp_endpoint` (or the
  `OTEL_EXPORTER_OTLP_ENDPOINT` env var). **No backend is assumed.**
- Prefer auto-instrumentation libraries (http, grpc, db clients) where they exist;
  supplement with manual spans around business-critical operations.
- One root span per request; propagate context across async/thread/goroutine
  boundaries; record errors on spans (record-exception + set status = error).

### Trace-correlated logs

Within a request context, every log line also carries `service.name`, `trace_id`,
and `span_id` so logs join up with traces.

### Semantic conventions

Use standard OTel attribute names (`http.request.method`,
`http.response.status_code`, `url.path`, `server.address`, `rpc.system`,
`messaging.system`, `db.system`, …) — don't invent attributes when a convention
exists. Set resource attributes (`service.name`, `service.version`,
`deployment.environment`) at SDK init.

### Cardinality safety

Never use unbounded values as metric labels (user IDs, request IDs, raw paths with
embedded IDs). Route raw paths through templates (`/users/{id}`). High-cardinality
labels are the most common production mistake.

### SDK lifecycle

Initialize the Tracer/Meter/Logger providers once at startup with the OTLP exporter
configured, and **flush/shut down gracefully on exit** so no telemetry is lost.
Missing shutdown/flush is the second most common mistake.

### Testing the instrumentation

Because service observability lands as acceptance criteria, its tests arrive with
the slice: assert the rate counter increments on a request and the error counter on
a failure; assert a log line parses as JSON and carries `trace_id`/`span_id` within
a request context. Test the observable behavior (a signal is emitted), not exporter
internals.
