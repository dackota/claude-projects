# claude-projects

**Scaffold self-contained Claude Code workspaces that remember, orchestrate specialized agents through a workflow, and enforce their own guardrails.** `proj` creates a project directory where Claude picks up exactly where it left off, *orchestrates a pipeline of focused sub-agents* to carry a rough idea through to shipped code, and can't quietly skip the disciplines you care about — repo hygiene, worktree isolation, an independent review before every PR. Skills, hooks, and agents ship *inside the workspace*, like a virtualenv for one body of work.

## The problem

Claude Code starts every session with a blank slate, and nothing holds it to your conventions. For a quick fix that's fine. For work that spans days and many sessions, two things bite you:

- **Re-orientation tax.** You re-explain the goal; Claude reopens an abandoned plan as if it's current. State that lives only in chat history evaporates when the session ends.
- **Drifting discipline.** Repos get cloned anywhere; worktrees fall behind their base; PRs open with no review. Prose rules in `CLAUDE.md` get ignored under pressure.

## What `proj` does

It creates a workspace with control files that hold project state *outside* the conversation, plus bundled skills, hooks, and agents that keep those files current and enforce discipline automatically. Four pillars:

- **Durable memory** — `STATUS.md` (a ~500-token current-state synthesis Claude reads *first* every session), an append-only `journal.yaml`, a `CONTEXT.md` glossary, and ADRs for hard-to-reverse decisions. Re-orientation cost drops to near zero.
- **An orchestrated, idea-to-ship pipeline** — the main session is an *orchestrator*, not the thing that types every line. `/next` reads the workspace state and dispatches the right phase (`grill-with-docs → to-prd → to-issues → tdd`), and the focused work is handed to short-lived sub-agents on fresh contexts and the right model tier: a Sonnet `tdd-implementer` runs the red-green-refactor loop while the orchestrator plans and reviews. You never have to remember which skill comes next.
- **Repo & worktree discipline** — the `repo` skill routes every repo/worktree operation through a generated `scripts/repo.sh`, blocks raw `git clone` / `worktree add`, and warns before you build on a stale worktree. Dependent slices can **stack** on an in-review branch so work never stalls.
- **Independent PR review** — the orchestrator spawns two fresh review agents (neither saw the implementation) at the `pr-security-review` gate, which holds `gh pr create` until they sign off: an `implementation-validator` checks the diff against the slice's acceptance criteria, then a `security-reviewer` checks it against bundled checklists.

Everything is **project-local**: skills, hooks, and agents are copied into the workspace and wired automatically, so it stays self-contained and portable.

The shape of it — one orchestrator, many short-lived specialists:

```
main session · orchestrator (Opus)
  holds project state · plans · routes · reviews
      │
      ├─ /tdd (hand-invoked) .. Opus runs the loop inline — for ad-hoc builds
      │
      ├─ /next builds a task .. spawns  tdd-implementer (Sonnet) → tests + code  ┐
      └─ gh pr create ........ spawns  implementation-validator → acceptance     │ fresh
                                       security-reviewer        → security       ┘ context
```

Two ways to build, **neither interactive** — the design was settled upstream (grilling, confirmed in `/to-prd` and `/to-issues`), so by build time the acceptance criteria are the contract and there's no planning gate. **Hand-invoke `/tdd`** when you want Opus to do the TDD itself for an ad-hoc request — it runs the loop inline, with you watching. **`/next`** builds pipeline tasks by spawning the Sonnet `tdd-implementer` sub-agent on a fresh context, so the orchestrator just plans/reviews. Every sub-agent — the implementer and the two PR-gate reviewers — starts clean, keeping the heavy, repeatable work on the cheaper model without inheriting a long session's drift.

## Quick start

```bash
proj my-feature          # scaffold + bundle all skills and hooks (default)
cd my-feature
$EDITOR PROJECT.md       # fill in your goal
claude                   # Claude reads STATUS.md first, then /next routes you
```

From there you rarely pick a skill by hand — **`/next` routes you.** It reads the workspace state, reports the phase, and runs the right one:

| Phase | When | Runs |
|-------|------|------|
| Bootstrap | `PROJECT.md` goal still blank | Claude helps you fill in `PROJECT.md` |
| Grill | no PRD yet | `/grill-with-docs` → `/to-prd` |
| Slice | PRD exists, no tasks | `/to-issues` |
| Pick | tasks exist, none active | next unblocked task → autonomous build (`tdd-implementer` sub-agent) |
| Build | a task is active | continue the build via the sub-agent |
| Land | task done, not PR'd | the PR-review gate |

The planning arc auto-chains in one session; building breaks to a fresh session per task to resist context drift.

## When to use it

Pays off when work spans **multiple sessions**, touches **real repos**, and ends in **PRs**.

- **Good fit:** features, migrations, or refactors across many sessions; anything you'll open PRs against; investigations where decisions accumulate; anything with a Jira ticket and a plan.
- **Not worth it:** a quick one-off fix, a single-session task, a question answered in one exchange.

If unsure, scaffold it anyway — `proj` takes seconds and stays out of your way.

## Install

```bash
git clone <repo-url> ~/Documents/repos/claude-projects
cd ~/Documents/repos/claude-projects
ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj   # optional: put proj on PATH
```

Skills are **bundled by default** — every `proj <name>` copies them into the workspace's `.claude/skills/` and wires the hooks automatically. Pass `--no-skills` to opt out, or `--skills LIST` for a subset.

## Usage

```bash
proj <project-name> [options]
```

| Flag | Description |
|------|-------------|
| `--dir <path>` | Base directory (default: current directory) |
| `--jira <KEY>` | Jira project key, e.g. `AIDP` |
| `--skills [LIST]` | Bundle only a comma-separated subset (default: all) |
| `--no-skills` | Don't bundle skills into the new project |
| `--dry-run` | Print what would be created without writing |
| `--force` | Overwrite if the target directory exists |
| `--show-claude-md` | Print the embedded CLAUDE.md template |
| `-h, --help` | Show help |

```bash
proj my-feature-work                                    # all skills bundled
proj aidp-migration --dir ~/Documents/repos --jira AIDP
proj minimal --no-skills                                # scaffold without skills
proj spike --skills tdd,grill-with-docs                 # bundle a subset
```

## Scaffolded structure

```
<project-name>/
├── CLAUDE.md          # project conventions for Claude Code
├── PROJECT.md         # goals and context (fill this in)
├── STATUS.md          # ~500-token current-state synthesis (read first each session)
├── CONTEXT.md         # domain glossary (canonical terms)
├── journal.yaml       # append-only structured event log
├── project.yaml       # source of truth: repos, tasks, Jira key
├── .claude/
│   ├── skills/        # bundled skills (default; --no-skills to opt out)
│   ├── agents/        # bundled agents (security-reviewer, implementation-validator, tdd-implementer)
│   └── settings.json  # auto-wired hooks (journal, sync-status, repo, pr-security-review)
├── docs/              # plans/, adr/, research/, validations/
├── scripts/           # repo.sh (when the repo skill is bundled) + one-off scripts
├── repos/             # cloned repos (gitignored; managed via scripts/repo.sh)
└── worktrees/         # git worktrees, worktrees/<task>/<repo> (gitignored)
```

## Skills

Bundled into every workspace by default. `/next` orchestrates them, but each stays directly invokable.

| Skill | What it does |
|-------|--------------|
| `/next` | Reads workspace state and routes to the right phase below |
| `/grill-with-docs` | Interviews you relentlessly to find holes in a rough idea; sharpens `CONTEXT.md`, offers ADRs |
| `/to-prd` | Synthesizes the conversation into a structured PRD (Jira issue or `docs/plans/`) |
| `/to-issues` | Breaks the PRD into vertical-slice issues marked AFK (autonomous) or HITL (needs a human) |
| `/tdd` | Red-green-refactor, one test at a time, non-interactive. Hand-invoke it for Opus to build a slice inline (ad-hoc); `/next` builds pipeline tasks via the Sonnet `tdd-implementer` sub-agent |
| `/repo` | Routes repo/worktree ops through `scripts/repo.sh`; isolates and stacks worktrees |
| `/pr-security-review` | Independent acceptance + security review before `gh pr create` |
| `/journal` | Appends typed entries to `journal.yaml` (mostly automatic via hooks) |
| `/sync-status` | Regenerates `STATUS.md` from current state (mostly automatic via hooks) |
| `/codebase-researcher` | Optional read-only codebase mapper; writes findings to `docs/research/` |

> `/grill-with-docs`, `/to-prd`, `/to-issues`, and `/tdd` are adapted from [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering).

## Learn more

**[docs/REFERENCE.md](docs/REFERENCE.md)** covers the internals: the living-status files (`STATUS.md` / `journal.yaml` schemas), doc-lifecycle frontmatter, `CONTEXT.md` and ADR conventions, the issue-tracker / task model, the full `/next` routing logic, every `repo.sh` subcommand, the PR-review gate flow, and the hooks each skill wires in.

> The living-status approach is inspired by [Give Your AI Unlimited, Updated Context](https://towardsdatascience.com/give-your-ai-unlimited-updated-context/).
