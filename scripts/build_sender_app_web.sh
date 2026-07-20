#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/sender_app_web"
WEB_RECAPTCHA_SITE_KEY="${CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY:-}"

if [[ -z "$WEB_RECAPTCHA_SITE_KEY" ]]; then
  echo "Missing CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY for Sender App Web App Check." >&2
  exit 1
fi

echo "Project: circum-2797c"
echo "Surface: Sender App"
echo "Entrypoint: lib/app/sender_mobile/sender_mobile_preview.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-sender-web"

"$FLUTTER_BIN" clean
rm -rf "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY="$WEB_RECAPTCHA_SITE_KEY" \
  --target=lib/app/sender_mobile/sender_mobile_preview.dart \
  --output="$OUTPUT_DIR"
node "$ROOT_DIR/scripts/finalize_web_artifact.js" sender-app "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=sender-app
