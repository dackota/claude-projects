# Parallel build fan-out

`/next` builds one task per session by default. When the **Pick frontier** holds
**two or more mutually independent** unblocked tasks (none in another's `blocked_by`,
transitively) and the user opts in ("build the next N in parallel"), build them
concurrently instead. **Isolation is what makes this safe** — each task gets its own
worktree, so builds never touch each other's files. Only ever fan out the
**frontier**: never parallelize two tasks with a dependency between them (a blocked
task waits for its blocker to land).

1. **Prefer AFK.** AFK tasks fan out directly. A HITL task needs human input
   first — gather every HITL task's input up front, or leave it out of the batch;
   the build loops themselves stay non-interactive.
2. **Set up per task**: `scripts/repo.sh worktree <task> <repo>` for each, and flip
   each `todo → active` (a `started` journal entry each).
3. **Fan out**: spawn one `tdd-implementer` per task **concurrently — all Agent
   calls in a single message** so they run in parallel. Give each ONLY its own
   task's acceptance criteria, its worktree as the working directory, plus
   `CONTEXT.md`/ADRs/test command. No task sees another's context.
4. **Land each independently as it returns** (pipeline, not barrier): review +
   re-run its tests → commit its slice → run the post-build gate(s) on its diff —
   `implementation-validator`, plus `otel-observability-engineer` in parallel for a
   service task that added a request path — → `active → done` only if all PASS, or
   loop that one task back to `tdd` on a CRITICAL/BLOCKER gap (record a `run` entry
   per gate, as in the single-build gate). One task looping back never holds up the
   others.
5. **Keep batches modest** (a few at a time) so reviews and acceptance gates stay
   tractable; a large frontier builds in waves.

## Orchestrator hygiene (this is where parallel work breaks)

N worktrees share **one** shell working directory and **one** set of workspace
files, so the ambient cwd drifts between tasks:

- Write `project.yaml` / `journal.yaml` / `STATUS.md` by **absolute path** — never
  rely on the shell's cwd (a drifted cwd silently writes a stray file into a
  worktree).
- Use `git -C <worktree> …` for every git op; don't `cd` to mutate the shared cwd.
- Open each PR with `scripts/repo.sh pr <task>` — its `cd` is internal, so it is
  cwd-safe and self-enforces the recorded review verdict. **This is the path to use
  under fan-out.** A **direct** `gh pr create` keys the PR gate on the *session's
  current directory* — the gate deliberately does **not** parse a leading `cd`
  (that repeatedly proved exploitable) — so run it only from **inside** the target
  worktree; a drifted cwd makes the gate block. In short: prefer `repo.sh pr`.
