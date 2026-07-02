# Development Workflow

> This file extends [common/git-workflow.md](./git-workflow.md) with the full feature development process that happens before git operations.

The Feature Implementation Workflow describes the development pipeline: research, planning, TDD, code review, and then committing to git.

## Feature Implementation Workflow

0. **Research & Reuse** _(mandatory before any new implementation)_
   - **GitHub code search first:** Run `gh search repos` and `gh search code` to find existing implementations, templates, and patterns before writing anything new.
   - **Library docs second:** Use Context7 or primary vendor docs to confirm API behavior, package usage, and version-specific details before implementing.
   - **Exa only when the first two are insufficient:** Use Exa for broader web research or discovery after GitHub search and primary docs.
   - **Check package registries:** Search npm, PyPI, crates.io, and other registries before writing utility code. Prefer battle-tested libraries over hand-rolled solutions.
   - **Search for adaptable implementations:** Look for open-source projects that solve 80%+ of the problem and can be forked, ported, or wrapped.
   - Prefer adopting or porting a proven approach over writing net-new code when it meets the requirement.

1. **Plan First**
   - Plan before coding. In a claude-projects workspace this is the
     `grill-with-docs → to-prd → to-issues` arc (routed by `/next`); elsewhere, any
     explicit planning step. (There is no standalone `planner` agent in this config.)
   - Produce a spec (PRD/plan) before implementation; identify dependencies and risks
   - Break the work into vertical slices / phases

2. **TDD Approach**
   - Red-green-refactor, one behavior at a time — see [testing.md](./testing.md)
   - In a claude-projects workspace the `tdd` skill / `tdd-implementer` sub-agent runs this
   - Test behavior through public interfaces; coverage is a guide, not a gate

3. **Independent Review**
   - Get a review from something that didn't write the code. In a claude-projects
     workspace that's the post-build `implementation-validator` (acceptance) and the
     `security-reviewer` at the PR gate; ad-hoc, the `code-reviewer` agent.
   - Address CRITICAL and HIGH issues (a CRITICAL blocks); fix MEDIUM when possible

4. **Commit & Push**
   - Detailed commit messages
   - Follow conventional commits format
   - See [git-workflow.md](./git-workflow.md) for commit message format and PR process

5. **Pre-Review Checks**
   - Verify all automated checks (CI/CD) are passing
   - Resolve any merge conflicts
   - Ensure branch is up to date with target branch
   - Only request review after these checks pass
