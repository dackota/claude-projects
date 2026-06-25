---
name: pr-security-review
description: Run an independent PR review — acceptance validation then security — on a PR's diff before it opens, then gate the PR on a single verdict. Use when about to open a PR, or when the PR gate blocks gh pr create. Derives the slice's task, spawns a fresh implementation-validator (acceptance) then security-reviewer (security) on the diff, records one SHA-keyed verdict, and folds findings into the PR body.
origin: claude-projects
agents:
  - implementation-validator
  - security-reviewer
---

# /pr-security-review — the unified PR-review gate

Run an **independent** review on the changes a PR would introduce, *before* the
PR opens, and gate creation on the result. Two separate agents — neither of which
saw the implementation conversation — review the diff with fresh eyes; this
catches what self-review rationalizes away. The review has two lenses, run in
order:

1. **Acceptance** (`implementation-validator`) — does the slice actually deliver
   the behavior its acceptance criteria promised?
2. **Security** (`security-reviewer`) — is the change safe?

Acceptance runs **first**: there is no point security-reviewing a slice that
doesn't even do what it promised, and a critical acceptance gap loops back to
`tdd` cheaply before the heavier security pass.

A PreToolUse hook (`hooks/pr-gate.sh`) blocks `gh pr create` until a passing
verdict exists for the current `HEAD` commit. This skill produces that verdict.

## When this runs

- You're about to open a PR, or
- The PR gate blocked `gh pr create` and told you to review first, or
- You invoke it manually to review a change the gate would otherwise skip.

## When the gate requires a review

With no recorded verdict for `HEAD`, the gate requires a review when **either**:

- **Acceptance** — the branch is a task in `project.yaml` (a slice PR). Every
  slice is acceptance-validated regardless of size; if the task can't be derived
  from the branch, the gate **warns and falls back** to the security rules below
  (acceptance is skipped, not blocked).
- **Security** — the diff touches **infra** files (any size) or is a **code
  change larger than `PR_SECURITY_MAX_SMALL_LINES` lines** (default 25). Small
  code-only and docs/config-only diffs skip the *security* lens.

Running this skill by hand always works regardless of size — it records a
verdict, and the gate honors a recorded verdict over any skip rule.

## Procedure

1. **Resolve range and identity.** Determine the base branch (the PR target —
   typically `origin/<default-branch>`; in a repo-skill worktree, the repo's
   recorded `default_branch`). Capture:
   - `BASE` = e.g. `origin/main`
   - `SHA`  = `git rev-parse HEAD`
   - `GITDIR` = `git rev-parse --absolute-git-dir`

2. **Derive the slice's task.** The branch name is the task id (worktrees are laid
   out `worktrees/<task-id>/<repo>` on branch `<task-id>`). Look it up in
   `project.yaml` `tasks[]` and read its acceptance criteria from the task's
   source PRD (`plan:`), or — in Jira mode — from the issue body. If the branch is
   **not** a task (off-convention work), skip the acceptance lens, note it in the
   PR body, and go straight to step 5 (security only).

3. **Acceptance review (runs first).** Launch the `implementation-validator` agent
   (Agent tool, `subagent_type: implementation-validator`) with a fresh context.
   Give it only:
   - the diff range (`$BASE...HEAD`) and the changed-file list,
   - the task's acceptance criteria and "what to build" description.

   Do **not** pass it the implementation rationale — independence is the point.
   It returns `VERDICT: PASS|BLOCK` + severity counts + findings; `BLOCK` iff
   `CRITICAL > 0`.

4. **Short-circuit on a critical acceptance gap.** If acceptance is `BLOCK`, do
   **not** run security — the slice doesn't deliver what it promised. Write a
   `BLOCK` verdict (step 6), then **loop back**: flip the task `done → active` in
   `project.yaml` (a `blocker` journal entry), report the CRITICAL gaps, and
   re-enter `tdd` to close them. Each fix is a new commit → a new `HEAD` →
   re-run this skill on the new SHA.

5. **Security review.** Classify the diff:
   ```
   bash "$CLAUDE_PROJECT_DIR"/.claude/skills/pr-security-review/classify.sh "$BASE"
   ```
   It prints `code`, `infra`, both, or nothing (`code → security-review`,
   `infra → cloud-infra-security`). If it prints nothing, the security lens is a
   trivial PASS — skip the agent. Otherwise launch the `security-reviewer` agent
   with a fresh context, given only the diff range and which dimension(s) apply.
   It returns the same verdict shape.

6. **Record the unified verdict** (the hook reads the first line). Combine the two
   lenses: overall `BLOCK` iff either lens is `BLOCK` (i.e. any `CRITICAL > 0`):
   ```
   mkdir -p "$GITDIR/pr-security-review"
   printf '%s\nACCEPTANCE %s C:%s H:%s M:%s L:%s\nSECURITY %s C:%s H:%s M:%s L:%s\n' \
     "$OVERALL" \
     "$aVerdict" "$aCrit" "$aHigh" "$aMed" "$aLow" \
     "$sVerdict" "$sCrit" "$sHigh" "$sMed" "$sLow" \
     > "$GITDIR/pr-security-review/$SHA"
   ```

7. **Act on the verdict.**
   - **BLOCK (any CRITICAL):** Do NOT open the PR. Report the CRITICAL findings by
     lens and fix them (acceptance gaps loop back to `tdd` per step 4). Each fix is
     a new commit → re-run this skill on the new SHA.
   - **PASS:** Build the PR body with a `## PR review` section summarizing both
     lenses (acceptance + security counts, and any HIGH/MEDIUM/LOW with
     `path:line`), then create the PR. The gate reads the `PASS` verdict for
     `HEAD` and allows it.

## Notes

- The verdict lives under `.git/` (per-clone, uncommitted) keyed by commit SHA —
  amending or adding commits invalidates it, forcing re-review.
- The gate only intercepts CLI `gh pr create` in a Claude session; `--web` and
  PRs opened in the GitHub UI bypass it.
- Classification patterns live in `classify.sh` — tune them there if a file type
  is routed to the wrong checklist.
- The block threshold is **CRITICAL-only**, for both lenses (matching security):
  a CRITICAL acceptance gap means a promised behavior is undelivered. HIGH and
  below are noted in the PR body but don't block.
