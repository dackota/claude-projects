---
name: pr-security-review
description: Independent security review that gates gh pr create — a fresh security-reviewer (no implementation context) reviews the diff, records a SHA-keyed verdict, and folds findings into the PR body. Use when about to open a PR, or when the PR gate blocks gh pr create.
origin: claude-projects
agents:
  - security-reviewer
---

# /pr-security-review — the PR security gate

Run an **independent** security review on the changes a PR would introduce,
*before* the PR opens, and gate creation on the result. A fresh `security-reviewer`
agent — one that never saw the implementation conversation — reviews the diff with
skeptical eyes; this catches what self-review rationalizes away.

> **Acceptance and correctness are not checked here.** Whether the slice delivers
> its acceptance criteria (`implementation-validator`) and is free of
> diff-introduced correctness bugs (`correctness-reviewer`) is validated *earlier*,
> by `/next`'s **post-build barrier** — run right after the `tdd-implementer`
> finishes and looped back to `tdd` before the task is ever marked done. By the
> time a PR opens, both have already passed — so this gate is purely the
> **security** lens.

A PreToolUse hook (`hooks/pr-gate.sh`) blocks `gh pr create` until a passing
verdict exists for the current `HEAD` commit. This skill produces that verdict.

## When this runs

- You're about to open a PR, or
- The PR gate blocked `gh pr create` and told you to review first, or
- You invoke it manually to review a change the gate would otherwise skip.

## When the gate requires a review

With no recorded verdict for `HEAD`, the gate requires a security review when the
diff touches **infra** files (any size) or a **trust-boundary surface** in the code
(network, DB/SQL, exec, env, file I/O, templates, or secrets/crypto — any size). A
**pure-logic** code change (no such surface) and docs/config-only diffs skip
automatically; the trust-boundary marker set is tunable via
`PR_SECURITY_SURFACE_MARKERS`. When a pure module skips, the `correctness-reviewer`
still records the security obligations it imposes on its callers, so nothing is lost.

Running this skill by hand always works regardless of size — it records a verdict,
and the gate honors a recorded verdict over any skip rule.

## Procedure

1. **Resolve range and identity.** Determine the base branch (the PR target —
   typically `origin/<default-branch>`; in a repo-skill worktree, the repo's
   recorded `default_branch`). Capture:
   - `BASE` = e.g. `origin/main`
   - `SHA`  = `git rev-parse HEAD`
   - `GITDIR` = `git rev-parse --absolute-git-dir`

2. **Classify the diff.**
   ```
   bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/classify.sh "$BASE"
   ```
   It prints any of `code`, `infra`, `surface`, or nothing — `code`/`surface` →
   security-review checklist, `infra` → cloud-infra-security checklist, and `surface`
   flags that the code diff touches a trust boundary. If it prints nothing
   (docs/config only), the review is a trivial PASS — skip the agent and record it
   with the classify-verified trivial mode (needed because `repo.sh pr` requires a
   verdict file even for a docs-only PR):
   ```
   bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/record-verdict.sh --trivial "$BASE"
   ```

3. **Security review.** Launch the `security-reviewer` agent (Agent tool,
   `subagent_type: security-reviewer`) with a fresh context, given only the diff
   range (`$BASE...HEAD`), the changed-file list, and which dimension(s) apply. Do
   **not** pass it the implementation rationale — independence is the point. Run it
   **in the foreground** (`run_in_background: false`) so the verdict returns in the
   tool result — backgrounding a gate turns the wait into repeated Stop-hook
   wake-up turns, each a full-prefix cache read (see `next/BARRIER.md`,
   "Collecting the verdicts"). It
   returns `VERDICT: PASS|BLOCK` + severity counts + findings; `BLOCK` iff
   `CRITICAL > 0`.

4. **Record the verdict — pipe the reviewer's output through the recorder; do
   NOT hand-write it.** Do **not** `printf 'PASS' > "$verdict_file"`. The
   orchestrator (the same agent trying to open the PR) hand-authoring a `PASS`
   into the gate file is structurally indistinguishable from a gate bypass —
   nothing links that literal `PASS` to a review that ran — and an auto-mode
   safety classifier will (correctly) refuse it as fabrication. Instead pipe the
   security-reviewer's **verbatim output** through `record-verdict.sh`, which
   parses the `VERDICT`/severity block, enforces the invariant (BLOCK iff
   CRITICAL>0), and writes the SHA-keyed file itself:
   ```
   bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/record-verdict.sh <<'REVIEW'
   <the security-reviewer's verbatim output — the VERDICT/CRITICAL/HIGH/MEDIUM/LOW
   block and its findings, exactly as returned>
   REVIEW
   ```
   Run it from inside the repo/worktree being gated — it derives `HEAD` itself
   (so a verdict can't be recorded for the wrong commit) and refuses a bare or
   absent verdict, or one whose count disagrees with the invariant, writing
   nothing on refusal. (If a classifier still blocks even this derived,
   invariant-checked recording, that's a false positive on a legitimate review:
   the reviewer's output is your evidence — surface it and use the documented
   `--web` fallback below rather than a raw hand-write.)

   Then append a `run` journal entry (`type: run`, `agent: security-reviewer`, the
   task id, `verdict`, `critical`/`high` counts, `rework`, `approver`): the `.git/`
   verdict gates the PR, while the journal entry is the durable audit trail that
   feeds `STATUS.md`'s **Pipeline health**. The `run-check.sh` hook nudges you.

5. **Act on the verdict.**

   > **Record first, then create — as two separate Bash calls.** The gate is a
   > PreToolUse hook that inspects the `gh pr create` command string *before* the
   > command runs. A verdict written in the *same* command (`… > "$verdict_file" &&
   > gh pr create …`, or a `scripts/repo.sh pr` chained after the write) has not
   > landed on disk when the hook fires, so the gate still sees no verdict and
   > blocks. Let the step-4 write complete in its own call, then create the PR in
   > the next call.

   - **BLOCK (any CRITICAL):** Do NOT open the PR. Report the CRITICAL findings and
     fix them. Each fix is a new commit → a new `HEAD` → re-run this skill on the
     new SHA.
   - **PASS:** Build the PR body with a `## Security review` section summarizing the
     counts (and any HIGH/MEDIUM/LOW with `path:line`). If the slice has a
     validation record (`docs/validations/<task>.md`, written by `/next`'s
     post-build barrier), **append a `## Security` section** to it — verdict · what
     was reviewed · the counts/findings — so the record carries all lenses. Then
     create the PR; the gate reads the `PASS` verdict for `HEAD` and allows it.

## Skipping the security review for one run

You may **intentionally skip** the security review for a single run — a spike, or a change
you judge has no security surface — under the same **"no silent skip"** rule as the barrier
gates (`next/BARRIER.md`, "Skipping a gate for one run", which also spells out the accepted
risk). You may self-initiate it (no approver), but the **reason is mandatory** and is
recorded through the recorder, never hand-written:

```
bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/record-verdict.sh \
  --skip --reason "docs-only touch-up, no code path"
```

This writes a `SKIP <reason>` verdict for `HEAD`. `pr-gate.sh` and `scripts/repo.sh pr`
honor it and **refuse a reasonless skip**; `repo.sh pr` lists it in the PR body's
"⚠ Skipped reviews" section so the human reviewing the PR sees that security was skipped
(the compensating control). On the raw `gh pr create` path, add that section to the PR body
yourself. Still append a `run` journal entry (`verdict: SKIP`, with the `reason`).

## Notes

- The verdict lives under `.git/` (per-clone, uncommitted) keyed by commit SHA —
  amending or adding commits invalidates it, forcing re-review.
- The gate only intercepts CLI `gh pr create` in a Claude session; `--web` and
  PRs opened in the GitHub UI bypass it.
- Classification patterns live in `classify.sh` — tune them there if a file type
  is routed to the wrong checklist.
- The block threshold is **CRITICAL-only**: HIGH and below are noted in the PR body
  but don't block.
