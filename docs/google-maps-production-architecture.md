# Google Maps Production Architecture

Status: repository prepared, console verification pending.

## Current Repository Flow

| Surface | Runtime | Key source | APIs used | Failure behaviour |
| --- | --- | --- | --- | --- |
| Sender Web tracking | Google Maps JavaScript SDK through `google_maps_flutter_web` | `CIRCUM_WEB_GOOGLE_MAPS_API_KEY` injected by `scripts/build_sender_app_web.sh` | Maps JavaScript API | Tracking falls back to the existing animated background when no map snapshot exists. |
| Sender Android | `google_maps_flutter` native Android SDK | `GOOGLE_MAPS_API_KEY` manifest placeholder from `SENDER_ANDROID_GOOGLE_MAPS_API_KEY` in CI | Maps SDK for Android | Native map widget can fail independently of booking state; deployment build now fails on missing key. |
| Sender iOS | `google_maps_flutter` native iOS SDK | `$(GOOGLE_MAPS_API_KEY)` read from `Info.plist` by `AppDelegate`; future CI secret name `SENDER_IOS_GOOGLE_MAPS_API_KEY` | Maps SDK for iOS | `GMSServices` is called only when the build setting is present. |
| Public Website addresses | Direct HTTPS from Flutter web | `GOOGLE_PLACES_API_KEY` | Places Autocomplete, Place Details, Find Place, Geocoding, Static Maps | Code falls back to seeded/manual address paths on request failure. |
| Sender mobile route preview | Direct HTTPS through Flutter polyline package | `GOOGLE_MAPS_DIRECTIONS_API_KEY` | Directions API | Route preview is skipped with a user-safe error when key is absent. |

## Direct REST API Audit

| File | Function/area | API | Purpose | Authentication | Should remain client-side? |
| --- | --- | --- | --- | --- | --- |
| `lib/app/send_package/bloc/send_package_bloc.dart` | destination route preview after pickup/drop-off selection | Directions API | Polyline and route distance preview | `GOOGLE_MAPS_DIRECTIONS_API_KEY` | Short term yes; long term move behind Firebase Functions for stronger key restriction and canonical distance. |
| `lib/website/shared/circum_website_app.dart` | `_googlePlacesAutocomplete` | Places Autocomplete API | Address suggestions | `GOOGLE_PLACES_API_KEY` | Move behind Firebase Functions. |
| `lib/website/shared/circum_website_app.dart` | `_googlePlaceDetails` | Place Details API | Coordinates and formatted address | `GOOGLE_PLACES_API_KEY` | Move behind Firebase Functions. |
| `lib/website/shared/circum_website_app.dart` | `_googleFindPlaceFromText` | Find Place API | Manual/typed address verification | `GOOGLE_PLACES_API_KEY` | Move behind Firebase Functions. |
| `lib/website/shared/circum_website_app.dart` | geocode request block | Geocoding API | Convert typed address to coordinates | `GOOGLE_PLACES_API_KEY` | Move behind Firebase Functions. |
| `lib/website/shared/circum_website_app.dart` | static map URL builder | Maps Static API | Receipt/summary-style map image URL | `GOOGLE_PLACES_API_KEY` | Move behind Firebase Functions or signed static map generation. |

Routes API is not used.

## Recommended Key Architecture

Keep platform SDK keys separate because Google Cloud API key application restrictions are platform-specific.

Required repository secrets today:

- `CIRCUM_WEB_GOOGLE_MAPS_API_KEY`: Sender Web map rendering, HTTP referrer restricted, Maps JavaScript API only.
- `SENDER_ANDROID_GOOGLE_MAPS_API_KEY`: Sender Android native map SDK, Android package/SHA restricted, Maps SDK for Android only.
- `RIDER_ANDROID_GOOGLE_MAPS_API_KEY`: Rider Android native map SDK, Android package/SHA restricted, Maps SDK for Android only.
- `GOOGLE_MAPS_DIRECTIONS_API_KEY`: temporary shared client-side Sender/Rider route preview key, API restricted to Directions API.
- `GOOGLE_PLACES_API_KEY`: temporary public website REST key, API restricted to Places, Geocoding, and Static Maps.

Reserved future iOS CI secrets:

- `SENDER_IOS_GOOGLE_MAPS_API_KEY`: Sender iOS native map SDK, iOS bundle restricted to `com.circum.app`, Maps SDK for iOS only.
- `RIDER_IOS_GOOGLE_MAPS_API_KEY`: Rider iOS native map SDK, iOS bundle restricted to `com.circum.rider`, Maps SDK for iOS only.

iOS builds currently consume `GOOGLE_MAPS_API_KEY` through Xcode build settings and there is no active iOS CI workflow. When iOS CI is enabled, the repository command should pass the product-specific secret into the existing build setting without code changes:

```bash
GOOGLE_MAPS_API_KEY="$SENDER_IOS_GOOGLE_MAPS_API_KEY" flutter build ipa --release --target=lib/main.dart
```

## Recommended Firebase Function Proxy

Long-term target:

1. Create backend functions for address autocomplete, place details, geocoding, static map URL generation, and route preview.
2. Store Google REST keys only in Cloud Functions secrets.
3. Apply App Check, auth, rate limits, and per-user quota.
4. Cache Places/Geocoding responses by normalized query and session token where licensing allows.
5. Cache route previews by rounded origin/destination and mode for short TTLs.
6. Return canonical distance/route metadata to clients.
7. Remove client-side `GOOGLE_PLACES_API_KEY` and `GOOGLE_MAPS_DIRECTIONS_API_KEY` after parity tests pass.

Migration order:

1. Public Website Places Autocomplete and Details.
2. Public Website Geocoding.
3. Sender mobile Directions route preview.
4. Static Maps generation.
5. Delete client-side REST key build requirements.

## Manual Console Actions

These cannot be completed from the repository.

1. Google Cloud Console -> APIs & Services -> Library -> Enable APIs.
   Button: Enable.
   Values: Maps SDK for Android, Maps SDK for iOS, Maps JavaScript API, Directions API, Places API, Geocoding API, Maps Static API.
   Why: code calls these APIs.
   Blocking: yes.
   Estimate: 5 minutes.

2. Google Cloud Console -> APIs & Services -> Credentials -> Sender Web key.
   Button: Edit API key.
   Values: HTTP referrers `https://circum-app-2797c.web.app/*`; API restriction Maps JavaScript API.
   Why: Sender Web map script is public and must be referrer restricted.
   Blocking: yes.
   Estimate: 3 minutes.

3. Google Cloud Console -> APIs & Services -> Credentials -> Sender Android key.
   Button: Edit API key.
   Values: package `com.circum.app`; upload SHA-1 `00:37:09:93:0D:C7:F1:4C:96:B7:CB:28:55:7F:09:83:60:AA:4A:91`; API restriction Maps SDK for Android.
   Why: Android SDK key must match app package and signing certificate.
   Blocking: yes.
   Estimate: 3 minutes.

4. Google Cloud Console -> APIs & Services -> Credentials -> Rider Android key.
   Button: Edit API key.
   Values: package `com.circum.rider`; upload SHA-1 `96:2E:01:F3:B1:AA:DF:96:C1:23:62:CB:4A:7F:83:42:9D:F5:08:8E`; API restriction Maps SDK for Android.
   Why: Android SDK key must match app package and signing certificate.
   Blocking: yes.
   Estimate: 3 minutes.

5. Google Play Console -> each app -> Setup -> App integrity.
   Button: copy App signing certificate SHA-1.
   Values: add the Play app-signing SHA-1 to the matching Google Cloud Android key and Firebase Android app if it differs from the upload SHA-1.
   Why: Play Store installs are signed by Play App Signing, not necessarily the upload key.
   Blocking: yes for Play installs.
   Estimate: 5 minutes.

6. Firebase Console -> Project settings -> Your apps -> Android apps.
   Button: Add fingerprint.
   Values: Sender SHA-1 `00:37:09:93:0D:C7:F1:4C:96:B7:CB:28:55:7F:09:83:60:AA:4A:91`; Rider SHA-1 `96:2E:01:F3:B1:AA:DF:96:C1:23:62:CB:4A:7F:83:42:9D:F5:08:8E`; plus Play app-signing SHA-1s if different.
   Why: Firebase Android app identity must match release certificates.
   Blocking: yes.
   Estimate: 5 minutes.

7. GitHub -> repository Settings -> Secrets and variables -> Actions.
   Button: New repository secret.
   Values: `CIRCUM_WEB_GOOGLE_MAPS_API_KEY`, `SENDER_ANDROID_GOOGLE_MAPS_API_KEY`, `RIDER_ANDROID_GOOGLE_MAPS_API_KEY`, `GOOGLE_PLACES_API_KEY`, `GOOGLE_MAPS_DIRECTIONS_API_KEY`.
   Why: CI build scripts now fail if these required keys are absent.
   Blocking: yes.
   Estimate: 5 minutes.

8. Future only, when iOS CI is enabled -> GitHub -> repository Settings -> Secrets and variables -> Actions.
   Button: New repository secret.
   Values: `SENDER_IOS_GOOGLE_MAPS_API_KEY`, `RIDER_IOS_GOOGLE_MAPS_API_KEY`.
   Why: iOS already reads `GOOGLE_MAPS_API_KEY`; future CI should map the product-specific secret into that existing Xcode build setting.
   Blocking: no until iOS CI is enabled.
   Estimate: 2 minutes.
