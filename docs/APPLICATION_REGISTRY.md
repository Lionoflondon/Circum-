# Circum Canonical Application Registry

**Status:** canonical developer reference
**Scope:** application identity, routes, build outputs, and Firebase Hosting
**Evidence source:** repository configuration and source code only. This document
does not claim the live state of a Firebase site unless that state is represented
in this repository.

## Read This Before Opening Or Deploying An App

| You need | Canonical application | Repository | Do not use |
| --- | --- | --- | --- |
| Sender, Gifts, Health+, Business, public Rider enrolment, or public web | **Circum Sender / Public App** | `github-sync/Circum-` | `Circum-Rider` for sender work |
| Current Rider web product | **Circum Rider Web App (Canonical)** | `github-sync/Circum-` | `Circum-Rider`, the legacy client |
| Internal operations | **Circum Admin Portal** | `github-sync/Circum-` | public Hosting targets |
| Marketing/public entry | **Circum Marketing Website** | `github-sync/Circum-` | Admin Hosting |

## Canonical Application Map

### Circum Sender / Public App (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Sender product plus public marketing, Gifts, Health+, Business entry points, and the canonical Rider web application. |
| Repository / directory | `github-sync/Circum-` |
| Entry point | `lib/main.dart` — web runs `WebSenderApp`; native runs `App`. |
| Web router | `lib/web_sender_app.dart`, `resolveCircumRoute(Uri.base)`. |
| Native router | `lib/app.dart`, `MaterialApp` with the session gate as `home`; named routes are `/sender/mobile` and `/rider/jobs`. |
| Platforms | Web, iOS, Android, macOS, Linux, Windows. |
| Firebase project | `circum-2797c`. |
| Hosting targets | `hosting:public` -> `circum-2797c`; `hosting:app` -> `circum-app-2797c`. |
| Build / deploy | `scripts/deploy_main_web.sh` builds `build/web_main` and deploys `hosting:public,hosting:app`. |
| Repository deployment status | Active: these targets are the only public-app targets in the checked-in deployment scripts. |

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
| `?app=sender` | `CircumSenderAppRoot` with `useSenderPreview: routeDeliveryId == null` | **Sender browser entry; preview when no delivery id is supplied** |
| `?app=health`, `?app=business`, `?app=profile` | `CircumSenderAppRoot` | **Sender product entry points** |
| `/story/**` | Cloud Function `giftStoryLanding` | **Secure Gift Story landing route** |
| `/rider/jobs` (native named route only) | `RiderHomeScreen` | **Shared compatibility route; not the dedicated Rider App entry point** |

### Circum Rider Web App (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Rider enrolment, sign-in, account setup, jobs, earnings, chat, and Rider operations. |
| Repository / directory | `github-sync/Circum-` |
| Entry point | `lib/main.dart` web -> `WebSenderApp`; Rider root -> `CircumRiderAppRoot`. |
| Router | `lib/web_sender_app.dart`, `resolveCircumRoute(Uri.base)`. |
| Direct routes | `/rider`; `?app=rider`; `?app=driver`; `?app=earn`; `?app=circum-order`. |
| Portal renderer | `_RiderEnrollmentPortal`. |
| Platforms | Web. |
| Firebase project | `circum-2797c`. |
| Hosting configuration | Public Sender/Public sites `circum-2797c` and `circum-app-2797c`, built from `build/web_main`. |
| Build / deploy | `scripts/deploy_main_web.sh`. |
| Repository deployment status | Active: deployed with the public Sender/Public build. |

#### Why this is the canonical Rider application

The current Rider product is implemented in the active `Circum-` repository as
`_RiderEnrollmentPortal`, shares the current authentication and operations
backend, and is deployed through the active public Hosting pipeline. Direct
Rider URLs now resolve to this portal rather than a preview.

### Rider Architecture Preview (Unrouted Internal Development Surface)

| Field | Value |
| --- | --- |
| Repository / renderer | `github-sync/Circum-`, `lib/web_sender_app.dart`, `_RiderArchitecturePreviewApp`. |
| Direct routes | None. |
| Evidence | `CircumRiderAppRoot` retains `_RiderArchitecturePreviewApp` only behind `useRiderPreview`; production route resolution no longer sets that flag for any Rider URL. |
| Classification | **Unrouted internal development surface. Not a Rider application or production URL.** |

**Conclusion for `https://circum-app-2797c.web.app/rider`:** it is the
**canonical Circum Rider Web App**. `resolveCircumRoute` selects the Rider
surface without `useRiderPreview`, so `CircumRiderAppRoot` renders the
authenticated `_RiderEnrollmentPortal`.

### Legacy Rider Client (Not Canonical)

| Field | Value |
| --- | --- |
| Repository / directory | `github-sync/Circum-Rider` |
| Entry point | `lib/main.dart` -> `CircumRider`. |
| Platforms | Web, iOS, Android, macOS, Linux, Windows. |
| Hosting configuration | Firebase site `circum-rider-2797c`, built from `build/web`. |
| Classification | **Legacy Rider client. Not the current Rider product or deployment path.** |
| Deployment | No checked-in script. The active `Circum-` public deployment scripts do not deploy its Hosting site. |

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
| `hosting:app` | `circum-app-2797c` | `build/web_main` | Circum Sender/Public + Marketing | `scripts/deploy_main_web.sh` |
| `hosting:admin` | `circum-admin-2797c` | `build/web_admin` | Circum Admin Portal | `scripts/deploy_admin_web.sh` |
| Rider legacy site | `circum-rider-2797c` | `build/web` | Legacy Rider Client (`Circum-Rider`) | No checked-in script; not in the current Rider deployment path. |

`scripts/deploy_all_web.sh` is the only checked-in script that deploys all
three main-repository Hosting targets. The canonical Rider web route is part of
the public build; it does not deploy the legacy Rider Hosting site.

## Workspace Copies And Non-Product Artifacts

| Path | Classification | Evidence |
| --- | --- | --- |
| `Circum--main` | **Unversioned workspace copy; not a canonical checkout** | No `.git` directory; duplicates a Circum app configuration. |
| `Circum-Rider-main` | **Unversioned workspace copy; not a canonical checkout** | No `.git` directory; duplicates a Rider configuration. |
| `circum-4-reference` | **Reference / AI Studio sample** | README labels it an AI Studio app and requires `GEMINI_API_KEY`; it is not a Circum Firebase app. |
| Flutter SDK, Node runtime, JDK, Android SDK directories | **Development tooling** | SDK/runtime layout, not product applications. |

## Permanent Naming Rules

1. Refer to `github-sync/Circum-` web public targets as **Circum Sender / Public App**, never simply “the app”.
2. Refer to `github-sync/Circum-` `/rider` as **Circum Rider Web App (Canonical)**.
3. Refer to `github-sync/Circum-Rider` as **Legacy Rider Client** unless an explicit migration changes that status.
4. Refer to `_RiderArchitecturePreviewApp` as an **unrouted internal development surface**. Do not create a public route to it.
5. Refer to `hosting:admin` as **Circum Admin Portal** only.
6. Refer to Business as a **Sender module**, never a standalone deployment target.
7. Before adding an application route or deploy script, update this registry in the same change.

## Current Corrections Recommended

1. **Use `circum-app-2797c.web.app/rider` for the current Rider web product.** It now renders the authenticated Rider portal.
2. **Do not use `github-sync/Circum-Rider` for current Rider product work** without a separately approved migration plan.
3. Keep `_RiderArchitecturePreviewApp` unrouted or remove it only in a dedicated cleanup task.
4. Update legacy deployment prose that still calls the public target `main`; the checked-in Firebase configuration uses `public` and `app`.

## Preserved Architecture

This registry documents existing ownership only. It does not rename routes,
move applications, alter Firebase Hosting, or change runtime behaviour.
