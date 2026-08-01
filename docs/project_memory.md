# Circum Project Memory

Last updated: 2026-07-23
Current working branch: `main`  
Firebase project: `circum-2797c`

## Live URLs

- Public web app: https://circumuk.com
- Firebase public fallback: https://circum-app-2797c.web.app
- Admin portal: https://admin.circumuk.com
- Firebase admin fallback: https://circum-admin-2797c.web.app

## Deployment Setup

- Public/root Firebase Hosting target: `hosting:public`
- Public fallback Firebase Hosting target: `hosting:app`
- Admin Firebase Hosting target: `hosting:admin`
- Main build output used by hosting: `build/web_main`
- Admin build output used by hosting: `build/web_admin`
- Current Firebase Hosting target map:
  - `public` -> `circum-2797c`
  - `app` -> `circum-app-2797c`
  - `admin` -> `circum-admin-2797c`
- Recent deploy commands used:
  - `firebase deploy --only hosting:public,hosting:app --project circum-2797c`
  - `firebase deploy --only hosting:admin --project circum-2797c`
  - `firebase deploy --only hosting:public,hosting:app,hosting:admin --project circum-2797c`

## Completed And Deployed

### Business Onboarding Materials

- Created printable A4 brochure pack for onboarding local businesses onto Circum:
  - general business paid pilot
  - dry cleaners, laundries, tailors, and boutiques
  - phone, laptop, and electronics repair shops
  - cake makers, bakeries, florists, and gift shops
  - furniture, vintage, marketplace, and bulky-item sellers
- Brochure files were created locally in:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/brochures`
- The brochures position Circum as overflow, urgent, awkward-item, fragile/high-value, and van-required delivery support rather than replacing existing delivery operations.
- Superseded this with a more customer-facing company sales brochure pack:
  - Circum overview: deliveries for customers, staff, and client care
  - delivery for everyone: customer convenience and everyday business delivery
  - Health+: pharmacy pickup support for users, families, and staff
  - client gifting: gifts and appreciation deliveries for good business clients
- The corrected brochure positioning sells Circum as a broad delivery company, not just an overflow courier.
- Created a refined six-page CIRCUM business brochure after reviewing
  `Circum_Business_Brochure.pdf`:
  - stronger customer-facing sales narrative
  - customer delivery, Health+, staff support, and client appreciation
  - only current, supportable service claims
  - real CIRCUM wordmark
  - `BUSINESS` sub-brand beneath the CIRCUM wordmark on the cover and closing page
  - richer full-colour service icons with stronger visual weight
  - official App Store and Google Play download badges on the closing page
  - corrected page 01 spacing between the customer-benefit heading, bullets,
    and lower business-use band
  - rebalanced the section 02 staff-benefit panel with improved padding,
    heading separation, and text spacing
  - updated section 03 to define Circum Gifts as thoughtfully curated,
    story-rich gifting experiences that strengthen customer loyalty and
    employee appreciation
  - print-ready A4 layout with visual rendering checks
- Refined brochure output:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/output/pdf/Circum_Business_Brochure_Improved.pdf`
- Refined brochure generator:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/brochures/generate_circum_business_brochure.py`
- Created a separate six-page quiet-luxury edition while preserving the
  approved brochure content and messaging:
  - warm ivory, graphite, midnight, platinum, and champagne visual system
  - embedded Baskerville and Avenir typography
  - generous editorial grid, restrained line icons, and print-style rules
  - original premium editorial photography for the cover, customer delivery,
    Health+, Circum Gifts, and partnership pages
  - official App Store and Google Play badges retained on the closing page
  - full visual QA and PDF integrity checks completed
- Luxury brochure output:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/output/pdf/Circum_Business_Brochure_Luxury.pdf`
- Luxury brochure generator:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/brochures/generate_circum_business_brochure_luxury.py`
- Luxury brochure photography:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/brochures/assets/luxury`
- The quiet-luxury mixed text/photo layout was superseded by a standard
  edition with separate image plates:
  - restores all six approved standard brochure pages
  - adds five unnumbered, full-bleed photography pages beside the sections
    they support
  - never places photography and text on the same page
  - automated PDF verification confirms every image plate contains zero text
- Current preferred brochure output:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/output/pdf/Circum_Business_Brochure_Standard_With_Image_Plates.pdf`
- Current preferred brochure generator:
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/brochures/generate_circum_business_brochure_standard_with_images.py`
- Rebuilt and verified the current preferred brochure PDF on 2026-07-23:
  - 11 A4 pages
  - five separate full-bleed image plates
  - image plate pages contain no text layer
- Added and verified one additional standard-style benefits page on 2026-07-23:
  - live tracking
  - secure payments
  - IRIS intelligence
  - Vanguard handling
  - connected support
  - Health+ and Gifts platform breadth
  - current preferred brochure is now 12 A4 pages with five image-only plates
- Updated the benefits page IRIS card on 2026-07-23:
  - defines IRIS as Circum's intelligent parcel assessment and trust engine
  - references photo and user-input analysis, parcel characteristic estimates,
    safe transport recommendations, and decision evidence
  - replaced the generic IRIS card icon with a dimensional intelligence mark
- Updated the benefits page product cards on 2026-07-23:
  - Live Tracking now references real-time location, progress, rider status,
    and journey events from collection to completion
  - Circum Payments now references Stripe, Apple Pay, Google Pay, saved cards,
    Roth Wallet, and intelligent split payments
  - Vanguard card is now named Vanguard Protocol and describes premium
    delivery protection, rider prioritisation, enhanced custody tracking,
    priority support, and peace of mind
  - Connected Support now references fast assistance, issue resolution,
    questions, and customer communication
  - Built beyond parcels now ties deliveries, payments, tracking, support,
    Vanguard, and the wider Circum experience together
  - Live Tracking, Circum Payments, Vanguard Protocol, and Connected Support
    cards use custom dimensional icons
- Updated numbered section 04 on 2026-07-23:
  - headline now says Circum adds value and ensures customer satisfaction
  - adjusted only that section header spacing to prevent overlap
- Created a designs-only brochure variant on 2026-07-23:
  - removes all full-bleed image plate pages
  - keeps the designed brochure pages and benefits page
  - outputs a compact 7-page A4 PDF
  - `/Users/jason/Documents/Codex/2026-06-04/before-implementing-iris-create-a-concise/output/pdf/Circum_Business_Brochure_Designs_Only.pdf`
- Cleaned local Codex-generated brochure work files on 2026-07-25:
  - emptied the temporary `tmp/` workspace, including rendered PDF pages,
    contact sheets, one-off screenshots, and the temporary PDF Python venv
  - removed local `.DS_Store` clutter
  - removed the superseded luxury PDF output
  - kept only the two current brochure outputs:
    `Circum_Business_Brochure_Standard_With_Image_Plates.pdf` and
    `Circum_Business_Brochure_Designs_Only.pdf`

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
  - public/root app
  - public fallback app
  - admin app
- Firebase Hosting routing fix completed on 2026-06-04:
  - `circumuk.com` serves the public build from `build/web_main`.
  - `circum-2797c.web.app` and `circum-app-2797c.web.app` serve the public build from `build/web_main`.
  - `admin.circumuk.com` and `circum-admin-2797c.web.app` serve the admin build from `build/web_admin`.
  - Public deploy script now deploys only `hosting:public,hosting:app`.
  - Admin deploy script now deploys only `hosting:admin`.
  - Full web deploy script now deploys only `hosting:public,hosting:app,hosting:admin`.
  - Public-host defensive guard prevents an admin-compiled web build from defaulting to admin mode on `circumuk.com`, `www.circumuk.com`, `circum-2797c.web.app`, or `circum-app-2797c.web.app`.
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
- `www.circumuk.com` did not resolve from local DNS during the 2026-06-04 Firebase routing verification. Add/repair the DNS/custom-domain record for `www` before treating it as live.
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
- `origin/iris-production-sync` currently points at `9b64b1a Add project memory documentation`.
- Local branch `iris-production-sync` is synchronized with `origin/iris-production-sync` at the time of this snapshot.
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

## Branch Reconciliation Report

Snapshot date: 2026-06-04  
Compared branches: `origin/main` and `origin/iris-production-sync`  
Merge base: `dadc442 Fix admin action button wrapping`  
`origin/iris-production-sync` HEAD: `9b64b1a Add project memory documentation`  
`origin/main` HEAD: `dadc442 Fix admin action button wrapping`

### Files Unique To Main

None found.

`origin/main` is the merge base for this comparison and has no branch-only commits or files relative to `origin/iris-production-sync`.

### Files Unique To IRIS Production Sync

- `docs/project_memory.md`
- `server/functions/iris-core.js`
- `server/functions/iris-core.test.js`
- `server/functions/iris-security.test.js`
- `server/functions/iris.js`

### Files Modified On IRIS Production Sync

These files already exist on `origin/main`, but differ on `origin/iris-production-sync`:

- `firestore.rules`
- `server/functions/accept-ride-requests.js`
- `server/functions/get-avaliable-requests.js`
- `server/functions/index.js`
- `server/functions/package.json`
- `server/functions/send-package.js`

### Files Modified Differently On Both Branches

None found.

Because `origin/main` is the merge base and has no commits that are absent from `origin/iris-production-sync`, there are no files with independent changes on both sides.

### Expected Conflicts

None expected from the current branch relationship.

`git merge-tree origin/main origin/iris-production-sync` produced a clean merge tree and did not report conflict markers or unresolved paths.

### Safe Merge Strategy

Recommended strategy:

1. Open a pull request from `iris-production-sync` into `main`.
2. Review the backend/function and Firestore rule changes carefully.
3. Run backend tests, especially:
   - `server/functions/iris-core.test.js`
   - `server/functions/iris-security.test.js`
   - delivery request creation tests around `send-package.js`
   - rider request visibility tests around `get-avaliable-requests.js`
   - rider acceptance tests around `accept-ride-requests.js`
4. Verify Firebase Functions dependency installation and deployment in a clean environment.
5. Merge only after backend deploy readiness is confirmed.

Because `main` is currently an ancestor of `iris-production-sync`, this can be merged without code conflicts if no new commits land on `main` first.

### Recommended Source Of Truth Branch

Recommended source of truth for IRIS/backend architecture: `origin/iris-production-sync`.

Reason:

- It contains the latest IRIS backend architecture.
- It contains the project memory documentation.
- It includes all current `main` history plus the IRIS-specific backend changes.

Recommended source of truth for currently deployed/stable public branch: `origin/main`.

Reason:

- It is the current production-stable baseline.
- It does not yet include the full IRIS backend/function divergence.

Operational recommendation:

- Treat `origin/iris-production-sync` as the candidate release branch.
- Treat `origin/main` as the production baseline until backend/functions are verified and the IRIS branch is merged.

### Merge Readiness

Merge readiness estimate: `84%`

Reasons:

- No branch-only `main` commits.
- No expected Git conflicts.
- IRIS files are already pushed to GitHub.
- Main risk is not source-control conflict; it is backend deployment/runtime verification for Firebase Functions and Firestore rule behaviour.

## Post-Merge Validation Report

Snapshot date: 2026-06-04  
Merged source: `origin/iris-production-sync`  
Merged target: `main`  
Merge type: fast-forward  
Merge result: clean, no Git conflicts  
Current merged HEAD: `ab35121 Document branch reconciliation`

### Backend Tests

Passed:

- `node --test iris-core.test.js iris-security.test.js`
  - 16 tests passed.
- `node --test health-plus-core.test.js`
  - 4 tests passed.

Note:

- Shell `npm` was not on the default PATH in this environment.
- Lint was run using the bundled project npm binary instead.

### Firebase Functions Validation

Passed:

- `npm run lint` from `server/functions` using bundled npm.
- `firebase deploy --only functions --project circum-2797c --dry-run` from `server`.

Warnings:

- Node.js 20 runtime is deprecated as of 2026-04-30 and scheduled for decommissioning on 2026-10-30.
- `functions.config()` / Cloud Runtime Config is deprecated and must be migrated before March 2027.

### Firestore Rules Validation

Passed:

- `firebase deploy --only firestore:rules --project circum-2797c --dry-run`
- `firestore.rules` compiled successfully.

### Send Package Flow Validation

Source-level validation passed with caveats:

- `server/functions/send-package.js` is exported as `sendPackage` from `server/functions/index.js`.
- The function requires authenticated users.
- It loads `deliveryRequests` by `requestId`.
- It blocks non-dispatchable IRIS results through `isDispatchable`.
- It filters online riders through `riderMatchesIris`.
- It sends FCM broadcast messages to matched riders.

Caveat:

- Full live validation still requires a real Firebase delivery request, online rider records, and FCM token verification.

### Rider Request Listing Validation

Source-level validation passed with caveats:

- `server/functions/get-avaliable-requests.js` is exported as `getAvaliableRequests` from `server/functions/index.js`.
- The function requires authenticated riders.
- It loads the rider profile from `riders/{uid}`.
- It filters requested delivery jobs through `isDispatchable`.
- It checks rider suitability through `riderMatchesIris`.
- It sorts Express/high-priority work above normal work using `dispatchPriority`.

Caveat:

- Full live validation still requires real rider location data and delivery request records.

### Rider Acceptance Flow Validation

Validation status: blocker found.

- `server/functions/accept-ride-requests.js` exists.
- It contains an authenticated callable function body.
- It performs IRIS dispatchability and rider compatibility checks.
- It is not exported from `server/functions/index.js`.

Impact:

- Firebase Functions dry-run will not deploy this function as a callable endpoint unless it is exported elsewhere.
- The rider acceptance flow cannot be considered production-ready from this merged source state.

Resolution needed:

- Export the existing acceptance callable from `server/functions/index.js`.
- Add or verify a focused acceptance test that proves first valid rider assignment works.
- Confirm the client calls the deployed callable name.

### Production Readiness

Post-merge production readiness estimate: `86%`

Ready:

- Git merge is clean.
- Backend IRIS tests pass.
- Health+ backend tests pass.
- Functions lint passes.
- Functions dry-run packaging/analyse passes.
- Firestore rules compile.
- Send package flow is exported and source-valid.
- Rider request listing is exported and source-valid.

Not ready:

- Rider acceptance callable exists but is not exported from `index.js`.
- Live Firebase/FCM end-to-end testing has not been run in this validation pass.
- Node runtime and Runtime Config deprecation warnings need planned migration.

## Rider Acceptance Blocker Resolution

Snapshot date: 2026-06-04  
Branch: `main`

### Files Changed

- `server/functions/index.js`
- `server/functions/accept-ride-requests.js`

### What Was Fixed

- Exported the existing rider acceptance callable as `acceptRideRequests`.
- Reworked `accept-ride-requests.js` from duplicated broadcast/search logic into an actual rider acceptance callable.
- The callable now:
  - requires Firebase Auth.
  - requires `requestId`.
  - loads the authenticated rider profile from `riderProfiles/{uid}` or `riders/{uid}`.
  - loads the delivery request by document ID or `requestId`.
  - checks IRIS dispatchability.
  - loads `irisPrivate/{requestId}` when present for private rider matching rules.
  - verifies rider suitability with `riderMatchesIris`.
  - transactionally assigns the first valid rider.
  - writes `status`, `dispatchStatus`, and `matchingStatus` as `accepted`.
  - stores `riderId`, `driverId`, `assignedDriverId`, and `assignedRiderId`.
  - stores rider display fields used by sender/admin screens.
  - creates or updates the booking chat thread.
  - sends the sender FCM `connection` / `accepted` update when a sender token exists.

### Callable Naming

- Firebase export name: `acceptRideRequests`.
- This matches the existing function filename and the expected callable naming convention used by the backend.
- Existing web rider flow also writes acceptance directly to Firestore; the callable now supports the backend/mobile function path.

### Workflow Validation

Validated at source level:

- Sender creates job:
  - `sendPackage` is exported.
  - `send-package.js` stores `deliveryRequests` and broadcasts to eligible riders.
- Rider sees available jobs:
  - `getAvaliableRequests` is exported.
  - `get-avaliable-requests.js` filters open `requested` jobs and sorts priority/Express work first.
- Rider accepts job:
  - `acceptRideRequests` is now exported.
  - acceptance is transactional and prevents another rider taking an already assigned request.
- Acceptance status updates:
  - delivery request status fields are updated to `accepted`.
  - rider assignment fields are stored for sender, rider, and admin views.
- Sender receives update:
  - callable sends FCM data payload with `type=connection`, `status=accepted`, and rider payload compatible with existing sender message handling.

### Validation Commands

Passed:

- `npm run lint` from `server/functions` using bundled npm.
- `node --test iris-core.test.js iris-security.test.js health-plus-core.test.js`
  - 20 tests passed.
- `firebase deploy --only functions --project circum-2797c --dry-run`
  - Functions loaded, analysed, and packaged successfully.

Warnings still present:

- Node.js 20 Firebase Functions runtime is deprecated and scheduled for decommissioning on 2026-10-30.
- `functions.config()` / Runtime Config is deprecated and should be migrated before March 2027.

### Production Readiness After Fix

Production readiness estimate: `93%`

Ready:

- IRIS backend tests pass.
- Health+ backend tests pass.
- Functions lint passes.
- Functions dry-run passes.
- Send package callable is exported.
- Rider request listing callable is exported.
- Rider acceptance callable is now exported and updates assignment state.
- Firestore rules already compiled successfully in the previous validation pass.

Remaining manual verification:

- Deploy functions to Firebase.
- Run one live sender-to-rider acceptance using real Firebase Auth users and a real FCM sender token.
- Confirm the sender receives the acceptance notification in-app.

## Final Production Deployment

Deployment timestamp: 2026-06-04T10:00:10Z  
Firebase project: `circum-2797c`  
Source branch: `main`  
Source commit deployed: `162c9fd Add available requests callable alias`

### Deployment Command

- `firebase deploy --only functions,firestore:rules,hosting:main,hosting:admin --project circum-2797c`

### Deployment Result

Passed:

- Firebase Functions deployed.
- Firestore rules deployed.
- Main hosting deployed.
- Admin hosting deployed.

Hosting URLs:

- Public custom domain: `https://circumuk.com`
- Public Firebase fallback: `https://circum-app-2797c.web.app`
- Admin custom domain: `https://admin.circumuk.com`
- Admin Firebase fallback: `https://circum-admin-2797c.web.app`

### Deployed Functions Verified

Callable/backend delivery:

- `sendPackage`
- `getAvailableRequests`
- `getAvaliableRequests`
- `acceptRideRequests`
- `sendMessage`
- `sendRiderUpdate`

IRIS:

- `analyseIris`
- `adjudicateIris`

Health+:

- `createHealthPlusCheckoutSession`
- `updateHealthPlusPickupStatus`

Stripe/payment:

- `StripePayEndpointMethodId`
- `createPaymentIntent`
- `StripePayEndpointIntentId`
- `confirmPaymentIntent`
- `StripeWebhook`
- `RetrieveCardDetails`

Other operational functions:

- `calculateEarnings`
- `endTrip`

### Final Validation Results

Passed:

- `main` pulled latest from `origin/main`.
- Working tree was clean before deployment.
- Functions lint passed.
- Backend tests passed: `20/20`.
- IRIS tests passed.
- Health+ tests passed.
- Firestore rules dry-run passed.
- Firebase Functions dry-run passed.
- Production deploy completed successfully.
- `circumuk.com` returned HTTP 200.
- `admin.circumuk.com` returned HTTP 200.
- Firebase fallback hosting URLs returned HTTP 200.
- `acceptRideRequests` appears in deployed Firebase Functions.
- `sendPackage` appears in deployed Firebase Functions.
- `getAvailableRequests` and legacy `getAvaliableRequests` appear in deployed Firebase Functions.
- `analyseIris` and `adjudicateIris` appear in deployed Firebase Functions.
- Health+ functions appear in deployed Firebase Functions.
- Stripe/payment functions appear in deployed Firebase Functions.

Warnings:

- Full browser-based sender/rider/admin UI walkthrough was not executed in this validation turn because no in-app browser control was available.
- A real authenticated production sender/rider workflow could not be completed automatically because the service-account key embedded in `lib/helper/messaging_server.dart` was rejected by Google with `invalid_grant: Invalid JWT Signature`, which indicates the key is likely revoked.
- No real Stripe payment session or charge was created during validation to avoid creating live financial records with dummy data.
- FCM sender acceptance delivery could not be confirmed without a real sender device token/session; the `acceptRideRequests` callable returns the `senderNotified` field and the deployed endpoint is live.
- Node.js 20 Functions runtime is deprecated and scheduled for decommissioning on 2026-10-30.
- `functions.config()` / Runtime Config is deprecated and should be migrated before March 2027.

### Workflow Status

- Sender creates parcel: source and deployed `sendPackage` path verified; live UI/authenticated creation still needs manual test credentials.
- Parcel appears in rider marketplace: deployed `getAvailableRequests` and legacy `getAvaliableRequests` verified; live data test still needs rider account/session.
- Rider accepts parcel: deployed `acceptRideRequests` verified; live data test still needs rider account/session.
- Sender receives update: source and deployed notification path verified; actual FCM delivery still needs a real sender device token.
- Admin can view status: admin hosting live; Firestore/admin source path present; manual admin login test still required.
- Tracking updates correctly: source path present; real accepted delivery test still required.
- Health+ journey: functions live and method guards verified; full checkout requires intentional live Stripe session.
- IRIS estimation: tests pass and deployed callable exists.
- Stripe payment flow: payment functions live and respond; no live charge/payment intent was created.

### Final Launch Readiness

Final launch readiness estimate: `94%`

Reason:

- Production deployment is complete.
- Required functions are now visible in Firebase.
- Rules and hosting are live.
- Backend validation passes.
- Remaining risk is live account/device/payment verification, not missing deployed code.
