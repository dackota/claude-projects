#!/usr/bin/env bash
# PreToolUse(Bash) hook: gate `gh pr create` on a fresh, passing security review.
#
# Allows the command only if a verdict file exists for the current HEAD commit
# and reads PASS. Otherwise blocks (exit 2) and tells Claude to run the
# /pr-security-review skill first. The verdict is keyed to the HEAD SHA, so any
# fix (which makes a new commit) re-requires review.
#
# Reads the Claude Code PreToolUse payload (JSON) on stdin.

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"

[[ -z "$cmd" ]] && exit 0

# Only gate PR creation.
printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+create' || exit 0

block() { echo "🔒 PR security gate: $1" >&2; exit 2; }

cwd="${cwd:-$PWD}"
gitdir="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null || true)"
sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)"
[[ -z "$gitdir" || -z "$sha" ]] && \
  block "can't resolve git repo/HEAD from the command's directory — run gh pr create inside the repo."

verdict_file="$gitdir/pr-security-review/$sha"
[[ -f "$verdict_file" ]] || \
  block "no security review for HEAD ($sha). Run the pr-security-review skill first — it reviews the diff with an independent agent, then re-run gh pr create."

verdict="$(head -n1 "$verdict_file" 2>/dev/null || echo BLOCK)"
case "$verdict" in
  PASS) exit 0 ;;
  *)    block "security review found CRITICAL issue(s) for HEAD ($sha). Fix them — the fix is a new commit, which re-reviews automatically — then re-run gh pr create." ;;
esac
