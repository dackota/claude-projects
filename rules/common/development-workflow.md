# Development Workflow

1. **Research first** — search GitHub (`gh search repos` / `gh search code`) and package
   registries for existing implementations before writing anything new; confirm API
   behavior against primary docs (Context7). Prefer adopting a proven approach over
   net-new code.
2. **Plan before coding** — produce a spec/PRD; break work into vertical slices.
3. **TDD** — red-green-refactor, one behavior at a time; see testing.md.
4. **Independent review** — something that didn't write the code reviews it.
   Severity: CRITICAL blocks the merge; HIGH should be fixed before merge; MEDIUM/LOW
   at your discretion.
5. **Commit & PR** — conventional commits (see git-workflow.md); request review only
   after CI passes, conflicts are resolved, and the branch is up to date.
