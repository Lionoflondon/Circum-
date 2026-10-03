# Private Gifts native TEST artifact

This is an operator certification harness, not a replacement release of Sender or Rider. The normal `lib/main.dart` entry point and LIVE checkout are unchanged. Building, exporting, uploading, installing and device certification are separate gates. Do not upload this local `0.0.1 (1)` artifact as a public release.

Build explicitly with `lib/gifts_test_main.dart`, `CIRCUM_PRIVATE_GIFTS_TEST=true` and `PAYMENT_ENVIRONMENT=test`. Otherwise startup is blocked. QA passwords and Stripe secret keys are not bundled. The build includes only a verified matching TEST publishable key; startup refuses a LIVE key.

The app calls only the pinned private `giftqa` service. Firebase Auth and App Check are required for every request. The server determines the role from the existing approved QA identities; a client-selected role is never trusted. It stores records under the existing isolated fixture root, suppresses customer emails/push and does not dispatch deliveries or pay out funds.

1. Approved Admin signs in and prepares a fixture; copy its ID.
2. Approved Sender signs in, enters that ID, then completes the £50 card PaymentSheet using Stripe TEST details.
3. `finalize_native_payment` verifies the bound TEST intent actually succeeded. It does not confirm the intent itself. Cancellation or an unpaid intent cannot create a paid Gift.
4. Admin progresses approval, curation and readiness in order.
5. Approved Rider records the private completion event.
6. Sender retrieves Story and reads email/notification counts.
7. Admin cleans up the fixture and its bound TEST customer. Successful Stripe TEST intents remain provider audit records.

The private native checkout returns a bound client secret only to the approved Sender. It returns no customer/ephemeral key and enables no saved cards or wallet payments. Existing browser actions retain their response shape and backend confirmation behavior.

This harness can prove native PaymentSheet and authenticated native transport after installation. Its private completion event does **not** prove real Rider acceptance, pickup, PIN, physical hand-off, native push delivery or the released Sender/Rider UI. Those require separate device evidence. Existing profiles are App Store distribution profiles, so local export alone does not provide direct installation on the paired device.

Validation: focused Flutter analysis/build guard test and strict Firestore emulator coverage for role denial, no unpaid native finalization, browser secret suppression, native client-secret binding, lifecycle retries/deduplication and zero fixture residue. Require repository CI before deploying the changed private service.
