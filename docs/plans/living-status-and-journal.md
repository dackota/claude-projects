---
title: Living Status and Journal System
created: 2026-06-04
last_updated: 2026-06-04
status: active
supersedes: []
superseded_by: null
related: []
jira: null
task: null
---

# Living Status and Journal System

## Problem

Project workspaces accumulate `docs/plans/`, `docs/decisions/`, `docs/research/`, and `docs/validations/` artifacts over weeks of work. As the project evolves:

- Old plans get revised; the originals stay in the tree without any marker that they're superseded.
- Decisions implicitly override earlier ones, but nothing wires the relationship together.
- Research becomes outdated when underlying assumptions change.
- Active work, completed work, and abandoned work all sit in the same directory with no surface-level distinction.

Each new Claude session pays a re-orientation tax: either it reads everything (wasted tokens on stale content) or reads nothing (misses critical context). The workspace is *supposed* to be self-contained context, but over time it becomes noisy context that defeats its own purpose.

The current `proj.sh` scaffold is purely a directory-and-template generator — it has no concept of project lifecycle, no living current-state surface, and no mechanism for keeping synthesis current.

## Solution

Inspired by Karpathy's "LLM Wiki" pattern ([Nobrega summary](https://towardsdatascience.com/give-your-ai-unlimited-updated-context/)) but adapted to a context where every artifact is born curated (no raw → wiki pipeline needed), add two control files and a lifecycle contract:

### 1. `STATUS.md` — LLM-first current-state synthesis

Lives at project root. Regenerated wholesale by `/sync-status` from authoritative inputs. The first file Claude reads each session, sized to fit in ~500 tokens. Dense, link-heavy, machine-parseable under structured headers.

Sections:

- Goal — one sentence from `PROJECT.md`
- Current state — 2–4 sentences
- Active work — bullet list with links to active docs
- Blocked / open questions — bullet list
- Recent decisions — dated, linked
- Key facts — load-bearing constraints learned through the project
- Next moves — bullet list

Frontmatter carries `last_synced` timestamp. STATUS.md is a *view*, not a source-of-truth — if you want a fact to persist, put it in a real artifact.

### 2. `journal.yaml` — append-only structured event log

Lives at project root. Strict YAML list of dated, typed entries. Written *immediately* when a significant event occurs; never rewritten. `/sync-status` reads it but never edits it.

Entry schema:

```yaml
- date: 2026-06-04
  type: decision          # decision | plan | started | done | blocker | supersession | research | pr
  summary: <one or two sentences>
  refs:                   # optional, list of paths or external IDs
    - docs/decisions/foo.md
    - DEVOPS-1525
  jira: DEVOPS-1525       # optional
```

Trigger events for organic appends (Claude writes immediately):

| Event | type |
|-------|------|
| Decision made or reversed | `decision` |
| Plan finalized or revised | `plan` |
| Task status flipped in `project.yaml` | `started` / `done` |
| Blocker hit | `blocker` |
| Doc superseded (frontmatter flipped) | `supersession` |
| Research finalized | `research` |
| PR opened, merged, or closed | `pr` |

Manual escape hatch: `/journal <type> "<summary>"`.

### 3. Lifecycle frontmatter on `docs/**.md`

Every doc in `docs/plans/`, `docs/decisions/`, `docs/research/`, `docs/validations/` carries:

```yaml
---
title: <human-readable title>
created: 2026-05-22
last_updated: 2026-06-04
status: active            # active | superseded | done | abandoned
supersedes: []            # paths to docs this replaces
superseded_by: null       # path to doc that replaced this
related:                  # cross-references for navigation
  - docs/decisions/foo.md
jira: DEVOPS-1525         # optional
task: null                # optional, links to a task id in project.yaml
---
```

`status` is the only authoritative currency signal. `last_updated` is informational (used by diagnostics to flag stale `active` docs). Docs are never moved — superseded docs stay in place with frontmatter flipped, and CLAUDE.md instructs Claude to skip non-`active` unless explicitly referenced.

### 4. `/sync-status` skill — full regenerate

Versioned in `claude-projects/skills/sync-status/`, symlinked into `~/.claude/skills/sync-status/` once per machine. Invokable by you or autonomously by Claude.

Behavior:

1. Read inputs: `PROJECT.md`, `project.yaml`, `journal.yaml`, frontmatter of all `docs/**.md`, full content of `status: active` docs.
2. Synthesize current state.
3. Overwrite `STATUS.md` with new content, updating `last_synced` timestamp.
4. Read-only on `project.yaml` and `journal.yaml`.
5. Bootstrap on first run: if `STATUS.md` or `journal.yaml` is missing, create them. If doc frontmatter is missing `status`, treat as `active` (safe default).

When Claude invokes autonomously:

> Call `/sync-status` when: (1) a plan has been finalized or revised, a decision committed, a task's status changed in `project.yaml`, or a meaningful blocker recorded — *and* you're about to hand back to the user OR finishing a logical work block. Do not sync after every individual doc edit.

The conjunction is "significant change AND natural pause," not either alone.

### 5. `/journal` skill — explicit entry escape hatch

Versioned in `claude-projects/skills/journal/`, symlinked into `~/.claude/skills/journal/`. Invokable by you or Claude for explicit journal entries.

Usage: `/journal <type> "<summary>"`. Appends a properly-formatted entry to `journal.yaml` with today's date. Validates `type` against the enum.

## Trade-offs

**Full regenerate vs. incremental merge** — Picked full regenerate. STATUS.md is a derived view, not source-of-truth. Hand-edits get lost intentionally — if a fact matters, it belongs in an underlying artifact. Token cost (~30–50k per sync for a mid-sized project) is acceptable given how rarely sync runs, and downstream sessions save much more by reading the dense synthesis instead of all active docs.

**No archive directory** — Picked frontmatter-only. Token cost of leaving superseded docs in place is small (low hundreds of tokens per session with disciplined CLAUDE.md guidance). The cost of an archive command is non-trivial (must rewrite cross-references; breaks external links from PRs / Jira / Slack that point to doc paths). YAGNI — if clutter becomes real, archive can be added later as a small script.

**Strict YAML for journal vs. free-form prose** — Picked strict YAML. Journal grows forever and is grep-target territory; structure pays off as it scales. Matches `project.yaml` convention. Slight cost: writing entries requires honoring schema.

**Skill in repo, symlinked globally** — Picked over per-project copy. Updates propagate via `git pull`; no per-project drift. Cost: one-time symlink step per machine.

**Trigger model: significant-change AND natural-pause** — Picked conjunctive. Avoids noisy mid-stream resyncs and avoids missing milestones at handoff. Cost: Claude has to exercise judgment about both signals.

## Considerations

- **Bootstrap path for existing projects.** `/sync-status` is designed to work on a project missing STATUS.md / journal.yaml — it creates them on first run. Existing projects opt in by running `/sync-status` once.
- **DEVOPS-1511 as validation.** That project has the richest history (multiple phases, supersessions, hand-written `note:` fields in `project.yaml`). Migrating it tests whether the design handles real-world mess.
- **`project.yaml` shape unchanged.** Existing field set (`name`, `jira_key`, `created`, `repos`, `tasks`) stays. `/sync-status` reads from it but doesn't require new fields.
- **Schema versioning.** Not adding `schema_version` to frontmatter or `journal.yaml` yet. If a breaking schema change happens later, add it then.
- **Diagnostic / staleness scan.** Out of scope for this plan. A future `/diagnose` skill could flag `active` docs with old `last_updated`, orphaned `superseded_by` references, broken `related` links. Park for now.

## Tasks

### Task 1 — Define schema and update embedded `CLAUDE.md` template in `proj.sh`

Update `claude_md_content()` heredoc in `scripts/proj.sh` to:

- Tell Claude to read `STATUS.md` first every session.
- Document the lifecycle frontmatter contract for `docs/**.md`.
- Document `journal.yaml` schema and trigger events.
- Document when to invoke `/sync-status` (significant change AND natural pause).
- Document when to invoke `/journal` and the type enum.
- Document the convention that superseded docs stay in place; Claude skips non-`active` unless explicitly referenced.

Distinct, reviewable: a single self-contained edit to one file (`proj.sh`) plus correspondingly the live `CLAUDE.md` at repo root for this meta-project.

### Task 2 — Update `proj.sh` scaffold + `test-proj.sh` for new outputs

`proj.sh` additions:

- Create `STATUS.md` stub at project root with `last_synced: null` frontmatter and a "not yet synced" placeholder body.
- Create `journal.yaml` stub at project root with `entries: []` (or simply `[]`).
- No new directories — keep filesystem footprint minimal.

`test-proj.sh` additions:

- Assert `STATUS.md` exists and has correct frontmatter.
- Assert `journal.yaml` exists and is valid YAML with an empty list.

Distinct, reviewable: scaffold + tests change together.

### Task 3 — Build `/sync-status` skill

Create `skills/sync-status/SKILL.md` (and any supporting scripts). Skill responsibilities:

- Read inputs: `PROJECT.md`, `project.yaml`, `journal.yaml`, frontmatter of all `docs/**.md`, full content of `status: active` docs.
- Bootstrap missing files if absent.
- Synthesize `STATUS.md` with the section structure defined above.
- Overwrite `STATUS.md`, update `last_synced` to current timestamp.
- Read-only on every other file.

Distinct, reviewable: a single new skill directory.

### Task 4 — Build `/journal` skill

Create `skills/journal/SKILL.md`. Skill responsibilities:

- Accept `<type>` and `<summary>` arguments.
- Validate `type` against enum.
- Append a new entry to `journal.yaml` with today's date and the given fields.
- Refuse to run if outside a claude-projects-style workspace (no `project.yaml` or no `journal.yaml`).

Distinct, reviewable: a single new skill directory.

### Task 5 — Update `README.md`

- Document new files in scaffolded structure: `STATUS.md`, `journal.yaml`.
- Document frontmatter schema for `docs/**.md`.
- Document `/sync-status` and `/journal` skills, with install steps (symlink commands).
- Document the model: STATUS.md is read first, journal.yaml is the event log, frontmatter signals currency.

Distinct, reviewable: one doc file.

### Task 6 — Migrate `DEVOPS-1511-decompose-monochart` as validation

In `~/Documents/repos/projects/DEVOPS-1511-decompose-monochart/`:

- Add lifecycle frontmatter to every existing doc in `docs/plans/`, `docs/decisions/`, `docs/research/`, `docs/validations/`. Mark superseded ones, link them, set `status` accurately.
- Create `journal.yaml` and backfill entries from the rich `note:` fields embedded in `project.yaml` tasks. Each existing note becomes one or more journal entries with appropriate type.
- Run `/sync-status` to generate the initial `STATUS.md`.
- Audit: does the resulting STATUS.md give a Claude session enough to orient without reading any other doc? Iterate on the skill / schema based on what's missing.

Distinct, reviewable: a single project's content change, plus any feedback edits to skills/schema (which may produce follow-up commits to Tasks 1–4).

## Open work after this plan

- Diagnostic skill (`/diagnose` or similar) — out of scope; revisit once we have lived experience with the schema.
- Archive mechanism — explicitly deferred. Reconsider only if frontmatter-in-place causes real friction.

## Appendix A — Worked examples

### A.1 Rendered `STATUS.md` (target output of `/sync-status`)

```markdown
---
last_synced: 2026-06-04T15:30:00
---

# Status

## Goal
Decompose the `aidp` Helm umbrella chart into independently versioned subcharts published to ECR.

## Current state
Phase 4 (forked app charts) in progress. Three of six consumer subcharts done and validated in sbx. Standard-api-app base chart (Phase A) seeded and published at v0.1.1 — unblocks the remaining consumer extractions.

## Active work
- DEVOPS-1522 — lowcode-agent: plan drafting ([plan](docs/plans/lowcode-agent.md))
- DEVOPS-1525 — mas consumer subchart: blocked on Phase A landed; ready to start ([plan](docs/plans/mas-consumer.md))

## Blocked / open questions
- ESO chart-scoped path write (OD-17) — deferred to end of project; all consumer subcharts currently use existing `app/{{ .Release.Name }}/aidp-chart/config` path.
- Umbrella `dackota-test` stuck on data-explorer-agent rolling update — `LITELLM_PROXY_API_KEY` empty in umbrella values; needs manual helm upgrade.

## Recent decisions
- 2026-05-22 — Switched mas to consumer-subchart pattern; the "existing custom chart" framing was wrong ([decision](docs/decisions/mas-pattern.md)).
- 2026-05-21 — `import-values` does not pass parent values to child dep (documented during DEVOPS-1519); consumers must own their own values.

## Key facts
- standard-api-app v0.1.1 published to ECR `prd/helm/standard-api-app`.
- Renovate `fileMatch` rule shipped in PR #755 (2026-05-21).
- Consumer subcharts own their `*-secrets` resource; umbrella does not.

## Next moves
- Finalize DEVOPS-1522 plan.
- Start DEVOPS-1525 implementation once plan reviewed.
- Park DEVOPS-1531 (umbrella cleanup) until all consumers extracted.
```

Roughly 350 tokens — fits the "~500 token" budget for the first thing every session reads.

### A.2 Rendered `journal.yaml` (target after a handful of entries)

```yaml
- date: 2026-05-22
  type: decision
  summary: Switched mas to consumer-subchart pattern; the custom-chart framing was wrong.
  refs:
    - docs/decisions/mas-pattern.md
    - docs/plans/mas-consumer.md
  jira: DEVOPS-1525

- date: 2026-05-22
  type: done
  summary: DEVOPS-1521 (data-explorer-agent) PR #829 re-validated; standalone 1/1 Running, all 5 steps PASS.
  refs:
    - https://github.com/Panasonic-Global-Applied-AI/kanpai-helm-charts/pull/829
  jira: DEVOPS-1521

- date: 2026-05-22
  type: blocker
  summary: Umbrella dackota-test stuck on data-explorer-agent rolling update; LITELLM_PROXY_API_KEY empty.
  jira: DEVOPS-1521

- date: 2026-06-01
  type: plan
  summary: Drafted lowcode-agent extraction plan; follows established consumer pattern.
  refs:
    - docs/plans/lowcode-agent.md
  jira: DEVOPS-1522
```

Entries are appended in chronological order. Multiple entries can share a date.

### A.3 Migrated doc frontmatter (target after Task 6 on DEVOPS-1511)

A research doc that's still load-bearing:

```markdown
---
title: standard-api-app dependency injection patterns
created: 2026-04-30
last_updated: 2026-05-21
status: active
supersedes: []
superseded_by: null
related:
  - docs/decisions/consumer-subchart-pattern.md
jira: DEVOPS-1650
---

# standard-api-app dependency injection patterns
...
```

A plan that's been replaced:

```markdown
---
title: mas custom-chart extraction (original framing)
created: 2026-05-15
last_updated: 2026-05-22
status: superseded
supersedes: []
superseded_by: docs/plans/mas-consumer.md
related:
  - docs/decisions/mas-pattern.md
jira: DEVOPS-1525
---

# mas custom-chart extraction (original framing)

> Superseded 2026-05-22: framing was wrong — mas already aliases standard-api-app
> in the umbrella; correct pattern is a consumer subchart. See `mas-consumer.md`.

...
```

### A.4 `STATUS.md` stub written by `proj.sh` (Task 2)

```markdown
---
last_synced: null
---

# Status

_Not yet synced. Run `/sync-status` once meaningful work begins, or Claude will invoke it after the first significant change + natural pause._
```

### A.5 `journal.yaml` stub written by `proj.sh` (Task 2)

```yaml
[]
```

(An empty YAML list. Appenders push onto it.)

### A.6 Skeleton `skills/sync-status/SKILL.md` (Task 3)

Follow the standard Claude Code skill format (see `~/.claude/skills/strategic-compact/SKILL.md` for a working example). Frontmatter:

```markdown
---
name: sync-status
description: Regenerate STATUS.md for the current claude-projects workspace by synthesizing PROJECT.md, project.yaml, journal.yaml, and active docs. Use when finishing a logical work block after significant changes, or when the user invokes /sync-status.
---

# /sync-status

Full regenerate of `STATUS.md` from authoritative inputs.

## When to run
... (the trigger spec from §4 of the plan)

## Inputs read
... (the input list from §4)

## Output
... (overwrite STATUS.md, structure per Appendix A.1)

## Bootstrap behavior
... (create STATUS.md / journal.yaml if missing; treat missing `status` as `active`)
```

### A.7 Skeleton `skills/journal/SKILL.md` (Task 4)

```markdown
---
name: journal
description: Append a single entry to journal.yaml in the current claude-projects workspace. Use when recording a significant event (decision, plan, blocker, done, etc.) and a natural pause hasn't arrived yet, or when the user invokes /journal explicitly.
---

# /journal

Append one structured entry to `journal.yaml`.

## Usage
/journal <type> "<summary>"

## Type enum
decision | plan | started | done | blocker | supersession | research | pr

## Behavior
- Validates type against enum; rejects unknown types with a clear error.
- Appends an entry with today's date (UTC).
- Refuses to run if no `journal.yaml` is present in the current working directory or its parents (avoid accidental writes outside a workspace).
```

## Appendix B — Implementation notes

- **Skill format reference**: Claude Code skills are `SKILL.md` files with frontmatter (`name`, `description`). See `~/.claude/skills/strategic-compact/SKILL.md` or `~/.claude/skills/code-tour/SKILL.md` for working examples.
- **Symlink install commands** (for README in Task 5):
  ```bash
  ln -s "$(pwd)/skills/sync-status" ~/.claude/skills/sync-status
  ln -s "$(pwd)/skills/journal"      ~/.claude/skills/journal
  ```
- **Heredoc gotchas in `proj.sh`**: the existing `claude_md_content()` uses `<< 'CLAUDE_MD_EOF'` (quoted) to disable variable interpolation. Keep that — the template should be byte-identical regardless of caller environment. If you need to interpolate (e.g. `$PROJECT_NAME`), use a separate unquoted heredoc.
- **Where the `CLAUDE.md` lives twice**: the embedded heredoc in `proj.sh` is the scaffolded template *for new projects*. The repo-root `CLAUDE.md` of `claude-projects` itself is a separate file (`/Users/dackota.johnson/Documents/repos/claude-projects/CLAUDE.md`) describing *this* meta-project. Both need to be kept in sync when the template changes — Task 1 should explicitly update both.
- **DEVOPS-1511 migration order** (Task 6): (a) add frontmatter to docs first, (b) create `journal.yaml` and backfill from `project.yaml` `note:` fields, (c) create stub `STATUS.md` if `/sync-status` isn't ready yet — or run `/sync-status` to generate it. The migration is read-only on `project.yaml`: don't strip the `note:` fields after backfilling; leave them as redundant evidence in case the journal entries are wrong.
- **Validation criterion for Task 6**: a fresh Claude session, starting from cold, should be able to orient itself on DEVOPS-1511 by reading only `STATUS.md` plus 1–2 linked active docs. If it has to grep through `project.yaml` notes or scan superseded plans, the synthesis is missing something.
- Schema versioning — defer until a breaking change forces it.
