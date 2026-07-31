# Sender UI Baseline v1.0

This document locks the approved Sender UI baseline.

The baseline covers:

- Home
- Send
- Activity
- Wallet
- Profile
- Shared navigation shell
- Shared page scaffold
- Glassmorphism
- Iridescence
- Typography
- Responsive behavior

## Rule

Future features may be added, but the approved visual structure must not change
unless the design baseline is intentionally versioned from `v1.0` to a new
approved version.

## Shell Contract

- One canonical Sender app scaffold owns the body and bottom navigation.
- Primary tabs must not introduce nested `Scaffold` roots.
- Primary tab bodies must fill the available app body above the bottom nav.
- The shared page shell must not cap page width.
- The shared page shell must not reserve dead space above the bottom nav.
- Bottom navigation must not scale or clip icons or labels.

## Responsive Contract

The Sender app is mobile-first.

Desktop and tablet adapt from the same app surface rather than using a separate
desktop shell. Wide layouts are allowed only when explicitly approved for a
baseline version and covered by visual regression tests.

## Token Contract

The canonical values live in:

`lib/app/sender_mobile/sender_ui_baseline.dart`

Protected categories:

- spacing
- border radius
- shadows
- blur values
- gradients
- color palette
- typography
- icon sizes
- navigation sizes
- animation durations
- easing curves

## Regression Gates

The Sender deploy workflow must run:

- `test/sender_mobile/sender_app_boot_contract_test.dart`
- `test/sender_mobile/sender_first_frame_layout_test.dart`
- `test/sender_mobile/sender_visual_baseline_contract_test.dart`

Any visual structure change must either preserve these tests or intentionally
bump the baseline version with an approved design review.
