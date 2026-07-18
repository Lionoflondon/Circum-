# Permanent Architecture Charter

This document is the permanent architecture law for Circum.

Circum is one platform composed of independent products. Product source is isolated. The platform backend is intentionally shared.

## Products

1. Circum Website
   - Sender Web
   - Rider Web
   - Website shell
   - Website routing
   - Website authentication
   - Website assets
   - Website deployment

2. Sender App
   - Sender mobile
   - Wallet
   - Booking
   - Tracking
   - Notifications
   - Profile
   - Payments
   - Mobile navigation

3. Rider App
   - Rider mobile
   - Jobs
   - Tracking
   - GPS
   - Earnings
   - Documents
   - Vehicles
   - Rider navigation

4. Admin
   - Admin UI
   - Review queues
   - Admin routing
   - Admin deployment

5. Backend
   - Cloud Functions
   - Firestore Rules
   - Storage Rules
   - Canonical business logic
   - Authentication authority
   - Payments
   - IRIS
   - Delivery lifecycle
   - Notification authority

## Sharing Rules

Allowed:

- Shared backend authority.
- Shared repository engineering tooling.
- Shared linting, formatting, and CI helpers.
- Shared ownership validators and deployment guards.
- Shared branding assets where duplication adds no architectural value.

Forbidden:

- Shared product source between Website, Sender App, Rider App, and Admin.
- Cross-product imports.
- Shared widgets, screens, routes, navigation, controllers, blocs, providers, repositories, models, services, helpers, or utilities between products.
- Product configuration imported by another product.

## Certification Standard

Architecture passes only when:

- Shared backend: allowed.
- Shared repository tooling: allowed.
- Shared branding assets: allowed where intentional.
- Shared product source: 0.
- Cross-product imports: 0.
- Transitive dependency intersections: 0, excluding backend.
- Product ownership violations: 0.

The backend is one platform. The products are independent. Shared product source code is never permitted.
