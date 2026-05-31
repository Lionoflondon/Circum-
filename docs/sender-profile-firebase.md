# Sender Profile Firebase Schema

The web Sender Profile uses the same Firebase identity as the iOS and Android sender app.

## Shared identity

- Firebase Auth UID is the sender ID.
- Primary profile document: `users/{uid}`.
- Optional sender-specific mirror: `senders/{uid}` if the mobile apps later need a dedicated sender collection.

## Profile fields

`users/{uid}`:

- `fullName` / `fullname`
- `email`
- `phoneNumber`
- `photoURL` / `image`
- `role: user`
- `userType: sender`
- `status`
- `verificationStatus`
- `savedAddresses`
- `savedRecipients`
- `communicationPreferences`
- `customerId`
- `createdAt`
- `updatedAt`

Payment data is shown only as a safe reference. Card numbers, CVC values, and raw payment details must never be stored in sender profile documents.

## Delivery history

The profile reads deliveries by Firebase UID from:

- `deliveryRequests` where `senderId == uid`
- `deliveryRequests` where `userId == uid`
- `history` where `userId == uid`

This matches the current mobile sender app, which writes active requests to `deliveryRequests/{uid}` and reads history through `history.userId`.

## Security rules

`firestore.rules` now includes sender ownership checks for:

- `users/{uid}`
- `senders/{uid}`
- `deliveryRequests`
- `history`

Admins can still access sender profile data through role-gated admin paths. Normal signed-in users should only read and update their own profile and delivery history.
