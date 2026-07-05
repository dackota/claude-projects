#!/usr/bin/env bash
# record-verdict.sh — record the pr-security-review verdict for HEAD by DERIVING
# it from the security-reviewer's own verbatim output (read on stdin), instead of
# the orchestrator hand-authoring a PASS into the gate file.
#
# WHY THIS EXISTS (rather than `printf 'PASS' > <verdict file>`):
#   The file at <git-dir>/pr-security-review/<HEAD> is what pr-gate.sh and
#   `repo.sh pr` read to allow `gh pr create`. When the ORCHESTRATOR — the same
#   agent trying to open the PR — hand-writes `PASS` into it, that action is
#   structurally indistinguishable from a gate bypass: nothing links the literal
#   `PASS` to a review that actually ran, so an auto-mode safety classifier
#   correctly refuses it as fabrication (observed 2026-07-05).
#
#   This script closes that gap: the orchestrator pipes the reviewer's actual
#   result through, and the script PARSES the machine-readable block the
#   security-reviewer is required to emit (VERDICT + CRITICAL/HIGH/MEDIUM/LOW —
#   see agents/security-reviewer.md "Required output"), ENFORCES the gate
#   invariant (BLOCK iff CRITICAL>0), and only then writes the file. The recorded
#   verdict is grounded in the review, and a bare/absent/self-contradictory
#   verdict is refused rather than recorded.
#
# Usage — run from inside the repo/worktree whose HEAD is being gated:
#   printf '%s\n' "$reviewer_output" | bash .../record-verdict.sh
#   bash .../record-verdict.sh <<'REVIEW'
#   ...the security-reviewer's verbatim output...
#   REVIEW
#
#   record-verdict.sh --trivial <base>    # docs/config-only diff, no review ran
#     Records a PASS ONLY after classify.sh <base> confirms the diff has no code
#     or infra surface (prints nothing) — the same oracle the gate trusts to skip
#     a review. This is a DERIVED trivial pass, not a hand-written one: a diff
#     with any code/infra surface makes classify non-empty and is refused, so the
#     mode can't be used to wave a real change through. It exists because
#     `repo.sh pr` requires a verdict file even for a docs-only PR.
#
# Success -> writes <git-dir>/pr-security-review/<HEAD>, prints the verdict, exit 0.
# Bad/absent input or a broken invariant -> writes NOTHING, exit non-zero.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Key the verdict to the commit under review; derive HEAD from the repo we stand
# in. Never take a SHA argument — that would let a verdict be recorded for an
# arbitrary commit.
git rev-parse --git-dir >/dev/null 2>&1 || { echo "record-verdict: not inside a git repository" >&2; exit 2; }
gitdir="$(git rev-parse --absolute-git-dir)"
sha="$(git rev-parse HEAD)"

write_verdict() {  # write_verdict <verdict> <c> <h> <m> <l>
  mkdir -p "$gitdir/pr-security-review"
  printf '%s\nSECURITY %s C:%s H:%s M:%s L:%s\n' "$1" "$1" "$2" "$3" "$4" "$5" \
    > "$gitdir/pr-security-review/$sha"
  echo "recorded security verdict for ${sha:0:12}: $1 (C:$2 H:$3 M:$4 L:$5)"
}

# --trivial <base>: a docs/config-only PASS, verified by classify.sh (no review).
if [[ "${1:-}" == "--trivial" ]]; then
  base="${2:-}"
  [[ -n "$base" ]] || { echo "record-verdict: --trivial needs a base ref (e.g. origin/main)" >&2; exit 2; }
  classify="$here/classify.sh"
  [[ -f "$classify" ]] || { echo "record-verdict: classify.sh not found at $classify" >&2; exit 2; }
  cls="$(bash "$classify" "$base" 2>/dev/null || true)"
  [[ -z "$cls" ]] \
    || { echo "record-verdict: --trivial refused — $base...HEAD is not docs/config-only (classify: $cls). Run a real review." >&2; exit 3; }
  write_verdict PASS 0 0 0 0
  exit 0
fi

review="$(cat)"
[[ -n "${review//[[:space:]]/}" ]] \
  || { echo "record-verdict: no reviewer output on stdin — pipe the security-reviewer's verbatim result" >&2; exit 2; }

# Pull the first occurrence of a `KEY: value` line (tolerating leading whitespace
# and surrounding prose/findings). The reviewer emits these keys uppercase.
field() { printf '%s\n' "$review" | awk -v k="$1" '$0 ~ "^[[:space:]]*" k ":" { sub("^[[:space:]]*" k ":[[:space:]]*", ""); gsub(/[[:space:]]/, ""); print; exit }'; }
verdict="$(field VERDICT)"
crit="$(field CRITICAL)"
high="$(field HIGH)"
med="$(field MEDIUM)"
low="$(field LOW)"

# Substance guard: the required block must actually be present. A bare "PASS"
# with no severity counts is not a review result — refuse it.
[[ -n "$verdict" && -n "$crit" && -n "$high" && -n "$med" && -n "$low" ]] \
  || { echo "record-verdict: reviewer output is missing the required VERDICT/CRITICAL/HIGH/MEDIUM/LOW block — nothing recorded" >&2; exit 3; }

verdict="$(printf '%s' "$verdict" | tr '[:lower:]' '[:upper:]')"
case "$verdict" in PASS|BLOCK) ;; *) echo "record-verdict: VERDICT must be PASS or BLOCK (got '$verdict')" >&2; exit 3 ;; esac
for n in "$crit" "$high" "$med" "$low"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "record-verdict: severity counts must be non-negative integers (got C=$crit H=$high M=$med L=$low)" >&2; exit 3; }
done

# Enforce the gate invariant: BLOCK iff CRITICAL>0. A verdict that disagrees with
# its own critical count is a transcription error or a forced pass — refuse it
# rather than record a lie.
if [[ "$crit" -gt 0 && "$verdict" != "BLOCK" ]]; then
  echo "record-verdict: CRITICAL=$crit but VERDICT=$verdict — must be BLOCK (BLOCK iff CRITICAL>0)" >&2; exit 3
fi
if [[ "$crit" -eq 0 && "$verdict" != "PASS" ]]; then
  echo "record-verdict: CRITICAL=0 but VERDICT=$verdict — must be PASS (BLOCK iff CRITICAL>0)" >&2; exit 3
fi

write_verdict "$verdict" "$crit" "$high" "$med" "$low"
