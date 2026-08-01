# Architecture Review

Use this checklist for any pull request that touches protected architecture files:

- `docs/PERMANENT_ARCHITECTURE_CHARTER.md`
- `deploy-manifest.json`
- `scripts/deploy_guard.js`
- `scripts/deploy_guard.self_test.js`
- `scripts/absolute_product_ownership.js`
- `scripts/backend_authority_guard.js`

## Required Answers

1. Why is architecture changing?

2. Which product boundary changes?

3. Why can't this be implemented without architecture changes?

4. What validator was updated?

5. Which new certification was run?

6. Does the change preserve backend authority for operational state?

## Approval Rule

Architecture changes require minimum two approvals. The author cannot approve their own architecture change.
