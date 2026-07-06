---
name: security-review
description: Security checklist for application code — secrets, input validation, injection, authn/z, XSS, CSRF, rate limiting. Use when adding auth, handling user input or uploads, touching secrets, creating API endpoints, or shipping sensitive features.
origin: ECC
---

# Security review

An OWASP-aligned checklist for **application code**. Each dimension is a set of
**checkable** items — verify every one that applies to the change; a single missed
class can compromise the system. This is the reference the `security-reviewer` agent
and the `pr-security-review` gate consult for code; `cloud-infra-security` covers
infrastructure.

Every item is a judgement against the diff, not a lint rule — **skip anything a
linter, SAST tool, or dependency scanner already enforces**, and cite `path:line`
for each finding.

## 1. Secrets

- No hardcoded keys, tokens, passwords, or connection strings — all from env or a secrets manager.
- Required secrets validated at startup (fail fast when missing).
- Secret files (`.env*`) gitignored; no secrets in git history or committed config.
- No secret ever reaches a log line or an error response.

## 2. Input validation

- Every input crossing a trust boundary validated against a schema before use — allowlist, not blocklist.
- File uploads bounded by size, MIME type, and extension.
- Validation failures return a safe message; no internal detail leaked.

## 3. Injection

- SQL/NoSQL via parameterized queries or an ORM — never string-concatenated user input.
- OS commands, LDAP, and template rendering never interpolate raw user input.
- Output encoded for its sink (shell, query, HTML) at the point of use.

## 4. Authentication & authorization

- Every sensitive operation checks authorization server-side, on the target object, before acting — never trust a client-supplied role.
- Session tokens in httpOnly + Secure + SameSite cookies, not localStorage.
- Row/tenant isolation enforced at the data layer (e.g. RLS), not just the app.
- Secure session lifecycle: rotation on privilege change, expiry, revocation.

## 5. XSS

- User-provided HTML sanitized against an allowlist; rely on the framework's escaping everywhere else.
- A Content-Security-Policy restricts script/style/connect sources.
- No user input reaches a raw-HTML sink unsanitized.

## 6. CSRF

- State-changing endpoints require a CSRF token or equivalent (double-submit / origin check).
- SameSite=Strict (or Lax with care) on session cookies.

## 7. Rate limiting & abuse

- Rate limits on every endpoint; stricter on auth, search, and other expensive paths.
- Limits keyed by both user and IP; backoff or lockout on repeated auth failure.

## 8. Sensitive-data exposure

- Client errors are generic; detail and stack traces stay in server logs.
- No passwords, tokens, PII, or full card/account numbers in logs.
- Sensitive data encrypted in transit (HTTPS enforced) and at rest.
- Responses return only the fields the caller needs — no leaking internal columns.

## 9. Signed / financial operations (if applicable)

- Signatures verified before a request is trusted; no blind signing.
- Transaction recipient, amount, and balance validated server-side against limits.

## 10. Dependencies & supply chain

- Lock file committed; CI installs from it (`npm ci`, `pip install -r`, …), not a loose resolve.
- No known-vulnerable dependencies (scanner clean); automated update alerts enabled.

## Reporting

Severity **CRITICAL** (exploitable now — injection, auth bypass, exposed secret) →
**HIGH** (likely exploitable) → **MEDIUM** (hardening gap) → **LOW** (defense in
depth). Block on any CRITICAL. Name the class and cite `path:line` for every finding.

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
