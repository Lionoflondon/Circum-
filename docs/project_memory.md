# Circum Project Memory

Last updated: 2026-06-04  
Current working branch: `iris-production-sync`  
Firebase project: `circum-2797c`

## Live URLs

- Public web app: https://circumuk.com
- Firebase public fallback: https://circum-app-2797c.web.app
- Admin portal: https://admin.circumuk.com
- Firebase admin fallback: https://circum-admin-2797c.web.app

## Deployment Setup

- Main Firebase Hosting target: `hosting:main`
- Admin Firebase Hosting target: `hosting:admin`
- Main build output used by hosting: `build/web_main`
- Admin build output used by hosting: `build/web_admin`
- Recent deploy commands used:
  - `firebase deploy --only hosting:main --project circum-2797c`
  - `firebase deploy --only hosting:admin --project circum-2797c`

## Completed And Deployed

### Public Sender Web App

- Rebranded the sender web app to Circum, including page title, logo usage, favicon/logo replacement work, and removal of SwiftLogistics wording.
- Reworked the public web app so it is sender-focused, with rider access separated from sender flows.
- Added responsive web behaviour for desktop and mobile instead of only showing a mobile-style layout.
- Added dark mode as the default visual mode.
- Added live chat/contact entry points for contacting Circum.
- Simplified public navigation and login/signup direction.
- Added multi-role handling so one Firebase Auth user can hold sender, rider, and admin roles.
- Added sender login/signup flow using Firebase Auth.
- Added sender profile functionality connected to Firebase data.
- Added sender delivery history, saved addresses, profile tabs, payment references, reviews, and support areas.
- Added saved pickup/drop-off addresses for senders with Home, Work, and Custom labels.
- Added UK-style address suggestions for pickup and drop-off input fields.
- Added compact scheduling controls for sender booking:
  - `scheduledPickupDate`
  - `scheduledPickupWindow`
  - `scheduledDropoffDate`
  - `scheduledDropoffWindow`
- Added standard sender booking data writes into existing Firebase delivery/request collections.
- Added standard/express/economy service-level work:
  - Economy is cheapest.
  - Standard is middle.
  - Express is higher priority and more expensive.
  - Express jobs get priority matching fields.
- Removed rider earnings from sender-facing screens.

### Pricing And Weight Logic

- Added config-based delivery pricing with base fare, distance fare, weight surcharge, vehicle surcharge, and service-level surcharge.
- Added weight bands:
  - Small Parcel
  - Medium Parcel
  - Heavy Parcel
  - Large Item
  - Extra Heavy/manual quote
- Added vehicle suitability logic so heavy parcels are not assigned to unsafe vehicle types.
- Added gram parsing, so values such as `178g` are treated as `0.178kg`.
- Fixed same-band weight conflicts so different weights inside the same pricing band do not show unnecessary pricing conflict warnings.
- Added tests around pricing boundaries, same-band behaviour, express pricing, and heavy parcel vehicle rules.

### IRIS Weight System

- Added an IRIS product recognition layer before generic category estimation.
- Added known catalogue/product weights, including:
  - iPhone 13: about `0.174kg`
  - iPhone 15: about `0.171kg`
  - AirPods Pro: about `0.056kg`
  - MacBook Air 13: about `1.24kg`
  - PlayStation 5: about `4.5kg`
  - Standard laptop and small parcel fallbacks
- Added source tracking for:
  - Customer declared weight
  - Catalogue match weight
  - AI/category estimated weight
  - Rider verified weight
  - Past verified parcel history
- Added internal truth-band metadata:
  - Exact Match
  - Very High Confidence
  - High Confidence
  - Medium Confidence
  - Low Confidence
- Added customer-facing IRIS explanation modal:
  - Shows how IRIS compares item description, catalogue matches, image analysis, customer declared weight, and rider verification.
  - Does not expose scoring formulas or internal thresholds.
- Added IRIS learning data:
  - Completed deliveries can store verified weight evidence.
  - Similar completed parcels can inform future safer weight-band selection.
  - Admin can review the learning data in delivery records.
- Added regression tests for known iPhone/AirPods product recognition and customer-declared weight overriding lower catalogue weight.

### Rider Web Portal

- Added rider-specific login/signup handling with Firebase Auth.
- Added rider profile/onboarding state logic:
  - no profile: show signup/onboarding
  - pending: show pending approval
  - approved: show rider dashboard
  - rejected: show rejection/help
  - suspended: show suspended screen
- Added rider dashboard areas for:
  - available jobs
  - accepted jobs
  - completed jobs
  - earnings
  - tips
  - ratings/performance
  - verification status
  - withdrawal balance
- Added rider document upload support for:
  - driving licence
  - insurance
  - proof of address
  - vehicle documents
  - profile photo
- Added rider job cards showing service level, pickup/drop-off, distance, ETA, parcel description, declared weight, IRIS estimate, final pricing weight, payout, and tips.
- Added first-valid rider acceptance assignment logic using existing Firebase delivery request records.
- Added rider final-weight verification workflow:
  - confirm accurate weight
  - report heavier weight
  - report significantly heavier weight
  - upload photo evidence
  - add optional note
- Added rider wallet and withdrawal request data flows.
- Added wallet transaction creation for completed jobs.

### Health+

- Added Health+ as an optional service separate from standard parcel delivery.
- Added Health+ page and opt-in flow for:
  - one-off prescription pickup
  - weekly pickup
  - every 2 weeks
  - every 28 days/monthly
  - custom schedule placeholder
- Added Health+ subscription cards:
  - Basic
  - Priority
  - Family
- Added Health+ data writes for profiles, pickups, recurring schedules, usage events, and payment references.
- Added Health+ safety/compliance copy:
  - Circum is a pickup/delivery service only.
  - Circum does not prescribe medication or provide medical advice.
  - Prescriptions remain the responsibility of the user/pharmacy.
- Added Health+ checkout function compatibility work.
- Kept Health+ out of the normal parcel booking journey.

### Admin Portal

- Created/deployed the admin portal separately from the public app.
- Admin live domain: `admin.circumuk.com`.
- Admin Firebase fallback: `circum-admin-2797c.web.app`.
- Added protected admin login flow.
- Added role-based admin access support for:
  - `super_admin`
  - `operations_admin`
  - `support_agent`
  - `finance_admin`
  - `driver_manager`
- Added admin user management foundations:
  - list admins
  - activate/deactivate admin access
  - change roles where permitted
  - audit admin access changes
- Added admin operations dashboard foundations:
  - delivery metrics
  - sender/customer records
  - driver records
  - support tickets
  - payments/finance records
  - Health+ visibility
  - audit logs
  - visitor records where available
- Added admin driver management workflow:
  - pending: approve/reject
  - approved/active: suspend, message, view profile
  - suspended: reactivate, message, view profile
  - rejected: reactivate, view profile
- Added driver profile drawer/page content:
  - name
  - email
  - phone
  - vehicle details
  - plate/registration
  - approval status
  - signup date
  - rating
  - completed/cancelled jobs
  - earnings
  - active jobs
  - documents where present
- Added audit logging for sensitive driver actions.
- Improved admin visual style with shared iridescent/glass styling.
- Fixed admin action-button overlap through the shared `_AdminActions` widget.
- Added admin delivery table visibility for Weight/IRIS summary.

### Communication

- Added booking chat thread support across sender, rider, and admin.
- Sender and assigned rider can message through booking-linked chat threads.
- Admin/Circum support can join booking chats.
- Added unread state foundations and live message UI using existing Firebase infrastructure.

### Firebase And Functions

- Firebase Hosting configured for multiple targets:
  - main public app
  - admin app
- Firebase project used: `circum-2797c`.
- Functions deployment work completed for Node 22 compatibility.
- Health+ checkout function compatibility work completed.
- Existing Firebase collections reused where possible, including:
  - `users`
  - `senderProfiles`
  - `riderProfiles`
  - `riders`
  - `riderDocuments`
  - `deliveryRequests`
  - `webSenderRequests`
  - `chats`
  - `payments`
  - `supportTickets`
  - `auditLogs`
  - `healthPlusProfiles`
  - `prescriptionPickups`
  - `recurringPickupSchedules`
  - `healthPlusUsageEvents`

## Recently Deployed Commits

- `dadc442` - Fix admin action button wrapping
- `e9ed519` - Improve IRIS weight recognition and learning
- `bd7a6f2` - Enhance shared admin panel styling
- `983f73d` - Fix admin action spacing and address suggestions
- `4fdaa3f` - Refine admin driver management workflow
- `e19f464` - Add booking chat across sender rider and admin
- `b0bad2b` - Gate rider portal and add Iris product weights
- `3b8c71e` - Compact sender schedule controls
- `a6eb2f1` - Deploy functions on Node 22 with admin guard

## In Progress / Needs Follow-Up

- Final checkout/live tracking issue:
  - Ensure missing weight never renders as `Small Parcel (0 kg)`.
  - If explicit weight is missing, display a valid default band label such as `Small Parcel (up to 2kg)`.
  - Ensure pricing uses the selected/estimated weight band rather than raw `0kg`.
  - Add rider-search timeout states:
    - loading/searching
    - matched
    - no riders available
    - retry
    - clear error message
  - Ensure chat button layout remains clean on tablet widths.
- Higher-weight source of truth:
  - Confirm all checkout displays and rider cards use `max(customerDeclaredWeightKg, irisEstimatedWeightKg)`.
  - Confirm `weightBand` always derives from that chargeable weight.
  - Add/keep regression test for `customerDeclaredWeightKg = 25` and `irisEstimatedWeightKg = 15`.
- IRIS learning:
  - Current implementation stores and uses sender-accessible completed delivery history where security rules allow.
  - A future backend aggregation could improve cross-user learning safely without exposing private delivery data.
- Admin operations panel:
  - Foundation is in place, but deeper CRUD/detail pages and pagination can still be expanded.
  - Finance and refund workflows need live operational verification before real financial use.
- Health+:
  - UI and data model are in place.
  - Recurring subscription lifecycle should be verified with live payment configuration before production use.
- Rider marketplace:
  - Core dashboard, jobs, verification, wallet, and weight verification foundations are in place.
  - Needs full end-to-end QA with real rider/sender accounts and Firebase security rules.

## Known Caveats

- `flutter analyze` currently exits non-zero because the repo reports info-level deprecation warnings, mainly:
  - `withOpacity` deprecation
  - legacy `Radio` group API warnings
- These analyzer messages have not blocked production web builds.
- Flutter web builds show wasm dry-run compatibility warnings from third-party packages such as secure storage, keyboard visibility, share_plus, and win32/ffi transitive code.
- These wasm warnings do not currently block the JavaScript web build.
- `.firebase/` appears as an untracked local Firebase cache folder and should remain uncommitted unless intentionally needed.
- Disk space previously blocked a Flutter web build; generated build folders were cleared to restore space.

## Suggested Next Safe Tasks

1. Fix checkout/tracking weight display so no checkout screen shows `0kg` unless a valid, intentional zero-weight state exists, which should generally be blocked.
2. Add matching timeout/retry handling to prevent endless “Connecting this delivery...” states.
3. Add a targeted regression test for 65-inch TV style flow:
   - customer weight `25kg`
   - IRIS estimate `15kg`
   - chargeable weight `25kg`
   - correct heavy/large band according to pricing constants
   - rider verification required
4. Run one full manual QA pass:
   - sender signs in
   - creates delivery
   - IRIS/weight pricing updates
   - rider sees broadcast
   - rider accepts
   - rider verifies weight
   - job completes
   - wallet transaction appears
   - admin can view job and evidence
5. Review Firestore security rules for chat, admin, rider documents, rider payouts, and IRIS learning data.

## Operational Notes

- Always keep Health+ separate from normal parcel delivery unless explicitly requested otherwise.
- Public web should remain sender-focused.
- Web supports both sender and rider entry, but mobile iOS/Android are separate sender/rider app experiences.
- Admin should remain isolated on `admin.circumuk.com`; do not expose admin links in public navigation.
- Do not show rider payout, Circum commission, or internal fee split on sender/customer screens.
- Pricing-critical weight should be transparent:
  - sender can see final weight used
  - rider can see declared, IRIS, and final weight before accepting
  - admin can see all weight sources and evidence

## Reconciliation Snapshot

Snapshot date: 2026-06-04  
Snapshot branch: `iris-production-sync`  
Snapshot local HEAD before push: `81a0669`  
Tracked remote branch: `origin/iris-production-sync`

### Current Deployed Backend Status

- Firebase project: `circum-2797c`.
- Backend/functions work exists in the repository on `iris-production-sync`.
- Recent backend/IRIS architecture commit present on GitHub branch `origin/iris-production-sync`: `624ed27 Sync IRIS v1 production architecture`.
- Functions/backend files differing from `origin/main` include:
  - `server/functions/iris.js`
  - `server/functions/iris-core.js`
  - `server/functions/iris-core.test.js`
  - `server/functions/iris-security.test.js`
  - `server/functions/index.js`
  - `server/functions/send-package.js`
  - `server/functions/accept-ride-requests.js`
  - `server/functions/get-avaliable-requests.js`
  - `server/functions/package.json`
  - `firestore.rules`
- Current deployed backend should be treated as partially verified until live function endpoint tests are run again after any backend deployment.

### IRIS Deployment Status

- IRIS web/client integration is present in `lib/web_sender_app.dart`.
- IRIS product-weight estimator is present in `lib/app/iris/iris_weight_estimator.dart`.
- IRIS backend architecture files are present under `server/functions/` on the `iris-production-sync` branch.
- `lib/iris/iris.dart` does not exist in this repository snapshot.
- IRIS implementation is not only local; it exists on GitHub branch `origin/iris-production-sync`.
- `origin/main` does not contain the full `iris-production-sync` backend divergence.

### Sender App Status

- Sender web app source exists in `lib/web_sender_app.dart`.
- Legacy/mobile sender package flow source exists in `lib/app/send_package/bloc/send_package_bloc.dart`.
- Sender flow has Firebase Auth/profile, booking, scheduling, saved addresses, pricing, IRIS, checkout summary, and tracking foundations.
- Known sender issue still pending: checkout/live tracking can display `Small Parcel (0 kg)` in some missing-weight paths and rider matching can appear stuck without a clean timeout/retry state.

### Rider App Status

- Rider web portal foundations exist in `lib/web_sender_app.dart`.
- Rider profile/onboarding, dashboard, job cards, document upload, wallet, withdrawal, and final weight verification foundations are present.
- Rider marketplace requires full end-to-end QA with real Firebase users and role/security-rule checks.

### Admin Status

- Admin portal is isolated at `admin.circumuk.com`.
- Admin app uses the same Flutter web source with `CIRCUM_ADMIN_HOSTING=true`.
- Admin dashboard, role access foundations, driver workflow, delivery table, IRIS weight summary, chats, support, audit, and visual/action-button improvements are present.
- Admin action-button overlap fix is deployed and committed as `dadc442`.

### Health+ Status

- Health+ is optional and separate from normal parcel booking.
- Health+ profiles, pickup records, recurring schedule records, usage events, checkout compatibility, and subscription UI foundations are present.
- Health+ recurring subscription/payment lifecycle still needs live payment verification before full operational use.

### Required File Existence Check

- `lib/iris/iris.dart`: missing.
- `lib/web_sender_app.dart`: exists.
- `lib/app/send_package/bloc/send_package_bloc.dart`: exists.

### A. Deployed Backend

- Firebase hosting has been deployed recently for:
  - public app: `circumuk.com`
  - admin app: `admin.circumuk.com`
- Backend/functions are represented in GitHub on `iris-production-sync`, but live backend deployment status should be considered "needs verification" unless the functions deploy log is checked again.

### B. GitHub Source State

- `origin/main` currently points at `dadc442 Fix admin action button wrapping`.
- `origin/iris-production-sync` currently points at `624ed27 Sync IRIS v1 production architecture` before pushing this memory update.
- Local branch `iris-production-sync` was ahead by one documentation commit before push.
- IRIS implementation is present on GitHub in `origin/iris-production-sync`.

### C. Missing Files

- `lib/iris/iris.dart` is missing.
- The active client estimator is instead located at `lib/app/iris/iris_weight_estimator.dart`.

### D. Divergent Files

Files present or modified on `iris-production-sync` compared with `origin/main`:

- `docs/project_memory.md`
- `firestore.rules`
- `server/functions/accept-ride-requests.js`
- `server/functions/get-avaliable-requests.js`
- `server/functions/index.js`
- `server/functions/iris-core.js`
- `server/functions/iris-core.test.js`
- `server/functions/iris-security.test.js`
- `server/functions/iris.js`
- `server/functions/package.json`
- `server/functions/send-package.js`

### E. Safe Deployment Readiness

Estimated safe deployment readiness: `78%`

Reasoning:

- Public/admin hosting builds and deploys have recently succeeded.
- IRIS architecture is committed to a GitHub branch.
- Sender, rider, admin, Health+, pricing, and chat foundations exist.
- Remaining blockers are concentrated around final checkout/tracking weight display, rider-matching timeout/retry state, live backend verification, and full end-to-end Firebase role/security QA.
