# claude-projects

Scaffolding and conventions for Claude Code project workspaces.

## Install

```bash
git clone git@github.com:dackota/claude-projects.git ~/Documents/repos/claude-projects
cd ~/Documents/repos/claude-projects

# Optionally make proj available on your PATH
ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj
```

Skills are **project-local by default** — `proj --skills` copies them into each workspace's `.claude/skills/` and wires the hooks automatically. Nothing else needed.

**Optional: make skills available globally** across all projects (not just ones scaffolded with `proj`):

```bash
cd ~/Documents/repos/claude-projects
ln -s "$(pwd)/skills/sync-status" ~/.claude/skills/sync-status
ln -s "$(pwd)/skills/journal"     ~/.claude/skills/journal
ln -s "$(pwd)/skills/grill-me"    ~/.claude/skills/grill-me
ln -s "$(pwd)/skills/to-prd"      ~/.claude/skills/to-prd
ln -s "$(pwd)/skills/to-issues"   ~/.claude/skills/to-issues
ln -s "$(pwd)/skills/tdd"         ~/.claude/skills/tdd
```

> **Note:** If you install skills both globally and per-project, hooks will fire twice. Pick one approach per machine.

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
/grill-me      ← First session have Claude grill you relentlessly untill you both have a shared understanding of the project
/to-prd        ← Takes the project design you decided on with the grill-me skill and converts it into a project requirements doc to capture the desired behaviours
/to-issues     ← Breaks the PRD into vertical slices of work and conviently labels them as AFK or HITL so Claude/you know when it can work on its own and when a human is needed
/tdd           ← Use Test Driven Development to work on each issue. The Red-green-refactor process creates a loop makes Claude work until its complete
/journal       ← (Passive) Claude records important pieces of info like decisions, issue status, etc automatically. /journal can also be called to force an entry
/sync-status   ← (Passive) When new plans/docs/etc are found, STATUS.md is updated to keep Claude focused on only the current relevant info
```

---

## What this is

Each project workspace is a directory that Claude Code uses as context for a large body of work — a feature, migration, investigation, etc. that benefits from having context on multiple sources (repos, plans, etc). This tool defines the structure those workspaces follow, provides a CLI to create them, and ships a set of commonly used and useful skills plus a living curated knowledge store that keeps Claude oriented across sessions.

## When to use it

This structure pays off when work spans **multiple sessions** and involves **decisions worth tracking**. The re-orientation cost it eliminates — Claude re-reading stale plans, rediscovering superseded decisions, losing track of what's in-progress — only matters when there's meaningful state to preserve.

**Good fit:**
- Feature work that will take more than one session to complete
- Migrations or refactors touching many files across many PRs
- Technical investigations where research and decisions accumulate
- Anything with a Jira ticket and a plan document behind it

**Not worth the overhead:**
- A quick one-off fix or a single-session task
- Exploratory spikes you'll throw away
- Simple questions answered in a single exchange

If you're not sure, scaffold it anyway — `proj` takes seconds and the workspace stays out of your way if you don't need it. The cost of over-structuring a small task is low; the cost of under-structuring a large one is a Claude that loses the thread every session.

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
proj spike --skills tdd,grill-me
```

## Scaffolded structure

```
<project-name>/
├── CLAUDE.md                  # project conventions for Claude Code
├── PROJECT.md                 # goals and context (fill this in)
├── STATUS.md                  # LLM-first current-state synthesis (read first each session)
├── journal.yaml               # append-only structured event log
├── project.yaml               # source of truth: repos, tasks, Jira keys
├── .gitignore                 # excludes repos/ and worktrees/
├── .claude/
│   ├── skills/                # populated when --skills is passed
│   └── settings.json          # hook wiring (created when journal/sync-status skills copied)
├── docs/
│   ├── plans/                 # implementation plans
│   ├── decisions/             # lightweight decision records
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

`STATUS.md` is a *view*, not a source of truth. If a fact needs to persist, put it in a plan or decision doc.

### journal.yaml

Append-only event log. Never rewritten — only appended. Entry schema:

```yaml
- date: YYYY-MM-DD
  type: decision   # decision | plan | started | done | blocker | supersession | research | pr
  summary: One or two sentences.
  refs:            # optional
    - docs/decisions/foo.md
  jira: DEVOPS-1234  # optional
```

Claude appends an entry immediately when: a decision is made, a plan is finalized, a task status flips, a blocker is hit, a doc is superseded, research is finalized, or a PR is opened/merged/closed.

## Doc lifecycle frontmatter

Every doc in `docs/` carries:

```yaml
---
title: Human-readable title
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
status: active            # active | superseded | done | abandoned
supersedes: []
superseded_by: null
related:
  - docs/decisions/foo.md
jira: null
task: null
---
```

`status` is the currency signal. Claude skips non-`active` docs unless explicitly referenced. Superseded docs stay in place — never moved or deleted — with `status: superseded` and a block-quote at the top explaining the supersession.

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

**Hooks:** a `PostToolUse` hook fires when `project.yaml` or any `docs/decisions/`, `docs/plans/`, or `docs/research/` file is written, nudging Claude to write the corresponding entry. A `Stop` hook fires if `docs/` files were modified since the last journal entry.

### /sync-status

Regenerates `STATUS.md` from all authoritative inputs — `PROJECT.md`, `project.yaml`, `journal.yaml`, and every `status: active` doc in `docs/`. Run it (or let Claude invoke it automatically) at the end of any session where meaningful work happened.

**Hook:** a `Stop` hook fires when `journal.yaml` is newer than `STATUS.md`, prompting Claude to sync before the session ends.

### /grill-me

Interviews you relentlessly about a plan or design — one question at a time, working through every branch of the decision tree. Use it to stress-test an idea before committing to a plan doc. Claude answers each question with a recommendation, so the interview also surfaces Claude's assumptions for you to correct.

```
/grill-me
```

Invoke it when you have a rough idea and want to find the holes before writing a plan. The output of a grilling session is the raw material for `/to-prd`.

### /to-prd

Synthesizes everything in the current conversation into a structured PRD without interviewing you further — it just writes. The PRD covers the problem statement, solution, an extensive list of user stories, implementation decisions, testing decisions, and out-of-scope items.

```
/to-prd
```

Use it after `/grill-me` has resolved the major open questions, or any time the conversation contains enough context to write a spec.

### /to-issues

Breaks a plan or PRD into independently-grabbable vertical-slice issues. Each issue cuts end-to-end through all layers (schema, API, UI, tests) and is either HITL (requires human input) or AFK (can be implemented and merged autonomously). Presents the breakdown for your review before publishing to the issue tracker.

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

### 1. Explore the idea — `/grill-me`

Start a session with a rough idea. Run `/grill-me` and let Claude interview you until every major design branch is resolved. Push back on Claude's recommendations where you disagree — those disagreements become the interesting decisions.

### 2. Write the spec — `/to-prd`

Once the grilling session has surfaced and resolved the key questions, run `/to-prd`. Claude synthesizes the conversation into a full PRD and publishes it to the issue tracker. No additional input needed.

### 3. Break it into issues — `/to-issues`

Run `/to-issues` (or `/to-issues <prd-issue>`) to decompose the PRD into vertical-slice issues. Review the proposed breakdown — adjust granularity, flag any wrong HITL/AFK calls, correct dependency ordering — then approve. Claude publishes them in dependency order.

### 4. Implement each issue — `/tdd`

Pick an issue and run `/tdd`. Claude confirms the public interface and which behaviors to test, then works through the implementation one test at a time. Each cycle: write a failing test, write minimal code to pass it, refactor.

### 5. Log events as they happen — `/journal`

Throughout any session, significant events get logged immediately: decisions made mid-implementation, task status flips in `project.yaml`, PRs opened or merged, blockers hit. The `PostToolUse` hook catches most file-write events automatically; use `/journal` directly for anything else.

### 6. Sync the status view — `/sync-status`

At the end of any session where meaningful work happened, `/sync-status` regenerates `STATUS.md` from the full current state. The `Stop` hook fires automatically if `journal.yaml` is newer than `STATUS.md`, so this rarely needs to be invoked manually.

### 7. Resume the next session

Every new session starts with Claude reading `STATUS.md` — a dense ~500-token synthesis of where the project is, what's active, what's blocked, and what comes next. No re-orientation cost.

---

## Tests

```bash
bash scripts/test-proj.sh
```
