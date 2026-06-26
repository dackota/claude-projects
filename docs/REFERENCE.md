# Reference

Internals for a `proj`-scaffolded workspace. The [README](../README.md) covers getting started; this doc covers the control files, conventions, and skill mechanics.

## Living status system

> Inspired by [Give Your AI Unlimited, Updated Context](https://towardsdatascience.com/give-your-ai-unlimited-updated-context/) — an LLM-optimized current-state document eliminates the re-orientation cost at the start of every session.

Each workspace carries two control files that keep Claude oriented across sessions.

### STATUS.md

Regenerated wholesale by `/sync-status`. The first file Claude reads each session — a ~500-token synthesis of current project state under these sections:

- **Goal** — one sentence from `PROJECT.md`
- **Current state** — 2–4 sentences
- **Active work** — bullet list with doc links
- **Blocked / open questions**
- **Recent decisions** — dated, linked
- **Key facts** — load-bearing constraints
- **Next moves**

`STATUS.md` is a *view*, not a source of truth. If a fact needs to persist, put it in a plan, an ADR, or the journal.

### journal.yaml

Append-only event log. Never rewritten — only appended. Entry schema:

```yaml
- date: YYYY-MM-DD
  type: decision   # decision | plan | started | done | blocker | supersession | research | pr
  summary: One or two sentences.
  refs:            # optional
    - docs/adr/0001-foo.md
  jira: DEVOPS-1234  # optional
```

Claude appends an entry immediately when: a decision is made, a plan is finalized, a task status flips, a blocker is hit, a doc is superseded, research is finalized, or a PR is opened/merged/closed.

## Doc lifecycle frontmatter

Every doc in `docs/plans/`, `docs/research/`, and `docs/validations/` carries the frontmatter below. ADRs (`docs/adr/`) and `CONTEXT.md` follow their own minimal formats and are exempt:

```yaml
---
title: Human-readable title
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []
superseded_by: null
related:
  - docs/adr/0001-foo.md
jira: null
task: null
---
```

`status` is the currency signal. Claude skips non-`active` docs unless explicitly referenced. Superseded docs stay in place — never moved or deleted — with `status: superseded` and a block-quote at the top explaining the supersession.

## Domain knowledge

Alongside the living-status files, each workspace keeps a glossary and a decision log so terminology and rationale survive across sessions.

### CONTEXT.md

A domain glossary: the canonical name for each concept in the project, with synonyms to avoid. Skills draw their vocabulary from it so language stays consistent across plans, issues, tests, and commits. `/grill-with-docs` maintains it inline as terms get resolved. It is a glossary only — no implementation details, no general programming concepts.

### docs/adr/

Architectural Decision Records capture *why* a decision was made — but only when it is hard to reverse, surprising without context, and the result of a real trade-off. Anything lighter is just a `decision` line in the journal. ADRs use sequential numbering (`0001-slug.md`) and can be a single paragraph.

## Issue tracker & tasks

`/to-prd` and `/to-issues` route their output based on `project.yaml`:

| `jira_key` | PRD lands in | Issues land in |
|------------|--------------|----------------|
| set | a Jira issue (`ready-for-agent` label) | Jira issues (`afk`/`hitl` label; `ready-for-agent` on AFK only) |
| empty | `docs/plans/<slug>-prd.md` | `project.yaml` `tasks` |

GitHub Issues are used only when you explicitly ask. A local task is a thin pointer that the journal and `STATUS.md` track:

```yaml
tasks:
  - id: extract-gateway-subchart
    title: Extract aidp-gateway subchart
    type: AFK            # AFK | HITL
    status: todo         # todo | active | done | blocked
    blocked_by: []
    plan: docs/plans/chart-split-prd.md
    jira: null
```

Status changes drive the journal (`todo → active` → `started`, `active → done` → `done`) and feed `STATUS.md`'s "Active work."

## How skills are bundled

Skills live in the scaffolder's `skills/` and are versioned alongside it. `proj` copies them into a new project's `.claude/skills/` **by default** (`--no-skills` to opt out, `--skills LIST` for a subset), or you can symlink them globally for use across all projects.

Hook-bearing skills (`journal`, `sync-status`, `repo`, `pr-security-review`) also get their hooks **idempotently merged** into `.claude/settings.json` — so they compose cleanly and re-running `proj update-skills` on an existing workspace adds any missing wiring without duplicating it. A skill can also pull in an agent via an `agents:` list in its frontmatter — `proj` copies the named definitions from the repo's `agents/` into `.claude/agents/`.

## /next — the workflow router

`/next` removes the "which skill do I run?" decision. It reads the workspace state (`project.yaml`, `docs/plans/` PRDs, `journal.yaml`, or — in Jira mode — the tracker), infers the lifecycle phase, and dispatches to the skill that handles it. It **complements** the phase skills (each stays directly invokable) and is wired into the scaffolded `CLAUDE.md` so a session self-orients after reading `STATUS.md`. `proj --skills next` also pulls in the skills it orchestrates.

| Phase | Detected by | Routes to |
|-------|-------------|-----------|
| Grill | no PRD yet | `grill-with-docs` (then `to-prd` on shared understanding) |
| Slice | PRD exists, no tasks | `to-issues` |
| Pick | tasks exist, none active | next unblocked task (AFK-preferred; HITL surfaced) → `tdd` |
| Build | a task is active | continue `tdd` |
| Land | task done, not PR'd | the unified PR-review gate |

The planning arc (grill → prd → issues) auto-chains in one session with a light confirm at each gate; building breaks to a **fresh session per task** to resist context drift. When a picked task depends on an in-review slice, `/next` stacks its worktree on that branch (via `repo.sh`) so work doesn't stall, and warns if a stacked base was reopened.

## /journal

Appends a single typed entry to `journal.yaml`. Use it immediately when something significant happens: a decision is made, a plan changes, a task starts or finishes, a blocker is hit.

```
/journal <type> "<summary>"

/journal decision "Switched to consumer-subchart pattern for chart extraction."
/journal started  "Beginning DEVOPS-1521 — extract aidp-gateway subchart."
/journal done     "DEVOPS-1521 PR #829 merged and sbx-validated."
/journal blocker  "ECR push failing — OIDC role missing ecr:GetAuthorizationToken."
/journal pr       "PR #831 opened for aidp-core extraction."
```

Valid types: `decision` · `plan` · `started` · `done` · `blocker` · `supersession` · `research` · `pr`

**Hooks:** a `PostToolUse` hook fires when `project.yaml` or any `docs/adr/`, `docs/plans/`, `docs/research/`, or `docs/validations/` file is written, nudging Claude to write the corresponding entry. A `Stop` hook fires if `docs/` files were modified since the last journal entry.

## /sync-status

Regenerates `STATUS.md` from all authoritative inputs — `PROJECT.md`, `project.yaml`, `journal.yaml`, and every `status: active` doc in `docs/`. Run it (or let Claude invoke it automatically) at the end of any session where meaningful work happened.

**Hook:** a `Stop` hook fires when `journal.yaml` is newer than `STATUS.md`, prompting Claude to sync before the session ends.

## /repo

Makes repo and worktree handling explicit and enforced, so you can trust Claude is using `repos/` and worktrees the way you intend — and isn't quietly building on a worktree that's gone stale. Installs a first-class, readable `scripts/repo.sh` and routes every repo/worktree operation through it:

```
scripts/repo.sh clone <url> [name]                        # clone into repos/, register in project.yaml
scripts/repo.sh worktree <task> <repo> [--onto <parent>]  # start work; stack on <parent> or auto-derive from blocked_by
scripts/repo.sh sync <task> [repo]                         # merge the base (or stacked parent) in
scripts/repo.sh status [task]                              # behind/ahead + dirty + STALE / BASE REOPENED flags
scripts/repo.sh remove <task> [repo]                       # remove worktree + delete local branch (safe by default)
scripts/repo.sh list                                       # registered repos
```

- **Repos are declared in `project.yaml`; worktrees are derived live** from `git worktree list` and the `worktrees/<task>/<repo>` layout (one task can span repos). No worktree state to drift out of sync.
- **`sync` is the only working-tree mutation** — it refuses on a dirty tree, merges `origin/<base>` (no force-push), and stops to report conflicts rather than auto-resolving. **`remove`** refuses to discard unpushed commits unless `--force`.
- **Stacked work** — when a task depends on another that's still in review, `worktree --onto <parent>` (or auto-derived from a single unmerged `blocked_by`) branches off the parent instead of the base, so dependent work doesn't stall. The stack pointer is the branch's git upstream; `sync` cascades the parent's fixes and re-points to the base once the parent merges. If a stacked parent is reopened, `status` flags it **BASE REOPENED** — `repo.sh` never auto-rebases a disturbed stack.

**Hooks:**
- A **PreToolUse `Bash`** guard blocks raw `git clone`, `git worktree add`, and branch create/switch inside `repos/`/`worktrees/`, redirecting Claude to `repo.sh`. Read-only git and `git checkout -- <file>` stay allowed.
- A **PreToolUse `Edit|Write`** hook warns (once per worktree per session) before Claude edits a worktree that's behind its base.
- A **`Stop`** hook summarizes any stale worktrees at session end.

`repo.sh` requires `yq` (v4) for `project.yaml` writes. On an existing workspace, `proj update-skills` installs `repo.sh` and merges the hooks in without disturbing your other settings.

## /pr-security-review — the unified PR-review gate

Holds `gh pr create` until an **independent** review signs off — fresh agents that never saw the implementation review the diff with skeptical eyes, which catches what self-review rationalizes away. The review has two lenses, run in order: **acceptance** (does the slice deliver what it promised?), then **security** (is it safe?). Bundles two checklist skills plus two agents:

- **`implementation-validator`** — a review-only agent that checks the diff against the slice's acceptance criteria (derived from the branch's `project.yaml` task → its PRD/issue). A CRITICAL gap means a promised behavior is undelivered: it blocks and **loops the task back** (`done → active`) into `tdd`.
- **`security-reviewer`** — a review-only agent (no `Write`/`Edit`) that checks the change against the bundled `security-review` (app-code) and `cloud-infra-security` (cloud/IaC) checklists. Both agents are copied into `.claude/agents/` via the skill's `agents:` frontmatter.
- **`security-review`** and **`cloud-infra-security`** — the checklists, bundled so each workspace is self-contained; the global `~/.claude/skills/` copies become symlinks back to these.

How it flows:

```
gh pr create
  -> hook: verdict recorded for HEAD <sha>?
       yes -> honor it (PASS allow / CRITICAL block)
       no  -> branch is a task (a slice PR)? -> BLOCK: review required (acceptance, any size)
              not a task in a workspace?     -> warn (acceptance skipped), fall back to security rules:
                infra in diff?               -> BLOCK: review required (any size)
                code-only & <= 25 lines?     -> allow (small change skips)
                docs/config only?            -> allow
                else (larger code)           -> BLOCK: review required
  /pr-security-review (run on block, or manually anytime):
     derive task -> implementation-validator (acceptance) -> security-reviewer (security)
     -> one verdict@<sha> in .git/pr-security-review/
     CRITICAL (either lens) -> blocks PR (fix -> new commit -> auto re-review)
     PASS                   -> both lenses folded into PR body, gh pr create allowed
```

Acceptance applies to every slice PR (a branch that is a task in `project.yaml`) regardless of size; if the task can't be derived from the branch, the gate warns and falls back to security-only. Security classification is path-based (`classify.sh`): app source → `security-review`; `.tf`/`.yaml`/`Dockerfile`/pipelines → `cloud-infra-security`; a mixed PR gets both — small code-only diffs skip the *security* lens (≤ 25 changed lines; override with `PR_SECURITY_MAX_SMALL_LINES`). You can run `/pr-security-review` by hand on any change, and a recorded verdict always wins. The gate covers CLI `gh pr create` only — `--web` and the GitHub UI bypass it.

## Phase skills

> `/grill-with-docs`, `/to-prd`, `/to-issues`, and `/tdd` are adapted from [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering).

### /grill-with-docs

Interviews you relentlessly about a plan or design — one question at a time, working through every branch of the decision tree. Each answer comes with Claude's recommendation, so the interview also surfaces Claude's assumptions for you to correct. As terms get resolved it sharpens `CONTEXT.md` inline, and it offers an ADR whenever a decision is hard to reverse, surprising without context, and the result of a real trade-off.

Invoke it when you have a rough idea and want to find the holes before writing a plan. The output is the raw material for `/to-prd`.

### /to-prd

Synthesizes everything in the current conversation into a structured PRD without interviewing you further — it just writes. The PRD covers the problem statement, solution, an extensive list of user stories, implementation decisions, testing decisions, and out-of-scope items. It publishes as a Jira issue when `project.yaml` has a `jira_key`, or saves to `docs/plans/<slug>-prd.md` otherwise.

Use it after `/grill-with-docs` has resolved the major open questions, or any time the conversation contains enough context to write a spec.

### /to-issues

Breaks a plan or PRD into independently-grabbable vertical-slice issues. Each issue cuts end-to-end through all layers (schema, API, UI, tests) and is either HITL (requires human input) or AFK (can be implemented and merged autonomously). Presents the breakdown for your review, then publishes: with a `jira_key`, as Jira issues labeled `afk`/`hitl` (plus `ready-for-agent` on AFK only); without one, as `project.yaml` tasks.

```
/to-issues
/to-issues <issue-number>   # start from an existing tracker issue
```

Use it after `/to-prd` to turn the spec into a concrete backlog.

### /tdd

Drives implementation using a strict red-green-refactor loop — one test at a time, never horizontal slicing. The main session **orchestrates**: it plans the slice (interface + prioritized behaviors), holds the planning gate with you for HITL tasks (deriving it from acceptance criteria for AFK tasks), then spawns a Sonnet **`tdd-implementer`** sub-agent to run the loop on a fresh context. It reviews what the implementer returns — re-running the tests and checking the tests are behavioral, not implementation-coupled — and owns close-out (status flips, validation doc). Keeps planning and orchestration on the main model while the implementation tokens go to Sonnet.

Use it when starting implementation of any issue produced by `/to-issues`.

### /codebase-researcher

A read-only codebase mapper: traces execution paths, maps architecture layers, and surfaces dependencies and risks for a subsystem, then writes the findings to `docs/research/`. It is **optional** — `grill-with-docs` already explores during grilling, so reach for this only when a question needs more depth than the interview should carry. `/next` may offer it mid-grill when a deep unknown surfaces, but never forces it.

## Typical workflow

These skills compose into a repeatable process from idea to shipped code — and **`/next` routes you through it**, so the steps below are what happens phase by phase, not a sequence you drive by hand. Throughout, the `repo` skill keeps each task isolated in its own worktree (stacking dependent slices when needed), and the PR-review gate vets the diff with two independent agents — acceptance then security — before any PR opens.

1. **Explore the idea — `/grill-with-docs`** — Claude interviews you until every major design branch is resolved, sharpening `CONTEXT.md` and recording hard-to-reverse decisions as ADRs.
2. **Write the spec — `/to-prd`** — Claude synthesizes the conversation into a full PRD and publishes it to Jira (or `docs/plans/`). No additional input needed.
3. **Break it into issues — `/to-issues`** — decompose the PRD into vertical slices. Review granularity, HITL/AFK calls, and dependency order, then approve.
4. **Implement each issue — `/tdd`** — work in a dedicated worktree (`repo.sh worktree <task> <repo>`). The main session plans the slice (confirming the interface with you for HITL tasks), then spawns a Sonnet `tdd-implementer` sub-agent that writes one failing test → minimal code → refactor, and reviews what it returns. `gh pr create` triggers the PR-review gate; a critical acceptance gap loops the task back into `tdd`.
5. **Log events as they happen — `/journal`** — significant events get logged immediately. The `PostToolUse` hook catches most file-write events automatically.
6. **Sync the status view — `/sync-status`** — at session end, `STATUS.md` regenerates from current state. The `Stop` hook fires automatically when `journal.yaml` is newer than `STATUS.md`.
7. **Resume the next session** — Claude reads `STATUS.md` first — a ~500-token synthesis of where the project is, what's active, blocked, and next. No re-orientation cost.
