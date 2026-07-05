#!/usr/bin/env bash
# record-barrier-gate.sh <gate> — record ONE post-build barrier gate's verdict for
# HEAD by DERIVING it from that gate agent's own verbatim output (read on stdin),
# instead of the orchestrator hand-authoring the barrier-review file.
#
# Same rationale as pr-security-review/record-verdict.sh (read its header): the
# orchestrator hand-writing `<gate> PASS` into <git-dir>/barrier-review/<HEAD> is
# indistinguishable from a gate bypass to an auto-mode safety classifier. This
# parses the gate agent's actual `VERDICT:` line, validates it against what the
# gate is allowed to return, and upserts `<gate> <verdict>` — so the recorded
# verdict is grounded in a review that ran.
#
# <gate> is one of: acceptance | correctness | runtime | observability.
# The gate agents emit `VERDICT: PASS|BLOCK` (runtime additionally `SKIP`).
# Call once per gate that ran; the calls may run in parallel in one message,
# and re-recording a gate overwrites just that gate's line (idempotent upsert).
#
# Success -> upserts the gate's line into barrier-review/<HEAD>, exit 0.
# Bad gate / verdict / input -> exit non-zero, file unchanged.
set -euo pipefail

gate="${1:-}"
case "$gate" in
  acceptance|correctness|runtime|observability) ;;
  *) echo "record-barrier-gate: gate must be acceptance|correctness|runtime|observability (got '${gate:-}')" >&2; exit 2 ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || { echo "record-barrier-gate: not inside a git repository" >&2; exit 2; }
gitdir="$(git rev-parse --absolute-git-dir)"
sha="$(git rev-parse HEAD)"

out="$(cat)"
[[ -n "${out//[[:space:]]/}" ]] \
  || { echo "record-barrier-gate: no gate output on stdin — pipe the $gate gate's verbatim result" >&2; exit 2; }

verdict="$(printf '%s\n' "$out" | awk '$0 ~ /^[[:space:]]*VERDICT:/ { sub(/^[[:space:]]*VERDICT:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }')"
[[ -n "$verdict" ]] \
  || { echo "record-barrier-gate: gate output has no VERDICT: line — nothing recorded" >&2; exit 3; }
verdict="$(printf '%s' "$verdict" | tr '[:lower:]' '[:upper:]')"

# SKIP is only meaningful for the runtime gate (no runnable surface / missing dep).
case "$gate:$verdict" in
  runtime:PASS|runtime:BLOCK|runtime:SKIP) ;;
  acceptance:PASS|acceptance:BLOCK|correctness:PASS|correctness:BLOCK|observability:PASS|observability:BLOCK) ;;
  *) echo "record-barrier-gate: verdict '$verdict' not valid for gate '$gate' (SKIP is runtime-only)" >&2; exit 3 ;;
esac

mkdir -p "$gitdir/barrier-review"
file="$gitdir/barrier-review/$sha"
tmp="$file.tmp.$$"
# Upsert: drop any prior line for this gate, keep the rest, append the fresh one.
if [[ -f "$file" ]]; then
  awk -v g="$gate" '$1 != g' "$file" > "$tmp"
else
  : > "$tmp"
fi
printf '%s %s\n' "$gate" "$verdict" >> "$tmp"
mv "$tmp" "$file"
echo "recorded barrier gate for ${sha:0:12}: $gate $verdict"
