# Logic Prototype

A tiny interactive terminal app that lets the user drive a state model by hand. Use this when the question is about **business logic, state transitions, or data shape** — the kind of thing that looks reasonable on paper but only feels wrong once pushed through real cases.

The TUI is throwaway. The logic module behind it is **portable** — a pure reducer / state machine / function set that lifts straight into the real build.

## When this is the right shape

- "I'm not sure this state machine handles the edge case where X then Y."
- "Does this data model actually let me represent the case where..."
- "I want to feel out what the API should look like before writing it."
- Anything where the user wants to **press keys and watch state change**.

If the question is "what should this look like" — wrong branch. Use [UI.md](UI.md).

## Process

### 1. State the question

Before writing code, write down the state model and the question you're prototyping — one paragraph, in a comment at the top of the file. A logic prototype that answers the wrong question is pure waste; make the question explicit so it can be checked later, whether the user watches now or returns to it AFK.

### 2. Pick the language

Use whatever the host project uses. If there's no obvious runtime (e.g. a docs repo), ask. Match the project's existing tooling conventions — don't add a new package manager or runtime just for the prototype.

### 3. Isolate the logic in a portable module

Put the logic answering the question behind a small, pure interface that could be lifted out and dropped into the real codebase later. The TUI around it is throwaway; the logic module is not.

Pick the shape that fits the question:

- **A pure reducer** — `(state, action) => state`. Good when actions are discrete events and state is a single value.
- **A state machine** — explicit states and transitions. Good when "which actions are even legal right now" is part of the question.
- **A small set of pure functions** over a plain data type. Good when there's no implicit current state — just transformations.
- **A class or module with a clear method surface** when the logic genuinely owns ongoing internal state.

Pick the shape that best fits the question, *not* whichever is easiest to wire to a TUI. Keep it pure: no I/O, no terminal code, no `console.log` for control flow. The TUI imports it and calls into it; nothing flows the other way.

This is what makes the prototype useful past its own lifetime — the validated module lifts into the real build; the TUI shell gets deleted.

### 4. Build the smallest TUI that exposes the state

Build a **lightweight TUI**: on every tick, clear the screen (`console.clear()` / `print("\033[2J\033[H")` / equivalent) and re-render the whole frame. The user always sees one stable view, not an ever-growing scrollback.

Each frame has two parts, in this order:

1. **Current state**, pretty-printed and diff-friendly (one field per line, or formatted JSON). Use **bold** for field names or section headers and **dim** for less important context (timestamps, IDs, derived values). Native ANSI escapes are fine — `\x1b[1m` bold, `\x1b[2m` dim, `\x1b[0m` reset. No styling library unless one is already in the project.
2. **Keyboard shortcuts** at the bottom: `[a] add user  [d] delete user  [t] tick clock  [q] quit`. Bold the key, dim the description, or vice-versa — whatever reads cleanly.

Behaviour:

1. **Initialise state** — a single in-memory object/struct. Render the first frame on start.
2. **Read one keystroke (or one line)** at a time; dispatch to a handler that produces the next state.
3. **Re-render** the full frame after every action — replace, don't append.
4. **Loop until quit.**

The whole frame should fit on one screen.

### 5. Make it runnable in one command

Add a script to the project's existing task runner (`package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`). The user runs `pnpm run <prototype-name>` or equivalent — never a remembered path. If the project has no task runner, put the command in a comment at the top of the file.

### 6. Hand it over

Give the user the run command. They drive it themselves; the interesting moments are "wait, that shouldn't be possible" or "huh, I assumed X would be different" — those are the bugs in the *idea*, which is the whole point. If they want new actions, add them. Prototypes evolve.

### 7. Capture the answer

When the prototype has done its job, the answer is the only thing worth keeping. If the user is around, ask what it taught them. Then capture it durably:

- **Fold the validated snippet into the PRD** — the reducer / machine / function surface pins the decision more precisely than prose. Hand it to [`to-prd`](../to-prd/SKILL.md), which inlines prototype snippets.
- **Or write a short ADR** in `docs/adr/` if the decision is worth remembering on its own.

If running AFK and the user hasn't responded, leave a placeholder note next to the prototype so the verdict can be filled in before it's deleted.

## Anti-patterns

- **Don't add tests.** A prototype that needs tests is no longer a prototype.
- **Don't wire it to the real database.** Use an in-memory store unless the question is specifically about persistence.
- **Don't generalise.** No "what if we wanted to support X later." The prototype answers one question.
- **Don't blur the logic and the TUI together.** If the reducer / state machine references `console.log`, prompts, or terminal escapes, it's no longer portable. Keep the TUI a thin shell over a pure module.
- **Don't ship the TUI shell into production.** The shell is optimised for hand-driving from a terminal. The logic module behind it is the bit worth keeping.
