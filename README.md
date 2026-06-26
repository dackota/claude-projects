# claude-projects

**Scaffold self-contained Claude Code workspaces that remember, follow a workflow, and enforce their own guardrails.** `proj` creates a project directory where Claude picks up exactly where it left off, carries a rough idea through to shipped code, and can't quietly skip the disciplines you care about — repo hygiene, worktree isolation, an independent acceptance-and-security review before every PR. Skills, hooks, and agents all ship *inside the workspace*, like a virtualenv for one body of work — no reliance on global config.

## The problem

Claude Code starts every session with a blank slate, and nothing holds it to your conventions. For a quick fix that's fine. But for work that spans days and many sessions — a feature, a migration, a long investigation — two things bite you:

- **Re-orientation tax.** You re-explain the goal; Claude reopens a plan you abandoned two sessions ago as if it's current, and re-proposes a decision you already reversed. State that lives only in chat history evaporates the moment the session ends.
- **Drifting discipline.** Repos get cloned wherever; branches get switched inside a shared clone, stranding in-progress work; worktrees silently fall behind their base, costing rework at merge time; PRs open with no security review. Prose rules in a `CLAUDE.md` get ignored under pressure.

The longer the project runs, the worse both get.

## What `proj` does

`proj` creates a workspace with control files that hold project state *outside* the conversation, plus bundled skills, hooks, and agents that keep those files current and enforce discipline automatically. Four pillars:

- **Durable memory** — `STATUS.md` (a ~500-token current-state synthesis Claude reads *first* every session), an append-only `journal.yaml`, a `CONTEXT.md` glossary, and ADRs for hard-to-reverse decisions. Re-orientation cost drops to near zero.
- **An idea-to-ship pipeline, routed for you** — `/next` reads the workspace's own state and dispatches the right phase (`grill-with-docs → to-prd → to-issues → tdd`), so you never have to remember which skill comes next. It auto-chains the planning arc and hands off to a fresh session per task. `/journal` and `/sync-status` keep the state files fresh in the background (wired via hooks, so you rarely invoke them by hand).
- **Repo & worktree discipline** — the `repo` skill routes every repo/worktree operation through a generated `scripts/repo.sh`, with a hook that blocks raw `git clone` / `worktree add` / branch-switching and warns before you build on a worktree that's gone stale. Dependent slices can **stack** on an in-review branch so work never stalls waiting for review.
- **Independent PR review (acceptance + security)** — the `pr-security-review` gate holds `gh pr create` until two fresh agents (neither of which saw the implementation) sign off: an `implementation-validator` checks the diff against the slice's acceptance criteria, then a `security-reviewer` checks it against bundled security checklists.

Everything is **project-local**: skills, hooks, and agents are copied into the workspace and wired automatically, so it stays self-contained and portable.

Scaffold one in seconds, then just start working:

```bash
proj my-feature
cd my-feature
claude
```

## When to use it

This pays off when work spans **multiple sessions**, touches **real repos**, and ends in **PRs** — that's where the memory, the repo discipline, and the security gate all earn their keep.

**Good fit:**
- Feature work, migrations, or refactors spanning many sessions and PRs
- Anything touching infrastructure or application code you'll open PRs against
- Technical investigations where research and decisions accumulate
- Anything with a Jira ticket and a plan document behind it

**Not worth the overhead:**
- A quick one-off fix or a single-session task
- Simple questions answered in a single exchange

If you're not sure, scaffold it anyway — `proj` takes seconds and stays out of your way if you don't need it.

---

## Install

```bash
git clone <repo-url> ~/Documents/repos/claude-projects
cd ~/Documents/repos/claude-projects

# Optionally make proj available on your PATH
ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj
```

Skills are **bundled by default** — every `proj <name>` copies them into the workspace's `.claude/skills/` and wires the hooks automatically. Pass `--no-skills` to opt out, or `--skills LIST` to bundle only a subset.

## Quick start

```bash
# Scaffold a new workspace — all skills + auto-wired hooks are bundled by default
proj my-project

cd my-project

# Fill in your goal of the project
$EDITOR PROJECT.md

# Start a session — Claude reads STATUS.md first for context
claude
```

From there you rarely pick a skill by hand — **`/next` routes you.** It reads the workspace state and runs the right phase:

```
/next            ← Routes you: reads STATUS.md / project.yaml, reports the phase, and runs the right phase below
/grill-with-docs ← First session: Claude grills you relentlessly until you share an understanding of the project, sharpening CONTEXT.md and offering ADRs as decisions land
/to-prd          ← Synthesizes the design into a PRD — a Jira issue, or docs/plans/<slug>-prd.md when there's no jira_key
/to-issues       ← Breaks the PRD into vertical slices marked AFK or HITL, so you know when Claude can work alone vs needs a human — published as Jira issues or project.yaml tasks
/tdd             ← Test-driven development; the red-green-refactor loop keeps Claude working until each task is complete
/journal         ← (Passive) Claude records decisions, task-status changes, PRs, etc. automatically; /journal can also force an entry
/sync-status     ← (Passive) Regenerates STATUS.md from current state so Claude stays focused on what's relevant now
/codebase-researcher ← (Optional) Read-only codebase mapper; offered mid-grill when a deep unknown needs research, never forced
```

## Usage

```bash
proj <project-name> [options]
```

**Options**

| Flag | Description |
|------|-------------|
| `--dir <path>` | Base directory (default: current directory) |
| `--jira <KEY>` | Jira project key, e.g. `AIDP` |
| `--skills [LIST]` | Skills are bundled by default; pass `LIST` (comma-separated) to bundle only a subset. Bare `--skills` equals the default (all skills). |
| `--no-skills` | Opt out of bundling skills into the new project. |
| `--dry-run` | Print what would be created without writing anything |
| `--force` | Overwrite if target directory already exists |
| `--show-claude-md` | Print the embedded CLAUDE.md template to stdout |
| `-h, --help` | Show help |

**Examples**

```bash
proj my-feature-work                                    # all skills bundled by default
proj aidp-migration --dir ~/Documents/repos --jira AIDP
proj minimal --no-skills                                # scaffold without skills
proj spike --skills tdd,grill-with-docs                 # bundle only a subset
```

## Scaffolded structure

```
<project-name>/
├── CLAUDE.md                  # project conventions for Claude Code
├── PROJECT.md                 # goals and context (fill this in)
├── STATUS.md                  # LLM-first current-state synthesis (read first each session)
├── CONTEXT.md                 # domain glossary (canonical terms)
├── journal.yaml               # append-only structured event log
├── project.yaml               # source of truth: repos, tasks, Jira key
├── .gitignore                 # excludes repos/ and worktrees/
├── .claude/
│   ├── skills/                # bundled skills (default; --no-skills to opt out)
│   ├── agents/                # bundled agents (security-reviewer, implementation-validator)
│   └── settings.json          # auto-wired hooks (journal, sync-status, repo, pr-security-review)
├── docs/
│   ├── plans/                 # implementation plans (and local PRDs)
│   ├── adr/                   # architectural decision records
│   ├── research/              # in-depth research docs
│   └── validations/           # proof of completion
├── scripts/                   # one-off and repeatable scripts (repo.sh present when the repo skill is bundled — i.e. by default)
├── repos/                     # cloned repos (gitignored; managed via scripts/repo.sh)
└── worktrees/                 # git worktrees, worktrees/<task>/<repo> (gitignored)
```

## Living status system

> Inspired by [Give Your AI Unlimited, Updated Context](https://towardsdatascience.com/give-your-ai-unlimited-updated-context/) — the idea that an LLM-optimized current-state document eliminates the re-orientation cost at the start of every session.

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

## Skills

Skills live in `skills/` and are versioned alongside the scaffolder. `proj` copies them into a new project's `.claude/skills/` **by default** (`--no-skills` to opt out, `--skills LIST` for a subset), or you can symlink them globally (see Install) for use across all projects.

Skills are copied per-project by default. Hook-bearing skills (`journal`, `sync-status`, `repo`, `pr-security-review`) also get their hooks **idempotently merged** into `.claude/settings.json` — so they compose cleanly and re-running `proj update-skills` on an existing workspace adds any missing wiring without duplicating it. `journal`/`sync-status` add `asyncRewake` hooks that prompt Claude to log events and keep `STATUS.md` current; `repo` adds a PreToolUse guard plus staleness hooks and drops `scripts/repo.sh` into the workspace; `pr-security-review` adds the PR gate. A skill can also pull in an agent via an `agents:` list in its frontmatter — `proj` copies the named definitions from the repo's `agents/` into `.claude/agents/`.

### /next — the workflow router

`/next` is the orchestrator that removes the "which skill do I run?" decision. It reads the workspace's state (`project.yaml`, `docs/plans/` PRDs, `journal.yaml`, or — in Jira mode — the tracker), infers the lifecycle phase, and dispatches to the skill that handles it. It **complements** the phase skills (each stays directly invokable) and is wired into the scaffolded `CLAUDE.md` so a session self-orients after reading `STATUS.md`. `proj --skills next` also pulls in the skills it orchestrates.

| Phase | Detected by | Routes to |
|-------|-------------|-----------|
| Grill | no PRD yet | `grill-with-docs` (then `to-prd` on shared understanding) |
| Slice | PRD exists, no tasks | `to-issues` |
| Pick | tasks exist, none active | next unblocked task (AFK-preferred; HITL surfaced) → `tdd` |
| Build | a task is active | continue `tdd` |
| Land | task done, not PR'd | the unified PR-review gate |

The planning arc (grill → prd → issues) auto-chains in one session with a light confirm at each gate; building breaks to a **fresh session per task** to resist context drift. When a picked task depends on an in-review slice, `/next` stacks its worktree on that branch (via `repo.sh`) so work doesn't stall, and warns if a stacked base was reopened.

```
/next
```

### /journal

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

### /sync-status

Regenerates `STATUS.md` from all authoritative inputs — `PROJECT.md`, `project.yaml`, `journal.yaml`, and every `status: active` doc in `docs/`. Run it (or let Claude invoke it automatically) at the end of any session where meaningful work happened.

**Hook:** a `Stop` hook fires when `journal.yaml` is newer than `STATUS.md`, prompting Claude to sync before the session ends.

### /repo

Makes repo and worktree handling explicit and enforced, so you can trust Claude is using `repos/` and worktrees the way you intend — and isn't quietly building on a worktree that's gone stale. Installs a first-class, readable `scripts/repo.sh` and routes every repo/worktree operation through it:

```
scripts/repo.sh clone <url> [name]                        # clone into repos/, register in project.yaml
scripts/repo.sh worktree <task> <repo> [--onto <parent>]  # start work; stack on <parent> or auto-derive from blocked_by
scripts/repo.sh sync <task> [repo]                        # merge the base (or stacked parent) in (worktrees drift while you work)
scripts/repo.sh status [task]                             # behind/ahead + dirty + STALE / BASE REOPENED flags, per worktree
scripts/repo.sh remove <task> [repo]                      # remove worktree + delete local branch (safe by default)
scripts/repo.sh list                                      # registered repos
```

- **Repos are declared in `project.yaml`; worktrees are derived live** from `git worktree list` and the `worktrees/<task>/<repo>` layout (one task can span repos). No worktree state to drift out of sync.
- **`sync` is the only working-tree mutation** — it refuses on a dirty tree, merges `origin/<base>` (no force-push), and stops to report conflicts rather than auto-resolving. **`remove`** refuses to discard unpushed commits unless `--force`.
- **Stacked work** — when a task depends on another that's still in review, `worktree --onto <parent>` (or auto-derived from a single unmerged `blocked_by`) branches off the parent instead of the base, so dependent work doesn't stall. The stack pointer is the branch's git upstream; `sync` cascades the parent's fixes and re-points to the base once the parent merges. If a stacked parent is reopened, `status` flags it **BASE REOPENED** — `repo.sh` never auto-rebases a disturbed stack.

**Hooks:**
- A **PreToolUse `Bash`** guard blocks raw `git clone`, `git worktree add`, and branch create/switch inside `repos/`/`worktrees/`, redirecting Claude to `repo.sh`. Read-only git and `git checkout -- <file>` stay allowed.
- A **PreToolUse `Edit|Write`** hook warns (once per worktree per session) before Claude edits a worktree that's behind its base — catching drift *before* the rework, not after.
- A **`Stop`** hook summarizes any stale worktrees at session end.

`repo.sh` requires `yq` (v4) for `project.yaml` writes. Already on an existing workspace? `proj update-skills` installs `repo.sh` and merges the hooks in without disturbing your other settings.

### /pr-security-review — the unified PR-review gate

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

> The `/grill-with-docs`, `/to-prd`, `/to-issues`, and `/tdd` skills are adapted from [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering).

### /grill-with-docs

Interviews you relentlessly about a plan or design — one question at a time, working through every branch of the decision tree. Each answer comes with Claude's recommendation, so the interview also surfaces Claude's assumptions for you to correct. As terms get resolved it sharpens `CONTEXT.md` (the domain glossary) inline, and it offers an ADR whenever a decision is hard to reverse, surprising without context, and the result of a real trade-off.

```
/grill-with-docs
```

Invoke it when you have a rough idea and want to find the holes before writing a plan. The output of a grilling session is the raw material for `/to-prd`.

### /to-prd

Synthesizes everything in the current conversation into a structured PRD without interviewing you further — it just writes. The PRD covers the problem statement, solution, an extensive list of user stories, implementation decisions, testing decisions, and out-of-scope items. It publishes as a Jira issue when `project.yaml` has a `jira_key`, or saves to `docs/plans/<slug>-prd.md` otherwise.

```
/to-prd
```

Use it after `/grill-with-docs` has resolved the major open questions, or any time the conversation contains enough context to write a spec.

### /to-issues

Breaks a plan or PRD into independently-grabbable vertical-slice issues. Each issue cuts end-to-end through all layers (schema, API, UI, tests) and is either HITL (requires human input) or AFK (can be implemented and merged autonomously). Presents the breakdown for your review, then publishes: with a `jira_key`, as Jira issues labeled `afk`/`hitl` (plus `ready-for-agent` on AFK only); without one, as `project.yaml` tasks.

```
/to-issues
/to-issues <issue-number>   # start from an existing tracker issue
```

Use it after `/to-prd` to turn the spec into a concrete backlog.

### /tdd

Drives implementation using a strict red-green-refactor loop — one test at a time, never horizontal slicing. Before writing any code, confirms the interface design and which behaviors matter most. Enforces testing through public interfaces only, not implementation details.

```
/tdd
```

Use it when starting implementation of any issue produced by `/to-issues`.

### /codebase-researcher

A read-only codebase mapper: traces execution paths, maps architecture layers, and surfaces dependencies and risks for a subsystem, then writes the findings to `docs/research/`. It is **optional** — `grill-with-docs` already explores during grilling, so reach for this only when a question needs more depth than the interview should carry. `/next` may offer it mid-grill when a deep unknown surfaces, but never forces it.

```
/codebase-researcher
```

---

## Typical workflow

These skills compose into a repeatable process from idea to shipped code — and **`/next` routes you through it**, so the steps below are what happens phase by phase, not a sequence you drive by hand. Throughout, the `repo` skill keeps each task isolated in its own worktree (stacking dependent slices when needed), and the unified PR-review gate vets the diff with two independent agents — acceptance then security — before any PR opens.

### 1. Explore the idea — `/grill-with-docs`

Start a session with a rough idea. Run `/grill-with-docs` and let Claude interview you until every major design branch is resolved — sharpening `CONTEXT.md` and recording any hard-to-reverse decisions as ADRs along the way.

### 2. Write the spec — `/to-prd`

Once the grilling session has surfaced and resolved the key questions, run `/to-prd`. Claude synthesizes the conversation into a full PRD and publishes it to Jira (or saves it to `docs/plans/` when there's no `jira_key`). No additional input needed.

### 3. Break it into issues — `/to-issues`

Run `/to-issues` (or `/to-issues <prd-issue>`) to decompose the PRD into vertical-slice issues. Review the proposed breakdown — adjust granularity, flag any wrong HITL/AFK calls, correct dependency ordering — then approve. Claude publishes them in dependency order.

### 4. Implement each issue — `/tdd`

Pick an issue and run `/tdd` — working in a dedicated worktree created with `scripts/repo.sh worktree <task> <repo>`, so the base clone stays clean. Claude confirms the public interface and which behaviors to test, then works through the implementation one test at a time: write a failing test, write minimal code to pass it, refactor. When the work is ready, `gh pr create` triggers the unified PR-review gate — an acceptance check then a security check — before the PR opens; a critical acceptance gap loops the task back into `tdd`.

### 5. Log events as they happen — `/journal`

Throughout any session, significant events get logged immediately: decisions made mid-implementation, task status flips in `project.yaml`, PRs opened or merged, blockers hit. The `PostToolUse` hook catches most file-write events automatically; use `/journal` directly for anything else.

### 6. Sync the status view — `/sync-status`

At the end of any session where meaningful work happened, `/sync-status` regenerates `STATUS.md` from the full current state. The `Stop` hook fires automatically if `journal.yaml` is newer than `STATUS.md`, so this rarely needs to be invoked manually.

### 7. Resume the next session

Every new session starts with Claude reading `STATUS.md` — a ~500-token synthesis of where the project is, what's active, what's blocked, and what comes next. No re-orientation cost.

