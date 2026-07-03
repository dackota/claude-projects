#!/usr/bin/env bash
# rollup.sh — cross-workspace outcome rollup (harness improvement plan B1 + B2).
#
# Reads the structured `type: run` / `type: blocker` journal entries enforced by
# the A1 schema hooks and reports the outcomes the efficiency audit had to hand-
# derive: block rate, block-by-gate, rework, runtime-SKIP rate, escapes-found-live,
# and human interventions. Deterministic — it counts fields, it does not estimate.
#
# Usage:  rollup.sh <workspace-dir> [<workspace-dir> ...]
#         each dir is a workspace root containing journal.yaml.
#
# Parsing is POSIX awk (must run under macOS BSD awk): no gensub / 3-arg match.

set -uo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: rollup.sh <workspace-dir> [<workspace-dir> ...]" >&2
  exit 2
fi

scanned=0
with_run=0
files=()
for d in "$@"; do
  j="$d/journal.yaml"
  [[ -f "$j" ]] || continue
  scanned=$((scanned + 1))
  files+=("$j")
  n=$(grep -cE '^  type:[[:space:]]*run[[:space:]]*$' "$j" 2>/dev/null || true)
  [[ "${n:-0}" -gt 0 ]] && with_run=$((with_run + 1))
done

awk -v scanned="$scanned" -v withrun="$with_run" '
  function val(line,   v) {
    v = line
    sub(/^  [a-z_]+:[[:space:]]*/, "", v)
    sub(/[[:space:]#].*$/, "", v)
    return v
  }
  function flush() {
    if (type == "run") {
      runs++
      if (verdict == "PASS") pass++
      else if (verdict == "BLOCK") { block++; if (task != "") btask[task] = 1 }
      else if (verdict == "SKIP") skip++
      gruns[agent]++
      if (verdict == "BLOCK") gblock[agent]++
      if (verdict == "SKIP")  gskip[agent]++
      if (escape == "true") escapes++
      if (approver != "" && approver != "null") approvals++
      r = rework + 0; if (r > maxrework) maxrework = r
    } else if (type == "blocker") {
      blockers++
    }
  }
  /^-[[:space:]]/ { flush(); type=""; agent=""; verdict=""; task=""; rework="0"; escape=""; approver="" }
  /^  type:/     { type=val($0) }
  /^  agent:/    { agent=val($0) }
  /^  verdict:/  { verdict=val($0) }
  /^  task:/     { task=val($0) }
  /^  rework:/   { rework=val($0) }
  /^  escape:/   { escape=val($0) }
  /^  approver:/ { approver=val($0) }
  END {
    flush()
    decided = pass + block
    rate = (decided > 0) ? int((block * 100.0) / decided + 0.5) : 0
    ntask = 0; for (k in btask) ntask++
    rt_runs = gruns["runtime-validator"] + 0
    rt_skip = gskip["runtime-validator"] + 0

    printf "Harness outcome rollup — %d workspace(s) scanned, %d with gate runs\n\n", scanned, withrun
    printf "Gate runs: %d (PASS %d / BLOCK %d / SKIP %d) — block rate %d%% (%d/%d decided)\n", \
      runs, pass, block, skip, rate, block, decided
    printf "By gate:   acceptance %d/%d · correctness %d/%d · runtime %d/%d · security %d/%d · observability %d/%d\n", \
      gblock["implementation-validator"]+0, gruns["implementation-validator"]+0, \
      gblock["correctness-reviewer"]+0,     gruns["correctness-reviewer"]+0, \
      gblock["runtime-validator"]+0,        gruns["runtime-validator"]+0, \
      gblock["security-reviewer"]+0,        gruns["security-reviewer"]+0, \
      gblock["otel-observability-engineer"]+0, gruns["otel-observability-engineer"]+0
    printf "Rework:    %d loop-back(s) across %d task(s); max rework %d\n", block, ntask, maxrework
    printf "Runtime SKIP: %d/%d runtime run(s) skipped\n", rt_skip, rt_runs
    printf "Escapes (found live): %d\n", escapes
    printf "Human interventions: %d blocker(s) + %d approval(s)\n", blockers, approvals
  }
' "${files[@]:-/dev/null}"
