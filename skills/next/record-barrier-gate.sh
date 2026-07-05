#!/usr/bin/env bash
# record-barrier-gate.sh <gate> [--skip --reason "<why>"] — record ONE post-build
# barrier gate's verdict for HEAD.
#
# Two modes:
#
#   1. DERIVE (default) — read that gate agent's verbatim output on stdin and DERIVE
#      the verdict from its `VERDICT:` line, instead of the orchestrator hand-authoring
#      the barrier-review file. Same rationale as pr-security-review/record-verdict.sh
#      (read its header): the orchestrator hand-writing `<gate> PASS` into
#      <git-dir>/barrier-review/<HEAD> is indistinguishable from a gate bypass to an
#      auto-mode safety classifier. This parses the gate agent's actual `VERDICT:` line,
#      validates it against what the gate is allowed to return, and upserts `<gate>
#      <verdict>` — so the recorded verdict is grounded in a review that ran.
#
#   2. SKIP (--skip --reason "<why>") — record an INTENTIONAL, per-run skip of a gate
#      that would otherwise run. A skip has no gate-agent output to derive from, so the
#      invariant is "no SILENT skip": the skip is honored only if it carries a non-empty
#      REASON, which this recorder REFUSES to omit. ANY gate may be intentionally skipped
#      this way. The reason is the sole audit control on a self-initiated skip and is
#      surfaced loudly downstream (PR body, STATUS.md, journal). See next/BARRIER.md
#      ("Skipping a gate for one run").
#
# <gate> is one of: acceptance | correctness | runtime | observability.
# On the DERIVE path the gate agents emit `VERDICT: PASS|BLOCK` (runtime additionally
# `SKIP` for no-runnable-surface); a *derived* SKIP stays runtime-only. An INTENTIONAL
# --skip records `SKIP <reason>` for any gate.
# Call once per gate; the calls may run in parallel in one message, and re-recording a
# gate overwrites just that gate's line (idempotent upsert).
#
# Success -> upserts the gate's line into barrier-review/<HEAD>, exit 0.
# Bad gate / verdict / input / missing reason -> exit non-zero, file unchanged.
set -euo pipefail

gate="${1:-}"
case "$gate" in
  acceptance|correctness|runtime|observability) ;;
  *) echo "record-barrier-gate: gate must be acceptance|correctness|runtime|observability (got '${gate:-}')" >&2; exit 2 ;;
esac
shift || true

# ── parse optional flags (intentional-skip mode) ──────────────────────────────
skip=0; reason=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip)   skip=1; shift ;;
    --reason) reason="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    *) echo "record-barrier-gate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# --reason only means anything with --skip; without it the verdict is DERIVED from stdin.
# Fail loudly rather than silently ignoring --reason and blocking on an empty stdin read.
if [[ "$skip" == 0 && -n "$reason" ]]; then
  echo "record-barrier-gate: --reason requires --skip (the derive path takes the verdict from stdin, not --reason)" >&2
  exit 2
fi

git rev-parse --git-dir >/dev/null 2>&1 || { echo "record-barrier-gate: not inside a git repository" >&2; exit 2; }
gitdir="$(git rev-parse --absolute-git-dir)"
sha="$(git rev-parse HEAD)"

reason_field=""
if [[ "$skip" == 1 ]]; then
  # INTENTIONAL skip: reason is mandatory and non-empty (collapsed to a single line so
  # the barrier-review file stays one line per gate).
  reason="$(printf '%s' "$reason" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//')"
  [[ -n "$reason" ]] \
    || { echo "record-barrier-gate: --skip requires a non-empty --reason (a skip must state why — no silent skip)" >&2; exit 2; }
  verdict="SKIP"
  reason_field=" $reason"
else
  # DERIVE: read the gate agent's verbatim output on stdin.
  out="$(cat)"
  [[ -n "${out//[[:space:]]/}" ]] \
    || { echo "record-barrier-gate: no gate output on stdin — pipe the $gate gate's verbatim result (or use --skip --reason to skip it)" >&2; exit 2; }

  verdict="$(printf '%s\n' "$out" | awk '$0 ~ /^[[:space:]]*VERDICT:/ { sub(/^[[:space:]]*VERDICT:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }')"
  [[ -n "$verdict" ]] \
    || { echo "record-barrier-gate: gate output has no VERDICT: line — nothing recorded" >&2; exit 3; }
  verdict="$(printf '%s' "$verdict" | tr '[:lower:]' '[:upper:]')"

  # A DERIVED SKIP is only meaningful for the runtime gate (no runnable surface /
  # missing dep). To intentionally skip any other gate, use --skip --reason.
  case "$gate:$verdict" in
    runtime:PASS|runtime:BLOCK|runtime:SKIP) ;;
    acceptance:PASS|acceptance:BLOCK|correctness:PASS|correctness:BLOCK|observability:PASS|observability:BLOCK) ;;
    *) echo "record-barrier-gate: verdict '$verdict' not valid for gate '$gate' (a derived SKIP is runtime-only; use --skip --reason to skip another gate)" >&2; exit 3 ;;
  esac
fi

mkdir -p "$gitdir/barrier-review"
file="$gitdir/barrier-review/$sha"
tmp="$file.tmp.$$"
# Upsert: drop any prior line for this gate, keep the rest, append the fresh one.
if [[ -f "$file" ]]; then
  awk -v g="$gate" '$1 != g' "$file" > "$tmp"
else
  : > "$tmp"
fi
printf '%s %s%s\n' "$gate" "$verdict" "$reason_field" >> "$tmp"
mv "$tmp" "$file"
echo "recorded barrier gate for ${sha:0:12}: $gate $verdict${reason_field}"
