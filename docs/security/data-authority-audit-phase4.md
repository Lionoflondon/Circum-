# Circum Data Authority Audit - Phase 4

Phase 4 expands the Firestore audit into a data authority audit for Sender,
Rider, Admin and the shared backend. This document records the current
production authority model and the Phase 4 repairs made in the working tree.

No commit and no deployment have been performed for Phase 4.

## Before vs After

| Area | Before | After |
|---|---|---|
| `deliveryRequests` create | Sender/Rider clients could create own delivery documents through rules. | Client creation removed. Admin remains allowed; backend Cloud Functions bypass rules and remain authoritative. |
| `deliveryRequests` lifecycle fields | Protected by `deliveryOperationalFieldsUnchanged()`. | Protection retained and covered by regression test. |
| `notifications` create | Clients could create notices addressed to themselves. | Client creation removed. Admin/backend authored only; clients can still read/archive their own notifications. |
| `senderBookingDrafts` | Callable-owned in rules. | Retained and covered by regression test. |
| Wallet/payment ledgers | Backend-owned in rules. | Retained and covered by regression test. |
| Indexes | Not changed. | Not changed. |

## Collection Authority Matrix

| Collection / Path | Owner | Allowed Writers | Allowed Readers | Security Rule | Validation Level | Cloud Function Owner | Status |
|---|---|---|---|---|---|---|---|
| `deliveryRequests` | Backend | Admin only in rules; backend functions author production writes | Admin, sender, assigned rider, eligible rider offer queries | `match /deliveryRequests/{deliveryId}` | Strong lifecycle-field protection | `sendPackage`, `createSenderPaidDelivery`, `acceptRideRequests`, `requestSenderCancellation`, `recordRiderArrival`, `updateDeliveryTrackingStatus`, `markRiderNoShow` | Protected |
| `deliveryRequests/{id}/tracking/liveLocation` | Rider with backend-bound assignment | Assigned rider only | Admin, sender, assigned rider | Nested `tracking` rule | Field allowlist | Rider tracking engine; backend delivery owner | Protected but needs backend arrival migration |
| `deliveries`, `deliveryRecords`, `bookings` | Deprecated / compatibility mirrors | Super admin via fallback; backend SDK where referenced | Admin fallback unless explicitly exposed | Fallback rule | Low explicitness | Stripe/Rider payout reconciliation references | Deprecated - no production client owner confirmed |
| `senderBookingDrafts/{uid}` | Backend | Callable only | Owning sender | Explicit match | Strong | `saveSenderDraft`, `loadSenderDraft`, `deleteSenderDraft` | Protected |
| `riders/{uid}` | Rider profile + backend operational authority | Rider for safe profile fields, Driver Manager/Admin for operational fields | Admin or owning rider | Explicit match | Strong protected-field checks | Rider onboarding/profile functions where available | Protected, but client still writes profile/application fields |
| `riderProfiles/{uid}` | Rider profile + backend operational authority | Rider for safe profile fields, Driver Manager/Admin for operational fields | Admin or owning rider | Explicit match | Strong protected-field checks | Rider profile/admin review flows | Protected, but direct profile writes remain intentional |
| `riderApplications/{uid}` | Rider submission + Admin review | Rider for non-review fields, Admin for review | Admin or owning rider | Explicit match | Review-field protection | Rider onboarding/Admin review | Protected |
| `riderDocuments/{docId}` | Rider submission + Admin review | Rider for upload metadata before review, Admin for review | Admin or owning rider | Explicit match | Review-field protection | Rider onboarding/Admin review | Protected |
| `riderEarnings/{uid}` | Backend/Admin | Admin only | Admin or owning rider | Explicit match | Strong | `rider-connect`, earnings ledger functions | Protected |
| `riderWalletTransactions` | Backend/Admin | Admin only | Admin or owning rider | Explicit match | Strong | `rider-connect`, Roth ledger | Protected |
| `payoutRequests` | Backend/Admin + constrained rider request | Rider can create request without raw bank fields; Admin updates | Admin or owning rider | Explicit match | Medium | `requestRiderWithdrawal`, `cancelRiderWithdrawal`, Stripe Connect functions | Needs migration to callable-only create |
| `wallets`, `senderWallets`, `walletTransactions`, `rothLedger` | Backend | No client create/update/delete | Finance admin or owner read | Explicit matches | Strong | Roth ledger/wallet functions | Protected |
| `payments`, `healthPlusPayments` | Finance/backend | Finance admin writes | Finance/admin/owner reads where applicable | Explicit matches | Medium | Stripe/payment functions | Protected |
| `senderPaymentRecords` | Backend Authoritative | Backend SDK only; client writes denied | Finance admin or owning sender | Explicit match | Strong | Stripe webhook/payment functions | Protected |
| `notifications` | Backend/Admin + client read state | Admin/backend create; owner can update read/archive fields | Admin or recipient | Explicit match | Strong after Phase 4 | `platform-notifications`, communication functions | Protected |
| `chats/{chatId}` and `messages` | Backend communication engine | Client writes denied; callables own lifecycle/messages | Admin or participant | Explicit match | Strong | `sendCircumMessage`, `markConversationRead`, `setConversationTyping`, `startAdminConversation` | Protected |
| `supportTickets` | Admin/support | Admin; public web live chat constrained create | Admin | Explicit match | Medium | Support/Admin flows | Needs support callable migration |
| `businessAccounts` | Business/Admin | Creator/manager constrained, Admin | Admin and business team | Explicit match | Medium | Business access functions | Needs syntax cleanup and callable-first migration |
| `business_wallets` | Shared: Backend + Finance Admin | Finance admin; backend SDK | Finance/admin/business members | Explicit match with transactions subcollection | Medium/Strong | Business payment functions | Protected |
| `businessInvoices` | Shared: Business draft + Finance/Admin operational state | Business managers may create/update non-payment fields; finance admin owns payment/status fields | Finance/admin/business members | Explicit match | Medium | Business payment functions and Business invoice UI | Protected with business draft ownership |
| `businessInvoicePayments` | Backend / Finance Admin Authoritative | Finance admin; backend SDK | Finance/admin/business members | Explicit match | Strong | Business payment functions | Protected |
| `businessRothPurchases` | Shared: Business request + Finance/Admin settlement | Business managers create pending requests; finance admin/backend settle | Finance/admin/business members | Explicit match | Medium/Strong | Business payment functions | Protected |
| `giftRequests` | Backend/Admin | Admin only | Admin, sender, eligible recipient story viewer | Explicit match | Strong | Gift payment/story functions | Protected |
| `giftPaymentDrafts` | Sender draft + backend payment | Sender constrained create; Admin update/delete | Admin or sender | Explicit match | Medium | `createGiftPayment`, `finalizeGiftPayment` | Needs callable-only draft migration |
| `giftCampaignParticipants` | Sender participant + Admin matching | Sender constrained profile fields, Admin matching fields | Admin or owner | Explicit match | Medium | Gift campaign/payment functions | Protected with follow-up |
| `giftCampaignMatches` | Admin/backend | Admin only | Admin | Explicit match | Strong | Admin gift matching | Protected |
| `giftBrands`, `giftRecommendationRepository` | Admin | Admin only | Admin | Explicit match | Strong | Admin gifts/IRIS | Protected |
| `prescriptionPickups` | Health+/Backend/Admin | Sender/user create/update, Admin, assigned rider read | Admin, sender/user, assigned rider | Explicit match | Medium | Health+ functions | Needs backend-authoritative transition tightening |
| `healthPlusProfiles`, `recurringPickupSchedules`, `healthPlusNotifications`, `healthPlusUsageEvents` | Health+/Admin | Sender/user constrained or Admin | Admin and owner | Explicit matches | Medium | Health+ functions | Needs backend-authoritative transition tightening |
| `irisPrivate` | Backend/Admin + constrained participants | Admin, sender private create, rider verification update | Admin | Explicit match | Strong field allowlists | IRIS/adjudication functions | Protected |
| `iris_learning`, `irisLearningOutliers` | Backend/Admin + constrained learning candidates | Sender/user constrained creates; Admin review | Signed-in or Admin depending path | Explicit matches | Medium | IRIS learning | Needs review for data minimisation |
| `adminAuditLogs`, `adminNotes`, `riderAdminEvents`, `riderPayoutAudit` | Admin/backend audit | Admin/backend | Admin | Explicit/fallback | Medium | Admin/backend actions | Protected, add explicit rules for all audit collections |
| `driverRatings` | Sender rating + Admin moderation | Customer creates own rating; Admin non-rating updates | Admin, customer, rider | Explicit match | Medium | Rating flow | Protected |
| `driverPerformanceMetrics` | Backend/Admin | Admin only | Admin or rider owner | Explicit match | Strong | Admin/performance jobs | Protected |
| `history` | Backend/Admin | Admin only | Admin, sender/rider participant | Explicit match | Strong | Legacy delivery history | Protected |
| `users/{uid}` | Sender profile + backend trust/legend authority | Sender for profile fields, Admin constrained, super admin | Admin or owner | Explicit match | Protected trust/legend fields | Sender profile/trust functions | Protected |
| `users/{uid}/savedAddresses` | Backend callable | Client writes denied | Owner | Explicit subcollection | Strong | `saveSenderSavedAddress`, `deleteSenderSavedAddress` | Protected |
| `senders/{uid}` | Sender profile | Sender/Admin writes | Sender/Admin reads | Explicit match | Low protected-field coverage | Legacy sender profile | Needs consolidation with `users` |
| `referrals`, `referralCodes` | Backend/Admin | Referrals client writes denied; admin code writes | Participants/Admin | Explicit match | Strong | Referral functions | Protected |
| `websiteVisitors`, `emailQueue`, `platformStats/legends` | Admin/backend/public telemetry | Mixed public/admin | Admin | Explicit/fallback | Low/Medium | Public/Admin functions | Needs explicit data minimisation review |

## Direct Client Operational Writes Found

These are client-side writes discovered during static scanning. Some are already
blocked by rules; others remain intentionally allowed profile/preference writes.

- Rider `home_bloc.dart` contains legacy direct `deliveryRequests.status` writes.
  Rules already block lifecycle field changes, but the client path should be
  retired in a later Rider cleanup pass.
- Rider live tracking writes `deliveryRequests/{id}/tracking/liveLocation` and
  `activeDeliveries/{id}`. Both paths now have explicit participant-bound
  field allowlists. Backend migration can still be considered later for stronger
  arrival/geofence authority, but the current client mirror is constrained.
- Sender/Admin monolith `web_sender_app.dart` contains direct Admin operations
  on delivery, rider, gift, support and audit collections. These require Admin
  callable migration over later phases.
- Sender notification repositories update read/archive/delete metadata directly;
  this remains intentionally client-managed.

## Rules Changed

- `deliveryRequests` client create removed.
- `notifications` client create removed.
- Added explicit `activeDeliveries` rules.
- Added explicit `senderPaymentRecords` rules.
- Added explicit `business_wallets` and transaction rules.
- Added explicit `businessInvoices` rules.
- Added explicit `businessInvoicePayments` rules.
- Added explicit `businessRothPurchases` rules.
- No indexes changed.

## Tests Added

- `test/security/data_authority_rules_test.js`

The test verifies:

- `deliveryRequests` cannot be directly created by Sender/Rider clients.
- Delivery lifecycle fields remain backend-owned.
- Operational notification creation is backend/admin authored only.
- `senderBookingDrafts` remains callable-owned.
- Wallet and Roth ledger collections remain backend-owned.
- `senderPaymentRecords` is explicit and backend-owned.
- `activeDeliveries` is explicit and limited to assigned rider location mirrors.
- Business wallet, invoice payment and Roth purchase collections reject unauthorised writes.
- Phase 4 explicit collections no longer rely on catch-all fallback rules.

## Remaining Risks

- The previously unknown/fallback collections from Phase 4 now have explicit
  rules. Deprecated compatibility mirrors (`deliveries`, `deliveryRecords`,
  `bookings`) still rely on fallback because no active client owner was confirmed.
- Admin web still performs direct Firestore writes for some finance/business
  operations. These are now classified as Finance/Admin authoritative rather than
  unknown, but backend callables would give stronger idempotency and audit shape.
- Health+ and gift draft flows still allow constrained client creation in some
  collections. This may be intentional, but production parity should eventually
  move critical transitions to callables.
