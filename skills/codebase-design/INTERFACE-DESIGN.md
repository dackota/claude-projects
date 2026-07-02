# Interface Design

How to shape a single module's interface for **depth** and testability. Assumes
the vocabulary in [SKILL.md](SKILL.md) — **module**, **interface**, **seam**,
**adapter**, **leverage**, **locality**.

This is the solo-designer companion to [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md):
use the heuristics here when shaping one interface; escalate to parallel agents
when the choice is genuinely hard.

## Write the whole interface down

The interface is **everything a caller must know**, not just the type signature.
Before you code, enumerate:

- **Signature** — entry points, params, return types.
- **Invariants** — what the module guarantees and what it requires of callers.
- **Ordering constraints** — must anything be called before/after anything else?
- **Error modes** — every way it can fail, and how failure surfaces (return,
  throw, result type).
- **Required configuration** — what must be supplied for it to work at all.
- **Performance characteristics** — cost, blocking behaviour, allocation.

An interface with hidden invariants is **shallow** even when the signature looks
small — callers still have to learn the hidden facts. Depth means the caller
learns little *and* the hidden facts don't leak.

## Aim for depth

When you have a draft interface, push it deeper. Ask:

- Can I **reduce the number of entry points**? Merge two methods that always fire
  together; drop one nobody calls.
- Can I **simplify the parameters**? Replace a bag of primitives with one named
  type; give the common case a sensible default.
- Can I **hide more complexity inside**? Every decision the caller doesn't have to
  make is depth gained.

Deep = small interface over rich implementation. Shallow = interface nearly as
complex as the implementation (a pass-through). See the diagram in
[SKILL.md](SKILL.md).

## Design for testability

Testability and depth pull the same direction: a deep interface is a small,
honest test surface. Follow these rules.

1. **Accept dependencies, don't create them.** Inject what the module talks to so
   a test can substitute it.

   ```typescript
   // Testable
   function processOrder(order, paymentGateway) {}

   // Hard to test — the gateway is welded in
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't mutate.** A returned value is directly assertable; a
   mutation is observable only by inspecting state afterwards.

   ```typescript
   // Testable
   function calculateDiscount(cart): Discount {}

   // Hard to test
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Keep the surface small.** Fewer entry points → fewer tests. Fewer params →
   simpler setup.

4. **Model errors in the interface.** Failure is part of the contract, not a
   surprise. Prefer explicit result/error types over exceptions that callers must
   discover by reading the implementation.

5. **The interface is the test surface.** Test through it, assert on observable
   outcomes, never on internal state. If a test has to reach *past* the interface,
   the module is the wrong shape — reshape it before writing the test.

## Design lenses

Before committing to a shape, view your draft through each lens below. These are
the same constraints [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md) hands to parallel
agents — run them in your own head when the stakes don't justify a full spawn:

- **Minimize the interface** — 1–3 entry points, maximum leverage per entry point.
- **Maximize flexibility** — where would extension points actually pay off?
- **Optimize the common caller** — make the default case trivial to invoke.
- **Ports & adapters** — if the module crosses a seam to a dependency (see
  [DEEPENING.md](DEEPENING.md)), does a port belong here?

If two lenses produce genuinely different, both-plausible interfaces, stop
choosing by hand and run [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md).

## Name with the domain

The design terms (module, seam, adapter…) describe the *shape*. The interface's
own names — types, methods, params — should use `CONTEXT.md` vocabulary so the
interface reads in the project's domain language. Keep the two consistent.

## Checklist

Before you consider an interface done:

- [ ] Full interface written down: signature, invariants, ordering, errors,
      config, performance
- [ ] Dependencies accepted, not created
- [ ] Returns results; no hidden mutation
- [ ] Smallest surface that delivers the behaviour
- [ ] Common case is trivial to call
- [ ] Errors modelled explicitly
- [ ] Deletion test passes — deleting the module would re-spread complexity
- [ ] Names align with `CONTEXT.md`; a worthwhile seam decision is captured in
      `docs/adr/`
