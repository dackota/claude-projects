# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies.
Assumes the vocabulary in [SKILL.md](SKILL.md) — **module**, **interface**,
**seam**, **adapter**.

Deepening means merging shallow, tightly-coupled modules into one deep module and
moving the test surface to its interface. The blocker is almost always
dependencies: how you test across the seam depends on what the module talks to.
Classify first, then deepen.

## Dependency categories

When assessing a candidate for deepening, classify its dependencies. The category
determines how the deepened module is tested across its seam.

### 1. In-process

Pure computation, in-memory state, no I/O. Always deepenable — merge the modules
and test through the new interface directly. No adapter needed.

### 2. Local-substitutable

Dependencies that have local test stand-ins (PGLite for Postgres, an in-memory
filesystem). Deepenable if the stand-in exists. The deepened module is tested with
the stand-in running in the test suite. The seam is internal; no port at the
module's external interface.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (microservices, internal APIs). Define
a **port** (interface) at the seam. The deep module owns the logic; the transport
is injected as an **adapter**. Tests use an in-memory adapter; production uses an
HTTP/gRPC/queue adapter.

Recommendation shape: *"Define a port at the seam, implement an HTTP adapter for
production and an in-memory adapter for testing, so the logic sits in one deep
module even though it's deployed across a network."*

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. The deepened module
takes the external dependency as an injected port; tests provide a mock adapter.

## Seam discipline

- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't
  introduce a port unless at least two adapters are justified (typically
  production + test). A single-adapter seam is just indirection.
- **Internal seams vs external seams.** A deep module can have internal seams
  (private to its implementation, used by its own tests) as well as the external
  seam at its interface. Don't expose an internal seam through the interface just
  because a test uses it.

## Testing strategy: replace, don't layer

Deepening moves the test surface. Move it — don't stack a new layer on top of the
old one.

- Old unit tests on the shallow modules become waste once tests at the deepened
  module's interface exist — **delete them**. Leaving them creates duplicate,
  implementation-coupled coverage that breaks on every refactor.
- Write new tests at the deepened module's interface. The **interface is the test
  surface**.
- Tests assert on observable outcomes through the interface, not internal state.
- Tests should survive internal refactors — they describe behaviour, not
  implementation. If a test has to change when the implementation changes, it's
  testing past the interface; reshape the interface or the test.

## When the interface isn't obvious

If more than one deepened interface looks plausible, don't guess — explore them in
parallel first. See [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md). Record the chosen
seam and why in `docs/adr/`.
