# Enterprise hardening evidence - 2026-08

## Security

- Custom Business permissions are allow-listed server-side and scoped to one
  `businessId`; only the canonical Business Owner may mutate templates.
- Customer trust projections require authentication, App Check, and canonical
  delivery ownership. Internal incidents, fraud/risk signals, operational notes,
  and payment-provider identifiers are not projected.
- Business custom-role documents are backend-written. Firestore permits direct
  reads only to the owning Business Owner or CIRCUM Admin.
- Repository scans found no backend secret literal introduced by this release.

## Runtime

Node.js 22 is the supported migration target. New/changed Functions are the
pilot cohort. The focused Functions suite passes under Node 22. Remaining
Node.js 20 Functions require a guarded rolling deployment before the platform
runtime migration is complete.

## Dependencies

`sharp` was directly reachable through proof-of-delivery image processing and
was upgraded to 0.35.3 to close the high-severity libvips advisory. Production
audit after the update reports no critical/high findings. Nine moderate findings
remain in the Firebase/Google dependency chain; automated remediation proposes
incompatible SDK downgrades/major changes, so no blind fix was applied.

## Monitoring and recovery

Existing uptime checks cover Sender, Rider, and Admin Hosting. Existing
Operations Brain monitoring covers critical Function, payment, notification,
and watchdog failures. Recovery procedures are recorded in
`docs/operations/enterprise-recovery-runbook.md`.

## Performance and cost

- Custom roles are capped at 50 per Business and fetched only in Owner team
  administration.
- Customer timelines are fetched on demand and capped at 100 events.
- No new polling, fan-out trigger, dashboard write, or duplicated event store
  was introduced.
- The existing Business operations projection remains bounded and paginated.

## Remaining work

- Complete the rolling Node.js 22 migration for unchanged production Functions.
- Run a restore drill in a non-production project and record recovery time and
  recovery point evidence.
- Continue bundle/startup profiling independently; this release adds no new
  media assets or frontend framework dependency.
