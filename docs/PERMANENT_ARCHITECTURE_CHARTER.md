# Permanent Architecture Charter

This document is the permanent architecture law for Circum.

Circum is one platform composed of independent products. Product source is isolated. The platform backend is intentionally shared.

## Canonical Products

1. Sender Mobile App
   - Repository: Circum-
   - Entrypoint: `lib/main.dart`
   - Surface identity: `circum-sender-mobile`
   - Build/deployment: native Android/iOS only
   - Must not share startup, routing, bootstrap, or hosting with Sender Web, Rider Mobile, Rider Web, Website, or Admin.

2. Sender Web
   - Repository: Circum-
   - Entrypoint: `lib/app/sender_mobile/sender_mobile_preview.dart`
   - Hosting target: `hosting:app`
   - Build directory: `build/sender_app_web`
   - Surface identity: `circum-sender-web`
   - Must not share startup, router, Flutter bootstrap, hosting target, or build directory with Sender Mobile, Rider Mobile, Rider Web, Website, or Admin.

3. Rider Mobile App
   - Repository: Circum-Rider
   - Entrypoint: `lib/main.dart`
   - Surface identity: `circum-rider-mobile`
   - Build/deployment: native Android/iOS only
   - Must not share startup, routing, bootstrap, or hosting with Rider Web, Sender Mobile, Sender Web, Website, or Admin.

4. Rider Web
   - Repository: Circum-Rider
   - Entrypoint: `lib/main_rider_web.dart`
   - Hosting site: `circum-rider-2797c`
   - Build directory: `build/web`
   - Surface identity: `circum-rider-web`
   - Must not share startup, router, Flutter bootstrap, hosting target, or build directory with Rider Mobile, Sender Mobile, Sender Web, Website, or Admin.

5. Circum Website
   - Repository: Circum-
   - Entrypoint: `lib/main_public_web.dart`
   - Hosting target: `hosting:public`
   - Build directory: `build/public_web`
   - Surface identity: `circum-public-web`
   - May link to product entrypoints, but does not own Sender Web or Rider Web startup/runtime.

6. Admin
   - Admin UI
   - Review queues
   - Admin routing
   - Admin deployment

7. Backend
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
- Shared startup entrypoints.
- Shared Flutter web bootstrap files.
- Shared hosting targets.
- Shared build directories.
- Shared product routers.
- Shared widgets, screens, routes, navigation, controllers, blocs, providers, repositories, models, services, helpers, or utilities between products.
- Product configuration imported by another product.

## Entrypoint Matrix

| Product | Entrypoint | Hosting/build target | Identity |
| --- | --- | --- | --- |
| Sender Mobile App | `lib/main.dart` | Native Android/iOS | `circum-sender-mobile` |
| Sender Web | `lib/app/sender_mobile/sender_mobile_preview.dart` | `hosting:app`, `build/sender_app_web` | `circum-sender-web` |
| Rider Mobile App | `Circum-Rider/lib/main.dart` | Native Android/iOS | `circum-rider-mobile` |
| Rider Web | `Circum-Rider/lib/main_rider_web.dart` | `circum-rider-2797c`, `build/web` | `circum-rider-web` |

## Recovery Procedure

1. Identify the affected product.
2. Build only that product from its canonical entrypoint.
3. Verify the generated artifact identity and `gitCommit` metadata.
4. Run product ownership and deployment guards.
5. Deploy only the product's hosting target or native release lane.
6. If any cross-product file changes, stop and split the work before release.

## Certification Standard

Architecture passes only when:

- Shared backend: allowed.
- Shared repository tooling: allowed.
- Shared branding assets: allowed where intentional.
- Shared product source: 0.
- Cross-product imports: 0.
- Transitive dependency intersections: 0, excluding backend.
- Product ownership violations: 0.
- Entrypoint overlap: 0.
- Build directory overlap: 0.
- Hosting target overlap: 0.
- Missing artifact metadata: 0.

The backend is one platform. The products are independent. Shared product source code is never permitted.
