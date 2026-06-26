# claude-projects

This is a **bootstrap tool repo** — not a project workspace. It provides the `proj` CLI and a set of bundled skills for scaffolding new Claude Code project workspaces.

## What's here

| Path | Purpose |
|------|---------|
| `scripts/proj.sh` | CLI that scaffolds new project workspaces |
| `scripts/test-proj.sh` | Smoke tests for `proj.sh` |
| `skills/` | Skills bundled with this repo (bundled into new projects by default; `--no-skills` to opt out) |
| `agents/` | Agent definitions a skill can pull in via its `agents:` frontmatter |
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
| `tdd` | Test-driven development red-green-refactor loop. Runs inline in the main agent when hand-invoked; `/next` builds tasks (AFK or HITL) by spawning the Sonnet `tdd-implementer` sub-agent (HITL gets a planning gate first) |
| `repo` | Hook-enforced repo & worktree management via `scripts/repo.sh` |
| `security-review` | App-code security checklist (OWASP, secrets, authn/z, injection) |
| `cloud-infra-security` | Cloud/IaC security checklist (IAM, network, CI/CD, secrets) |
| `pr-security-review` | Gates `gh pr create` behind an independent `security-reviewer` agent |

## Working on this repo

- **Adding a skill**: create `skills/<name>/SKILL.md` (+ any supporting `.md` files). No other changes needed — `proj` bundles any skill in `skills/` by default (and `--skills <name>` picks it up by name).
- **Hook-bearing skills** (`journal`, `sync-status`, `repo`, `pr-security-review`) are special-cased in `wire_skill_hooks()` / `post_install_skill()` in `scripts/proj.sh`, which idempotently merge their hooks into the workspace's `.claude/settings.json` (and, for `repo`, copy `repo.sh` out to `scripts/`). Wire a new hook-bearing skill there.
- **Agent-bearing skills**: a skill declares the agents it needs via an `agents:` list in its `SKILL.md` frontmatter. `install_skill_agents()` reads that with `yq` and copies the named `agents/<name>.md` into the workspace's `.claude/agents/` (auto-discovered, no wiring). Add new agents under `agents/`.
- **`security-review` & `cloud-infra-security`** are the canonical sources for those skills; `~/.claude/skills/<name>` are symlinks back to them.
- **Changing the scaffold template**: edit the `claude_md_content()` heredoc in `scripts/proj.sh`. Run `bash scripts/test-proj.sh` to verify.
- **Installing `proj` globally**: `ln -s "$(pwd)/scripts/proj.sh" /usr/local/bin/proj`
- **Installing skills globally**: `ln -s "$(pwd)/skills/<name>" ~/.claude/skills/<name>`

## proj CLI quick reference

```
proj <name>                     # scaffold + bundle all skills (default)
proj <name> --no-skills         # scaffold without bundling skills
proj <name> --skills tdd,grill-with-docs  # scaffold + bundle a specific subset
proj <name> --jira KEY          # include Jira key in project.yaml
proj --dry-run <name>           # preview without writing
proj --show-claude-md           # print the embedded CLAUDE.md template
```
