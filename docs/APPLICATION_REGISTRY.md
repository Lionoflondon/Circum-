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
| Native Rider iOS, Android, desktop, or its dedicated web app | **Circum Rider App** | `github-sync/Circum-Rider` | `Circum-/rider`, which is a preview route |
| Internal operations | **Circum Admin Portal** | `github-sync/Circum-` | public Hosting targets |
| Marketing/public entry | **Circum Marketing Website** | `github-sync/Circum-` | Admin Hosting |

## Canonical Application Map

### Circum Sender / Public App (Canonical)

| Field | Value |
| --- | --- |
| Purpose | Sender product plus public marketing, Gifts, Health+, Business entry points, and the embedded Rider enrolment portal. |
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

### Circum Rider App (Canonical Native Rider Application)

| Field | Value |
| --- | --- |
| Purpose | Dedicated Rider app for rider onboarding, verification, jobs, history, support, earnings, and account flows. |
| Repository / directory | `github-sync/Circum-Rider` |
| Entry point | `lib/main.dart` -> `CircumRider`. |
| Router | `lib/app.dart` uses the authenticated-state `Navigator`; Rider app routes are registered in `lib/main.dart`. |
| Authentication route tree | Unknown session -> `IndexPage`; unauthenticated -> `OnboardingView`; authenticated/incomplete -> `AddDetailsView`; authenticated/pending -> `ApplicationSubmittedView`; authenticated/approved -> `AppNavView`. |
| Named routes | `RiderJobOfferScreen.routeName`; `/rider/jobs/offers/preview`. |
| Platforms | Web, iOS, Android, macOS, Linux, Windows. |
| Firebase project | `circum-2797c`. |
| Hosting configuration | Firebase site `circum-rider-2797c`, built from `build/web`. |
| Hosting URL implied by configuration | `https://circum-rider-2797c.web.app`. |
| Build / deploy | No repository deployment script is checked in. Standard configured path is `flutter build web --release`, followed by `firebase deploy --only hosting --project circum-2797c`. |
| Repository deployment status | **Deployment pipeline not represented in `Circum-`**. The standalone Rider repository has a site configuration but no checked-in deploy script. Whether the site is currently live cannot be determined from repository evidence alone. |

#### Why this is the canonical Rider application

`Circum-Rider` is the only dedicated Rider repository in this workspace with a
`circum_rider` Flutter package, its own `CircumRider` root widget, mobile
platform folders, Rider-only authentication state machine, and its own Firebase
Hosting site configuration. It is therefore the canonical Rider app for native
Rider work.

### Embedded Rider Web Portal (Canonical Public-Web Companion, Not A Native App)

| Field | Value |
| --- | --- |
| Repository / entry | `github-sync/Circum-`, `lib/web_sender_app.dart`, `_RiderEnrollmentPortal`. |
| Purpose | Public-web Rider enrolment, sign-in, account setup, and Rider operations from the main public build. |
| How it opens | The public home Rider role action calls `_openRole(CircumRole.rider)`, which creates `CircumRiderAppRoot` with `usePreview: false`. |
| Direct Hosting target | None. It is part of the public Sender/Public build on `hosting:public` and `hosting:app`. |
| Classification | **Canonical public-web Rider companion. Not the canonical native Rider app.** |

### Rider Architecture Preview (Explicitly Non-Canonical)

| Field | Value |
| --- | --- |
| Repository / renderer | `github-sync/Circum-`, `lib/web_sender_app.dart`, `_RiderArchitecturePreviewApp`. |
| Direct routes | `/rider`; `?app=rider`; `?app=driver`; `?app=earn`; `?app=circum-order`. |
| Evidence | `resolveCircumRoute` sets `useRiderPreview: true` for each route; `CircumRiderAppRoot` renders `_RiderArchitecturePreviewApp` whenever that flag is true. |
| Classification | **Preview / compatibility route. Not the canonical Rider app and not the embedded Rider portal.** |
| Deployment | It is shipped incidentally in the public Sender/Public build because it shares the same web bundle. Do not use it for Rider acceptance testing or Rider production sign-in. |

**Conclusion for `https://circum-app-2797c.web.app/rider`:** it is a
**Rider Architecture Preview**, not the canonical Rider App. This conclusion is
based solely on the explicit `useRiderPreview: true` assignment in
`resolveCircumRoute` and the conditional renderer in `CircumRiderAppRoot`.

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
| Rider standalone site | `circum-rider-2797c` | `build/web` | Circum Rider App (`Circum-Rider`) | No checked-in script; deploy from the Rider repository only. |

`scripts/deploy_all_web.sh` is the only checked-in script that deploys all
three main-repository Hosting targets. It does **not** deploy the standalone
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
2. Refer to `github-sync/Circum-Rider` as **Circum Rider App (Canonical)** for all native Rider work.
3. Refer to the main-repository Rider sign-in surface as **Embedded Rider Web Portal**.
4. Refer to `/rider`, `?app=rider`, `?app=driver`, `?app=earn`, and `?app=circum-order` as **Rider Architecture Preview routes**. Do not present them as Rider production app URLs.
5. Refer to `hosting:admin` as **Circum Admin Portal** only.
6. Refer to Business as a **Sender module**, never a standalone deployment target.
7. Before adding an application route or deploy script, update this registry in the same change.

## Current Corrections Recommended

1. **Do not use `circum-app-2797c.web.app/rider` to demonstrate or test the actual Rider app.** It is an explicit preview renderer.
2. **Use `github-sync/Circum-Rider` for the iOS Rider app** and deploy its web build only to `circum-rider-2797c` after a Rider-specific release workflow exists.
3. **Do not infer a live Rider deployment from the main repository.** The active main deployment scripts omit the Rider site.
4. Update legacy deployment prose that still calls the public target `main`; the checked-in Firebase configuration uses `public` and `app`.

## Preserved Architecture

This registry documents existing ownership only. It does not rename routes,
move applications, alter Firebase Hosting, or change runtime behaviour.
