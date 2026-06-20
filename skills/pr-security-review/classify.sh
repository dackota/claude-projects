#!/usr/bin/env bash
# classify.sh [base-ref] — classify the pre-PR diff into security-review dimensions.
#
# Prints any combination of "code" and "infra" (space-separated), or nothing if
# the diff touches neither (e.g. a docs-only PR). Used by the pr-security-review
# skill to decide which checklist(s) the reviewer applies.
#
#   code  -> app source -> security-review checklist
#   infra -> IaC / pipelines / cloud config -> cloud-infra-security checklist

set -euo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  base="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [[ -z "$base" ]] && base="origin/main"
fi

mb="$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")"
files="$(git diff --name-only "$mb...HEAD" 2>/dev/null || true)"
[[ -z "$files" ]] && exit 0

code=0
infra=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    # ── infra: IaC, pipelines, containers, k8s/helm, cloud config ─────────────
    *.tf|*.tfvars|*.hcl|*.tpl)                 infra=1 ;;
    *.yaml|*.yml)                              infra=1 ;;
    Dockerfile|*/Dockerfile|*.Dockerfile)      infra=1 ;;
    # ── code: application source ──────────────────────────────────────────────
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)         code=1 ;;
    *.py|*.go|*.rb|*.java|*.kt|*.rs|*.php)     code=1 ;;
    *.cs|*.c|*.h|*.cpp|*.cc|*.scala|*.swift)   code=1 ;;
    *.sh|*.bash)                               code=1 ;;
    *) : ;;  # docs, json, lockfiles, etc. — no dimension
  esac
done <<< "$files"

out=""
[[ $code  -eq 1 ]] && out="code"
[[ $infra -eq 1 ]] && out="${out:+$out }infra"
[[ -n "$out" ]] && echo "$out"
exit 0
