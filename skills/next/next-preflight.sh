#!/usr/bin/env bash
# next-preflight.sh — verify /next's pipeline is actually installed before routing.
#
# `skill_deps` guarantees the happy-path install pulls the right skills, but a
# degraded install (yq missing at scaffold → agents silently absent, manual
# tampering, a partial copy) can leave /next running a barrier whose gate agents,
# repo tooling, or PR-security hook don't exist — worktree ops fail loudly, but a
# missing security gate ships PRs silently. This names what's missing, up front.
#
# Run from the workspace root (or set CLAUDE_PROJECT_DIR). Exits 0 when whole,
# 1 when anything required is missing (listing each gap on stderr).

set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
settings="$root/.claude/settings.json"
missing=0

report() { echo "  [MISSING] $1" >&2; missing=$((missing + 1)); }

# Required scripts (worktree/repo ops).
[[ -f "$root/scripts/repo.sh" ]] || report "scripts/repo.sh (repo/worktree operations)"

# Required gate + build agents.
for a in tdd-implementer implementation-validator correctness-reviewer runtime-validator security-reviewer; do
  [[ -f "$root/.claude/agents/${a}.md" ]] || report "agent: ${a}"
done

# Required companion skills.
for s in next journal sync-status repo pr-security-review tdd; do
  [[ -d "$root/.claude/skills/${s}" ]] || report "skill: ${s}"
done

# Required hooks wired in settings.json (name-based; independent of jq).
if [[ -f "$settings" ]]; then
  for h in run-check rework-cap barrier-gate journal-stop pr-gate git-guard sync-status-stop; do
    grep -q "${h}" "$settings" || report "hook wiring: ${h}"
  done
else
  report ".claude/settings.json (no hooks wired)"
fi

if [[ "$missing" -gt 0 ]]; then
  echo "next-preflight: ${missing} required component(s) missing — the pipeline is incomplete." >&2
  echo "Fix with 'proj update-skills' (ensure jq + yq are installed), or re-scaffold. Do not route /next until resolved." >&2
  exit 1
fi
echo "next-preflight: pipeline intact (scripts, agents, skills, hooks all present)."
exit 0
