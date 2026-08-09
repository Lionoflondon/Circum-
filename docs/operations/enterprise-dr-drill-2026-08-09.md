# CIRCUM non-production recovery drill - 2026-08-09

Scope: deterministic local and emulator-backed validation only. No production
documents, payments, deliveries, notifications, or deployments were mutated.

| Scenario | Recovery path exercised | Target recovery time | Result |
| --- | --- | --- | --- |
| Failed deployment | Resolve the last certified SHA from the production manifest, redeploy through the guarded release workflow, then run a read-only smoke. | 15 minutes | PASS - rollback authority and guard contract verified. |
| Failed payment finalisation | Preserve the Stripe event/session identity and retry the canonical idempotent finaliser. | 10 minutes | PASS - transient failure propagated and the same event identity succeeded on retry. |
| Failed notification | Retain the canonical notification document and correlation identity, then use the existing retry transition. | 15 minutes | PASS - retrying, sent, and failed audit outcomes verified. |
| Stuck delivery | Detect through the bounded watchdog projection and open one deterministic incident. | 10 minutes detection plus operator response | PASS - stationary accepted delivery produced one stable incident identity. |
| Accidental Admin action | Preserve before/after audit evidence and use a reasoned domain-owned compensating action. | 30 minutes | PASS - recovery reason, before/after state, and recovery timeline are mandatory. |

Automated drill command:

```sh
cd server/functions
node --test enterprise-dr-drill.test.js
```

The drill validates recovery entry points and retry contracts; it does not
authorize destructive rollback automation or direct production data edits.
