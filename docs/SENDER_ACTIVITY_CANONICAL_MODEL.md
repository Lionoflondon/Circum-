# Sender Activity canonical model

Sender Activity is a projection of authoritative records. It is not a projection of notifications.

| Surface | Authoritative source | Customer-visible rule |
| --- | --- | --- |
| Live, scheduled, accepted, in-progress, completed and cancelled deliveries | `deliveryRequests/{deliveryId}` where `senderId` belongs to the signed-in Sender | A row exists only while the authoritative delivery record exists and belongs to the Sender. The canonical timestamp is `updatedAt`, with `createdAt` retained for legacy display fallback. |
| Gifts | `giftRequests/{giftId}` where `senderId` belongs to the signed-in Sender | A gift row is allowed only for a real gift record. A notification cannot create one. |
| Health+ | `prescriptionPickups/{pickupId}` where `profileId` belongs to the signed-in Sender | A Health+ row is allowed only for a real pickup record. |
| Roth / Wallet history | The sender-scoped `walletTransactions` ledger returned by `getSenderWalletTransactions` | Ledger ordering and pagination are independent of delivery Activity. Wallet records are never treated as deliveries. |
| Home recent deliveries | The same sender-owned `deliveryRequests` source as Activity | Home shows a bounded view of authoritative delivery records, ordered by the server timestamp before limiting. |
| Notification Centre and Home notification strip | `notifications/{notificationId}` where `recipientId` belongs to the signed-in Sender | Notifications are communications only. Archived, dismissed, suppressed and expired records are excluded by the shared visibility predicate. |

Delivery notification deep links validate the referenced delivery against the current Firebase Auth identity before showing detail or tracking. Missing, deleted, QA-cleaned and wrong-owner references show a safe unavailable state and never create a booking.

Synthetic QA deliveries use an immutable server-created provenance marker. They are excluded from customer notifications, dispatch, settlement, payout and analytics. Client-supplied boolean flags alone are not trusted.
