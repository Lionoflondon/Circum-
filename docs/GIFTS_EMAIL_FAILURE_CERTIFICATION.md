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
| Delivery completes before Story unlock | Gift delivery retained; email waits | Existing queue retries until secure Story is ready | Story automation and transactional worker | Delivered email contains Story link only after unlock | PASS: legacy queue and Story-ready fixtures |
| Duplicate delivery completion | One pair of role-specific Story tokens and three logical emails | Gift transaction read plus create-only queue IDs | Story automation and Gift updated Eventarc publisher | Sender delivery with Story link; Sender and Recipient Story-ready | PASS: concurrent unlock fixture |
| Story token committed, email queue fails | Unlocked Story and tokens retained; `retry_required` recorded | Same tokens and deterministic queue IDs | Gift updated Eventarc publisher; admin retry | Delayed Story email with original token | PASS: injected queue failure and recovery fixture |
| Story automation fails before Gift becomes delivered | Delivery record complete; Gift flagged `retry_required` with linked delivery ID | Admin retry verifies completed linked delivery, then unlocks | `retryGiftStoryAutomation` | No false delivery email | PASS: admin recovery helper fixture rejects incomplete delivery and reuses the original two tokens and three email identities |
| Wrong Gift/recipient/Story token | No email | Source and role revalidation | Transactional email worker | No cross-customer link | PASS: fixture |
| Wrong sender family | Queue rejected before provider | Gifts address guard | Transactional email worker | No cross-family send | PASS: fixture |
| App restart after payment or delivery | Server Gift, ledger, delivery and Story state persist | Existing client recovery and backend reads | Existing Sender app | Restored from backend | BLOCKED: native restart fixture not run in this branch |

## Release gates still open

- Protected rules/emulator and architecture CI must pass on the PR.
- `gift-email-reconciliation.js` provides bounded read-only paid-Gift and completed-delivery discovery pages, exact-Gift inspection, create-only repair for missing payment/delivery/Story queue items, and explicit due-queue replay. Scans are manual, limited to 100 indexed source records per page, and never send or mutate. The Gift-created Eventarc trigger must still be installed and verified.
- The changed `onGiftDeliveryCompleted` and `retryGiftStoryAutomation` Gen 1 exports need narrow activation proof. A successful source test is not live event ownership.
- Private runtime health, merged source SHA, intended traffic, event routing, correct Gifts sender identity, and no unexpected 5xx require post-deployment evidence.

Until these gates are closed, the Gifts journey is **not certified for production**.

## Recovery ownership and bounded detection

| Partial state | Detection | Recovery owner | Idempotency ID / safe retry | Terminal state |
|---|---|---|---|---|
| Paid Gift; confirmation missing | Read-only `paymentStatus == paid` Gift page (maximum 100, document-ID cursor), then exact Gift, queue and Roth ledger reads | Gift-created Eventarc publisher, then operator exact-Gift repair if event delivery was missed | `gift_payment_confirmed_{giftId}` create-only; no financial write | Sent or explicit terminal no-send |
| Completed delivery; Story missing | Read-only `status in [completed, complete, delivered]` delivery page (maximum 100, document-ID cursor), then exact linked Gift read; delivery/Gift `retry_required` state | Existing `onGiftDeliveryCompleted`; explicit exact-Gift operator Story repair if the managed admin callable cannot activate | Committed sender/recipient tokens reused; deterministic email IDs | Story unlocked, or operator-visible retry-required |
| Unlocked Story; notification/email missing | Exact Gift and three deterministic queue IDs | Gift-updated Eventarc publisher, then operator exact-Gift repair | `gift_{giftId}_gift_delivered`, `gift_story_{giftId}_sender`, `gift_story_{giftId}_recipient` create-only | Sent or explicit terminal no-send |
| Retryable Gift email overdue | Exact deterministic queue IDs and `nextAttemptAt` | Transactional worker; authorized operator exact-Gift replay | Fixed queue ID and Resend idempotency key, same source revalidation | Sent or terminal after bounded attempts |

The scanner reads one bounded, indexed source page per invocation and emits only candidates; it neither schedules itself nor repairs automatically. An operator follows each candidate with the exact-Gift command below. Pagination is explicit through `nextAfterId`, so a page is not falsely described as a whole-database certificate. A read-only paid-Gift page is `node server/functions/gift-email-reconciliation.js --scan-paid --limit=50`; a completed-delivery page is `--scan-deliveries --limit=50`. Pass `--after-id=<nextAfterId>` for the next page. Exact-Gift repair never charges, debits, restores, or regenerates Story tokens.
Missing or invalid email contacts are reported as unavailable on exact-Gift inspection and are not repeatedly treated as missing queue items; they remain a no-send until an authoritative contact exists.

## Targeted operator recovery

From an authorized runtime with production Firestore access, inspect one known Gift with `node server/functions/gift-email-reconciliation.js --gift-id=<exact-gift-id>`. Add `--repair` only after reviewing the inspection output and confirming the customer communication should be created. Repair writes only deterministic email queue and Story notification records; it does not charge a card, debit Roth, create a Gift, or regenerate Story tokens. A completed delivery that still needs Story unlock is reported and must be handled through the existing admin Story retry with linked delivery verification. A due, stuck Gift queue item can be replayed only with `--repair --replay-stuck` from an authorized environment with the configured provider secret; the worker revalidates the Gift and uses the same provider idempotency key.

If the existing managed admin Story retry cannot be activated, the same verified recovery helper is available explicitly as `--repair-story --gift-id=<exact-gift-id> --delivery-id=<exact-delivery-id>` from an authorized operator runtime. It first reads the completed, Gift-linked delivery, then reuses committed tokens and deterministic email queue identities. It never charges, debits, restores, or creates a Gift. Do not use it for an unverified or incomplete delivery.
