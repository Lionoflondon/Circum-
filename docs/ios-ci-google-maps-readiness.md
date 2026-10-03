# iOS CI Google Maps Readiness

Status: placeholder architecture only. iOS CI is not enabled in this repository.

## Existing Runtime Wiring

Sender iOS already reads Google Maps from the Xcode build setting `GOOGLE_MAPS_API_KEY`.

- `ios/Runner/Info.plist` exposes `GoogleMapsApiKey` as `$(GOOGLE_MAPS_API_KEY)`.
- `ios/Runner/AppDelegate.swift` reads `GoogleMapsApiKey` and calls `GMSServices.provideAPIKey`.

No repository code change is required when iOS CI is introduced.

## Reserved Future Secret

- `SENDER_IOS_GOOGLE_MAPS_API_KEY`

Use this secret for Sender iOS CI only. The Google Cloud key should be restricted to:

- Application restriction: iOS apps.
- Bundle ID: `com.circum.app`.
- API restriction: Maps SDK for iOS.

## Future CI Command Pattern

Do not add this as an active workflow until Apple signing is ready.

```bash
test -n "${SENDER_IOS_GOOGLE_MAPS_API_KEY}" || (echo "Missing SENDER_IOS_GOOGLE_MAPS_API_KEY" >&2; exit 1)
GOOGLE_MAPS_API_KEY="${SENDER_IOS_GOOGLE_MAPS_API_KEY}" flutter build ipa --release --target=lib/main.dart
```

## Remaining External Work

1. Create the GitHub secret `SENDER_IOS_GOOGLE_MAPS_API_KEY`.
2. Configure Apple signing certificates, profiles, and App Store Connect access.
3. Enable the iOS workflow.
