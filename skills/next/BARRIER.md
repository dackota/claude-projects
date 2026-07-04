# The post-build validation barrier

This is the **single normative home** for `/next`'s post-build validation barrier and
the handoff to the PR security gate. The `next` router core, the `tdd` skill,
`pr-security-review`, and the review agents' frontmatter all **point here** rather than
restating the protocol — change it here and nowhere else.

The barrier belongs to the **Build phase**: it runs right after a slice is built and
before the task is marked `done`. Read this file only when you are actually building —
the router core stays lean the rest of the time.

## Run the gates — one parallel message

Once your **cheap smoke** of a `COMPLETE` `tdd-implementer` summary is clean — a
fail-fast build/test check to confirm the summary holds, **not** a full re-validation
(the fresh gates below are the validation; the orchestrator's own deep re-validation is
redundant with them — see the router core's Review step) — **commit the slice** in the
worktree, then run the barrier's gates in parallel — all in a single message, so adding
gates adds no wall-clock latency.

**Collecting the verdicts.** Each gate **returns its verdict inline** — its final
`VERDICT: …` block is the Agent call's result, which you parse directly. The barrier is a
synchronization point: collect every gate's verdict before you record runs or advance.
Running the gates in the **foreground** (so their verdicts come back in the tool result of
that one parallel message) is the clean path — it needs no follow-up retrieval. If instead
you spawn them in the background, **wait for each gate's completion notification** — the
verdict arrives on its own. Do **not** fetch a still-running gate's output to "check on
it": retrieving a running sub-agent's output returns its raw transcript, not a verdict, and
burns context for nothing. Note the audit hook (`run-check.sh`) nudges you when a gate is
*dispatched*, not when its verdict is ready — for a backgrounded gate that fires at spawn,
so treat it as "remember to journal this once it returns," not as a signal to go looking.

### Acceptance gate (always)

Spawn the `implementation-validator` (Agent tool,
`subagent_type: implementation-validator`) on a **fresh context** to verify the slice
against its contract *before* it is marked done. Give it only the diff range
(`<base>...HEAD`) + changed files and the task's acceptance criteria / "what to build"
— **not** the implementation rationale; independence is the point. Pass the diff
**range**, not pasted file contents — the agent fetches the diff itself with `git`,
which keeps secrets out of its prompt (an `agent-controls` control). It returns
`VERDICT: PASS | BLOCK` (`BLOCK` iff `CRITICAL > 0`).

### Correctness gate (always)

In the **same message** as the acceptance gate, spawn the `correctness-reviewer`
(Agent tool, `subagent_type: correctness-reviewer`) on a fresh context with the same
diff range + changed files and the task's "what to build" — again **not** the
implementation rationale. It is the independent net for correctness bugs *this diff
introduced* that no acceptance criterion named (nil derefs, races, leaks, swallowed
errors, wrong conditions). It **defers security** to the PR security gate and treats
maintainability smells as non-blocking warnings. It returns `VERDICT: PASS | BLOCK`
(`BLOCK` iff `CRITICAL > 0`, a diff-introduced bug). Run it on every build, like the
acceptance gate — correctness is not a per-project choice.

### Runtime gate (when the diff is runnable)

When the diff touches **runnable product source** (skip tests/docs/config-only — the
same classification the security gate's `classify.sh` makes), spawn the
`runtime-validator` (Agent tool, `subagent_type: runtime-validator`) in the **same
message** as the other gates, pointed at the committed worktree. Unlike the read-only
reviewers it may **execute** — build, boot, and drive the artifact — but never modifies
source, commits, or deploys. It drives the affected flow per its baked playbook
(CLI · server boot+probe · image build+boot · UI render · library harness), preferring
`project.yaml`'s `validation.run_cmd` when set. It returns `VERDICT: PASS | BLOCK |
SKIP`: **BLOCK** on an objective runtime failure (won't build/boot, the driven flow
errors or 500s), **SKIP** when there's no runnable surface or the sandbox lacks a
needed dependency (a DB, creds, an external service). **A SKIP never stalls the
barrier** — treat it as pass for advancement and record why it skipped.

### Observability gate (service tasks only)

If `project.yaml` has `observability.enabled: true`, the agent
`otel-observability-engineer` is installed, **and** the diff adds a request-serving
path, spawn that agent on the same diff **in the same message** as the acceptance,
correctness, and (when it ran) runtime gates so they all run concurrently (no added
latency). It returns its own `VERDICT: PASS | BLOCK` (`BLOCK` iff `BLOCKER > 0`)
against `.claude/skills/observability/standard.md`. Skip it silently when the flag is
off, the agent isn't installed, or the diff adds no request path.

## Record each gate run (the Audit step)

After a gate agent returns — PASS, BLOCK, or SKIP — append a `run` journal entry
(`type: run`) with its `agent`, `task`, `verdict`, the `critical`/`high` counts it
reported (the BLOCKER count for the observability gate; none for a runtime SKIP), the
task's `rework` count so far (how many times it has looped back through this gate), and
`approver` (null unless a named human approved a gated action). These are **structured
fields, not prose**: the `run-check.sh` hook records that a gate ran and nudges you, and
the `Stop` hook then refuses to stop until every recorded gate run has a matching,
well-formed `run` entry (a missing or prose-only entry is an error, not just a nudge).
These entries feed `STATUS.md`'s **Pipeline health**. The security gate at `gh pr create`
records its own `run` entry the same way.

The validation record is the **single home** for gate detail — one record per slice,
each gate a section. `run` entries stay a terse one-line metric (gate · SHA · verdict ·
counts · a ref to the record); `done` and `pr` journal entries **link** to the record
rather than restating findings. Detail lives in exactly one place.

## Advance or loop back

Treat these gates as one barrier — the slice advances only if **all** PASS; a runtime
**SKIP** counts as pass, and the observability gate counts only when it ran:

- **All PASS** → **write the validation record** to
  `docs/validations/<task-id>-<slug>.md` (workspace lifecycle frontmatter; one section
  per gate — verdict · what it validated · how · evidence — built from what each gate
  returned; record the *passing* state). You write it, not the review agents (they are
  read-only) — an `agent-controls` control.

  Then **record the barrier verdict** so the PR gate can enforce it in code — the same
  pattern the security gate uses. As a **separate write, before** you open the PR (a
  verdict chained in the same command as `gh pr create` may not have landed when the
  hook fires — the write-then-act rule), write one line per gate to
  `"$(git rev-parse --absolute-git-dir)"/barrier-review/"$(git rev-parse HEAD)"`:

  ```
  acceptance PASS
  correctness PASS
  runtime SKIP          # or PASS/BLOCK — recorded, not gated here
  observability PASS    # omit when the gate didn't run
  ```

  You write this (the gate agents are read-only) — it is the acceptance/correctness
  analogue of the `.git/pr-security-review/<sha>` verdict. `barrier-gate.sh` (raw
  `gh pr create`) and `scripts/repo.sh pr` both require `acceptance PASS` **and**
  `correctness PASS` for HEAD, so a slice can no longer reach a PR with these gates
  silently skipped.

  Then flip the task `active → done` and proceed to **Land** — open the PR with
  `scripts/repo.sh pr <task>` (cwd-safe; self-enforces the recorded barrier **and**
  security verdicts), where the security review runs and **appends its own section** to
  the validation record. The PR gate does **not** re-run acceptance or correctness —
  the recorded barrier verdict already covers this HEAD SHA, so only the security review
  runs there (no duplicate validation per slice).
- **Any BLOCK** → the slice isn't ready. Leave the task `active`, write a `blocker`
  journal entry with the failing gate's findings (the validator's CRITICAL acceptance
  gaps, the correctness gate's CRITICAL bugs, the runtime gate's failure, and/or the
  observability BLOCKERs), and **re-spawn the `tdd-implementer`** framed as *closing
  those specific gaps* — pass it the findings, not a fresh build. **If a BLOCK recurs in
  the same family across loops** — the reworked `HEAD` fails a *sibling* input of the same
  broken invariant — stop forwarding the reported case-by-case: name the invariant, require
  the fix at a **single chokepoint**, and require a **property/invariant test that covers
  the class** (`rules/common/testing.md`). Patching each reported case in turn just
  surfaces the next sibling on the following loop; a class-level fix + invariant test ends
  the family in one pass. Its fixes are new
  commits → re-run the failed gate(s) on the new `HEAD`. Loop until all PASS. BLOCK
  findings stay in the journal, not the record — the record captures the state that
  ultimately passed. This keeps the loop-back cheap and local — the task never reaches
  a PR (or even `done`) until it passes.

**The loop is bounded — it does not run forever.** A `rework-cap.sh` PreToolUse hook
refuses to re-spawn `tdd-implementer` once any single gate has BLOCKed this task more
than `validation.max_rework` times (default **3** — the 3rd rework is allowed, a 4th is
refused; counted per gate from the `run` entries). The count is scoped to the **current
build episode**: a gate's own PASS ends its rework streak and resets its counter, so a
task reopened long after it passed (a security reopen, a manual reopen) starts fresh
rather than inheriting the earlier episode's BLOCK count. When the cap fires, do not fight it:
a gate that keeps blocking the same slice signals a **wrong seam, a flaky test, or an
impossible criterion**, not something another build loop will fix. Flip the task to
`blocked`, write a `blocker` entry with the recurring finding, and hand it to a human.

## Inline (`/tdd`) mode

When `/tdd` is invoked **by hand**, the loop runs inline in the main agent (Opus) and
there is no auto-gate — you are watching live. Close-out is your own confidence that
the slice is done; run `/pr-security-review` by hand if you want an independent pass.
Either way, security is reviewed later at the PR gate. See the `tdd` skill for the
inline close-out steps.
