# Isolated Deployment Pipeline

Production deployments must never run from a developer's active working tree.

The only approved hosting deployment path is:

```bash
scripts/deploy_isolated.sh <sender|public|admin> --branch origin/main
```

Surface wrappers are also allowed because they call the isolated runner:

```bash
scripts/deploy_sender_app_web.sh --branch origin/main
scripts/deploy_public_web.sh --branch origin/main
scripts/deploy_admin_web.sh --branch origin/main
```

## Rules

- The active working tree may be dirty, but it is never deployed.
- A fresh temporary git worktree is created for every deployment.
- The deployment worktree starts from the requested ref and must be clean.
- Only explicitly approved commits or patches may be applied.
- Approved changes are checked against the requested surface scope.
- Approved changes are checked by `scripts/validate_product_boundary.js`.
- Validation and builds run inside the temporary worktree.
- Only one hosting target is deployed per command.
- The temporary worktree is removed after the deployment exits.

## Surface Targets

| Surface | Entrypoint | Output | Hosting target |
| --- | --- | --- | --- |
| Sender App Web | `lib/main_sender_web.dart` | `build/sender_app_web` | `hosting:app` |
| Public Web | `lib/main_public_web.dart` | `build/public_web` | `hosting:public` |
| Admin Web | `lib/main.dart` with `CIRCUM_ADMIN_HOSTING=true` | `build/web_admin` | `hosting:admin` |

## Shared Web App Check

All Circum web surfaces use one Firebase App Check reCAPTCHA Enterprise site
key. Provide it at build time only:

```bash
CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<site-key> scripts/deploy_isolated.sh <sender|public|admin> --branch origin/main
```

The build scripts pass it through Flutter as:

```bash
--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<site-key>
```

Do not hardcode the key, log it, or reintroduce per-surface web App Check
environment variables.

## Failure Conditions

Deployment fails if the temporary workspace:

- is dirty after checkout;
- receives unapproved modified files;
- fails the product-boundary validator;
- references forbidden cross-surface markers from the entrypoint;
- changes outside generated build artifacts during validation/build;
- fails `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test`;
- fails web artifact identity validation;
- targets more than one hosting surface.

The old broad multi-target web deployment path is intentionally removed.
