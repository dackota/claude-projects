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
#   3. No verdict, the code diff touches a trust boundary ("surface": network, DB,
#      exec, env, secrets, templates) -> require review (any size).
#   4. No verdict, no infra and no trust-boundary surface (a pure-logic module or
#      docs/config only) -> allow. The correctness gate records any security
#      obligations a pure module imposes on its callers, so the deferred-security
#      ledger isn't lost; run /pr-security-review by hand for a full pass anytime.
#
# The skip keys on the trust boundary the diff *touches*, not its size — a pure
# module skips at any size and a surface-touching change is reviewed at any size.
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
# The gate keys strictly on the payload cwd — the directory the session is in when
# `gh pr create` runs. It deliberately does NOT parse a leading `cd` out of the
# command to redirect identity: every attempt to do so proved unsafe. A crafted
# single command can make the parsed directory diverge from where gh actually
# executes — via a second `cd`, a subshell / brace-group / `$( )` / backtick
# substitution, or a multi-line decoy line — letting a stale/foreign PASS authorize
# an unreviewed PR. For cwd-safe PR creation under parallel worktrees use
# `scripts/repo.sh pr`, which resolves the worktree by path and self-enforces the
# verdict inside its own subshell (no free-form command parsing).
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

# 3. A trust-boundary surface in the code diff (network / DB / exec / env / secrets /
#    templates) requires review at any size.
case " $dims " in
  *" surface "*) block "the diff touches a security-relevant surface (network / DB / exec / env / secrets / templates). Run the pr-security-review skill, then re-run gh pr create." ;;
esac

# 4. No infra and no trust-boundary surface -> a pure-logic module or docs/config
#    only -> allow. The correctness gate records any security obligations a pure
#    module imposes on its callers, so nothing is lost; /pr-security-review remains
#    available by hand for a full pass on demand.
exit 0
