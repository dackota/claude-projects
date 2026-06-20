---
name: pr-security-review
description: Run an independent security review on a PR's diff before it opens, then gate the PR on the verdict. Use when about to open a PR, or when a PR security gate hook blocks gh pr create. Classifies the diff (code/infra), spawns a fresh security-reviewer agent on the changes, records a SHA-keyed verdict, and folds findings into the PR body.
origin: claude-projects
agents:
  - security-reviewer
---

# /pr-security-review

Run an **independent** security review on the changes a PR would introduce,
*before* the PR opens, and gate creation on the result. A separate agent — one
that never saw the implementation conversation — reviews the diff with fresh
eyes; this catches what self-review rationalizes away.

A PreToolUse hook (`hooks/pr-gate.sh`) blocks `gh pr create` until a passing
verdict exists for the current `HEAD` commit. This skill produces that verdict.

## When this runs

- You're about to open a PR, or
- The PR security gate blocked `gh pr create` and told you to review first, or
- You invoke it manually to review a change the gate would otherwise skip.

## What the gate auto-skips

The `gh pr create` gate does **not** require a review for every PR. With no
recorded verdict, it requires review when the diff touches **infra** files (any
size) or is a **code change larger than `PR_SECURITY_MAX_SMALL_LINES` lines**
(default 25). Small code-only diffs and docs/config-only diffs pass
automatically. Running this skill by hand always works regardless of size — it
records a verdict, and the gate honors a recorded verdict over any skip rule.

## Procedure

1. **Resolve range and identity.** Determine the base branch (the PR target —
   typically `origin/<default-branch>`; in a repo-skill worktree, the repo's
   recorded `default_branch`). Capture:
   - `BASE` = e.g. `origin/main`
   - `SHA`  = `git rev-parse HEAD`
   - `GITDIR` = `git rev-parse --absolute-git-dir`

2. **Classify the diff.** Run the bundled classifier:
   ```
   bash .claude/skills/pr-security-review/classify.sh "$BASE"
   ```
   It prints `code`, `infra`, both, or nothing. Map dimensions to checklists:
   `code → security-review`, `infra → cloud-infra-security`.

3. **No dimensions?** If the classifier prints nothing (e.g. docs-only PR),
   write a `PASS` verdict (step 6) and skip the agent — there's nothing
   security-relevant to review.

4. **Spawn the independent reviewer.** Launch the `security-reviewer` agent
   (Agent tool, `subagent_type: security-reviewer`) with a fresh context. Give it
   only:
   - the diff range (`$BASE...HEAD`) and the changed-file list,
   - which dimension(s) apply (so it loads the right checklist skill(s)).

   Do **not** pass it the implementation rationale — independence is the point.

5. **Read its verdict.** The agent returns a `VERDICT: PASS|BLOCK` line, severity
   counts, and findings. `BLOCK` iff `CRITICAL > 0`.

6. **Record the verdict** (the hook reads this):
   ```
   mkdir -p "$GITDIR/pr-security-review"
   printf '%s\nCRITICAL:%s HIGH:%s MEDIUM:%s LOW:%s\n' \
     "$VERDICT" "$nCrit" "$nHigh" "$nMed" "$nLow" \
     > "$GITDIR/pr-security-review/$SHA"
   ```

7. **Act on the verdict.**
   - **BLOCK (CRITICAL > 0):** Do NOT open the PR. Report the CRITICAL findings
     and fix them. Each fix is a new commit → a new `HEAD` → re-run this skill on
     the new SHA (the prior verdict no longer matches).
   - **PASS:** Build the PR body with a `## Security review` section summarizing
     the findings (counts + any HIGH/MEDIUM/LOW, with `path:line`), then create
     the PR: `gh pr create --body <body-with-security-section> ...`. The gate
     reads the `PASS` verdict for `HEAD` and allows it.

## Notes

- The verdict lives under `.git/` (per-clone, uncommitted) keyed by commit SHA —
  amending or adding commits invalidates it, forcing re-review.
- The gate only intercepts CLI `gh pr create` in a Claude session; `--web` and
  PRs opened in the GitHub UI bypass it.
- Classification patterns live in `classify.sh` — tune them there if a file type
  is routed to the wrong checklist.
