---
title: claude-projects
created: 2026-05-13
---

# claude-projects

## Goals

Provide a CLI (`proj`) and embedded conventions that scaffold Claude Code project workspaces — directories with a living current-state surface (`STATUS.md`), an append-only event log (`journal.yaml`), lifecycle-frontmatted docs, and two project skills (`/sync-status`, `/journal`) that keep context current across sessions.

## Context

Claude Code sessions are ephemeral. Without a synthesized current-state surface, each new session pays a re-orientation tax — reading stale plans, superseded decisions, and completed work mixed with active work. This repo defines the structure and tooling to eliminate that tax: every scaffolded workspace has a dense, link-heavy `STATUS.md` that Claude reads first, a `journal.yaml` that captures significant events as they happen, and lifecycle frontmatter on every doc that signals whether it is still load-bearing.
