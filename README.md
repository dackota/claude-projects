# crew

crew helps you get coding work done with Claude Code. You describe what you want. Claude asks you questions until the plan is clear. Then Claude builds each piece in parallel, checks its own work, and opens a pull request for each piece.

You do the thinking up front. The build runs on its own.

Full design: [docs/SPEC.md](docs/SPEC.md).

## Before you start

You need these tools installed:

| Tool | What it is | Install |
|------|------------|---------|
| Claude Code | The AI coding agent that runs in your terminal | https://docs.anthropic.com/en/docs/claude-code |
| `git` | Version control | Comes with Xcode tools on Mac, or `brew install git` |
| `gh` | GitHub from the command line | `brew install gh`, then `gh auth login` |
| `jq` | Reads JSON | `brew install jq` |
| `yq` | Reads YAML | `brew install yq` |

Your code must already be in a git repo on your computer. crew does not clone repos.

## Install crew

```bash
git clone https://github.com/dackota/crew ~/repos/crew
ln -s ~/repos/crew/scripts/crew.sh /usr/local/bin/crew
```

Check it works:

```bash
crew --help
```

## Set up a workspace

A workspace is a folder that sits next to your code. It holds the plan, the task list, and a log. Your code stays where it is.

```bash
crew myproject --repo ~/repos/my-app
```

That makes a folder named `myproject` in the current directory. To point at more than one repo, pass `--repo` more than once. To track tasks as GitHub Issues too, add `--tracker github`.

Now open it in Claude Code:

```bash
cd myproject
claude
```

## The workflow

Type these commands into Claude Code, in order. Each one starts with a slash.

### 1. `/research <topic>` (optional)

Claude reads docs and code and writes notes to `docs/research/`. Use this when you are not sure how something works yet.

### 2. `/grill-with-docs`

Tell Claude what you want to build. Claude asks you questions, in rounds, until nothing is left unclear. Answer them. This is the most important step. Time spent here saves many fix rounds later.

### 3. `/to-spec`

Claude writes the plan as a spec in `docs/specs/`. Read it. Ask for changes if anything is off.

### 4. `/to-tickets`

Claude breaks the spec into small tasks and shows you the list. Each task is one complete piece that can be tested on its own. Say yes, or ask to merge or split tasks. Claude then writes them to `project.yaml`.

### 5. `/build`

Claude builds every task that is ready, all at once. For each task it:

1. Makes a separate copy of your repo (a git worktree) so tasks do not collide.
2. Writes tests and code.
3. Has a second agent check that the task does what the spec says, by running the real thing.
4. Fixes problems, up to 3 times.
5. Opens a pull request, and merges it when CI is green and your repo's rules allow.

It does not ask you anything. When a task cannot be finished, it is marked `blocked` with a note, and Claude tells you at the end.

To build only some tasks: `/build T-3 T-5`.

## Coming back later

Open the workspace and type:

```
/resume
```

Claude tells you what is active, blocked, and ready, and what command to run next.

## Files you will see

| File | What it is |
|------|------------|
| `project.yaml` | The task list. This is the source of truth |
| `STATUS.md` | A short summary. Read this first |
| `journal.yaml` | A log of everything that happened |
| `docs/specs/` | The plans |
| `docs/research/` | Research notes |
| `worktrees/` | Working copies of your repos, one per task. Safe to ignore |

## When something goes wrong

**A task is blocked.** Read its `note` in `project.yaml`. Fix the code by hand in its folder under `worktrees/`, or change the task and run `/build T-<n>` again.

**A pull request stayed open.** CI failed, or your repo needs a review. Handle it on GitHub as usual. Then run `bash scripts/land.sh T-<n>` to finish.

**Claude refuses a git command.** A safety hook stops Claude from committing to your real repo folder. All work must happen in `worktrees/`. This is on purpose.

**Claude will not stop.** A hook asks for a journal entry when a task changed status. Claude will add one and stop.

## Other commands

```bash
crew myproject --repo ~/repos/my-app --dry-run   # show what would be made
crew myproject --repo ~/repos/my-app --force     # start over
crew update-skills [myproject]                    # pull in newer skills after updating crew
```

## For contributors

```bash
bash scripts/test-crew.sh
```

Skills in `skills/` are vendored from Matt Pocock's [engineering skills](https://github.com/mattpocock/skills/tree/main/skills/engineering) with two small edits, plus our own `build`, `resume`, `journal`, `sync-status`, and `verify`.
