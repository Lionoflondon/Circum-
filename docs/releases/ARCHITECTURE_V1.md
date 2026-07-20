# Architecture V1

Date: 2026-07-18  
Architecture tag: `architecture-v1`  
Status: Frozen

## Reference

This release note is governed by [Permanent Architecture Charter](../PERMANENT_ARCHITECTURE_CHARTER.md).

## Protected Products

- Circum Website
- Sender App
- Rider App
- Admin
- Backend

## Backend Sharing Policy

The Backend is intentionally shared and remains the platform authority for:

- Cloud Functions
- Firestore Rules
- Storage Rules
- Canonical business logic
- Authentication authority
- Payments
- IRIS
- Delivery lifecycle
- Notification authority

## Product Ownership Rules

- Website, Sender App, Rider App, and Admin must not share product source.
- Products must not import another product's UI, routing, navigation, controllers, blocs, providers, repositories, models, services, helpers, or utilities.
- Repository engineering tooling may be shared.
- Shared branding assets are allowed where intentional and where they contain no product logic.

## Certification Results

- Shared backend: allowed.
- Shared repository tooling: allowed.
- Shared branding assets: allowed where intentional.
- Shared product source: 0.
- Cross-product imports: 0.
- Transitive dependency intersections: 0.
- Product ownership violations: 0.

## Protected Architecture Files

- `docs/PERMANENT_ARCHITECTURE_CHARTER.md`
- `deploy-manifest.json`
- `scripts/deploy_guard.js`
- `scripts/deploy_guard.self_test.js`
- `scripts/absolute_product_ownership.js`

Future changes to protected architecture files require explicit architecture review, minimum two approvals, and a fresh certification run.
