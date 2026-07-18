# Circum Product Isolation Boundaries

Every Circum product is released as an independent product surface. A deployment
must fail when the selected surface includes files from another product.

## Product Boundaries

| Product | Primary source boundary | Deployment guard surface |
| --- | --- | --- |
| Sender App | `lib/app/sender_mobile/`, `lib/app/send_package/`, `lib/app/sender_profile/`, Sender-owned delivery/account/support modules | `sender-app` |
| Sender Web | `lib/main_sender_web.dart`, Sender Web build/deploy scripts | `sender-web` |
| Public Website | `lib/main_public_web.dart`, `lib/web_platform_routing.dart`, `lib/web_sender_app.dart` | `public-web` |
| Admin | `lib/main.dart`, `lib/app/admin/` | `admin` |
| Cloud Functions | `server/`, `firestore.rules`, `storage.rules` | `backend` |
| Rider App | Separate `Circum-Rider` repository | guarded by repository separation |
| Rider Web | Separate `Circum-Rider` repository hosting build | guarded by repository separation |

## Shared Modules Remaining

The following modules are intentionally shared inside the Circum repository:

- `lib/app/security/`: App Check startup helpers used by web entrypoints.
- `lib/firebase_options.dart`: Firebase client configuration.
- `pubspec.yaml` and `pubspec.lock`: Flutter package graph for this repository.
- `scripts/`: build, deployment and validation tooling.
- `docs/`: release and product-boundary documentation.

Shared modules are permitted only when the selected deployment guard explicitly
allows them. Sender App deployments intentionally do not allow web entrypoints,
backend code, Firebase rules, mobile platform configuration, or other product
modules.

## Deployment Guard

Use `scripts/validate_product_boundary.js` before deployment:

```bash
node scripts/validate_product_boundary.js --surface=sender-app --base=<base> --head=<head>
```

If a file crosses a product boundary, the validator exits non-zero and prints:

```text
DEPLOYMENT BLOCKED
Cross-application contamination detected.
```

The isolated web deployment pipeline calls this validator before build and
deployment. Future deployment scripts must do the same for their selected
surface.

## Cache Isolation

Web build outputs are physically separated:

- Sender Web: `build/sender_app_web`
- Public Web: `build/public_web`
- Admin: `build/web_admin`

The isolated deployment script removes generated web outputs before each build
and deploys only one Firebase Hosting target per run.
