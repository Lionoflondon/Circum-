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
- Validation and builds run inside the temporary worktree.
- Only one hosting target is deployed per command.
- The temporary worktree is removed after the deployment exits.

## Surface Targets

| Surface | Entrypoint | Output | Hosting target |
| --- | --- | --- | --- |
| Sender App Web | `lib/app/sender_mobile/sender_mobile_preview.dart` | `build/sender_app_web` | `hosting:app` |
| Public Web | `lib/main_public_web.dart` | `build/public_web` | `hosting:public` |
| Admin Web | `lib/main.dart` with `CIRCUM_ADMIN_HOSTING=true` | `build/web_admin` | `hosting:admin` |

## Product Web App Check

Each Circum web surface uses its own Firebase App Check reCAPTCHA Enterprise
site key. Provide the relevant key at build time only:

```bash
PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<website-site-key> scripts/deploy_isolated.sh website --branch origin/main
CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<sender-site-key> scripts/deploy_sender_app_web.sh
```

The build scripts pass it through Flutter as:

```bash
--dart-define=PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<website-site-key>
--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<sender-site-key>
```

Do not hardcode keys, log them, or share one product's App Check key with
another product.

## Failure Conditions

Deployment fails if the temporary workspace:

- is dirty after checkout;
- receives unapproved modified files;
- references forbidden cross-surface markers from the entrypoint;
- changes outside generated build artifacts during validation/build;
- fails `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test`;
- fails web artifact identity validation;
- targets more than one hosting surface.

The old broad multi-target web deployment path is intentionally removed.
