---
name: cloud-infra-security
description: Security checklist for cloud infrastructure and CI/CD — IAM, secrets, network, logging, CDN/WAF, backups. Use when deploying to cloud, writing IaC, configuring IAM, setting up a CI/CD pipeline, or managing cloud secrets.
origin: ECC
---

# Cloud & infrastructure security

A checklist for cloud infra, IaC, and deployment pipelines. Each dimension is a set
of **checkable** items — verify every one that applies; cloud misconfiguration is the
top breach cause, and one open bucket or wildcard IAM policy exposes everything. This
is the infra companion to `security-review` (application code). The through-line is
**least privilege + defense in depth**.

Judge against the actual config/diff — **skip anything a policy scanner (tfsec,
Checkov, cloud config rules) already enforces** — and cite the resource/file for each
finding.

## 1. IAM & access

- Policies scoped to specific actions and resource ARNs — no `*:*`, no `Resource: "*"`.
- Root/owner account unused for operations; MFA on every privileged account.
- Workloads assume roles (short-lived credentials), never long-lived access keys.
- Unused credentials, roles, and keys removed; access reviewed periodically.

## 2. Secrets

- All secrets in a managed store (Secrets Manager / SSM / Vault) — not env-only, not baked into images/AMIs.
- Automatic rotation for database and service credentials; keys rotated at least quarterly.
- Secret access audit-logged; no secret in Terraform state, plan output, or CI logs.

## 3. Network

- Databases and internal services not publicly reachable — in private subnets.
- Security groups scoped to needed ports and CIDRs — no `0.0.0.0/0` ingress on admin ports (SSH/RDP), no wide port ranges.
- Admin access via VPN/bastion only; VPC flow logs enabled.

## 4. Logging & monitoring

- Audit logging (CloudTrail or equivalent) on across all regions and services.
- Auth failures and privileged/admin actions logged; alerts on anomalies.
- Retention meets compliance (90+ days); logs centralized and tamper-resistant.

## 5. CI/CD pipeline

- Cloud auth via OIDC/federation, not long-lived credentials in CI secrets.
- Pipeline runs secret scanning and dependency/vulnerability audit; images scanned before push.
- Least-privilege job permissions; branch protection, required review, and signed commits enforced.
- Builds reproducible from lock files (`npm ci`, etc.).

## 6. CDN / WAF / edge

- WAF enabled with a managed ruleset (OWASP CRS); rate limiting and bot/DDoS protection on.
- TLS strict (modern minimum version); HSTS and security headers (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy) set at the edge.

## 7. Data protection & recovery

- Encryption at rest and in transit on all data stores.
- Storage buckets private by default; public access blocked at the account level.
- Automated backups with retention meeting RPO; deletion protection or point-in-time recovery on critical stores.
- Recovery tested; RPO/RTO defined; DR runbook documented.

## Reporting

Severity **CRITICAL** (public data store, wildcard IAM, exposed secret, DB open to
the internet) → **HIGH** → **MEDIUM** → **LOW**. Block on any CRITICAL. Name the
misconfiguration and cite the resource/file for every finding.

## Resources

- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [OWASP Cloud Security](https://owasp.org/www-project-cloud-security/)
