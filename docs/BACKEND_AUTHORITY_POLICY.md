# Backend Authority Policy

This is the Circum authority rule for all new work.

## Principle

The backend is the authoritative source of truth for operational state.

Client apps may collect input, render state, listen to realtime updates, store
local preferences, and hold draft UI state. Client apps must not directly write
operational records or decide business outcomes.

## Backend Owns

All new features must route these actions through Cloud Functions, server-owned
triggers, or another approved backend service:

- identity and role authority
- rider approval, verification, availability, dispatch state, rank, trust, and payouts
- sender account recovery and operational booking state
- delivery lifecycle, cancellation, completion, tracking, proof, and recovery
- IRIS classification, referrals, learning, weight authority, and prohibited item policy
- payments, Stripe sessions, refunds, Roth, wallet balances, ledgers, invoices, and subscriptions
- Health+ bookings, custody, checkout, recurring schedules, and notifications
- Gifts campaigns, matching, procurement, stories, vault access, and recipient tokens
- Vanguard eligibility, protection, timelines, and completion
- Business membership, roles, invoices, payments, join codes, and subscriptions
- chat messages, read authority, moderation, support, and notification delivery
- admin recovery actions, audit logs, investigations, and operational overrides

The client pattern is:

```text
Client input
  -> Callable or backend trigger
  -> Backend validation and audit
  -> Firestore or Storage write
  -> Realtime listener update
  -> Client refresh
```

The forbidden pattern is:

```text
Client input
  -> Direct operational Firestore or Storage write
```

## Client May Own

Client-side writes are allowed only for non-operational state:

- theme
- accessibility settings
- local preferences
- local cache
- draft form state
- purely client-side view state

If a value can affect dispatch, payment, wallet, rank, verification, access,
delivery lifecycle, Health+, Gifts, Vanguard, Business, IRIS, chat, notification
delivery, or Admin recovery, it is operational and must be backend-owned.

## Enforcement

`scripts/backend_authority_guard.js` runs in CI and blocks new client-side
operational Firestore writes.

Run it locally before opening a PR:

```sh
node scripts/backend_authority_guard.js
```

To audit the full current client surface:

```sh
node scripts/backend_authority_guard.js --all
```

Existing legacy writes must be migrated deliberately, one workflow at a time,
with tests and deployment isolation. New features must not add to the legacy
surface.

## Feature Review Checklist

Every new feature must answer:

1. What backend callable or trigger owns the mutation?
2. What server-side validation protects it?
3. What audit record is created for operational actions?
4. What Firestore or Storage records are server-owned?
5. What realtime listener refreshes the client after the backend write?
6. What rule prevents direct client writes to the same operational state?

If these answers are missing, the feature is not ready to merge.
