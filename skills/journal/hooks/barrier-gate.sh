#!/usr/bin/env bash
# PreToolUse(Bash) hook: gate `gh pr create` on the post-build barrier verdict.
#
# The security lens is gated separately by pr-security-review/hooks/pr-gate.sh.
# THIS gate is the acceptance + correctness lens — the barrier's two "always" gates
# (implementation-validator, correctness-reviewer). BARRIER.md promises "the task
# never reaches a PR until both PASS"; without this hook that promise is prose only —
# a drifting orchestrator could flip the task done and open the PR having skipped the
# gates, and only the security review would fire. This makes the promise code.
#
# The gate agents are review-only (an agent-controls invariant — they hold no
# Write/Edit), so — exactly as for the validation record — the ORCHESTRATOR writes a
# SHA-keyed barrier verdict after the gates return, one line per gate:
#     acceptance PASS
#     correctness PASS
#     runtime SKIP          # optional (PASS|BLOCK|SKIP) — not gated here
#     observability PASS    # optional — not gated here
# at "$GITDIR/barrier-review/$SHA" (GITDIR = git rev-parse --absolute-git-dir).
# This gate requires acceptance == PASS AND correctness == PASS for HEAD.
#
# Decision order for the `gh pr create` HEAD commit:
#   1. A barrier verdict recorded for HEAD -> honor it (both PASS -> allow the
#      barrier lens; otherwise block). A recorded BLOCK can't be routed around by
#      switching from `repo.sh pr` to a raw `gh pr create`.
#   2. No verdict, and the PR is being created from a pipeline task worktree
#      (cwd under worktrees/) whose diff touches code/infra/surface -> BLOCK: a
#      built slice must carry a barrier verdict. Fail closed if the gate agents
#      aren't even installed (degraded install).
#   3. No verdict, not a task-worktree PR (inline /tdd or an ad-hoc PR) -> allow.
#      Inline mode is human-supervised ("you are the reviewer"); security still
#      gates it via pr-gate.sh. Record a verdict by hand to gate it here too.
#
# The `repo.sh pr` pipeline path invokes gh *internally*, so this hook never sees it;
# repo.sh self-enforces the same verdict (mirroring how it self-enforces security).
#
# Reads the Claude Code PreToolUse payload (JSON) on stdin.

set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"

[[ -z "$cmd" ]] && exit 0

# Only gate PR creation.
printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+create' || exit 0

block() { echo "🔒 barrier gate: $1" >&2; exit 2; }

cwd="${cwd:-$PWD}"
# Key strictly on the payload cwd — the directory gh runs in — for the same reasons
# pr-gate.sh does: never parse a leading `cd` out of the command to redirect identity.
gitdir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null || true)"
sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)"
[[ -z "$gitdir" || -z "$sha" ]] && \
  block "can't resolve git repo/HEAD from the command's directory — run gh pr create inside the repo."

verdict_file="$gitdir/barrier-review/$sha"

# 1. Honor an existing barrier verdict for HEAD.
if [[ -f "$verdict_file" ]]; then
  acc="$(grep -E '^acceptance[[:space:]]' "$verdict_file" 2>/dev/null | head -n1 | awk '{print $2}')"
  cor="$(grep -E '^correctness[[:space:]]' "$verdict_file" 2>/dev/null | head -n1 | awk '{print $2}')"
  if [[ "$acc" == "PASS" && "$cor" == "PASS" ]]; then
    exit 0
  fi
  block "post-build barrier for HEAD ($sha) is not PASS (acceptance=${acc:-none}, correctness=${cor:-none}). Close the flagged gaps — each fix is a new commit that re-runs the gate(s) — then re-record the verdict and re-run gh pr create."
fi

# No verdict recorded. Only FORCE the barrier for a pipeline task-worktree PR.
case "$cwd/" in
  */worktrees/*) ;;                 # a /next task worktree — the pipeline path
  *) exit 0 ;;                      # inline / ad-hoc — human-supervised; allow
esac

# It's a task-worktree PR. Classify the diff; a docs/config-only slice has no
# behavior to validate (parity with the runtime gate's SKIP and the security skip).
root="${CLAUDE_PROJECT_DIR:-}"
[[ -z "$root" ]] && root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd 2>/dev/null || true)"
classify="$root/.claude/skills/pr-security-review/classify.sh"
base="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
[[ -z "$base" ]] && base="origin/main"

if [[ -f "$classify" ]]; then
  dims="$( cd "$cwd" && bash "$classify" "$base" 2>/dev/null || true )"
  [[ -z "$dims" ]] && exit 0        # docs/config-only — nothing to validate; allow
fi
# classify missing (degraded install) OR the diff touches code/infra/surface -> require.

# Fail closed: a built slice can't have validly passed if the gate agents aren't
# even installed. Security fails closed the same way (no reviewer -> no PASS verdict).
for a in implementation-validator correctness-reviewer; do
  [[ -f "$root/.claude/agents/${a}.md" ]] || \
    block "the '${a}' gate agent isn't installed — the acceptance/correctness barrier can't have run. Fix the install (proj update-skills; ensure jq + yq present), then rebuild the slice through /next."
done

block "this slice was built in a task worktree but has no post-build barrier verdict for HEAD ($sha). Run the barrier (the acceptance + correctness gates) via /next before opening the PR — or, opening it by hand, record the verdict at \$GITDIR/barrier-review/$sha (acceptance PASS / correctness PASS)."
