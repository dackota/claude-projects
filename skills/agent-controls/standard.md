# Agent-controls standard

When an agent sits between a human and a system, someone has to decide what it may
read, what it may change, who reviews its output, and how the team recovers when it
is wrong. This standard names those controls. It is the *operating model around the
agent* — boundaries, checks, approvals, recovery — not the agent's cleverness.

The bar is language- and framework-agnostic: it describes controls, not code.

## The operating contract (per agent)

Every agent carries an **operating contract** — a declared, machine-readable brief
that reads like a contract, not prose buried in a system prompt. Seven fields, and
an agent with a gap in any of them stays in **advisory (read-only) mode** until the
gap is closed:

| Field | What it declares |
|-------|------------------|
| `actor` | Who is acting — the agent's identity. |
| `permitted-evidence` | The context it may read: which diffs, files, logs, tickets, runbooks. An allowlist, not "the whole repo." |
| `blocked-actions` | What it must never do — the actions outside its remit (modify files, mutate git, push, deploy, sign). |
| `tool-scope` | `read-only` \| `write` \| `deploy` — the coarse capability tier. Read-only *inspection* is separated from *write*. |
| `approval-rule` | Which actions need a **named human** before execution (`none` for advisory/review-only agents). |
| `required-check` | The check or evidence that must pass before its output is trusted (a verdict format, a test, an independent review). |
| `fallback` | What happens when it cannot prove its result — default to flagging/blocking, never to silently proceeding. |

## The seven control dimensions

The contract above is enforced by attending to seven dimensions. Each has a bar; a
request-serving agent that violates a **BLOCKER**-level bar is not production-ready.

1. **Context rules** — the agent reads only its `permitted-evidence`. Hand it a diff
   *range* it fetches itself, not pasted file contents; scope its repos/logs/tickets.
2. **Tool boundaries** — read-only inspection is a different tier from write/deploy.
   An agent's granted tools must not exceed its declared `tool-scope`. A review-only
   agent must not hold `Write`/`Edit`; where it needs `Bash` for inspection
   (`git diff`, running tests), `blocked-actions` must forbid mutating commands.
   **BLOCKER**: granted tools exceed the declared scope.
3. **Approval gates** — actions the `approval-rule` names require a **named human**
   before execution; the approver is recorded (see audit trails). **BLOCKER**: an
   irreversible action executes with no named approver.
4. **Verification paths** — high-risk output is proven by tests, simulations, static
   checks, or an **independent** reviewer (one that never saw the implementation)
   before it is trusted. **BLOCKER**: a high-risk change ships with no check.
5. **Audit trails** — record each run: inputs, the agent, the verdict, approvals,
   failures, and rework. The record is durable, not just in-session. **BLOCKER**: a
   gated action leaves no trace of who approved it or what the verdict was.
6. **Secret handling** — credentials, wallets, API keys, and production config stay
   out of prompts and context. Prefer passing references the agent resolves over
   pasting values. **BLOCKER**: a secret is embedded in an agent's prompt/context.
7. **Recovery / rollback** — before an action that is hard to reverse, the fallback
   and rollback path are known. **BLOCKER**: an irreversible action has no recovery
   plan.

## Reversibility is the dial

Delegation is cheap when the task is **reversible** and local. It gets serious the
moment the agent can touch **money, production, availability, or security posture**.
Scale the controls to the blast radius:

- **Reversible / local** → advisory + write is fine autonomously; a check still runs.
- **Irreversible / high blast radius** → a named human approves before execution, the
  agent works read-only until that approval, and a rollback path exists.

## Production-readiness checklist

Before an agent is trusted with write or execute access, all seven must be answered
concretely (not "TBD"):

- [ ] **Access** — which context/systems it can reach (`permitted-evidence`).
- [ ] **Tool scope** — read-only vs write vs deploy, matching granted tools.
- [ ] **Verification** — the check that must pass before output is trusted.
- [ ] **Approval** — which actions need a named human, and who.
- [ ] **Logging** — what each run records, and where.
- [ ] **Rollback** — the recovery path when it is wrong.
- [ ] **Owner** — the named human accountable for the agent.

If the brief cannot answer these, the agent stays in **advisory mode**.

## Severity (for a reviewer applying this standard)

| Severity | Meaning |
|----------|---------|
| BLOCKER | A control dimension's BLOCKER bar is violated (tools exceed scope, unapproved irreversible action, secret in prompt, no recovery for an irreversible change) — blocks. |
| HIGH | A named control is present but weak (approval rule vague, verification not independent). |
| MEDIUM | A hardening gap (contract field underspecified, audit record thin). |
| LOW | Polish (wording, redundant evidence in the allowlist). |
