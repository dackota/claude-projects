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
| Bootstrap | `PROJECT.md` Goals still empty/placeholder | help the user fill in `PROJECT.md`, then re-derive |
| Grill | no PRD yet | `grill-with-docs` (then `to-prd` on shared understanding) |
| Slice | PRD exists, no tasks | `to-issues` |
| Pick | tasks exist, none active | next unblocked task → build via `tdd-implementer` sub-agent (HITL: gather human input first) |
| Build | a task is active | continue the build via the sub-agent; the post-build acceptance gate loops back here on a gap |
| Land | task done, not PR'd | open the PR — the security review runs at `gh pr create` (acceptance already passed) |

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

## Independent review — acceptance at build time, security at PR time

Two independent reviews guard each slice — both by a fresh agent that never saw the implementation, which catches what self-review rationalizes away — but they fire at **different seams**:

### Acceptance — the post-build gate (`/next`)

When `/next` builds a task, the moment the `tdd-implementer` returns a `COMPLETE` summary and the orchestrator's own review is clean, `/next` **commits the slice** and spawns the **`implementation-validator`** on a fresh context to check the diff against the task's acceptance criteria (derived from the branch's `project.yaml` task → its PRD/issue) *before* the task is marked done.

- A CRITICAL gap (a promised behavior undelivered) **loops the slice straight back to `tdd`**: the task stays `active`, a `blocker` journal entry records the gaps, and the `tdd-implementer` is re-spawned with the findings to close them. Each fix is a new commit → the validator re-runs on the new `HEAD`. The task never reaches `done` (let alone a PR) until acceptance passes — so "doesn't do what it promised" is caught in seconds, not at PR review.
- The `implementation-validator` is review-only (no `Write`/`Edit`) and is copied into `.claude/agents/` via the `next` skill's `agents:` frontmatter.
- This gate is part of the `/next` **subagent** build only. Hand-invoked `/tdd` runs inline with you watching, so there is no auto-gate — your own review is the acceptance check.

### Observability — a baseline everywhere, a gate for services (`/observability`)

The canonical `standard.md` has **two layers**. The **baseline** (structured logs, correct levels, no swallowed errors) rides in `tdd`'s build discipline on **every** task — service or not, flag or no flag — so even a CLI or library ships diagnosable logging. The **service standard** (RED metrics, OTLP export, tracing, SDK lifecycle) is gated by `project.yaml` `observability.enabled: true`.

For **service projects**, a task that adds a request-serving path gets a second post-build gate alongside acceptance. `/next` spawns the **`otel-observability-engineer`** agent on the same diff, **in parallel with** `implementation-validator` (both review-only, so no added latency), to verify the slice against the service standard (RED, trace-correlated logs, OTel semantic conventions, cardinality, SDK flush).

- A **BLOCKER** (a request path missing a RED member, or unstructured logging) loops the slice back to `tdd` exactly like an acceptance CRITICAL; HIGH/MEDIUM/LOW are recorded but pass.
- The **service standard** is dormant unless the flag is set (bundled into every workspace, but no RED/OTLP for CLI/IaC/docs projects). The flag is set during design (`grill-with-docs`/`to-prd`); observability then enters `to-issues` acceptance criteria and is built by `tdd`, so it's designed-in, not bolted on. The agent is copied into `.claude/agents/` via the `observability` skill's `agents:` frontmatter.

### Security — the PR gate (`/pr-security-review`)

Holds `gh pr create` until an independent **security** review signs off. (Acceptance is already done by the time a PR opens, so the PR gate is security-only.) Bundles the security agent plus its two checklists:

- **`security-reviewer`** — a review-only agent (no `Write`/`Edit`) that checks the change against the bundled `security-review` (app-code) and `cloud-infra-security` (cloud/IaC) checklists.
- **`security-review`** and **`cloud-infra-security`** — the checklists, bundled so each workspace is self-contained; the global `~/.claude/skills/` copies become symlinks back to these.

How it flows:

```
gh pr create
  -> hook: verdict recorded for HEAD <sha>?
       yes -> honor it (PASS allow / CRITICAL block)
       no  -> infra in diff?           -> BLOCK: security review required (any size)
              code-only & <= 25 lines? -> allow (small change skips)
              docs/config only?        -> allow
              else (larger code)       -> BLOCK: security review required
  /pr-security-review (run on block, or manually anytime):
     classify diff -> security-reviewer (security)
     -> verdict@<sha> in .git/pr-security-review/
     CRITICAL -> blocks PR (fix -> new commit -> auto re-review)
     PASS     -> security summary folded into PR body, gh pr create allowed
```

Security classification is path-based (`classify.sh`): app source → `security-review`; `.tf`/`.yaml`/`Dockerfile`/pipelines → `cloud-infra-security`; a mixed PR gets both — small code-only diffs skip (≤ 25 changed lines; override with `PR_SECURITY_MAX_SMALL_LINES`), as do docs/config-only diffs. You can run `/pr-security-review` by hand on any change, and a recorded verdict always wins. The gate covers CLI `gh pr create` only — `--web` and the GitHub UI bypass it.

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

Drives implementation using a strict red-green-refactor loop — one test at a time, never horizontal slicing. The **loop never requires interaction**: an AFK task's design was settled upstream (grilling → `to-prd` → `to-issues`), so its acceptance criteria are a complete contract. A **HITL** task is the exception — it was flagged because it needs human input (a decision the upstream phases couldn't settle); that input is gathered *before* the loop, which then runs non-interactively. Two ways it runs, by who invoked it:

- **Hand-invoked → main-agent mode.** You run `/tdd` directly and the main agent (Opus) runs the loop **inline** — the path for an ad-hoc request where you want the main model doing the implementation itself, with you watching. It derives the plan from the acceptance criteria (or the request) and runs; no planning gate. The user is in-session, so for a HITL task (or a genuine question) it just asks, then continues.
- **`/next` build → subagent mode.** For a HITL task, `/next` first gathers the human input the task needs (it can talk to the user; the sub-agent can't). Then it flips the task `todo → active`, sets up the worktree, and spawns the Sonnet **`tdd-implementer`** sub-agent on a fresh context with the criteria (plus any gathered HITL input). The sub-agent derives the plan, runs the loop, and returns a `COMPLETE | PARTIAL | BLOCKED` summary; `/next` reviews it (re-running tests, checking the tests are behavioral), then runs the **post-build acceptance gate** — it commits the slice and spawns a fresh `implementation-validator` against the acceptance criteria, looping back to the sub-agent on a CRITICAL gap, and only flipping `active → done` once acceptance passes (then proceeding to the security PR gate). A fork that surfaces mid-build comes back as `BLOCKED` (reactive, not a routine gate). This path keeps the orchestrator lean and the implementation tokens on Sonnet.

Use it when starting implementation of any issue produced by `/to-issues`.

### /codebase-researcher

A read-only codebase mapper: traces execution paths, maps architecture layers, and surfaces dependencies and risks for a subsystem, then writes the findings to `docs/research/`. It is **optional** — `grill-with-docs` already explores during grilling, so reach for this only when a question needs more depth than the interview should carry. `/next` may offer it mid-grill when a deep unknown surfaces, but never forces it.

## Typical workflow

These skills compose into a repeatable process from idea to shipped code — and **`/next` routes you through it**, so the steps below are what happens phase by phase, not a sequence you drive by hand. Throughout, the `repo` skill keeps each task isolated in its own worktree (stacking dependent slices when needed), and two independent agents vet the work — an `implementation-validator` checks acceptance right after the build (looping back to `tdd` on a gap), and a `security-reviewer` checks security before any PR opens.

1. **Explore the idea — `/grill-with-docs`** — Claude interviews you until every major design branch is resolved, sharpening `CONTEXT.md` and recording hard-to-reverse decisions as ADRs.
2. **Write the spec — `/to-prd`** — Claude synthesizes the conversation into a full PRD and publishes it to Jira (or `docs/plans/`). No additional input needed.
3. **Break it into issues — `/to-issues`** — decompose the PRD into vertical slices. Review granularity, HITL/AFK calls, and dependency order, then approve.
4. **Implement each issue — `/tdd`** — work in a dedicated worktree (`repo.sh worktree <task> <repo>`). `/next` builds the task by spawning a Sonnet `tdd-implementer` sub-agent that derives the plan from the acceptance criteria and writes one failing test → minimal code → refactor, returning a summary the orchestrator reviews — for a HITL task `/next` gathers the human input it needs first, then the loop runs non-interactively. (Hand-invoke `/tdd` instead when you want Opus to build inline for an ad-hoc request — same loop, in the main agent.) Right after the build, the **post-build acceptance gate** validates the slice against its criteria and loops it back into the build on a critical gap — so the task only reaches `done` once it delivers what it promised. `gh pr create` then triggers the security review.
5. **Log events as they happen — `/journal`** — significant events get logged immediately. The `PostToolUse` hook catches most file-write events automatically.
6. **Sync the status view — `/sync-status`** — at session end, `STATUS.md` regenerates from current state. The `Stop` hook fires automatically when `journal.yaml` is newer than `STATUS.md`.
7. **Resume the next session** — Claude reads `STATUS.md` first — a ~500-token synthesis of where the project is, what's active, blocked, and next. No re-orientation cost.
