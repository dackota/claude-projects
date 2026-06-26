---
status: accepted
date: 2026-06-25
---

# The PR gate runs acceptance validation and security as one unified review

The `pr-security-review` skill gated `gh pr create` on an independent *security*
review, but nothing independently checked that a slice actually delivered the
behavior its acceptance criteria promised — "done" (a `tdd` close-out) was taken
on faith. We add a per-task **acceptance** lens: an independent
`implementation-validator` agent (cloned from the `security-reviewer` shape,
review-only) that checks the slice's diff against its task's acceptance criteria.
Rather than stand up a second gate beside the security one, we **rescope
`pr-security-review` into a single unified PR-review gate**: one PreToolUse hook
on `gh pr create` runs acceptance **then** security, short-circuiting on the
first CRITICAL, and records **one** SHA-keyed verdict combining both lenses. The
two agents stay distinct (separate prompts, separate failure modes, separate
verdict sections folded into the PR body); only the gate *plumbing* is unified.
Acceptance runs first because there is no point security-reviewing a slice that
doesn't do what it promised, and a CRITICAL acceptance gap loops back to `tdd`
(`done → active`) cheaply before the heavier security pass.

## Considered options

- **Two independent skills + two hooks on `gh pr create`** (an
  `pr-acceptance-review` sibling) — rejected. Claude Code runs same-matcher hooks,
  but coordinating *ordering* and *CRITICAL short-circuit* between two separate
  hooks is brittle; one gate that sequences both lenses is robust and shares a
  single verdict cache.
- **Fold acceptance checking into the `security-reviewer` agent** — rejected.
  Acceptance and security fail for different reasons and want different prompts;
  one agent doing both jobs does each worse and muddies the verdict.
- **Keep `pr-security-review` security-only; no acceptance gate** — rejected. This
  is the status quo gap: a slice can pass security and still not deliver its
  promised behavior, and self-review of acceptance rationalizes gaps away.
- **Chosen: unified gate, two distinct agents sequenced acceptance→security, one
  SHA-keyed verdict.** The block threshold is CRITICAL-only for both lenses,
  matching the existing security semantics, so contributors learn one model.

## Consequences

- The skill name `pr-security-review` becomes a slight misnomer — its scope is now
  "PR review (acceptance + security)." We keep the name to avoid breaking the
  scaffolder wiring, hook path, and `.git/pr-security-review/<sha>` verdict cache.
- The gate now requires a review for **every slice PR** (a branch that is a task
  in `project.yaml`), regardless of size — acceptance applies to all slices. When
  the task can't be derived from the branch, the gate warns and falls back to the
  security-only rules rather than blocking off-convention work.
