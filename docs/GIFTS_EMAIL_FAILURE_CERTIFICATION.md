# Gifts email failure certification

This matrix covers the Gifts payment → final Gift → queue → delivery → Story → email path. `PASS` refers to fixture or source tests only until the merged revision, Eventarc trigger, and live private consumer are verified. No real charge, Roth debit, Gift, or customer email is used for certification.

| Failure point | Expected persisted state | Safe retry / identity | Reconciliation owner | Customer communication | Result |
|---|---|---|---|---|---|
| Roth reservation/debit before finalization interruption | Reserved debit persists; no paid Gift or confirmation until the provider succeeds and finalization commits | Reservation retry uses the same provider identity and `gift_roth_{giftDraftId}`; finalization transaction is atomic | Gift finalizer and checkout reservation recovery | No premature confirmation | PASS: emulator lost-response fixture asserts one debit, no Gift/email before finalization, and safe retry |
| Stripe accepted, client response lost | Provider result recoverable; no new charge | Existing reservation / PaymentIntent identity and webhook replay | Gift payment webhook and client recovery | Stripe receipt for card portion; Circum Gift confirmation only after paid state | PASS: existing source and webhook replay tests; live provider recovery not exercised |
| Split funding interrupted | No paid Gift or confirmation until card and Roth components finalize | Existing reservation and Roth ledger identity; terminal expiry restores once | Gift finalizer / reservation recovery | No premature confirmation | PASS: emulator lost-response and expiry replay fixtures assert one debit, one restoration, no Gift/email |
| Paid Gift, publisher fails before queue create | Paid Gift and Roth debit remain intact | Eventarc replay or exact-Gift repair creates `gift_payment_confirmed_{giftId}` once | Gift created Eventarc publisher and targeted operator repair | No false confirmation; delayed confirmation on retry | PASS: create-only and targeted repair fixtures; live event routing pending |
| Queue create succeeds, publisher loses response | One queue item remains | Create-only deterministic queue ID | Eventarc publisher | One logical email | PASS: replay fixture |
| Eventarc duplicate, including 20 concurrent attempts | One claimed queue item | Transactional claim and fixed queue ID | Transactional email worker | One logical email | PASS: concurrency fixture |
| Resend accepts, HTTP response lost | Queue remains retryable | Same Resend `Idempotency-Key` | Transactional email worker | Provider deduplicates logical send | PASS: lost-response fixture |
| Resend accepts, sent-status write fails | Queue stays processing until lease expiry | Same Resend key after lease | Transactional email worker | No second logical send | PASS: write-failure fixture |
| Resend 429 or 5xx | Gift remains complete; queue retryable | Bounded backoff, maximum attempts | Transactional email worker | Delayed email | PASS: 429/5xx fixtures; stuck-queue reconciliation pending |
| Invalid or suppressed recipient | Gift remains complete; queue terminal no-send | No retry | Transactional email worker | No email | PASS: fixture |
| Source or recipient changes before send | Queue suppressed | No retry | Transactional email worker | No false email | PASS: fixture |
| Delivery completes before Story unlock | Gift delivery retained; Sender delivery email may queue immediately and Story email waits | Deterministic delivery queue identity; Story queue uses the committed secure token | Gift updated publisher and Story automation | Sender delivery email has the canonical Gifts route; Story email contains the secure link only after unlock | PASS: delivery and Story-ready fixtures |
| Duplicate delivery completion | One pair of role-specific Story tokens and three logical emails | Gift transaction read plus create-only queue IDs | Story automation and Gift updated Eventarc publisher | Sender delivery with Story link; Sender and Recipient Story-ready | PASS: concurrent unlock fixture |
| Story token committed, email queue fails | Unlocked Story and tokens retained; `retry_required` recorded | Same tokens and deterministic queue IDs | Gift updated Eventarc publisher; admin retry | Delayed Story email with original token | PASS: injected queue failure and recovery fixture |
| Story automation fails before Gift becomes delivered | Delivery record complete; Gift flagged `retry_required` with linked delivery ID | Admin retry verifies completed linked delivery, then unlocks | `retryGiftStoryAutomation` | No false delivery email | PASS: admin recovery helper fixture rejects incomplete delivery and reuses the original two tokens and three email identities |
| Wrong Gift/recipient/Story token | No email | Source and role revalidation | Transactional email worker | No cross-customer link | PASS: fixture |
| Wrong sender family | Queue rejected before provider | Gifts address guard | Transactional email worker | No cross-family send | PASS: fixture |
| App restart after payment or delivery | Server Gift, ledger, delivery and Story state persist | Existing client recovery and backend reads | Existing Sender app | Restored from backend | BLOCKED: native restart fixture not run in this branch |

## Release gates still open

- Protected rules/emulator and architecture CI must pass on the PR.
- `gift-email-reconciliation.js` is a forward-only, bounded, indexed, idempotent reconciler for the seven required post-policy communications. It requires persisted cutover metadata plus explicit start/end/cursor/page/max bounds, publishes through the canonical queue publisher, records terminal suppression for missing or invalid recipients, and never calls Resend directly. It ignores every authoritative event before the cutover, even when `updatedAt` is later. It is a manual/one-shot operation; it is not a scheduler or a second email owner.
- The changed `onGiftDeliveryCompleted` and `retryGiftStoryAutomation` Gen 1 exports need narrow activation proof. A successful source test is not live event ownership.
- Private runtime health, merged source SHA, intended traffic, event routing, correct Gifts sender identity, and no unexpected 5xx require post-deployment evidence.

Until these gates are closed, the Gifts journey is **not certified for production**.

## Recovery ownership and bounded detection

| Partial state | Detection | Recovery owner | Idempotency ID / safe retry | Terminal state |
|---|---|---|---|---|
| Post-policy required Gift event; communication missing | Indexed authoritative business-event timestamp range, then source, ledger, recipient and secure-token checks | Forward reconciler publishes through the canonical publisher; it never sends directly | Event-specific deterministic `emailQueue` identity and terminal outcome identity; no financial write | Sent, existing, or explicit terminal suppression |
| Delivered Gift; Story not yet unlocked | Delivered Sender email can publish from authoritative `deliveredAt`; Story pair waits for `giftStoryAvailableAt` and committed tokens | Gift updated publisher and Story automation | `gift_<giftId>_gift_delivered`, then `gift_story_<giftId>_{sender|recipient}` | Sender delivery message, then secure Story pair |
| Retryable Gift email overdue | Existing queue claim/lease and source revalidation | Transactional worker | Fixed queue ID and provider idempotency key | Sent or bounded terminal failure |

Each invocation has explicit UTC `--start`, `--end`, `--page-size`, `--max-work`, and optional encoded per-stream cursor values. The cutover is recorded once in `systemConfiguration/giftsCommunicationsPolicy` with version `gifts-communications-v1`; there is no history repair mode, retrospective resend campaign, or special-case mutation for known old anomalies. Missing or invalid contacts create one durable suppression outcome and are not repeatedly treated as missing work. Re-running the same bounded window is an idempotent no-op for already queued or suppressed logical communications.
