# Rothcross Engineering Release Standard

Every major deployment must prove the product journey, not only compile-time tests
or button-level checks. A deployment is not complete until the relevant
end-to-end workflows are verified and reported.

## Mandatory Completion Report

Every release report must include:

- Code tests run
- Regression checks run
- End-to-end workflows verified
- Live deployment URL
- Commit hash
- Known issues

## Sender Web Booking Workflow

For Sender Web booking changes, verify:

- Create booking
- IRIS estimate
- Payment/payment state
- Booking persists after refresh
- Booking restores after close/reopen
- Active Deliveries/My Bookings shows the booking
- Rider broadcast only happens after a valid canonical delivery record exists
- Vanguard/PIN data exists and survives reload
- Tracking opens correctly

Booking creation must be atomic:

1. Generate `deliveryId`.
2. Create the canonical Firestore delivery record.
3. Persist every required booking field:
   - Sender
   - Recipient
   - Pickup
   - Drop-off
   - Parcel
   - IRIS
   - Vanguard
   - Delivery option
   - Vehicle
   - Pricing
   - Pickup PIN
   - Drop-off PIN
   - Status
   - Timestamps
4. Validate that the canonical record is complete.
5. Mark the booking as `awaiting_payment`.
6. Process payment.
7. If payment succeeds:
   - Update to `payment_complete`.
   - Record payment reference.
   - Write audit entry.
8. Only after payment and canonical validation may the booking transition to:
   - `awaiting_broadcast`
   - `broadcasting`
   - `rider_assigned`

Failure handling:

- Any failure before payment leaves the booking in a recoverable state.
- Any failure after payment must never lose the booking.
- Payment must never exist without a canonical delivery record.
- A rider must never see a delivery missing required fields.
- A sender must always be able to reopen and resume any incomplete booking.

Consistency requirements:

- Firestore is the only source of truth.
- Sender Web, Rider App, and Admin must all read the same canonical delivery
  document.
- Frontend memory is only a cache and must never be relied upon for
  business-critical data.

Required Sender Web end-to-end cases:

- Browser refresh during booking
- Browser close and reopen
- Network interruption before payment
- Network interruption after payment
- Device restart
- Duplicate tab opening
- Multiple rapid payment attempts
- Recovery of incomplete bookings
- Rider acceptance after recovery
- Vanguard PIN persistence
- Tracking restoration

## Rider Workflow

Where relevant, verify:

- Job appears
- Rider can accept
- Arrival states work
- Pickup PIN verification works
- In-transit state works
- Drop-off PIN verification works
- Completion works

## Admin Workflow

Where relevant, verify:

- IRIS Repository approval works
- Existing bulk actions work
- Rider approval/suspension/freeze paths work where affected
- Audit logs are written
- Counters update correctly

## Backend Workflow

Where relevant, verify:

- Firestore records are complete
- State transitions are valid
- No orphaned deliveries
- No stale active deliveries
- No duplicate broadcasts
- No missing PIN/payment/status fields
- Notifications are triggered where expected
