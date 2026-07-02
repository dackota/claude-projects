# Code Review Standards

## When to Review

**Mandatory triggers:** after writing/modifying code, before commits to shared branches, security-sensitive changes (auth, payments, user data), architectural changes, before merging PRs.

**Pre-review:** CI passing, conflicts resolved, branch up to date.

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | Security vulnerability or data loss risk | **BLOCK** — must fix before merge |
| HIGH | Bug or significant quality issue | **WARN** — should fix before merge |
| MEDIUM | Maintainability concern | **INFO** — consider fixing |
| LOW | Style or minor suggestion | **NOTE** — optional |

## Approval Criteria

- **Approve**: no CRITICAL or HIGH issues
- **Warning**: only HIGH issues (merge with caution)
- **Block**: any CRITICAL issue found

## Agents

- **code-reviewer** — quality, patterns, best practices
- **security-reviewer** — OWASP Top 10, secrets, injection
