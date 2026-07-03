# The Land-phase integration review

This is the **single normative home** for `/next`'s **assembled-branch integration
review** — the whole-branch counterpart of the per-slice post-build barrier
([BARRIER.md](./BARRIER.md)). The `next` router core points here rather than restating
the protocol — change it here and nowhere else.

The barrier reviews each slice's diff **in isolation, at build time**. Nothing in that
loop ever looks at the **assembled** branch — the set of slices composing a feature,
seen together. This review fills that gap. It belongs to the **Land phase**: it runs on
the branch that will become the PR, and it is the **correctness/consistency sibling of
the PR security review** — both are whole-`origin/main...HEAD` reviews at the PR
boundary.

```
post-build barrier (per slice, build-time) :  acceptance  +  correctness  [+ runtime + obs]
PR gate            (whole branch, land-time):  security    +  integration
```

## When it runs — and when it SKIPs

Run the integration review at Land, **before opening the PR**, when the PR **assembles
more than one slice** — a stack of dependent tasks, or a feature whose last slice just
completed. Spawn it **in the same message as the security review** (both take the same
`origin/main...HEAD` diff at the same HEAD, so they run concurrently — no added
wall-clock).

**SKIP it — and record why — when the PR is a single slice.** The post-build barrier
already reviewed that entire `base...HEAD` diff; there is no *assembly* to review, so
there are no seams a whole-branch pass could find that the per-slice pass couldn't.

> **Trigger detection is the orchestrator's job, deliberately.** Like
> [RELEASE-VERIFY.md](./RELEASE-VERIFY.md) (which the orchestrator triggers for
> release/deploy tasks), *whether* an integration review is needed is a Land-phase
> judgment the orchestrator makes from the task graph — "does this PR's
> `origin/main...HEAD` span more than one `done` slice / is it a stack?" — not something
> the PR-gate hook forces, because a shell hook cannot robustly tell a multi-slice
> assembly from a single slice that happened to land in several commits. The hook's role
> is to **honor a recorded verdict** (below); the orchestrator's role is to **run the
> review when the trigger holds**. Skipping it silently on a genuine multi-slice PR is a
> process miss, the same class as skipping release-verify — surface it, don't hide it.

## Run the review

Spawn the `integration-reviewer` (Agent tool, `subagent_type: integration-reviewer`) on
a **fresh context**. Give it only:

- the **assembled diff range** (`origin/main...HEAD`) + changed files,
- the **PRD / epic story** (the integrated contract), and
- the **list of slices** composing the branch and each slice's acceptance criteria.

**Not** the implementation conversation — independence is the point (an `agent-controls`
control; pass the diff **range**, not pasted contents, so the agent fetches it itself and
secrets stay out of its prompt). It reviews the **seams between slices** — cross-slice
consistency/parity, broken integrated flows, half-migrations, and emergent design — and
explicitly does **not** re-grade per-slice acceptance, per-diff correctness, or security
(those are already owned). It returns `VERDICT: PASS | BLOCK` (`BLOCK` iff `CRITICAL >
0`, a cross-slice defect).

## Record the verdict (the Audit step)

Two writes, exactly as the barrier and security gates do (the agent is read-only, so
**you** write both):

1. A **`run` journal entry** (`type: run`, `agent: integration-reviewer`, `task`,
   `verdict`, `critical`/`high`, `rework`, `approver`) — `run-check.sh` records that the
   gate ran and the Stop hook enforces the entry, same as every other gate.
2. The **SHA-keyed verdict file**, as a **separate write before you open the PR** (a
   verdict chained into the same command as `gh pr create` may not have landed when the
   hook fires — the write-then-act rule). Single line, mirroring the security verdict:

   ```
   PASS
   ```

   at `"$(git rev-parse --absolute-git-dir)"/integration-review/"$(git rev-parse HEAD)"`.

Add an **Integration** section to the slice/epic validation record with the reviewer's
evidence.

## Enforcement — the verdict is wired into the PR gate

Both PR paths **honor a recorded integration verdict** for HEAD — a recorded `BLOCK`
cannot be routed around:

- **`barrier-gate.sh`** (raw `gh pr create`) checks `integration-review/<sha>` **before**
  the barrier verdict, so a recorded integration BLOCK blocks the PR even when acceptance
  + correctness are PASS.
- **`scripts/repo.sh pr`** (the pipeline path — invokes `gh` internally, so the hook
  can't see it) self-enforces the same recorded verdict.

Both **honor if present**; neither **forces** the review (see the trigger note above —
that's the orchestrator's call). So the failure mode a hook can prevent — *routing around
a BLOCK by switching PR paths* — is prevented; the failure mode it can't robustly detect
— *a genuine multi-slice PR with no review at all* — stays the orchestrator's
responsibility, flagged not hidden.

## Advance or loop back

- **PASS** → record the verdict and open the PR (`scripts/repo.sh pr <task>`), where the
  security review runs alongside. The PR carries both whole-branch verdicts (security +
  integration) plus the per-slice barrier verdicts.
- **BLOCK** → the assembly isn't ready. Write a `blocker` journal entry naming the
  diverging slices and the violated invariant, then **spawn a corrective reconciliation
  slice** (`tdd-implementer`, framed as *"reconcile slices X and Y at seam Z"*, with a
  property/invariant test over the shared contract where one fits — `rules/common/testing.md`).
  That corrective slice goes through the normal post-build barrier, then **re-run the
  integration review** on the new `HEAD`. The loop is bounded by the same
  `rework-cap.sh` mechanism the barrier uses — a recurring integration BLOCK signals a
  real design fork, not something another loop will fix; escalate to a human.
