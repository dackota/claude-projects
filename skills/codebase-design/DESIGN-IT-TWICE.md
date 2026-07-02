# Design It Twice

When the interface for a chosen deepening candidate isn't obvious, explore several
in parallel before committing. Based on "Design It Twice" (Ousterhout) — your first
idea is unlikely to be the best.

Uses the vocabulary in [SKILL.md](SKILL.md) — **module**, **interface**, **seam**,
**adapter**, **leverage**. The sub-agents below are generic: spawn them with the
Agent tool and a per-agent brief. This skill defines no agents of its own.

## Process

### 1. Frame the problem space

Before spawning sub-agents, write a user-facing explanation of the problem space
for the chosen candidate:

- The constraints any new interface would need to satisfy.
- The dependencies it would rely on, and which category they fall into (see
  [DEEPENING.md](DEEPENING.md)).
- A rough illustrative code sketch to ground the constraints — not a proposal,
  just a way to make the constraints concrete.

Show this to the user, then immediately proceed to Step 2. The user reads and
thinks while the sub-agents work in parallel.

### 2. Spawn sub-agents

Spawn 3+ sub-agents in parallel using the Agent tool. Each must produce a
**radically different** interface for the deepened module.

Prompt each with a separate technical brief — file paths, coupling details, the
dependency category from [DEEPENING.md](DEEPENING.md), and what sits behind the
seam. The brief is independent of the user-facing framing in Step 1. Give each
agent a different design constraint:

- **Agent 1 — minimize the interface.** Aim for 1–3 entry points max. Maximize
  leverage per entry point.
- **Agent 2 — maximize flexibility.** Support many use cases and extension points.
- **Agent 3 — optimize the common caller.** Make the default case trivial to
  invoke.
- **Agent 4 (if cross-seam) — ports & adapters.** Design around a port for a
  remote-owned or true-external dependency (see [DEEPENING.md](DEEPENING.md)).

Include both [SKILL.md](SKILL.md) design vocabulary and `CONTEXT.md` domain
vocabulary in each brief, so every agent names things consistently with the
architecture language and the project's domain language.

Each sub-agent outputs:

1. **Interface** — types, methods, params, plus invariants, ordering, error modes.
2. **Usage example** — how callers invoke it.
3. **What the implementation hides** behind the seam.
4. **Dependency strategy and adapters** (see [DEEPENING.md](DEEPENING.md)).
5. **Trade-offs** — where leverage is high, where it's thin.

### 3. Present and compare

Present the designs sequentially so the user can absorb each one, then compare
them in prose. Contrast by:

- **Depth** — leverage at the interface: how much behaviour per unit of interface
  learned.
- **Locality** — where change concentrates when requirements shift.
- **Seam placement** — where each design puts the seam, and whether that seam is
  real (two adapters) or hypothetical (one).

After comparing, give your own recommendation: which design is strongest and why.
If elements from different designs combine well, propose a hybrid. Be opinionated
— the user wants a strong read, not a menu. Once chosen, record the decision and
the rejected alternatives in `docs/adr/`.
