# Public Auth Flow

Circum web now follows a simple public-first flow.

## Public routes

Logged-out visitors can see:

- Home
- Send a parcel entry point
- Become a rider entry point
- High-level pricing and service copy
- Contact/support messaging

Logged-out visitors cannot see:

- Sender dashboard
- Parcel booking forms
- Delivery history
- Sender profile details
- Health+ booking details
- Rider application form
- Rider earnings
- Rider document upload
- Rider ratings
- Admin tools

## Sender flow

Entry points:

- `?app=sender`
- `?app=profile`
- `?app=health`

If the visitor is logged out, the web app shows sender login/signup only. After Firebase Auth succeeds, the app checks the account role. Sender accounts continue to the sender dashboard. Rider and admin accounts are signed out of the sender flow with a clear message.

Sender account data uses:

- `users/{uid}` with `userType: sender`
- `deliveryRequests` where `senderId == uid` or `userId == uid`
- `history` where `userId == uid`

## Rider flow

Entry points:

- `?app=rider`
- `?app=earn`
- `?app=driver`

Logged-out visitors see a short rider intro and rider login/signup only. After Firebase Auth succeeds, the app checks for a rider role/profile. Rider accounts can access application, jobs, earnings, ratings, documents, vehicle details, and withdrawal tools. Sender and admin accounts are blocked from rider tools.

Rider account data uses:

- `riderProfiles/{uid}`
- `riders/{uid}`
- driver earnings/performance/rating collections tied to the rider UID

## Admin flow

Admin is not exposed through the public build. The public app ignores `?app=admin`. Admins use the separate Firebase Hosting target intended for `admin.circumuk.com`.

## Role checks

Role checks use `RoleAccessPolicy`, which reads:

- Firebase custom claims: `adminRole`, `role`, `roles`
- `users/{uid}` fields: `role`, `userType`
- `riderProfiles/{uid}` fields: `role`, `userType`
- `adminUsers/{uid}` fields: `role`, `roles`

Admins are directed away from the public sender/rider flows.

## Firestore rules

`firestore.rules` now narrows reads and writes around role ownership:

- Senders can read and write their own profile.
- Senders can read their own delivery records.
- Riders can read available jobs and jobs assigned to them.
- Riders cannot read private sender profile records.
- Senders cannot read private rider records beyond assigned delivery summaries.
- Admin-only collections remain admin-only.

Deploy the rules after testing the current iOS and Android flows against them.
