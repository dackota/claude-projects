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
| `grill-with-docs` | Relentless design interview that sharpens `CONTEXT.md` and offers ADRs |
| `to-prd` | Synthesize conversation context into a PRD |
| `to-issues` | Break a plan into tracer-bullet vertical-slice issues |
| `tdd` | Test-driven development red-green-refactor loop |
| `repo` | Hook-enforced repo & worktree management via `scripts/repo.sh` |

## Working on this repo

- **Adding a skill**: create `skills/<name>/SKILL.md` (+ any supporting `.md` files). No other changes needed — `proj --skills` picks up any skill in `skills/` by name.
- **Hook-bearing skills** (`journal`, `sync-status`, `repo`) are special-cased in `wire_skill_hooks()` / `post_install_skill()` in `scripts/proj.sh`, which idempotently merge their hooks into the workspace's `.claude/settings.json` (and, for `repo`, copy `repo.sh` out to `scripts/`). Wire a new hook-bearing skill there.
- **Changing the scaffold template**: edit the `claude_md_content()` heredoc in `scripts/proj.sh`. Run `bash scripts/test-proj.sh` to verify.
- **Installing `proj` globally**: `ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj`
- **Installing skills globally**: `ln -s "$(pwd)/skills/<name>" ~/.claude/skills/<name>`

## proj CLI quick reference

```
proj <name>                     # scaffold a bare workspace
proj <name> --skills            # scaffold + copy all bundled skills to .claude/skills/
proj <name> --skills tdd,grill-with-docs  # scaffold + copy specific skills
proj <name> --jira KEY          # include Jira key in project.yaml
proj --dry-run <name>           # preview without writing
proj --show-claude-md           # print the embedded CLAUDE.md template
```
