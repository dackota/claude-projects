#!/usr/bin/env bash
# classify.sh [base-ref] — classify the pre-PR diff into security-review dimensions.
#
# Prints any combination of "code", "infra", and "surface" (space-separated), or
# nothing when the diff is docs/config-only with no trust boundary. Used by the
# pr-security-review skill and pr-gate.sh to decide whether a security review fires.
#
#   code    -> app source (runnable) -> security-review checklist / runtime gate
#   infra   -> IaC / pipelines / cloud config -> cloud-infra-security checklist
#   surface -> the code diff touches a trust boundary (network, DB/SQL, exec, env,
#              file I/O, templates, secrets/crypto) -> a security review is required
#              even for a small diff.
#
# A code diff with NO "surface" and no "infra" is a *pure module* (pure logic, no I/O
# or trust boundary): the security-reviewer spawn is skipped for it (the
# correctness-reviewer records any security obligations it imposes on future callers,
# so the deferred-security ledger isn't lost). The trust-boundary marker set is
# tunable via PR_SECURITY_SURFACE_MARKERS (an extended-regex that overrides the
# default); the default is a starting point, finalized per project.
#
# Inherent surfaces: *.sql (DDL/DML — the DB boundary) and *.env* files (secrets/
# config) register "surface" by file type alone. *.json is ambiguous (fixture,
# config, IaC template), so its added lines are content-scanned: IaC markers
# (CloudFormation/IAM policy/ARM/k8s) -> infra; secret-ish markers -> surface.
# package-lock.json is ignored as lockfile churn.

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
surface=0
code_files=()
json_files=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    # ── infra: IaC, pipelines, containers, k8s/helm, cloud config ─────────────
    *.tf|*.tfvars|*.hcl|*.tpl)                 infra=1 ;;
    *.yaml|*.yml)                              infra=1 ;;
    Dockerfile|*/Dockerfile|*.Dockerfile)      infra=1 ;;
    # ── inherent trust boundaries: the file type IS the surface, no scan needed ─
    *.sql)                                     code=1; surface=1 ;;  # DDL/DML = the DB boundary
    *.env|*.env.*|*.envrc)                     surface=1 ;;          # secrets/config by definition
    # ── code: application source (also scanned for a trust-boundary surface) ───
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)         code=1; code_files+=("$f") ;;
    *.py|*.go|*.rb|*.java|*.kt|*.rs|*.php)     code=1; code_files+=("$f") ;;
    *.cs|*.c|*.h|*.cpp|*.cc|*.scala|*.swift)   code=1; code_files+=("$f") ;;
    *.sh|*.bash)                               code=1; code_files+=("$f") ;;
    # ── json: ambiguous (fixture, config, IaC template) — content-scanned below ─
    package-lock.json|*/package-lock.json)     : ;;  # lockfile churn — no dimension
    *.json)                                    json_files+=("$f") ;;
    *) : ;;  # docs, lockfiles, etc. — no dimension
  esac
done <<< "$files"

# Content scan: does the code diff introduce a trust-boundary surface? Scan only the
# added/modified lines (`^+`, excluding the `+++` header) of the changed code files —
# it is what the diff *touches* that matters, not the whole file. Erring broad here is
# safe: a false "surface" costs an extra review, a missed one skips a needed review.
DEFAULT_MARKERS='net/http|https?://|net\.Dial|[^a-zA-Z]socket|websocket|requests\.(get|post|put|delete|patch|request)|httpx|urllib|fetch\(|axios|database/sql|[^a-zA-Z]sql\.|SELECT[[:space:]]|INSERT[[:space:]]|UPDATE[[:space:]]|DELETE[[:space:]]|psycopg|sqlite|sequelize|prisma|mongoose|[^a-zA-Z]gorm|os/exec|exec\.command|subprocess|child_process|runtime\.exec|[^a-zA-Z]popen|[^a-zA-Z]system\(|os\.getenv|process\.env|getenv|environ|html/template|text/template|render_template|jinja|[^a-zA-Z]crypto|[^a-zA-Z]hmac|[^a-zA-Z]jwt|bcrypt|api[_-]?key|[^a-zA-Z]secret|password|[^a-zA-Z]token|writefile|fs\.write|ioutil\.|os\.open'
MARKERS="${PR_SECURITY_SURFACE_MARKERS:-$DEFAULT_MARKERS}"
if [[ ${#code_files[@]} -gt 0 ]]; then
  if git diff "$mb...HEAD" -- "${code_files[@]}" 2>/dev/null \
       | grep -E '^\+' | grep -Ev '^\+\+\+' \
       | grep -Eiq "$MARKERS"; then
    surface=1
  fi
fi

# JSON content scan: the added lines decide the dimension. Marker sets are kept
# narrower than the code set so fixture/lockfile churn (URLs, hashes) doesn't
# force reviews — only IaC shapes and secret-ish keys register.
JSON_INFRA_MARKERS='AWSTemplateFormatVersion|arn:aws|"(AssumeRole)?PolicyDocument"|"Effect"[[:space:]]*:[[:space:]]*"(Allow|Deny)"|deploymentTemplate\.json|"apiVersion"[[:space:]]*:'
JSON_SURFACE_MARKERS='api[_-]?key|[^a-zA-Z]secret|password|[^a-zA-Z]token|private[_-]?key|credential|BEGIN [A-Z ]*PRIVATE KEY'
if [[ ${#json_files[@]} -gt 0 ]]; then
  json_added="$(git diff "$mb...HEAD" -- "${json_files[@]}" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+' || true)"
  if [[ -n "$json_added" ]]; then
    if grep -Eiq "$JSON_INFRA_MARKERS" <<< "$json_added"; then infra=1; fi
    if grep -Eiq "$JSON_SURFACE_MARKERS" <<< "$json_added"; then surface=1; fi
  fi
fi

out=""
[[ $code    -eq 1 ]] && out="code"
[[ $infra   -eq 1 ]] && out="${out:+$out }infra"
[[ $surface -eq 1 ]] && out="${out:+$out }surface"
[[ -n "$out" ]] && echo "$out"
exit 0
