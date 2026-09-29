# Sender notification Cloud Run owner

`circum-sender-notification-events` is the private Eventarc consumer for Sender
notification publishers that must not be recreated or updated as Gen 1
Functions. It runs the existing notification handlers through the canonical
`communication-engine` path, so notification IDs, deep-link normalization,
ownership checks, FCM payloads, and dedupe keys remain unchanged.

## Eventarc routes

| Firestore path | Event | Existing export replaced |
| --- | --- | --- |
| `deliveryRequests/{deliveryId}` | updated | `onDeliveryUpdated` |
| `chats/{chatId}/messages/{messageId}` | created | `onChatMessageCreated` |
| `giftRequests/{giftId}` | created/updated | `onGiftRequestCreated`, `onGiftRequestUpdated` |
| `giftCampaignParticipants/{participantId}` | updated | `onGiftCampaignParticipantUpdated` |
| `storyNotifications/{notificationId}` | updated | `onStoryNotificationWrite` |
| `supportTickets/{ticketId}` | created | `onSupportTicketCreated` |
| `disputes/{disputeId}` | created | `onDisputeCreated` |
| `riderProfiles/{riderId}` | updated | `onRiderProfileUpdated` |
| `payoutRequests/{requestId}` | updated | `onPayoutUpdated` |

The service accepts only these Firestore document paths and the matching
created/updated Eventarc type. It rejects arbitrary paths and event types.
Eventarc replay is guarded by `eventHandlerClaims`; notification-level dedupe
keys remain the final exactly-once boundary during the controlled owner handoff;
the old Gen 1 revisions are not removed by this change.

The already-owned delivery-created, gift-delivery-completed, and notification
retry services remain separate owners. No Gen 1 deletion is part of this
handoff.
