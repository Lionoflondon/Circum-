# SwiftLogistics Prototype

Flutter implementation of the AI Studio logistics iteration. The current app is
a self-contained prototype with mock shipment data and three main views:

- Home landing page with tracking input
- Customer Portal for booking shipments and viewing statuses
- Driver Portal for accepting jobs and marking deliveries complete

The original Circum Firebase, Stripe, map, and delivery modules are still in the
repository for reference, but the active app entry point is the simplified
prototype in `lib/main.dart` and `lib/app.dart`.

## Run Locally

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```

## Production Notes

Before re-enabling the original Firebase/Stripe backend flows, rotate any
service account keys or webhook secrets that were previously committed, and keep
server credentials out of the Flutter client.
