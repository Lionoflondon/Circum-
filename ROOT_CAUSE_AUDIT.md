# Root Cause Audit

Root cause: Circum previously allowed deployment and source boundaries to be inferred from convention rather than enforced by repository structure, product ownership metadata and deployment automation.

Corrective architecture:

- Circum Website owns Sender Web and Rider Web.
- Sender App is independent from Website.
- Rider App remains independent in the Rider repository.
- Admin is independent.
- Backend is independent.
- `deploy-manifest.json` defines product ownership.
- `scripts/deploy_guard.js` blocks cross-product deployment.
- `scripts/deploy_guard.self_test.js` validates the manifest itself.
