# Product Isolation Architecture Prompt

The active Circum product boundaries are:

1. Circum Website: Sender Web and Rider Web.
2. Sender App: independent mobile app.
3. Rider App: independent repository.
4. Admin: independent operations product.
5. Backend: independent Firebase backend.

No deployment may proceed unless the deployment guard and guard self-test pass.
