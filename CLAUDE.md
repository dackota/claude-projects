# claude-projects

This is a **bootstrap tool repo** — not a project workspace. It provides the `proj` CLI and a set of bundled skills for scaffolding new Claude Code project workspaces.

## What's here

| Path | Purpose |
|------|---------|
| `scripts/proj.sh` | CLI that scaffolds new project workspaces |
| `scripts/test-proj.sh` | Smoke tests for `proj.sh` |
| `skills/` | Skills bundled with this repo (can be copied into new projects via `--skills`) |
| `README.md` | User-facing documentation |

## Skills

Skills live in `skills/<name>/` and each contains a `SKILL.md` plus any supporting files.

Bundled skills:

| Skill | Purpose |
|-------|---------|
| `journal` | Append typed entries to `journal.yaml` |
| `sync-status` | Regenerate `STATUS.md` from project state |
| `grill-me` | Relentless design interview, one question at a time |
| `to-prd` | Synthesize conversation context into a PRD |
| `to-issues` | Break a plan into tracer-bullet vertical-slice issues |
| `tdd` | Test-driven development red-green-refactor loop |

## Working on this repo

- **Adding a skill**: create `skills/<name>/SKILL.md` (+ any supporting `.md` files). No other changes needed — `proj --skills` picks up any skill in `skills/` by name.
- **Changing the scaffold template**: edit the `claude_md_content()` heredoc in `scripts/proj.sh`. Run `bash scripts/test-proj.sh` to verify.
- **Installing `proj` globally**: `ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj`
- **Installing skills globally**: `ln -s "$(pwd)/skills/<name>" ~/.claude/skills/<name>`

## proj CLI quick reference

```
proj <name>                     # scaffold a bare workspace
proj <name> --skills            # scaffold + copy all bundled skills to .claude/skills/
proj <name> --skills tdd,grill-me  # scaffold + copy specific skills
proj <name> --jira KEY          # include Jira key in project.yaml
proj --dry-run <name>           # preview without writing
proj --show-claude-md           # print the embedded CLAUDE.md template
```
