#!/usr/bin/env bash
# Build-only preparation. Contains no deployment, upload or publication command.
set -euo pipefail
: "${BUILD_NAME:?Set BUILD_NAME after reconciling the store version}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER higher than every uploaded store build}"
python3 scripts/security-release-preflight.py
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
GOOGLE_MAPS_API_KEY="${ANDROID_GOOGLE_MAPS_API_KEY:?Set the restricted Android Maps key}" python3 scripts/provider-ready-build.py android
if [[ "$(uname -s)" == Darwin ]]; then
  (cd ios && pod install --deployment)
  GOOGLE_MAPS_API_KEY="${IOS_GOOGLE_MAPS_API_KEY:?Set the restricted iOS Maps key}" python3 scripts/provider-ready-build.py ios
fi
printf '%s\n' 'Local build preparation finished. Signing, device testing, store upload and rollout require separate review and approval.'
