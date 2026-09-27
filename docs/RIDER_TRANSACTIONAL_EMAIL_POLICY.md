# Rider transactional email policy

Policy version: `rider-communications-v1`

Policy effective time: recorded at production activation and passed explicitly to the bounded reconciler. No pre-effective Rider record is eligible, and no historical record is backfilled.

The single delivery path is authoritative Rider/backend state → deterministic `emailQueue` document → Eventarc → private `circum-transactional-email` → Rider profile recipient revalidation → Resend. Email failure never rolls back Rider approval, delivery completion, earnings, Connect status, payout, or account closure.

## Final communications matrix

| Event/state | Push/in-app | Email | Recipient/source | Template and deterministic ID | Reconciled | Status |
|---|---|---|---|---|---|---|
| Application received | Yes | No | Rider app state | Existing onboarding notifications | No | Push/in-app only |
| Email verification and password reset | Firebase Auth | Firebase Auth | Firebase Auth | Firebase-owned | No | Unchanged |
| Application needs information | Yes | Yes | `riderProfiles/{riderId}` | `rider-application-more_information_requested`; `rider_application_{riderId}_more_information_requested_{decisionTime}` | Yes | Existing policy path, revalidated |
| Application approved | Yes | Yes | `riderProfiles/{riderId}` | `rider-application-approved`; `rider_application_{riderId}_approved_{decisionTime}` | Yes | Existing policy path, revalidated |
| Application rejected | Yes | Yes | `riderProfiles/{riderId}` | `rider-application-rejected`; `rider_application_{riderId}_rejected_{decisionTime}` | Yes | Existing policy path, privacy-safe |
| Document rejected/replacement required | Yes | Yes | `riderDocuments/{documentId}` plus `riderProfiles/{riderId}` | `rider-document-action-required`; `rider_document_{documentId}_{status}_{reviewTime}` | Yes | New |
| Vehicle routine upload/progress | Yes | No | Rider application authority | Existing application centre state | No | Push/in-app only |
| Go online/offline, location, GPS, offers, offer expiry, accepted job | Yes | No | Rider operational authority | Existing notification owners | No | Push/in-app only |
| Pickup, in transit, arrival, drop-off | Yes | No | Delivery operational authority | Existing notification owners | No | Push/in-app only |
| Delivery completed and earning recorded | Yes | Yes | `riderEarningTransactions/{deliveryId}` plus Rider profile | `rider-earnings-delivery`; `rider_earning_delivery_earning_{deliveryId}` | Yes | New |
| Cancellation/no-show compensation recorded | Yes | Yes | `riderEarningTransactions/{transactionId}` plus Rider profile | `rider-earnings-compensation`; `rider_earning_{type}_{transactionId}` | Yes | New |
| Earnings adjustment credit | Yes | Yes | `riderEarningTransactions/{transactionId}` plus Rider profile | `rider-earnings-adjustment`; `rider_earning_adjustment_credit_{transactionId}` | Yes | New |
| Tip received | Yes | No | Tip and earning authority | Existing tip/push path | No | Push/in-app only |
| Stripe Connect action required/restricted | Yes | Yes | `riderProfiles/{riderId}` Stripe status | `rider-connect-action_required`; `rider_connect_{riderId}_action_required_{syncTime}` | Yes by profile stream | New |
| Stripe Connect payouts enabled | Yes | Yes once | `riderProfiles/{riderId}` Stripe status | `rider-connect-enabled`; `rider_connect_{riderId}_enabled_{syncTime}` | Yes by profile stream | New |
| Withdrawal requested | Yes | Yes | `payoutRequests/{requestId}` plus Rider profile | `rider-payout-requested`; `rider_payout_requested_{requestId}_{createdTime}` | Yes | New |
| Payout paid | Yes | Yes | `payoutRequests/{requestId}` plus Rider profile | `rider-payout-paid`; `rider_payout_paid_{requestId}_{paidTime}` | Yes | New |
| Payout failed/cancelled/action required | Yes | Yes | `payoutRequests/{requestId}` plus Rider profile | `rider-payout-failed`; `rider_payout_failed_{requestId}_{failedTime}` | Yes | New, state-safe |
| Account closure blocked | Yes | No | Account authority | Existing in-app security flow | No | In-app only |
| Account closed | In-app | No new email source found | Account authority | No new publisher added | No | No invented email |
| Routine retries/internal status | No customer message | Never | Internal | No email publisher | No | Never email |

The Rider/general sender family is Info: `info@circumuk.com` or the already approved Info fallback. No Gifts, Business, or Health+ identity is accepted for these queue records.

## Copy and safety contract

Rider mail explains what happened, why it matters, and the next step. It does not include document contents, reviewer notes, bank details, Stripe internal status names, queue/provider identifiers, raw enums, or private Sender data. Payout-failure copy does not claim that funds were lost, refunded, or returned. Earnings mail confirms the authoritative ledger record; it is never evidence that money moved.

Missing, invalid, or suppressed Rider recipients become terminal no-send outcomes. The consumer revalidates the Rider profile email and source state immediately before Resend. Provider retries reuse the same queue ID and Resend idempotency key.

The bounded reconciliation module examines only indexed milestone timestamps on or after the policy effective time: application decisions, document action, earning/compensation/adjustment records, and withdrawal/payout milestones. It has explicit page and work limits. A second identical run must publish zero new communications.
