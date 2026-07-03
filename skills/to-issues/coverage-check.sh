#!/usr/bin/env bash
# coverage-check.sh — assert every PRD requirement is owned by a slice.
#
# The escape class the canary surfaced: a requirement no slice owns reaches
# production because nothing was responsible for building it — it passes every
# build gate because there is no diff to review. Build-time gates can't catch it;
# decomposition must. This turns to-issues' coverage map from unverified prose into
# a deterministic check: it reads the PRD's enumerated requirement IDs and the
# `covers:` list on each slice, and fails if any requirement is owned by no slice.
#
# Usage:  coverage-check.sh <prd.md> [project.yaml]
#   Requirements are lines in the PRD like `- R1: <behavioral requirement>`.
#   Ownership is the `covers: [R1, R4]` list on tasks whose `plan` is this PRD.
# Exit: 0 all owned · 1 an unowned requirement · 2 usage/environment error.

set -uo pipefail

prd="${1:-}"
project="${2:-project.yaml}"

[[ -n "$prd" && -f "$prd" ]] || { echo "coverage-check: PRD not found: '${prd}'" >&2; exit 2; }
[[ -f "$project" ]] || { echo "coverage-check: project.yaml not found: '${project}'" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "coverage-check: yq is required. Install: brew install yq" >&2; exit 2; }

prd_base=$(basename "$prd")

# Enumerated requirement IDs from the PRD (`- R<n>: ...`).
reqs=$(grep -oE '^-[[:space:]]*R[0-9]+:' "$prd" | grep -oE 'R[0-9]+' | sort -u)
if [[ -z "$reqs" ]]; then
  echo "coverage-check: no requirements found in ${prd_base} — expected a '## Requirements' section with '- R<n>:' lines." >&2
  exit 2
fi

# Requirement IDs owned by a slice whose plan is this PRD.
covered=$(yq -r '.tasks[]? | select((.plan // "") | test("'"$prd_base"'$")) | .covers[]?' "$project" 2>/dev/null | grep -oE 'R[0-9]+' | sort -u)

unowned=$(comm -23 <(printf '%s\n' "$reqs") <(printf '%s\n' "$covered"))

if [[ -n "$unowned" ]]; then
  echo "coverage-check: FAIL — requirement(s) in ${prd_base} owned by no slice:" >&2
  printf '  %s\n' $unowned >&2
  echo "Add a slice that owns each, fold it into an existing slice, or record it out of scope with the user — never publish with an unowned requirement." >&2
  exit 1
fi

echo "coverage-check: OK — every requirement in ${prd_base} is owned by a slice ($(printf '%s\n' "$reqs" | grep -c .) total)."
exit 0
