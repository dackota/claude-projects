---
name: codebase-design
description: Vocabulary and principles for designing deep modules — rich behaviour behind a small interface at a clean seam. Use when designing or improving a module's interface, placing a seam, or making code more testable or AI-navigable.
origin: claude-projects
---

# Codebase Design

Design **deep modules**: a lot of behaviour behind a small interface, placed at a
clean seam, testable through that interface. Use this language and these
principles wherever code is being designed or restructured. The aim is
**leverage** for callers, **locality** for maintainers, and testability for
everyone.

This file is the home for the vocabulary. Other skills reference it. The three
supporting files go deeper: [interface design](INTERFACE-DESIGN.md) (shaping one
interface), [deepening](DEEPENING.md) (merging shallow modules given their
dependencies), and [design it twice](DESIGN-IT-TWICE.md) (exploring several
interfaces in parallel before committing).

## Glossary

Use these terms exactly — don't substitute "component," "service," "API," or
"boundary." Consistent language is the whole point. These are the **design**
terms; the project's domain nouns and verbs live in `CONTEXT.md`. Keep the two
aligned: name a module's interface with `CONTEXT.md` vocabulary, describe its
shape with the terms below.

**Module** — anything with an interface and an implementation. Deliberately
scale-agnostic: a function, class, package, or tier-spanning slice. _Avoid_:
unit, component, service.

**Interface** — everything a caller must know to use the module correctly: the
type signature, but also invariants, ordering constraints, error modes, required
configuration, and performance characteristics. _Avoid_: API, signature (too
narrow — they refer only to the type-level surface).

**Implementation** — what's inside a module, its body of code. Distinct from
**Adapter**: a thing can be a small adapter with a large implementation (a
Postgres repo) or a large adapter with a small implementation (an in-memory
fake). Reach for "adapter" when the seam is the topic; "implementation"
otherwise.

**Depth** — leverage at the interface: the amount of behaviour a caller (or test)
can exercise per unit of interface they have to learn. A module is **deep** when a
large amount of behaviour sits behind a small interface, **shallow** when the
interface is nearly as complex as the implementation.

**Seam** _(Michael Feathers)_ — a place where you can alter behaviour without
editing in that place; the *location* at which a module's interface lives. Where
to put the seam is its own design decision, distinct from what goes behind it.
_Avoid_: boundary (overloaded with DDD's bounded context).

**Adapter** — a concrete thing that satisfies an interface at a seam. Describes
*role* (what slot it fills), not substance (what's inside).

**Leverage** — what callers get from depth: more capability per unit of interface
they learn. One implementation pays back across N call sites and M tests.

**Locality** — what maintainers get from depth: change, bugs, knowledge, and
verification concentrate in one place rather than spreading across callers. Fix
once, fixed everywhere.

## Deep vs shallow

**Deep module** = small interface + lots of implementation:

```
┌─────────────────────┐
│   Small Interface   │  ← few entry points, simple params
├─────────────────────┤
│                     │
│  Deep Implementation│  ← complex behaviour hidden
│                     │
└─────────────────────┘
```

**Shallow module** = large interface + little implementation (avoid):

```
┌─────────────────────────────────┐
│       Large Interface           │  ← many methods, complex params
├─────────────────────────────────┤
│  Thin Implementation            │  ← just passes through
└─────────────────────────────────┘
```

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module
  can be internally composed of small, mockable, swappable parts — they just
  aren't part of the interface. A module can have **internal seams** (private to
  its implementation, used by its own tests) as well as the **external seam** at
  its interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it
  was a pass-through and wasn't hiding anything. If complexity reappears across N
  callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. If
  you want to test *past* the interface, the module is probably the wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't
  introduce a seam unless something actually varies across it (typically
  production + test).

## Designing for testability

Deep interfaces make testing natural. Three rules, expanded in
[interface design](INTERFACE-DESIGN.md):

1. **Accept dependencies, don't create them.**

   ```typescript
   // Testable — the gateway is injected
   function processOrder(order, paymentGateway) {}

   // Hard to test — the gateway is created inside
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't mutate.**

   ```typescript
   // Testable — assert on the return value
   function calculateDiscount(cart): Discount {}

   // Hard to test — observable only as a side effect
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Keep the surface small.** Fewer entry points → fewer tests. Fewer params →
   simpler setup.

## Relationships

- A **Module** has exactly one **Interface** (the surface it presents to callers
  and tests).
- **Depth** is a property of a **Module**, measured against its **Interface**.
- A **Seam** is where a **Module**'s **Interface** lives.
- An **Adapter** sits at a **Seam** and satisfies the **Interface**.
- **Depth** produces **Leverage** for callers and **Locality** for maintainers.

## Rejected framings

- **Depth as ratio of implementation-lines to interface-lines** (Ousterhout):
  rewards padding the implementation. We use depth-as-leverage instead.
- **"Interface" as the language `interface` keyword or a class's public methods**:
  too narrow — interface here includes every fact a caller must know.
- **"Boundary"**: overloaded with DDD's bounded context. Say **seam** or
  **interface**.

## Going deeper

- **Shaping one interface for depth and testability** — see
  [interface design](INTERFACE-DESIGN.md).
- **Deepening a cluster given its dependencies** — see [deepening](DEEPENING.md):
  dependency categories, seam discipline, and replace-don't-layer testing.
- **Exploring alternative interfaces** — see [design it twice](DESIGN-IT-TWICE.md):
  spin up parallel sub-agents to design the interface several radically different
  ways, then compare on depth, locality, and seam placement.

When a design decision is worth recording — where a seam goes, why a module is
deep, which framing won — capture it as an ADR under `docs/adr/`.
