---
name: prototype
description: Build a throwaway prototype to answer a design question — "does this logic/state model feel right?" or "what should this look like?". Use during design, before committing to a build, to sanity-check a state model or explore what a UI should be.
origin: claude-projects
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

Hand-invoked during design, before committing to a build. The prototype's *answer* — not its code — feeds the rest of the pipeline: fold a decision-encoding snippet into the PRD via [`to-prd`](../to-prd/SKILL.md), or record the verdict as an ADR in `docs/adr/`.

## Pick a branch

Identify which question is being answered — from the prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build a tiny interactive terminal app that pushes the state machine through cases that are hard to reason about on paper.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on one route, switched by a URL search param and a floating switcher bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype close to where it will actually be used (next to the module or page it prototypes for) so context is obvious — but name it so a casual reader sees it's a prototype, not production. For throwaway UI routes, obey the project's existing routing convention; don't invent a new top-level structure.
2. **One command to run.** Whatever the project's task runner supports — `pnpm <name>`, `python <path>`, `bun <path>`, etc. The user starts it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing a prototype *checks*, not something it depends on. If the question is explicitly about a database, hit a scratch DB or a local file named clearly "PROTOTYPE — wipe me".
4. **Skip the polish.** No tests, no error handling beyond what makes it *runnable*, no abstractions. Learn something fast, then delete it.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the change is visible.
6. **Delete or absorb when done.** Once the question is answered, either delete the prototype or fold the validated decision into the real code — don't leave it rotting in the repo.

## When done

The *answer* is the only thing worth keeping from a prototype. Capture it durably, paired with the question it answered:

- **Fold a decision-encoding snippet into the PRD.** If the prototype produced a snippet that pins a decision more precisely than prose can — a reducer, state machine, schema, or type shape — hand it to [`to-prd`](../to-prd/SKILL.md), which already accepts prototype snippets and inlines the decision-rich parts.
- **Or record an ADR in `docs/adr/`.** For a decision worth remembering on its own, write a short ADR (create `docs/adr/` lazily; sequential `NNNN-slug.md` numbering).

If the user is around, that capture is a quick conversation. If not, leave a placeholder note next to the prototype so the verdict can be filled in — by them, or by you on the next pass — before the prototype is deleted.
