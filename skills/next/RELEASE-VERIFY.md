# Release-verify — Land-phase live verification

`/next`'s **Land** phase normally just opens the PR. When the task that just landed is
a **release/deploy task**, Land additionally runs **release-verify**: it drives the
shipped release against its **live deployment** (read-only) to catch the failure class
the read-only and sandbox gates can't — a change that passed every pre-merge gate but
misbehaves once actually deployed. This file is the single normative home for that
step; the router points here and is read only when Land handles a release task.

## When it fires — release-task detection

Run release-verify when the completed task is a release/deploy task, detected in this
order:

1. **Explicit (preferred):** the task carries `release: true` in `project.yaml`
   (deterministic — "explicit over inferred", the same philosophy as
   `validation.run_cmd`). In Jira mode, a `release` label.
2. **Backstop:** the task's diff bumps a **deploy tag or version** (a chart
   `version`/`appVersion`, an image tag, a `VERSION` file, a release manifest) even
   when it wasn't flagged — this catches an untyped release.

Neither → normal Land (just open the PR); do not run release-verify.

## What it does

1. **Derive the checklist.** Collect the PRD user stories covered by the slices
   **shipped since the last release** (the tasks marked `done` since the previous
   release task / tag). Turn each into a concrete, drivable behavior — the endpoints,
   flows, or rollouts to confirm against the live deployment.
2. **Spawn `runtime-validator` in release mode** (Agent tool,
   `subagent_type: runtime-validator`) on a fresh context, giving it the checklist and
   **read-only access to the live deployment** (the `kubectl` context / port-forward /
   base URL). It drives each item read-only and returns `VERDICT: PASS | BLOCK | SKIP`
   (see the agent's *Release mode*). It never mutates the cluster or deploys.
3. **Act on the verdict:**
   - **PASS** → the release behaves live. Record it and finish Land.
   - **BLOCK** → a shipped behavior is broken on the live deployment. Surface it
     loudly with the evidence — this is a post-deploy regression to fix forward. It is
     past the pre-merge barrier, so there is no `tdd` loop-back here; the fix is a new
     slice. Do **not** silently pass.
   - **SKIP** → the agent could not reach the deployment (no context/creds/network).
     **Fall back to HITL:** hand the derived checklist to the user to run manually and
     record their result. A SKIP never stalls the release.
4. **Record it.** Write the verdict + evidence to a release **validation record**
   (`docs/validations/release-<tag-or-date>.md`, lifecycle frontmatter per `docs/README.md`) and
   append a `run` journal entry (`agent: runtime-validator`, the release ref as the
   task) so Status synthesis **Pipeline health** rolls it up. This is the durable
   answer to "how was this release verified?"

## Boundaries

- **Read-only against live infra.** Release-verify observes; it never deploys, scales,
  edits, or otherwise mutates the live/shared environment. Verifying a release must not
  change it.
- **Not the pre-merge barrier.** The post-build barrier (BARRIER.md) still gates every
  slice before `done`. Release-verify is the *additional* live check at Land for
  release tasks — it backstops the escapes only observable against a real deployment
  (the glob-fan-out / runtime-config class).
