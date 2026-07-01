---
name: pr-security-review
description: Run an independent security review on a PR's diff before it opens, then gate the PR on the verdict. Use when about to open a PR, or when the PR gate blocks gh pr create. Spawns a fresh security-reviewer (no implementation context) on the diff, records one SHA-keyed verdict, and folds findings into the PR body. Acceptance is validated earlier, by /next's post-build gate — this gate is security-only.
origin: claude-projects
agents:
  - security-reviewer
---

# /pr-security-review — the PR security gate

Run an **independent** security review on the changes a PR would introduce,
*before* the PR opens, and gate creation on the result. A fresh `security-reviewer`
agent — one that never saw the implementation conversation — reviews the diff with
skeptical eyes; this catches what self-review rationalizes away.

> **Acceptance is not checked here.** Whether the slice actually delivers the
> behavior its acceptance criteria promised is validated *earlier*, by `/next`'s
> **post-build acceptance gate** (`implementation-validator`, run right after the
> `tdd-implementer` finishes and looped back to `tdd` before the task is ever
> marked done). By the time a PR opens, acceptance has already passed — so this
> gate is purely the **security** lens.

A PreToolUse hook (`hooks/pr-gate.sh`) blocks `gh pr create` until a passing
verdict exists for the current `HEAD` commit. This skill produces that verdict.

## When this runs

- You're about to open a PR, or
- The PR gate blocked `gh pr create` and told you to review first, or
- You invoke it manually to review a change the gate would otherwise skip.

## When the gate requires a review

With no recorded verdict for `HEAD`, the gate requires a security review when the
diff touches **infra** files (any size) or is a **code change larger than
`PR_SECURITY_MAX_SMALL_LINES` lines** (default 25). Small code-only and
docs/config-only diffs skip automatically.

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
   It prints `code`, `infra`, both, or nothing (`code → security-review`,
   `infra → cloud-infra-security`). If it prints nothing, the review is a trivial
   PASS — skip the agent and record a PASS verdict.

3. **Security review.** Launch the `security-reviewer` agent (Agent tool,
   `subagent_type: security-reviewer`) with a fresh context, given only the diff
   range (`$BASE...HEAD`), the changed-file list, and which dimension(s) apply. Do
   **not** pass it the implementation rationale — independence is the point. It
   returns `VERDICT: PASS|BLOCK` + severity counts + findings; `BLOCK` iff
   `CRITICAL > 0`.

4. **Record the verdict** (the hook reads the first line):
   ```
   mkdir -p "$GITDIR/pr-security-review"
   printf '%s\nSECURITY %s C:%s H:%s M:%s L:%s\n' \
     "$verdict" "$verdict" "$sCrit" "$sHigh" "$sMed" "$sLow" \
     > "$GITDIR/pr-security-review/$SHA"
   ```
   Then append a `run` journal entry (`type: run`, `agent: security-reviewer`, the
   task id, `verdict`, `critical`/`high` counts, `rework`, `approver`): the `.git/`
   verdict gates the PR, while the journal entry is the durable audit trail that
   feeds `STATUS.md`'s **Pipeline health**. The `run-check.sh` hook nudges you.

5. **Act on the verdict.**
   - **BLOCK (any CRITICAL):** Do NOT open the PR. Report the CRITICAL findings and
     fix them. Each fix is a new commit → a new `HEAD` → re-run this skill on the
     new SHA.
   - **PASS:** Build the PR body with a `## Security review` section summarizing the
     counts (and any HIGH/MEDIUM/LOW with `path:line`), then create the PR. The gate
     reads the `PASS` verdict for `HEAD` and allows it.

## Notes

- The verdict lives under `.git/` (per-clone, uncommitted) keyed by commit SHA —
  amending or adding commits invalidates it, forcing re-review.
- The gate only intercepts CLI `gh pr create` in a Claude session; `--web` and
  PRs opened in the GitHub UI bypass it.
- Classification patterns live in `classify.sh` — tune them there if a file type
  is routed to the wrong checklist.
- The block threshold is **CRITICAL-only**: HIGH and below are noted in the PR body
  but don't block.
