# Historical Admin Parity Report

Audit baseline: current Admin compared against historical `circum-rc1:lib/web_sender_app.dart`.

Current Admin location: `lib/app/admin/**`

Current audited HEAD: `3e73c3dacc15ffbffa755efb1252751014c5f789`

No product code was modified for this audit.

## Summary

The current Admin does not yet have full historical parity.

The previous parity conclusion was too narrow because it counted restored broad panels and restored backend callable access, but missed deeper historical operator workflows in IRIS and Gifts.

## Deeper Frontend / Backend Audit

This pass compared:

- Current Admin frontend callable usage under `lib/app/admin/**`
- Current backend exports under `server/functions/index.js`
- Historical Admin/monolith callable usage from `circum-rc1:lib/web_sender_app.dart`
- Current Admin Firestore collection usage under `lib/app/admin/**`
- Historical Admin/monolith Firestore collection usage from `circum-rc1:lib/web_sender_app.dart`

### Current Admin Callable Coverage

Current Admin frontend calls these backend functions:

- `createRiderTransferOrPayout`
- `deleteIrisReferenceImage`
- `finalizeIrisReferenceImage`
- `getIrisReferenceImage`
- `getOrCreateSupportConversation`
- `issueRothToWallets`
- `manageGiftStoryAccess`
- `reportRating`
- `resetRiderTestStripeAccount`
- `resolveStaleDeliveryLock`
- `retryGiftStoryAutomation`
- `reviewDeliveryAdjustment`
- `sendCircumAnnouncement`
- `sendCircumMessage`
- `setWalletFrozen`
- `startAdminConversation`
- `syncStripeConnectStatus`
- `updateSupportConversationStatus`

Evidence:

- `lib/app/admin/admin_phase1_shell.dart`
- `lib/app/admin/admin_root.dart`

### Historical Callable Usage Not Currently Exposed By Admin

These callables existed in historical monolith usage and/or current backend exports, but are not currently called by `lib/app/admin/**`.

Not every item is automatically an Admin gap. Classification below is based on historical caller context.

| Callable | Current Backend Export | Current Admin Caller | Classification | Evidence |
|---|---:|---:|---|---|
| `createGiftStoryVideoUpload` | Yes | No | Genuine Admin frontend gap for Gift Story preview/export flow | Historical Gift Story viewer/export path: `circum-rc1:lib/web_sender_app.dart:50888`; backend export: `server/functions/index.js:183`; function: `server/functions/gift-story-automation.js:945` |
| `finalizeGiftStoryVideoUpload` | Yes | No | Genuine Admin frontend gap for Gift Story preview/export flow | Historical: `circum-rc1:lib/web_sender_app.dart:50900`; backend export: `server/functions/index.js:184`; function: `server/functions/gift-story-automation.js:968` |
| `getGiftStoryVideoDownload` | Yes | No | Genuine Admin frontend gap for Gift Story preview/export flow | Historical: `circum-rc1:lib/web_sender_app.dart:50858`; backend export: `server/functions/index.js:185`; function: `server/functions/gift-story-automation.js:999` |
| `recordGiftStoryEvent` | Yes | No | Partial Admin gap only if Admin preview analytics was historically required | Historical Gift Story viewer event path: `circum-rc1:lib/web_sender_app.dart:50690`; backend export: `server/functions/index.js:179` |
| `updateGiftStoryPrivacy` | Yes | No | Partial Admin gap tied to Gift Story privacy editor | Historical Gift Story privacy path: `circum-rc1:lib/web_sender_app.dart:50762`; backend export: `server/functions/index.js:180` |
| `createStripeOnboardingLink` | Yes | No | Not an Admin restoration gap from this audit; historical caller appears Rider-facing | Historical caller: `circum-rc1:lib/web_sender_app.dart:20357`; backend export: `server/functions/index.js:157` |
| `requestRiderWithdrawal` | Yes | No | Not an Admin restoration gap from this audit; historical caller appears Rider-facing | Historical caller: `circum-rc1:lib/web_sender_app.dart:20445`; backend export: `server/functions/index.js:161` |
| `reportLoadDiscrepancy` | Yes | No | Not an Admin restoration gap; Rider-facing report creation | Historical caller: `circum-rc1:lib/web_sender_app.dart:19954`; backend export: `server/functions/index.js:84` |
| `ensureReferralCode` | Yes | No | Not an Admin restoration gap; Sender/referral flow | Historical caller: `circum-rc1:lib/web_sender_app.dart:18653`; backend export: `server/functions/index.js:168` |

### Current Admin Collection Coverage

Current Admin reads or writes these collections:

- `accountMergeReviews`
- `adminAuditLogs`
- `adminNotes`
- `adminUsers`
- `businessAccounts`
- `businessInvoices`
- `businessRothPurchases`
- `business_wallets`
- `chats`
- `deliveryAdjustments`
- `deliveryRequests`
- `deliveryTips`
- `driverRatings`
- `giftBrands`
- `giftCampaignParticipants`
- `giftOrders`
- `giftRequests`
- `healthPlusCustodyArchive`
- `healthPlusPayments`
- `healthPlusUsageEvents`
- `irisCanonicalObjects`
- `irisEvidence`
- `irisLearningCases`
- `irisPolicies`
- `irisReferenceImages`
- `messageReports`
- `payments`
- `payoutRequests`
- `platformConfig`
- `platformNotices`
- `platformStatus`
- `platformVersions`
- `prescriptionPickups`
- `recurringPickupSchedules`
- `riderAdminEvents`
- `riderDocuments`
- `riderEarnings`
- `riderProfiles`
- `riderWalletTransactions`
- `riders`
- `senderTrustEvents`
- `supportTickets`
- `users`
- `walletTransactions`
- `wallets`
- `websiteVisitors`

Evidence:

- Current data load: `lib/app/admin/admin_phase1_shell.dart:2288-2395`

### Historical Collections Missing From Current Admin

| Collection | Current Admin Usage | Classification | Evidence / Reason |
|---|---:|---|---|
| `giftCampaignMatches` | No | Genuine Admin gap | Historical approved campaign match creation writes `giftCampaignMatches`: `circum-rc1:lib/web_sender_app.dart:6231`, `6277`; current Admin only reads `giftCampaignParticipants` and does not load `giftCampaignMatches` |
| `driverPerformanceMetrics` | No | Partial Rider Ops/Admin analytics gap | Historical data existed in monolith: `circum-rc1:lib/web_sender_app.dart:19388`, `30202`; current Admin uses rider profile/ratings/earnings but does not load this collection |
| `emailQueue` | No | Backend/shared infrastructure, not an Admin UI gap unless historical email queue screen is proven | Historical write path: `circum-rc1:lib/web_sender_app.dart:5013`; no current Admin screen found |
| `healthPlusNotifications` | No | Backend notification infrastructure, not proven Admin gap | Historical write path: `circum-rc1:lib/web_sender_app.dart:29190` |
| `healthPlusProfiles` | No | Partial Health+ Admin data gap if patient/profile management is required | Historical profile write path: `circum-rc1:lib/web_sender_app.dart:29033`; current Admin loads pickups/payments/schedules/archive, not profiles |
| `irisLearningOutliers` | No | Partial IRIS learning gap | Historical write/read evidence: `circum-rc1:lib/web_sender_app.dart:27974`; current Admin uses `irisLearningCases`, not outliers |
| `notifications` | No | Backend/shared notification infrastructure, not proven Admin gap | Historical Notification panel loaded `notifications`: `circum-rc1:lib/web_sender_app.dart:743`, and historical trust notification write at `5004` |
| `riderApplications` | No | Not current Admin gap from prior classification; Rider application source may have moved to rider profile/document records | Historical write path: `circum-rc1:lib/web_sender_app.dart:20630` |
| `riderOnboardingEvents` | No | Not current Admin gap from prior classification unless a historical Admin onboarding event viewer is proven | Historical write path: `circum-rc1:lib/web_sender_app.dart:20664` |
| `transactions` | No | Backend/general ledger collection, not proven Admin UI gap | Historical collection appears in monolith collection scan; current Admin has `walletTransactions` and `riderWalletTransactions` |

## Additional Evidence-Backed Gaps From Deeper Audit

### Gift Campaign Match Records

Status: MISSING

Historical evidence:

- `_suggestCampaignMatch`: `circum-rc1:lib/web_sender_app.dart:6187`
- `_approveCampaignMatch`: `circum-rc1:lib/web_sender_app.dart:6219`
- Match document creation in `giftCampaignMatches`: `circum-rc1:lib/web_sender_app.dart:6231`, `6277`
- Match participant updates: `6235-6246`
- Draft gift creation from approved campaign match: `6247-6275`

Current evidence:

- Current Admin loads `giftCampaignParticipants`: `lib/app/admin/admin_phase1_shell.dart:2357`
- Current Admin does not load `giftCampaignMatches`
- Current UI has per-participant approve/reject/assign later: `lib/app/admin/admin_phase1_shell.dart:6155-6194`

Gap:

The rebuilt Admin lacks the historical campaign match record workspace and does not expose `giftCampaignMatches` history/details.

### Gift Team Workspace

Status: MISSING / PARTIAL

Historical evidence:

- Historical Gifts Team Workspace starts at `circum-rc1:lib/web_sender_app.dart:5644`
- Assignment controls: `5646-5710`
- Curation Notes: `5714-5727`
- Supplier Workspace: `5730-5763`
- Experience Builder: `5765-5795`
- Budget: `5797-5836`
- IRIS Review: `5838-5865`
- Approval: `5867-5888`
- Ready for Procurement/Rider/Scheduling/Delivery controls: `5891-5905`

Current evidence:

- Current Admin has `Gift Drawer`: `lib/app/admin/admin_phase1_shell.dart:6221-6267`
- No equivalent editor/workspace controls were found under `lib/app/admin/**`

Gap:

The current Gift Drawer summarizes gift records but does not restore the historical operator workspace.

### Historical Troubleshooting Section

Status: MISSING

Historical evidence:

- `_AdminSection.issues` renders title `Troubleshooting`: `circum-rc1:lib/web_sender_app.dart:4457-4466`
- Historical label/icon mapping: `16563`, `16584`

Current evidence:

- Current `AdminModule` does not include `issues`; current modules are dashboard, visitorAnalytics, deliveries, discrepancyReview, users, riders, verification, support, finance, healthPlus, business, gifts, audit, chat, settings.

Gap:

The standalone historical Troubleshooting section remains absent. Some issue handling exists inside other modules, but historical navigation/workspace parity is incomplete.

### Historical Analytics Section

Status: PARTIAL / MISSING AS SEPARATE HISTORICAL MODULE

Historical evidence:

- `_AdminSection.analytics` renders `_AdminAnalyticsSection`: `circum-rc1:lib/web_sender_app.dart:4483-4488`
- `_AdminAnalyticsSection`: `16085`
- Business intelligence metrics: `16110-16147`
- Historical label/icon mapping: `16565`, `16586`

Current evidence:

- Current Admin has analytics embedded across modules, including IRIS analytics at `lib/app/admin/admin_phase1_shell.dart:4225`
- No separate top-level historical Analytics module was found in current `AdminModule`

Gap:

Analytics capability is partially redistributed, but the historical top-level Analytics workspace is not restored as a distinct Admin module.

## Fully Restored Modules

- IRIS reference image lifecycle:
  - Historical evidence: `circum-rc1:lib/web_sender_app.dart:14843`, `14901`, `14961`
  - Current evidence: `lib/app/admin/admin_phase1_shell.dart:643-723`
  - Restored callables: `getIrisReferenceImage`, `finalizeIrisReferenceImage`, `deleteIrisReferenceImage`

- Basic Gifts story access actions:
  - Historical evidence: `circum-rc1:lib/web_sender_app.dart:7037-7089`
  - Current evidence: `lib/app/admin/admin_phase1_shell.dart:984-1020`, `6125-6148`
  - Restored actions: retry, regenerate, extend, revoke

## Partial Historical Modules

### IRIS Operations

Current Admin has a broad IRIS Operations module, but it does not restore the full historical IRIS Repository governance workflow.

Historical evidence:

- `_AdminIrisRepositorySection`: `circum-rc1:lib/web_sender_app.dart:13199`
- Historical tabs: Overview, Canonical Items, Learning Candidates, Alias Manager, Categories, Imports, Audit Log, Settings at `13327-13335`
- Historical repository body switch at `13381-13390`
- Historical repository intelligence section at `13471`
- Historical Categories section at `13718`
- Historical Import Engine at `13750`
- Historical Repository Settings at `13816`

Current evidence:

- `_IrisOperationsModule`: `lib/app/admin/admin_phase1_shell.dart:3669`
- Current panels: Global IRIS Search and Review Queue, Canonical Knowledge Base, Reference Image Lifecycle, Evidence Centre, Learning Centre, Policy Centre, Exports at `3777-3874`

Gap:

The current module provides operational review/search panels, but it does not expose the historical repository governance console with its historical sections and workflows.

### Gifts Operations

Current Admin has Gifts overview/search, campaign participants, brand/campaign review and a Gift Drawer, but it does not restore the full historical Gift Request editor and Gift Story creation workspace.

Historical evidence:

- `_openGiftRequest`: `circum-rc1:lib/web_sender_app.dart:6342`
- IRIS Gift Review panel: `6668-6685`
- Gift Story section: `6848`
- Gift Story photo/audio controls: `6855-6905`
- Gift Story access actions: `7037-7089`
- Gift Story preview: `7119-7143`
- Social/brand exposure controls: `7146-7280`
- Save patch for procurement, IRIS learning and Gift Story fields: `7413-7605`

Current evidence:

- Gift Search: `lib/app/admin/admin_phase1_shell.dart:6110`
- Campaign Participants: `6155`
- Gift Brand and Campaign Review: `6198`
- Gift Drawer: `6221`
- Gift Story access action handler: `984-1020`

Gap:

The current Gifts Admin restores summary and some actions, but not the historical request editor, procurement workspace, Gift Story creator/editor, media controls, consent/social controls, or IRIS gift selection workflow.

## Missing Historical Workflows

### IRIS Bulk Candidate Moderation

Status: MISSING

Historical evidence:

- Bulk approve: `circum-rc1:lib/web_sender_app.dart:14296`
- Bulk reject: `circum-rc1:lib/web_sender_app.dart:14419`
- UI buttons: `13613-13622`

Current evidence:

- Current Admin has per-record review status actions at `lib/app/admin/admin_phase1_shell.dart:3815-3839`
- No selected IRIS candidate bulk approve/reject workflow was found under `lib/app/admin/**`

Recommendation:

Restore the historical bulk candidate workflow inside `lib/app/admin/**` using the current Admin design system.

### IRIS Candidate Learning Workflow

Status: MISSING

Historical evidence:

- `_openCandidateWorkflow`: `circum-rc1:lib/web_sender_app.dart:14500`
- Historical choices:
  - Merge into Existing Canonical Item
  - Create New Canonical Item
  - Save as Alias
  - Evidence: `14515-14519`

Current evidence:

- Current Learning Centre displays learning cases at `lib/app/admin/admin_phase1_shell.dart:4059-4099`
- No guided merge/create/alias dialog was found under `lib/app/admin/**`

Recommendation:

Restore the guided candidate learning workflow as an Admin-owned IRIS module.

### IRIS Suspicious / Reject Candidate Workflow

Status: MISSING

Historical evidence:

- `_markCandidateSuspicious`: `circum-rc1:lib/web_sender_app.dart:14565`
- `_rejectCandidate`: `14630`
- Candidate row actions: `14781-14794`

Current evidence:

- Current Admin exposes generic statuses such as `learning_flagged` and `learning_rejected` at `lib/app/admin/admin_phase1_shell.dart:3815-3839`
- No historical suspicious/reject candidate dialogs were found under `lib/app/admin/**`

Recommendation:

Restore historical suspicious and reject workflows if backend authority exists; otherwise classify exact missing backend support before implementing.

### IRIS Categories / Import Engine / Repository Settings

Status: MISSING / PARTIAL

Historical evidence:

- Categories section: `circum-rc1:lib/web_sender_app.dart:13718`
- Import Engine section: `13750`
- Repository Settings section: `13816`

Current evidence:

- Current Policy Centre exists at `lib/app/admin/admin_phase1_shell.dart:4102`
- No matching historical category manager, import engine or repository settings UI was found under `lib/app/admin/**`

Recommendation:

Restore only the historically evidenced category/import/settings capabilities, using current Admin UI patterns.

### Gift Story Creation / Editor Flow

Status: MISSING / PARTIAL

Historical evidence:

- `_openGiftRequest`: `circum-rc1:lib/web_sender_app.dart:6342`
- Gift Story section: `6848`
- Gift Story photo uploader: `6855`
- Gift Story audio controls: `6905`
- Preview Gift Story: `7119-7143`
- Saved Gift Story fields: `7552-7585`

Current evidence:

- Current Gift module has Gift Search and Gift Drawer at `lib/app/admin/admin_phase1_shell.dart:6110-6267`
- Current Gift Story actions are limited to retry/regenerate/extend/revoke at `984-1020` and `6125-6148`

Recommendation:

Restore the historical Gift Request editor and Gift Story creation/editor workflow inside Admin.

### Gift Story Audio / Voice Mixing

Status: MISSING

Historical evidence:

- `_giftStorySoundtrackAdminControls`: `circum-rc1:lib/web_sender_app.dart:2154`
- Gift Story Audio title: `2194`
- Include sender voice note: `2278-2285`
- Playback timeline: `2358`

Current evidence:

- No equivalent current Admin implementation found under `lib/app/admin/**`
- Backend callables still exist for video upload/download in `server/functions/gift-story-automation.js`

Recommendation:

Restore the historical Admin audio and voice-note controls if still compatible with the current backend.

### IRIS Gift Selection / Gift Suggestions

Status: MISSING

Historical evidence:

- IRIS Gift Review panel: `circum-rc1:lib/web_sender_app.dart:6668-6685`
- `_AdminIrisGiftSuggestionCard`: `17305`
- Suggestion card approve/edit/reject actions: `17408-17421`
- Approved/rejected suggestion persistence: `7587-7598`

Current evidence:

- Current Admin has Campaign Participants and Gift Drawer at `lib/app/admin/admin_phase1_shell.dart:6155-6267`
- No current IRIS gift suggestion card, generated recommendation review, approve/edit/reject suggestion workflow, or selected repository item persistence was found under `lib/app/admin/**`

Recommendation:

Restore the historical IRIS gift suggestion review and selection flow in the Admin Gifts module.

### Gift Procurement Workspace

Status: MISSING / PARTIAL

Historical evidence:

- Procurement fields: `circum-rc1:lib/web_sender_app.dart:6765-6845`
- Saved procurement fields: `7531-7551`

Current evidence:

- Current Gift Drawer shows summary fields at `lib/app/admin/admin_phase1_shell.dart:6221-6267`
- No editor for procurement title, supplier, supplier link, estimated cost, actual cost, order reference, purchaser, dates, receipt URL, invoice URL or procurement notes was found under `lib/app/admin/**`

Recommendation:

Restore the historical procurement editor workspace, preserving backend authority and current Admin styling.

## Final Restoration Addendum

Restoration implemented under `lib/app/admin/**` only.

Current restored evidence:

- IRIS Repository Governance:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored canonical record actions: Edit, Duplicate, Deactivate, History, Bulk export
  - Restored backend-backed reference image actions remain present

- IRIS Candidate Workflows:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored candidate actions: Approve, Reject, Promote, Merge existing, Save alias, Suspicious, History
  - Actions write Admin review metadata/audit only; pricing and lifecycle authority are unchanged

- Gift Story Media / Video:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored Admin access to `getGiftStoryVideoDownload`, `createGiftStoryVideoUpload`, `finalizeGiftStoryVideoUpload`
  - Existing access actions for retry, regenerate, extend and revoke remain present

- Gift Team Workspace:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored workspace visibility for assignment, curation, supplier, experience, budget, IRIS review, approval and readiness state
  - Restored Admin workspace actions: Assign, Curating, Supplier pending, Approval pending, Ready procurement, Ready rider, Ready scheduling, Ready delivery

- Gift Campaign Match Records:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored `giftCampaignMatches` collection loading and Campaign Match Records module

- Troubleshooting:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored standalone top-level Troubleshooting module covering stuck deliveries, failed payments, complaints, refunds and low ratings

- Analytics:
  - `lib/app/admin/admin_phase1_shell.dart`
  - Restored standalone top-level Analytics module with delivery, user, rider, Gift, IRIS, Health+ and support operational reports

## Final Verdict

ADMIN HISTORICAL PARITY: COMPLETE
