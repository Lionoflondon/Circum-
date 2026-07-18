#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/public_web"
WEB_RECAPTCHA_SITE_KEY="${CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY:-}"

if [[ -z "$WEB_RECAPTCHA_SITE_KEY" ]]; then
  echo "Missing CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY for Public Web App Check." >&2
  exit 1
fi

echo "Project: circum-2797c"
echo "Surface: Public Web"
echo "Entrypoint: lib/main_public_web.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-public-web"

rm -rf "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --dart-define=CIRCUM_WEB_SURFACE=public \
  --dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY="$WEB_RECAPTCHA_SITE_KEY" \
  --target=lib/main_public_web.dart \
  --output="$OUTPUT_DIR"
node "$ROOT_DIR/scripts/finalize_web_artifact.js" public "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=public
