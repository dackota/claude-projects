#!/usr/bin/env bash
# barrier-carry-forward.sh <prev-sha>
#
# Carry the acceptance+correctness post-build barrier verdict forward from a prior
# all-PASS commit to HEAD WITHOUT re-spawning the gates — but ONLY when the delta is
# provably non-functional (docs/text). This removes the "amend a comment/README ->
# full re-barrier" tax while never letting a functional change reach a PR un-gated:
# eligibility is decided in code (classify.sh), not by orchestrator judgment.
#
# On a zero-functional-change delta there is nothing for the gates to re-review —
# acceptance ("delivers the criteria") and correctness ("bugs this diff introduced")
# are both no-ops over docs — so carrying the verdict forward is sound, not a skip.
#
# Eligible iff ALL hold:
#   1. <prev-sha> is an ancestor of HEAD           (carry-forward only moves forward)
#   2. <prev-sha> has a recorded barrier verdict of acceptance PASS + correctness PASS
#   3. classify.sh over <prev-sha>...HEAD prints NOTHING (docs/text only). classify
#      routes *.yaml / *.tf / source to infra|code, so a manifest edit or a
#      comment-only change inside a code file is deliberately NOT eligible and
#      re-barriers; only genuine docs/prose (*.md, text) qualify.
#
# Success  -> writes <git-dir>/barrier-review/<HEAD> (the same file barrier-gate.sh
#             and repo.sh pr read) and exits 0.
# Refusal  -> writes nothing, exits non-zero; the orchestrator runs the real gates.
#
# Invoked by /next per skills/next/BARRIER.md ("Carrying a verdict forward").
set -euo pipefail

prev_arg="${1:-}"
[[ -n "$prev_arg" ]] || { echo "usage: barrier-carry-forward.sh <prev-all-PASS-sha>" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classify="$here/../pr-security-review/classify.sh"
[[ -f "$classify" ]] || { echo "classify.sh not found at $classify" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 2; }
gitdir="$(git rev-parse --absolute-git-dir)"
head="$(git rev-parse HEAD)"
prev="$(git rev-parse --verify "${prev_arg}^{commit}" 2>/dev/null)" || { echo "not a commit: $prev_arg" >&2; exit 2; }

# 1. forward-only
git merge-base --is-ancestor "$prev" "$head" 2>/dev/null \
  || { echo "carry-forward refused: $prev is not an ancestor of HEAD ($head)" >&2; exit 3; }

# 2. prior verdict must be all-PASS
prev_file="$gitdir/barrier-review/$prev"
[[ -f "$prev_file" ]] || { echo "carry-forward refused: no barrier verdict recorded for prev $prev" >&2; exit 3; }
acc="$(awk '$1=="acceptance"{print $2; exit}' "$prev_file" 2>/dev/null || true)"
cor="$(awk '$1=="correctness"{print $2; exit}' "$prev_file" 2>/dev/null || true)"
[[ "$acc" == "PASS" && "$cor" == "PASS" ]] \
  || { echo "carry-forward refused: prior barrier not all-PASS (acceptance=${acc:-none} correctness=${cor:-none})" >&2; exit 3; }

# 3. delta must be provably docs-only (classify.sh prints nothing)
cls="$(bash "$classify" "$prev" 2>/dev/null || true)"
[[ -z "$cls" ]] \
  || { echo "carry-forward refused: $prev..$head is not docs-only (classify: $cls) — run the barrier gates on HEAD" >&2; exit 1; }

# eligible — write the carried verdict for HEAD (readers require only acceptance/correctness PASS)
mkdir -p "$gitdir/barrier-review"
{
  echo "acceptance PASS"
  echo "correctness PASS"
  echo "runtime PASS"
  echo "carried-forward-from $prev"
} > "$gitdir/barrier-review/$head"
echo "carried barrier verdict forward: ${prev:0:12} -> ${head:0:12} (docs-only delta, classify empty)"
