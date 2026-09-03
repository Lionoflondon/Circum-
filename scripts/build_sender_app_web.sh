#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/sender_app_web"
SYMBOLS_ROOT="$ROOT_DIR/build/release_symbols/sender_app_web"
WEB_RECAPTCHA_SITE_KEY="${CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY:-}"
WEB_GOOGLE_MAPS_API_KEY="${CIRCUM_WEB_GOOGLE_MAPS_API_KEY:-}"
STRIPE_PUBLISHABLE_KEY_VALUE="${STRIPE_PUBLISHABLE_KEY:-}"
PAYMENT_ENVIRONMENT_VALUE="${PAYMENT_ENVIRONMENT:-}"
BUILD_HASH="$(git rev-parse HEAD)"
RELEASE_TAG="${CIRCUM_RELEASE_TAG:-$(git describe --tags --exact-match HEAD 2>/dev/null || git describe --tags --always --dirty)}"
DIAGNOSTICS_PANEL="${CIRCUM_WEB_DIAGNOSTICS_PANEL:-false}"
EXTRA_FLUTTER_BUILD_ARGS=()
if [[ -n "${CIRCUM_SENDER_WEB_EXTRA_BUILD_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FLUTTER_BUILD_ARGS=(${CIRCUM_SENDER_WEB_EXTRA_BUILD_ARGS})
fi

if [[ -z "$WEB_RECAPTCHA_SITE_KEY" ]]; then
  echo "Missing CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY for Sender App Web App Check." >&2
  exit 1
fi

if [[ -z "$WEB_GOOGLE_MAPS_API_KEY" ]]; then
  echo "Missing CIRCUM_WEB_GOOGLE_MAPS_API_KEY for Sender App Web Google Maps." >&2
  exit 1
fi

if [[ -z "$STRIPE_PUBLISHABLE_KEY_VALUE" ]]; then
  echo "Missing STRIPE_PUBLISHABLE_KEY for Sender App payments." >&2
  exit 1
fi

PAYMENT_ENVIRONMENT="$PAYMENT_ENVIRONMENT_VALUE" \
  STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY_VALUE" \
  "$ROOT_DIR/scripts/validate_sender_payment_environment.sh"

echo "Project: circum-2797c"
echo "Surface: Sender App"
echo "Entrypoint: lib/app/sender_mobile/sender_mobile_preview.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-sender-web"
echo "Build hash: $BUILD_HASH"
echo "Release tag: $RELEASE_TAG"

rm -rf "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --source-maps \
  --no-wasm-dry-run \
  --no-web-resources-cdn \
  ${EXTRA_FLUTTER_BUILD_ARGS+"${EXTRA_FLUTTER_BUILD_ARGS[@]}"} \
  --dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY="$WEB_RECAPTCHA_SITE_KEY" \
  --dart-define=STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY_VALUE" \
  --dart-define=PAYMENT_ENVIRONMENT="$PAYMENT_ENVIRONMENT_VALUE" \
  --dart-define=CIRCUM_BUILD_HASH="$BUILD_HASH" \
  --dart-define=CIRCUM_RELEASE_TAG="$RELEASE_TAG" \
  --dart-define=CIRCUM_WEB_DIAGNOSTICS_PANEL="$DIAGNOSTICS_PANEL" \
  --target=lib/app/sender_mobile/sender_mobile_preview.dart \
  --output="$OUTPUT_DIR"

node - "$OUTPUT_DIR/index.html" "$WEB_GOOGLE_MAPS_API_KEY" <<'NODE'
const fs = require('fs');
const [indexPath, apiKey] = process.argv.slice(2);
let html = fs.readFileSync(indexPath, 'utf8');
const mapsScript = `<script src="https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}"></script>`;
if (!html.includes('maps.googleapis.com/maps/api/js')) {
  html = html.replace('</head>', `  ${mapsScript}\n</head>`);
}
fs.writeFileSync(indexPath, html);
NODE

SYMBOLS_DIR="$SYMBOLS_ROOT/$BUILD_HASH"
rm -rf "$SYMBOLS_DIR"
mkdir -p "$SYMBOLS_DIR"
find "$OUTPUT_DIR" -name '*.map' -type f -print0 | while IFS= read -r -d '' map_file; do
  relative_path="${map_file#$OUTPUT_DIR/}"
  mkdir -p "$SYMBOLS_DIR/$(dirname "$relative_path")"
  cp "$map_file" "$SYMBOLS_DIR/$relative_path"
  rm "$map_file"
done
if [[ -f "$OUTPUT_DIR/main.dart.js" ]]; then
  perl -0pi -e 's/\n\/\/# sourceMappingURL=main\.dart\.js\.map\s*$//' "$OUTPUT_DIR/main.dart.js"
fi
node "$ROOT_DIR/scripts/finalize_web_artifact.js" sender-app "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=sender-app
