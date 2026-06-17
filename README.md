# claude-projects

**Give Claude Code a memory that survives across sessions.** `proj` scaffolds a project workspace where Claude picks up exactly where it left off — no re-explaining the goal, no re-reading plans you abandoned days ago, no re-litigating decisions you already made.

## The problem

Claude Code starts every session with a blank slate. For a quick fix, that's fine. But for work that spans days and many sessions — a feature, a migration, a long investigation — you pay a re-orientation tax *every single time*:

- You re-explain what the project is and why it matters.
- Claude opens a plan you abandoned two sessions ago and treats it as current.
- It re-proposes a decision you already made and reversed.
- Nobody — you or Claude — has a reliable picture of what's in progress, what's blocked, and what's next.

The longer the project runs, the worse the drift. State that lives only in the chat history evaporates the moment the session ends.

## What `proj` does

`proj` creates a workspace with a handful of control files that hold project state *outside* the conversation, plus skills that keep those files current automatically. The result is a directory Claude treats as durable memory for one body of work:

- **`STATUS.md`** — a ~500-token, always-current synthesis Claude reads *first* every session: goal, active work, blockers, recent decisions, next moves. Re-orientation cost drops to near zero.
- **`journal.yaml`** — an append-only event log. Every decision, plan, blocker, task flip, and PR is recorded the moment it happens, so the project's history survives the session.
- **Domain glossary + ADRs** — canonical terminology (`CONTEXT.md`) and the *why* behind hard-to-reverse decisions (`docs/adr/`), so they don't get re-litigated later.
- **An idea-to-ship skill pipeline** — `/grill-with-docs → /to-prd → /to-issues → /tdd` carries a rough idea through to shipped code, while `/journal` and `/sync-status` keep the state files fresh in the background (wired via hooks, so you rarely invoke them by hand).

Scaffold one in seconds, then just start working:

```bash
proj my-feature --skills
cd my-feature
claude
```

## When to use it

This structure pays off when work spans **multiple sessions** and involves **decisions worth tracking**. The re-orientation cost it eliminates only matters when there's meaningful state to preserve.

**Good fit:**
- Feature work that will take more than one session to complete
- Migrations or refactors touching many files across many PRs
- Technical investigations where research and decisions accumulate
- Anything with a Jira ticket and a plan document behind it

**Not worth the overhead:**
- A quick one-off fix or a single-session task
- Simple questions answered in a single exchange

If you're not sure, scaffold it anyway — `proj` takes seconds and the workspace stays out of your way if you don't need it. The cost of over-structuring a small task is low; the cost of under-structuring a large one is a Claude that loses the thread every session.

---

## Install

```bash
git clone <repo-url> ~/Documents/repos/claude-projects
cd ~/Documents/repos/claude-projects

# Optionally make proj available on your PATH
ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj
```

Skills are **project-local by default** — `proj --skills` copies them into each workspace's `.claude/skills/` and wires the hooks automatically. Nothing else needed.

## Quick start

```bash
# Scaffold a new workspace with all skills and auto-wired hooks
proj my-project --skills

cd my-project

# Fill in your goal of the project
$EDITOR PROJECT.md

# Start a session — Claude reads STATUS.md first for context
claude
```

From there, use the skills as you work. They compose into a natural flow:

```
/grill-with-docs ← First session: Claude grills you relentlessly until you share an understanding of the project, sharpening CONTEXT.md and offering ADRs as decisions land
/to-prd          ← Synthesizes the design into a PRD — a Jira issue, or docs/plans/<slug>-prd.md when there's no jira_key
/to-issues       ← Breaks the PRD into vertical slices marked AFK or HITL, so you know when Claude can work alone vs needs a human — published as Jira issues or project.yaml tasks
/tdd             ← Test-driven development; the red-green-refactor loop keeps Claude working until each task is complete
/journal         ← (Passive) Claude records decisions, task-status changes, PRs, etc. automatically; /journal can also force an entry
/sync-status     ← (Passive) Regenerates STATUS.md from current state so Claude stays focused on what's relevant now
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
| `--skills [LIST]` | Copy skills into `.claude/skills/` in the new project. `LIST` is an optional comma-separated subset. Omit to copy all bundled skills. |
| `--dry-run` | Print what would be created without writing anything |
| `--force` | Overwrite if target directory already exists |
| `--show-claude-md` | Print the embedded CLAUDE.md template to stdout |
| `-h, --help` | Show help |

**Examples**

```bash
proj my-feature-work
proj aidp-migration --dir ~/Documents/repos --jira AIDP
proj big-refactor --skills --dry-run
proj spike --skills tdd,grill-with-docs
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
│   ├── skills/                # populated when --skills is passed
│   └── settings.json          # hook wiring (created when journal/sync-status skills copied)
├── docs/
│   ├── plans/                 # implementation plans (and local PRDs)
│   ├── adr/                   # architectural decision records
│   ├── research/              # in-depth research docs
│   └── validations/           # proof of completion
├── scripts/                   # one-off and repeatable scripts
├── repos/                     # cloned repos (gitignored)
└── worktrees/                 # git worktrees (gitignored)
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

Skills live in `skills/` and are versioned alongside the scaffolder. Pass `--skills` to `proj` to copy them into a new project's `.claude/skills/`, or symlink them globally (see Install) for use across all projects.

Skills are copied per-project by default. When the `journal` or `sync-status` skills are copied, `proj` also creates `.claude/settings.json` with `asyncRewake` hooks that automatically prompt Claude to log events and keep `STATUS.md` current.

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

---

## Typical workflow

These skills compose into a repeatable process from idea to shipped code.

### 1. Explore the idea — `/grill-with-docs`

Start a session with a rough idea. Run `/grill-with-docs` and let Claude interview you until every major design branch is resolved — sharpening `CONTEXT.md` and recording any hard-to-reverse decisions as ADRs along the way.

### 2. Write the spec — `/to-prd`

Once the grilling session has surfaced and resolved the key questions, run `/to-prd`. Claude synthesizes the conversation into a full PRD and publishes it to Jira (or saves it to `docs/plans/` when there's no `jira_key`). No additional input needed.

### 3. Break it into issues — `/to-issues`

Run `/to-issues` (or `/to-issues <prd-issue>`) to decompose the PRD into vertical-slice issues. Review the proposed breakdown — adjust granularity, flag any wrong HITL/AFK calls, correct dependency ordering — then approve. Claude publishes them in dependency order.

### 4. Implement each issue — `/tdd`

Pick an issue and run `/tdd`. Claude confirms the public interface and which behaviors to test, then works through the implementation one test at a time. Each cycle: write a failing test, write minimal code to pass it, refactor.

### 5. Log events as they happen — `/journal`

Throughout any session, significant events get logged immediately: decisions made mid-implementation, task status flips in `project.yaml`, PRs opened or merged, blockers hit. The `PostToolUse` hook catches most file-write events automatically; use `/journal` directly for anything else.

### 6. Sync the status view — `/sync-status`

At the end of any session where meaningful work happened, `/sync-status` regenerates `STATUS.md` from the full current state. The `Stop` hook fires automatically if `journal.yaml` is newer than `STATUS.md`, so this rarely needs to be invoked manually.

### 7. Resume the next session

Every new session starts with Claude reading `STATUS.md` — a ~500-token synthesis of where the project is, what's active, what's blocked, and what comes next. No re-orientation cost.

