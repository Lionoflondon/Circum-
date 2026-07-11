# Circum Canonical Application Registry

**Status:** canonical developer reference
**Scope:** application identity, routes, build outputs, and Firebase Hosting
**Evidence source:** repository configuration and source code only. This document
does not claim the live state of a Firebase site unless that state is represented
in this repository.

## Read This Before Opening Or Deploying An App

| You need | Canonical application | Repository | Do not use |
| --- | --- | --- | --- |
| Sender, Gifts, Health+, Business, or public web | **Circum Sender / Public App** | `github-sync/Circum-` | `Circum-Rider` for sender work |
| Current Rider product | **Circum Rider App (Canonical)** | `github-sync/Circum-Rider` | the public redirect host as a Rider portal |
| Internal operations | **Circum Admin Portal** | `github-sync/Circum-` | public Hosting targets |
| Marketing/public entry | **Circum Marketing Website** | `github-sync/Circum-` | Admin Hosting |

## Canonical Application Map

### Circum Sender / Public App (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Sender product plus public marketing, Gifts, and Health+ and Business entry points. Rider URLs redirect to the dedicated Rider app. |
| Repository / directory | `github-sync/Circum-` |
| Entry point | `lib/main.dart` — web runs `WebSenderApp`; native runs `App`. |
| Web router | `lib/web_sender_app.dart`, `resolveCircumRoute(Uri.base)`. |
| Native router | `lib/app.dart`, `MaterialApp` with the session gate as `home`; named routes are `/sender/mobile` and `/rider/jobs`. |
| Platforms | Web, iOS, Android, macOS, Linux, Windows. |
| Firebase project | `circum-2797c`. |
| Hosting targets | `hosting:public` -> `circum-2797c`; `hosting:sender` -> `circum-app-2797c`. |
| Build / deploy | Public: `scripts/deploy_main_web.sh` builds `build/web_main` and deploys `hosting:public`. Sender app: `scripts/deploy_sender_app.sh` builds `build/web_sender` and deploys `hosting:sender`. |
| Repository deployment status | Active: these targets are isolated in checked-in deployment scripts. |

Public URLs represented by Hosting configuration:

- `https://circum-2797c.web.app`
- `https://circum-app-2797c.web.app`
- Custom public URL documented in this repository: `https://circumuk.com`

The native main-repository route `/rider/jobs` renders `RiderHomeScreen`, but
the native application starts at `_SessionGate`. Treat it as a shared
Rider-jobs compatibility route inside the Sender/Public repository, not as the
dedicated Rider app entry point.

#### Sender/Public route group

| Route / entry | Renderer | Classification |
| --- | --- | --- |
| `/` | `CircumPublicAppRoot` | **Canonical public and marketing entry** |
| `/gifts`, `/terms`, `/privacy`, `/vanguard`, `/business` | `CircumPublicAppRoot` public route variants | **Canonical public routes** |
| `https://circum-app-2797c.web.app/` | `CircumSenderAppRoot` with `useSenderMobileApp: true` | **Canonical hosted Sender mobile app entry** |
| `?app=sender` | `CircumSenderAppRoot` with `useSenderMobileApp: routeDeliveryId == null` | **Sender browser compatibility entry; mobile app when no delivery id is supplied** |
| `?app=health`, `?app=business`, `?app=profile` | `CircumSenderAppRoot` | **Sender product entry points** |
| `/story/**` | Cloud Function `giftStoryLanding` | **Secure Gift Story landing route** |
| `/rider/jobs` (native named route only) | `RiderHomeScreen` | **Shared compatibility route; not the dedicated Rider App entry point** |

### Circum Rider App (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Rider enrolment, sign-in, resumable onboarding, jobs, earnings, chat, and Rider operations. |
| Repository / directory | `github-sync/Circum-Rider` |
| Entry point | `lib/main.dart` -> `CircumRider` -> `App` session gate. |
| Router | `lib/app.dart` session gate; `AppNavView` after approved authentication. |
| Public entry | `/rider`; `?app=rider`; `?app=driver`; `?app=earn`; `?app=circum-order` redirect here from the Sender/Public host. |
| Portal renderer | `CircumRider`; no main-repository Rider portal is production-routed. |
| Platforms | Web, iOS, Android, macOS, Linux, Windows. |
| Firebase project | `circum-2797c`. |
| Hosting configuration | Firebase site `circum-rider-2797c`, built from `build/web`. |
| Build / deploy | `flutter build web --release --no-wasm-dry-run` then `firebase deploy --only hosting`. |
| Repository deployment status | Active: dedicated Rider Hosting deployment. |

#### Why this is the canonical Rider application

The current Rider product is implemented in `Circum-Rider`, which uses the
shared Firebase project, Rider documents, delivery engine, earnings, payouts,
notifications, and communications backend. The public Sender/Public host only
redirects Rider URLs to this application and never renders a Rider portal.

### Rider Architecture Preview (Unrouted Internal Development Surface)

| Field | Value |
| --- | --- |
| Repository / renderer | `github-sync/Circum-`, `lib/web_sender_app.dart`, `_RiderArchitecturePreviewApp`. |
| Direct routes | None. |
| Evidence | `CircumRiderAppRoot` retains `_RiderArchitecturePreviewApp` only behind `useRiderPreview`; production route resolution no longer sets that flag for any Rider URL. |
| Classification | **Unrouted internal development surface. Not a Rider application or production URL.** |

**Conclusion for `https://circum-app-2797c.web.app/rider`:** it is a
**canonical public entry redirect**, not a Rider portal. It redirects to
`https://circum-rider-2797c.web.app`, the canonical Circum Rider App.

### Circum Admin Portal (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Internal operations and administration. |
| Repository / directory | `github-sync/Circum-` |
| Entry point | `lib/main.dart` web -> `WebSenderApp`; `CircumAdminAppRoot` in `lib/web_sender_app.dart`. |
| Router | `resolveCircumRoute` selects the admin surface for the admin Hosting build, or `/admin`. |
| Hosting target | `hosting:admin` -> `circum-admin-2797c`. |
| Build / deploy | `scripts/deploy_admin_web.sh`, which builds with `--dart-define=CIRCUM_ADMIN_HOSTING=true` into `build/web_admin`. |
| URLs documented in repository | `https://circum-admin-2797c.web.app`, `https://admin.circumuk.com`. |
| Repository deployment status | Active: dedicated target and deploy script. |

### Circum Marketing Website (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Public Circum marketing and public entry experience. |
| Repository / entry | `github-sync/Circum-`, `lib/web_sender_app.dart`, `CircumPublicAppRoot`. |
| Router | `/` and the public route group listed above. |
| Hosting | Same `hosting:public` and `hosting:app` build as the Sender/Public App. |
| Classification | **Canonical public website; not a separate Firebase application.** |

### Business Portal (Canonical Sender Module)

| Field | Value |
| --- | --- |
| Purpose | Business workspace inside the Sender/Public product. |
| Repository / entry | `github-sync/Circum-`, `lib/app/business/business_view.dart`. |
| Web entry | `?app=business` selects `CircumSenderAppRoot` with its Business entry. |
| Hosting / deployment | Same public Sender/Public targets and `scripts/deploy_main_web.sh`. |
| Classification | **Canonical Sender module, not a standalone app or Hosting target.** |

## Firebase Hosting And Deployment Map

| Target | Site | Build directory | Canonical owner | Checked-in deploy command |
| --- | --- | --- | --- | --- |
| `hosting:public` | `circum-2797c` | `build/web_main` | Circum Sender/Public + Marketing | `scripts/deploy_main_web.sh` |
| `hosting:sender` | `circum-app-2797c` | `build/web_sender` | Circum Sender App | `scripts/deploy_sender_app.sh` |
| `hosting:admin` | `circum-admin-2797c` | `build/web_admin` | Circum Admin Portal | `scripts/deploy_admin_web.sh` |
| Rider Hosting | `circum-rider-2797c` | `build/web` | Circum Rider App (`Circum-Rider`) | `flutter build web --release --no-wasm-dry-run` then `firebase deploy --only hosting` |

There is no combined main-repository Hosting deployment script. Admin and
public releases must use their separate protected commands. The canonical
Rider web route is part of the public build; it does not deploy the legacy
Rider Hosting site.

## Workspace Copies And Non-Product Artifacts

| Path | Classification | Evidence |
| --- | --- | --- |
| `Circum--main` | **Unversioned workspace copy; not a canonical checkout** | No `.git` directory; duplicates a Circum app configuration. |
| `Circum-Rider-main` | **Unversioned workspace copy; not a canonical checkout** | No `.git` directory; duplicates a Rider configuration. |
| `circum-4-reference` | **Reference / AI Studio sample** | README labels it an AI Studio app and requires `GEMINI_API_KEY`; it is not a Circum Firebase app. |
| Flutter SDK, Node runtime, JDK, Android SDK directories | **Development tooling** | SDK/runtime layout, not product applications. |

## Permanent Naming Rules

1. Refer to `github-sync/Circum-` web public targets as **Circum Sender / Public App**, never simply “the app”.
2. Refer to `github-sync/Circum-Rider` as **Circum Rider App (Canonical)**.
3. Refer to `/rider` on the Sender/Public host as a **canonical Rider entry redirect**, never a Rider portal.
4. Refer to `_RiderArchitecturePreviewApp` and `_RiderEnrollmentPortal` as non-production legacy implementation surfaces. Do not create a public route to either.
5. Refer to `hosting:admin` as **Circum Admin Portal** only.
6. Refer to Business as a **Sender module**, never a standalone deployment target.
7. Before adding an application route or deploy script, update this registry in the same change.

## Current Corrections Recommended

1. **Use `circum-rider-2797c.web.app` for the current Rider web product.** Public Rider URLs redirect there.
2. **Use `github-sync/Circum-Rider` for current Rider product work.**
3. Keep `_RiderArchitecturePreviewApp` and `_RiderEnrollmentPortal` unrouted or remove them only in a dedicated cleanup task.
4. Update legacy deployment prose that still calls the public target `main`; the checked-in Firebase configuration uses `public` and `app`.

## Preserved Architecture

This registry documents existing ownership only. It does not rename routes,
move applications, alter Firebase Hosting, or change runtime behaviour.
