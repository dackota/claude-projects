#!/usr/bin/env bash
# PreToolUse(Bash) hook: gate `gh pr create` on the PR security review.
#
# Acceptance (does the slice deliver what it promised?) is validated earlier, by
# /next's post-build gate — NOT here. This gate is the security lens only.
#
# Decision order for the current HEAD commit:
#   1. A verdict already recorded (manual or prior run) -> honor it (PASS allow,
#      BLOCK block). A manual `/pr-security-review` therefore always wins.
#   2. No verdict, infra files in the diff -> require review (any size — a
#      one-line IAM/security-group/bucket change is the small-but-critical case).
#   3. No verdict, no security-relevant files (docs/config only) -> allow.
#   4. No verdict, code-only and <= PR_SECURITY_MAX_SMALL_LINES (default 25)
#      changed lines -> allow (small change skips; review still available by
#      running the pr-security-review skill manually).
#   5. Otherwise (larger code change) -> require review.
#
# Reads the Claude Code PreToolUse payload (JSON) on stdin.

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"

[[ -z "$cmd" ]] && exit 0

# Only gate PR creation.
printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+create' || exit 0

block() { echo "🔒 PR review gate: $1" >&2; exit 2; }

cwd="${cwd:-$PWD}"

# This hook fires BEFORE the command runs, so the payload's cwd is the session's
# working directory as it was *before* the command — stale for the common
# `cd <worktree> && gh pr create …` idiom (parallel work across worktrees drifts
# that one shared cwd). Honor a leading cd, but ONLY in the exact, unambiguous
# shape `cd <dir> && gh pr create …`: a single cd immediately followed by the gh
# command, with nothing else before it. Regex cannot safely emulate shell cwd
# resolution — a second cd can hide in a subshell `( … )`, brace group `{ …; }`,
# command substitution `$( … )`, or control flow — so we whitelist that one shape
# (bare or double-quoted <dir>) and fall back to the payload cwd (fail closed) for
# anything else, never guessing where gh actually runs.
_cd="$(printf '%s' "$cmd" | sed -nE 's/^[[:space:]]*cd[[:space:]]+("[^"]+"|[^[:space:]&;|(){}$]+)[[:space:]]*&&[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]].*)?$/\1/p')"
if [[ -n "$_cd" ]]; then
  _cd="${_cd#\"}"; _cd="${_cd%\"}"   # strip surrounding double quotes, if present
  case "$_cd" in
    /*) cwd="$_cd" ;;
    *)  cwd="$cwd/$_cd" ;;
  esac
fi
gitdir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null || true)"
sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)"
[[ -z "$gitdir" || -z "$sha" ]] && \
  block "can't resolve git repo/HEAD from the command's directory — run gh pr create inside the repo."

# 1. Honor an existing verdict (a manual review always takes precedence).
verdict_file="$gitdir/pr-security-review/$sha"
if [[ -f "$verdict_file" ]]; then
  verdict="$(head -n1 "$verdict_file" 2>/dev/null || echo BLOCK)"
  case "$verdict" in
    PASS) exit 0 ;;
    *)    block "PR review found CRITICAL issue(s) for HEAD ($sha). Fix them — the fix is a new commit, which re-reviews automatically — then re-run gh pr create." ;;
  esac
fi

# No verdict yet. Decide whether the security lens is exempt.
MAX="${PR_SECURITY_MAX_SMALL_LINES:-25}"

base="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
[[ -z "$base" ]] && base="origin/main"

# Classify the diff via the bundled classifier (path resolved from this hook).
hook_dir="$(cd "$(dirname "$0")" && pwd)"
classify="$hook_dir/../classify.sh"
if ! dims="$( cd "$cwd" && bash "$classify" "$base" 2>/dev/null )"; then
  block "couldn't classify the diff — run the pr-security-review skill manually to review before opening the PR."
fi

# 2. Infra (even one line) always requires review.
case " $dims " in
  *" infra "*) block "infra changes require a security review at any size. Run the pr-security-review skill, then re-run gh pr create." ;;
esac

# 3. No security-relevant files (docs/config only) -> allow.
[[ -z "${dims// /}" ]] && exit 0

# 4/5. Code-only: skip when small, else require review.
mb="$(git -C "$cwd" merge-base "$base" HEAD 2>/dev/null || echo "$base")"
stat="$(git -C "$cwd" diff --shortstat "$mb...HEAD" 2>/dev/null || true)"
ins="$(printf '%s' "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '^[0-9]+' || true)"
del="$(printf '%s' "$stat" | grep -oE '[0-9]+ deletion'  | grep -oE '^[0-9]+' || true)"
lines=$(( ${ins:-0} + ${del:-0} ))

if [[ "$lines" -le "$MAX" ]]; then
  exit 0  # small code-only change — gate skipped; /pr-security-review still available
fi

block "code change is ${lines} lines (> ${MAX}) with no security review. Run the pr-security-review skill, then re-run gh pr create. (Small code-only diffs ≤ ${MAX} lines skip automatically; tune with PR_SECURITY_MAX_SMALL_LINES.)"
