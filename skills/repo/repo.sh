#!/usr/bin/env bash
# repo.sh — the sanctioned entry point for repo & worktree operations in a
# claude-projects workspace. Raw `git clone` / `git worktree add` / branch
# create/switch under repos/ and worktrees/ are blocked by a PreToolUse guard
# hook; route them through here instead.
#
# Usage:
#   repo.sh clone <url> [name]            Clone into repos/<name>, register in project.yaml
#   repo.sh worktree <task> <repo> [url] [--onto <parent>]
#                                         Create worktrees/<task>/<repo> on branch <task>;
#                                         stack on <parent>'s branch (or auto-derive from a
#                                         single unmerged blocked_by), else branch off base
#   repo.sh sync <task> [repo]            Fetch + merge the base (or the stacked parent) in
#   repo.sh pr <task> [repo] [-- <gh args>]  Open a PR for a task's worktree — cwd-safe
#                                         (the cd is internal), honors the recorded review verdict
#   repo.sh status [task]                 Live drift/dirty report for worktrees
#   repo.sh remove <task> [repo] [--force] Remove worktree(s) + delete local branch
#   repo.sh list                          List registered repos
#   repo.sh help                          Show this help
#
# State model: repos are declared in project.yaml `repos`; worktrees are derived
# live from `git worktree list` and the worktrees/<task>/<repo> directory layout.

set -euo pipefail

# ── colours / logging ─────────────────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}[repo]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[repo]${RESET} $*"; }
error() { echo -e "${RED}[repo]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── dependencies ──────────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || die "git is required but not found on PATH."
command -v yq  >/dev/null 2>&1 || die "yq (v4) is required for project.yaml writes. Install: brew install yq"

# ── project root ──────────────────────────────────────────────────────────────
# Walk up from CWD until project.yaml is found — that directory is the workspace.
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/project.yaml" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

ROOT="$(find_project_root)" || die "Not inside a claude-projects workspace (no project.yaml found above $PWD)."
PROJECT_YAML="$ROOT/project.yaml"
REPOS_DIR="$ROOT/repos"
WORKTREES_DIR="$ROOT/worktrees"

# ── project.yaml helpers ──────────────────────────────────────────────────────
repo_field() {  # repo_field <name> <field>
  local v
  v="$(yq e ".repos[] | select(.name == \"$1\") | .$2" "$PROJECT_YAML" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  echo "$v"
}

repo_is_registered() { [[ -n "$(repo_field "$1" name)" ]]; }

register_repo() {  # register_repo <name> <url> <path> <default_branch>
  local name="$1" url="$2" path="$3" base="$4"
  if repo_is_registered "$name"; then
    return 0
  fi
  yq e -i \
    ".repos += [{\"name\": \"$name\", \"url\": \"$url\", \"path\": \"$path\", \"default_branch\": \"$base\"}]" \
    "$PROJECT_YAML"
  info "Registered repo '$name' in project.yaml"
}

# Default branch of a checked-out clone, via origin's HEAD symref.
detect_default_branch() {  # detect_default_branch <repo-path>
  local b
  b="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  echo "${b#origin/}"
}

# Resolve a repo's base branch: prefer project.yaml, fall back to live detection.
base_branch() {  # base_branch <repo-name>
  local b; b="$(repo_field "$1" default_branch)"
  if [[ -z "$b" && -d "$REPOS_DIR/$1" ]]; then
    b="$(detect_default_branch "$REPOS_DIR/$1")"
  fi
  echo "${b:-main}"
}

# Status of a task in project.yaml (empty if the id is not a task).
task_status() {  # task_status <task-id>
  local v
  v="$(yq e ".tasks[] | select(.id == \"$1\") | .status" "$PROJECT_YAML" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  echo "$v"
}

# The branch a task should stack on, auto-derived from its blocked_by: echoes the
# parent branch name when exactly one blocker has a live local branch not yet
# merged into the base; empty when none, or when several qualify (ambiguous).
auto_stack_parent() {  # auto_stack_parent <task> <clone> <base>
  local task="$1" clone="$2" base="$3" blockers parent="" b count=0
  blockers="$(yq e -r ".tasks[] | select(.id == \"$task\") | .blocked_by[]?" "$PROJECT_YAML" 2>/dev/null || true)"
  [[ -z "$blockers" ]] && return 0
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    git -C "$clone" show-ref --verify --quiet "refs/heads/$b" || continue       # live branch?
    git -C "$clone" merge-base --is-ancestor "$b" "origin/$base" 2>/dev/null && continue  # already merged?
    parent="$b"; count=$((count + 1))
  done <<< "$blockers"
  if [[ "$count" -gt 1 ]]; then
    # >&2 is required: this function runs inside $(...), so stdout is the return
    # value (the parent branch) — the warning must not contaminate it.
    warn "Task '$task' has multiple unmerged blockers with live branches; not auto-stacking. Use --onto <task>." >&2
    return 0
  fi
  echo "$parent"
}

# A worktree's stacked parent branch, or empty when it tracks origin/<base>.
# The stack relationship lives in git: a stacked branch's upstream is a *local*
# branch (the parent); an ordinary worktree tracks origin/<base>.
stacked_parent() {  # stacked_parent <worktree>
  local up
  up="$(git -C "$1" rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
  if [[ -n "$up" && "$up" != origin/* ]]; then echo "$up"; fi
  return 0
}

# ── commands ──────────────────────────────────────────────────────────────────
cmd_clone() {
  local url="${1:-}" name="${2:-}"
  [[ -z "$url" ]] && die "Usage: repo.sh clone <url> [name]"
  if [[ -z "$name" ]]; then
    name="$(basename "$url")"; name="${name%.git}"
  fi
  local dest="$REPOS_DIR/$name"

  if [[ -d "$dest/.git" ]]; then
    warn "Repo '$name' already cloned at repos/$name — fetching latest."
    git -C "$dest" fetch --all --prune
  else
    mkdir -p "$REPOS_DIR"
    info "Cloning $url -> repos/$name"
    git clone "$url" "$dest"
  fi

  local base; base="$(detect_default_branch "$dest")"; base="${base:-main}"
  register_repo "$name" "$url" "repos/$name" "$base"
  info "Repo '$name' ready (default branch: $base)"
}

cmd_worktree() {
  local task="" repo="" url="" onto="" args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --onto) onto="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  task="${args[0]:-}"; repo="${args[1]:-}"; url="${args[2]:-}"
  [[ -z "$task" || -z "$repo" ]] && die "Usage: repo.sh worktree <task> <repo> [url] [--onto <parent>]"

  local clone="$REPOS_DIR/$repo"
  # Auto-clone if the repo isn't present yet.
  if [[ ! -d "$clone/.git" ]]; then
    if [[ -z "$url" ]]; then
      url="$(repo_field "$repo" url)"
    fi
    [[ -z "$url" ]] && die "Repo '$repo' is not cloned and no url is known. Run: repo.sh clone <url> $repo"
    cmd_clone "$url" "$repo"
  fi

  git -C "$clone" fetch --all --prune
  git -C "$clone" worktree prune 2>/dev/null || true
  local base; base="$(base_branch "$repo")"
  local wt="$WORKTREES_DIR/$task/$repo"

  if [[ -d "$wt" ]]; then
    warn "Worktree already exists: worktrees/$task/$repo (no-op)"
    return 0
  fi

  # Resolve the branch to stack on: explicit --onto wins; otherwise auto-derive
  # from the task's single unmerged blocker (if any). Empty => branch off base.
  local parent=""
  if [[ -n "$onto" ]]; then
    git -C "$clone" show-ref --verify --quiet "refs/heads/$onto" \
      || die "--onto '$onto': no such branch in repo '$repo'. Create its worktree first."
    parent="$onto"
  else
    parent="$(auto_stack_parent "$task" "$clone" "$base")"
  fi

  mkdir -p "$WORKTREES_DIR/$task"
  if git -C "$clone" show-ref --verify --quiet "refs/heads/$task"; then
    info "Adding worktree on existing branch '$task': worktrees/$task/$repo"
    git -C "$clone" worktree add "$wt" "$task"
  elif [[ -n "$parent" ]]; then
    info "Stacking '$task' on '$parent': worktrees/$task/$repo"
    git -C "$clone" worktree add -b "$task" "$wt" "$parent"
    # Record the stack in git: the child branch's upstream IS the parent branch.
    git -C "$clone" branch --set-upstream-to="$parent" "$task" >/dev/null || true
  else
    info "Adding worktree on new branch '$task' off origin/$base: worktrees/$task/$repo"
    git -C "$clone" worktree add -b "$task" "$wt" "origin/$base"
  fi
}

cmd_sync() {
  local task="${1:-}" only_repo="${2:-}"
  [[ -z "$task" ]] && die "Usage: repo.sh sync <task> [repo]"
  local task_dir="$WORKTREES_DIR/$task"
  [[ -d "$task_dir" ]] || die "No worktrees for task '$task' (looked in worktrees/$task)."

  local found=false rc=0 wt repo base parent target
  for wt in "$task_dir"/*; do
    [[ -e "$wt/.git" ]] || continue
    repo="$(basename "$wt")"
    [[ -n "$only_repo" && "$repo" != "$only_repo" ]] && continue
    found=true
    base="$(base_branch "$repo")"

    git -C "$wt" fetch --all --prune

    if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
      error "worktrees/$task/$repo has uncommitted changes — commit or stash first, then re-run sync."
      rc=1; continue
    fi

    # A stacked worktree tracks its parent branch until the parent merges into
    # the base, at which point it re-points to origin/<base> (the PR retargets).
    parent="$(stacked_parent "$wt")"
    if [[ -n "$parent" ]] && git -C "$wt" merge-base --is-ancestor "$parent" "origin/$base" 2>/dev/null; then
      info "worktrees/$task/$repo: parent '$parent' merged into $base — re-pointing to origin/$base"
      git -C "$wt" branch --set-upstream-to="origin/$base" >/dev/null 2>&1 || true
      parent=""
    fi
    if [[ -n "$parent" ]]; then target="$parent"; else target="origin/$base"; fi

    info "Syncing worktrees/$task/$repo (merge $target)"
    if git -C "$wt" merge "$target"; then
      info "worktrees/$task/$repo is up to date with $target"
    else
      error "Merge conflict in worktrees/$task/$repo. Conflicted files:"
      git -C "$wt" diff --name-only --diff-filter=U | sed 's/^/    /' >&2
      error "Resolve, commit, or run 'git -C worktrees/$task/$repo merge --abort' to back out. Left in conflict state."
      rc=1
    fi
  done

  $found || die "No matching worktree for task '$task'${only_repo:+ repo '$only_repo'}."
  return $rc
}

cmd_status() {
  local only_task="${1:-}"
  if [[ ! -d "$WORKTREES_DIR" ]] || [[ -z "$(ls -A "$WORKTREES_DIR" 2>/dev/null || true)" ]]; then
    info "No worktrees yet."
  fi

  shopt -s nullglob
  local printed_header=false wt task repo branch base behind ahead dirty flag parent against
  local fetched=" "  # space-delimited set of already-fetched repo names (bash 3.2 safe)
  for wt in "$WORKTREES_DIR"/*/*; do
    [[ -e "$wt/.git" ]] || continue
    task="$(basename "$(dirname "$wt")")"
    repo="$(basename "$wt")"
    [[ -n "$only_task" && "$task" != "$only_task" ]] && continue

    # fetch-always (once per repo per invocation); prune stale worktree admin
    # entries left by a hand-deleted worktree dir while we're here.
    case "$fetched" in
      *" $repo "*) ;;
      *) git -C "$wt" fetch -q --all --prune 2>/dev/null || true
         git -C "$REPOS_DIR/$repo" worktree prune 2>/dev/null || true
         fetched="${fetched}${repo} " ;;
    esac

    branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    base="$(base_branch "$repo")"
    # A stacked worktree drifts against its parent branch, not the base.
    parent="$(stacked_parent "$wt")"
    if [[ -n "$parent" ]]; then against="$parent"; else against="origin/$base"; fi
    behind="$(git -C "$wt" rev-list --count "HEAD..$against" 2>/dev/null || echo 0)"
    ahead="$(git -C "$wt" rev-list --count "$against..HEAD" 2>/dev/null || echo 0)"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    flag=""
    [[ "${behind:-0}" -gt 0 ]] && flag="  ⚠ STALE"
    # A stacked child whose parent task reopened (done -> active) is building on
    # shifting ground — surface it loudly; we never auto-rebase the stack.
    if [[ -n "$parent" && "$(task_status "$parent")" == "active" ]]; then
      flag="${flag}  ⚠ BASE REOPENED"
    fi

    if ! $printed_header; then
      echo ""
      printf "  %-22s %-22s %-14s %s\n" "WORKTREE" "BRANCH" "vs base/parent" "DIRTY"
      printed_header=true
    fi
    printf "  %-22s %-22s -%-3s +%-8s %-4s%s\n" \
      "$task/$repo" "$branch" "${behind:-0}" "${ahead:-0}" "${dirty:-0}" "$flag"
  done
  $printed_header || info "No worktrees to report."
  echo ""
}

cmd_remove() {
  local task="" only_repo="" force=false a
  for a in "$@"; do
    case "$a" in
      --force) force=true ;;
      *) if [[ -z "$task" ]]; then task="$a"; elif [[ -z "$only_repo" ]]; then only_repo="$a"; fi ;;
    esac
  done
  [[ -z "$task" ]] && die "Usage: repo.sh remove <task> [repo] [--force]"
  local task_dir="$WORKTREES_DIR/$task"
  [[ -d "$task_dir" ]] || die "No worktrees for task '$task'."

  shopt -s nullglob
  local wt repo clone base unpushed dirty rc=0
  for wt in "$task_dir"/*; do
    [[ -e "$wt/.git" ]] || continue
    repo="$(basename "$wt")"
    [[ -n "$only_repo" && "$repo" != "$only_repo" ]] && continue
    clone="$REPOS_DIR/$repo"
    base="$(base_branch "$repo")"

    # A stacked child records this branch as its upstream — deleting the parent
    # branch would orphan the stack. Refuse without --force; warn when forced.
    children="$(git -C "$clone" for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads 2>/dev/null \
      | awk -v p="$task" '$2 == p {print $1}' | tr '\n' ' ')"
    if [[ -n "${children// /}" ]]; then
      if $force; then
        warn "worktrees/$task/$repo: stacked children (${children% }) are being orphaned — re-point or sync them."
      else
        error "worktrees/$task/$repo: branch '$task' is the stacked base of: ${children% }. Sync/re-point or remove them first, or pass --force."
        rc=1; continue
      fi
    fi

    if ! $force; then
      dirty="$(git -C "$wt" status --porcelain 2>/dev/null)"
      if [[ -n "$dirty" ]]; then
        error "worktrees/$task/$repo has uncommitted changes. Commit/stash or pass --force."
        rc=1; continue
      fi
      # Unpushed = commits on the branch not on its upstream (or not on origin/base).
      if git -C "$wt" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        unpushed="$(git -C "$wt" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
      else
        unpushed="$(git -C "$wt" rev-list --count "origin/$base..HEAD" 2>/dev/null || echo 0)"
      fi
      if [[ "${unpushed:-0}" -gt 0 ]]; then
        error "worktrees/$task/$repo has $unpushed unpushed commit(s). Push them or pass --force to discard."
        rc=1; continue
      fi
    fi

    info "Removing worktree worktrees/$task/$repo"
    if $force; then
      git -C "$clone" worktree remove --force "$wt"
    else
      git -C "$clone" worktree remove "$wt"
    fi
    if git -C "$clone" show-ref --verify --quiet "refs/heads/$task"; then
      git -C "$clone" branch -D "$task" >/dev/null && info "Deleted local branch '$task' in repo '$repo'"
    fi
    # Clear any stale admin entries (e.g. a worktree dir removed by hand).
    git -C "$clone" worktree prune 2>/dev/null || true
  done

  # Drop the task dir if now empty.
  rmdir "$task_dir" 2>/dev/null && info "Removed empty worktrees/$task" || true
  return $rc
}

cmd_list() {
  local count; count="$(yq e '.repos | length' "$PROJECT_YAML" 2>/dev/null || echo 0)"
  if [[ "${count:-0}" -eq 0 ]]; then
    info "No repos registered in project.yaml yet."
    return 0
  fi
  echo ""
  printf "  %-24s %-10s %s\n" "NAME" "BRANCH" "URL"
  yq e -r '.repos[] | [.name, .default_branch, .url] | @tsv' "$PROJECT_YAML" \
    | while IFS=$'\t' read -r name branch url; do
        printf "  %-24s %-10s %s\n" "$name" "$branch" "$url"
      done
  echo ""
}

cmd_pr() {
  command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required for 'repo.sh pr'. Install: brew install gh"

  # Args: <task> [repo] [-- <extra gh pr create args>]. Everything after `--` is
  # passed through verbatim to `gh pr create` (e.g. --title/--body-file/--draft).
  local args=() passthru=() seen_dd=false a
  for a in "$@"; do
    if $seen_dd; then passthru+=("$a"); continue; fi
    if [[ "$a" == "--" ]]; then seen_dd=true; continue; fi
    args+=("$a")
  done
  local task="${args[0]:-}" only_repo="${args[1]:-}"
  [[ -z "$task" ]] && die "Usage: repo.sh pr <task> [repo] [-- <extra gh pr create args>]"

  local task_dir="$WORKTREES_DIR/$task"
  [[ -d "$task_dir" ]] || die "No worktrees for task '$task' (looked in worktrees/$task)."

  # A PR is per-repo: resolve exactly one target worktree.
  shopt -s nullglob
  local matches=() m
  for m in "$task_dir"/*; do
    [[ -e "$m/.git" ]] || continue
    [[ -n "$only_repo" && "$(basename "$m")" != "$only_repo" ]] && continue
    matches+=("$m")
  done
  [[ ${#matches[@]} -eq 0 ]] && die "No matching worktree for task '$task'${only_repo:+ repo '$only_repo'}."
  [[ ${#matches[@]} -gt 1 ]] && die "Task '$task' spans multiple repos — name one: repo.sh pr $task <repo>"

  local wt="${matches[0]}" repo base branch
  repo="$(basename "$wt")"
  base="$(base_branch "$repo")"
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -z "$branch" || "$branch" == "HEAD" ]] && die "worktrees/$task/$repo has no branch checked out."

  # Guards: clean tree, and actually ahead of the base.
  [[ -n "$(git -C "$wt" status --porcelain)" ]] && \
    die "worktrees/$task/$repo has uncommitted changes — commit them first."
  git -C "$wt" fetch -q origin "$base" 2>/dev/null || true
  local ahead; ahead="$(git -C "$wt" rev-list --count "origin/$base..HEAD" 2>/dev/null || echo 0)"
  [[ "${ahead:-0}" -eq 0 ]] && die "worktrees/$task/$repo has no commits beyond origin/$base — nothing to PR."

  # Self-enforce the PR review gate. Because repo.sh invokes gh *internally*, the
  # PreToolUse gh-pr-create hook never sees it — so honor the recorded verdict
  # here (same file the gate / pr-security-review skill write, keyed by HEAD SHA).
  local sha gitdir verdict_file verdict
  sha="$(git -C "$wt" rev-parse HEAD)"
  gitdir="$(git -C "$wt" rev-parse --absolute-git-dir)"
  verdict_file="$gitdir/pr-security-review/$sha"
  [[ -f "$verdict_file" ]] || \
    die "No PR review verdict for HEAD ($sha). Run the pr-security-review skill in worktrees/$task/$repo, then re-run."
  verdict="$(head -n1 "$verdict_file" 2>/dev/null || echo BLOCK)"
  [[ "$verdict" == "PASS" ]] || \
    die "PR review verdict for HEAD is '$verdict' — resolve the CRITICAL findings (each fix is a new commit, re-reviewed), then re-run."

  # Default to --fill (title/body from commits) when the caller passes no gh args.
  [[ ${#passthru[@]} -eq 0 ]] && passthru=(--fill)

  info "Pushing '$branch' and opening a PR into '$base' (repo '$repo')"
  git -C "$wt" push -u origin "$branch"
  # cwd-safe: this cd is the script's own subshell, never the caller's shell.
  # gh detects the repo from the worktree's origin remote.
  ( cd "$wt" && gh pr create --base "$base" --head "$branch" "${passthru[@]}" )
}

usage() { grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'; }

# ── dispatch ──────────────────────────────────────────────────────────────────
SUB="${1:-help}"; shift || true
case "$SUB" in
  clone)    cmd_clone "$@" ;;
  worktree) cmd_worktree "$@" ;;
  sync)     cmd_sync "$@" ;;
  pr)       cmd_pr "$@" ;;
  status)   cmd_status "$@" ;;
  remove)   cmd_remove "$@" ;;
  list)     cmd_list "$@" ;;
  help|-h|--help) usage ;;
  *) die "Unknown command: $SUB (run 'repo.sh help')" ;;
esac
