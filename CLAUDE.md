# Project Structure

See `PROJECT.md` for what this project is trying to accomplish.

## Project Structe

- `project.yaml` - source of truth: repos, tasks, Jira keys, and config
- `PROJECT.md` - project goals and context (read this for the why)
- `CLAUDE.md` - this file
- `docs/` - directory to store project documentation
- `docs/plans/` - directory to store planning documents
- `docs/decisions/` - directory to store research and analysis documents
- `docs/research/` - directory to store research and analysis documents
- `docs/validations/` - directory to store validation documents
- `scripts/` - directory to contain one off scripts used in the project but not belonging to a specific repository
- `repos/` - directory containing cloned repos
- `worktrees/` - directory containing git worktrees associated with tasks

Code repos and worktrees are cloned inside the project directory but are 
`.gitignored`-excluded, they are traced via `projet.yaml`, not committed here. 
Read `project.yaml` to see what repos and tasks exist.

### Artifact Types

All artifacts MUST BE written in Markdown unless otherwise mentioned during a
session. File names MUST use dash separated words. For all Markdown files in
`docs/` you MUST include frontmatter.

- Plans are used to iterate on an idea and used as the source context for work
  to be done. Plans MUST detail the Problem, Solution, Trade-offs, and
  Considerations. Plans MUST BE broken down into Tasks. Each Task MUST BE a
  distinct body of work. A Task MUST BE able to be easily reviewable by a human.
  Store theses in `docs/plans/`. Use this directory when I say things like:
  "create a plan", "let's plan out", "I want to plan a", "plan it out".

- Decision records are used to capture decisions made while buildings or
  executing a plan. Theses are light weight decisions that will guide future
  tasks of the plan or project. Decisions may be turned into Architectural
  Decision Records (ADR) at some point in the future at my discretion. Store
  these in `docs/decisions/`.

- Research document are used to store in depth information about a topic or
  workitem. The research may be referenced by multiple plans. Store these in
  `docs/research/`. Use this directory when I say things like: "Research how X
  works". This can also be used when a plan requires in depth research.

- Validation documents are used to prove that a plan was successfully
  completed. When I ask you to validate that the plan was completed you will
  review the plan, gather evidence of completed work, and create a validation
  document. This MUST include tangible and auditable examples such as file paths
  and lines `path/to/file.ext:34` or the output summary of a successful test run.
  Store these documents in `docs/validations/`.

- Scripts for complex or repeatable workitems. When you need to do something
  that is more complex due to the number of commands or the amount of logic
  (conditionals, loops, advanced scripting language features) or when you need to
  run the same command set over and over again you will create a script. Scripts
  will be put into `scripts/`. Scripts should be written in Bash but you can use
  Python as well.

- Repos is a directory that stores repositories needed by this project. Theses
  repositories may be needed for research or changes in order to complete the
  project. Clone the required repos here.

- Worktrees is a directory that stores git worktrees needed by this project.
  Worktrees MUST be used when working on Tasks. You MUST NOT directly create
  worktrees. 

