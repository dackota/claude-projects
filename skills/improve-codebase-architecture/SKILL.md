---
name: improve-codebase-architecture
description: Find deepening opportunities in a codebase, informed by the domain language in CONTEXT.md and the decisions in docs/adr/. Use when the user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, or make a codebase more testable and AI-navigable.
origin: claude-projects
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## Vocabulary

Use the vocabulary from the `codebase-design` skill (`.claude/skills/codebase-design/SKILL.md`) exactly — Module, Interface, Implementation, Depth, Deep, Shallow, Seam, Adapter, Leverage, Locality. Don't drift into "component," "service," "API," or "boundary." That skill owns the glossary and the principles (the **deletion test**; the interface is the test surface; one adapter = hypothetical seam, two = real seam). Read it before writing suggestions; do not restate it here.

This skill is _informed_ by the project's domain model. `CONTEXT.md` names good seams; ADRs in `docs/adr/` record decisions the skill must not re-litigate.

## Process

### 1. Explore

Read `CONTEXT.md` (the domain glossary) and any ADRs in `docs/adr/` touching the area you're working in — first.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics — explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts are untested, or hard to test through their current interface?

Match each candidate to a deepening category from `.claude/skills/codebase-design/DEEPENING.md` — that's the taxonomy you'll tag cards with.

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the repo. Resolve the temp dir from `$TMPDIR`, falling back to `/tmp` (or `%TEMP%` on Windows), and write to `<tmpdir>/architecture-review-<timestamp>.html` so each run gets a fresh file. Open it — `xdg-open <path>` on Linux, `open <path>` on macOS, `start <path>` on Windows — and tell the user the absolute path. Never write it into the repo.

The report uses **Tailwind via CDN** for layout and **Mermaid via CDN** for graph-shaped diagrams. Mix Mermaid with hand-built CSS/SVG — Mermaid for call graphs, dependencies, and sequences; hand-drawn divs/SVG for editorial visuals (mass diagrams, cross-sections, collapse animations). Every candidate gets a **before/after visualisation**. Be visual.

One card per candidate:

- **Files** — which files/modules are involved.
- **Problem** — one sentence: what hurts.
- **Solution** — one sentence: what changes.
- **Benefits** — in terms of locality and leverage, and how tests improve.
- **Before / After diagram** — side by side, custom-drawn, showing the shallowness and the deepening.
- **Recommendation strength** — a badge: `Strong`, `Worth exploring`, or `Speculative`.

End with a **Top recommendation** section: which candidate to tackle first and why.

**Use `CONTEXT.md` vocabulary for the domain, `codebase-design` vocabulary for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module" — not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an ADR in `docs/adr/`, only surface it when the friction is real enough to warrant reopening that ADR. Mark it clearly in the card (an amber warning callout: _"contradicts ADR-0007 — but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram patterns, and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation — same discipline as the `grill-with-docs` skill. Walk the design tree: constraints, dependencies, the shape of the deepened module, what sits behind the seam, which tests survive.

Side effects happen inline as decisions crystallize:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md` (format: `.claude/skills/grill-with-docs/CONTEXT-FORMAT.md`). Create the file lazily if it doesn't exist.
- **Sharpening a fuzzy term mid-conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing — skip ephemeral reasons ("not worth it right now") and self-evident ones. Format: `.claude/skills/grill-with-docs/ADR-FORMAT.md`.
- **Want to explore alternative interfaces for the deepened module?** See `.claude/skills/codebase-design/INTERFACE-DESIGN.md` (and `.claude/skills/codebase-design/DESIGN-IT-TWICE.md` for weighing two designs before committing).
