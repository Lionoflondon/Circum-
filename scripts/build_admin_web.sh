#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/web_admin"
WEB_RECAPTCHA_SITE_KEY="${ADMIN_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY:-}"

if [[ -z "$WEB_RECAPTCHA_SITE_KEY" ]]; then
  echo "Missing ADMIN_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY for Admin Web App Check." >&2
  exit 1
fi

echo "Project: circum-2797c"
echo "Surface: Admin Web"
echo "Entrypoint: lib/main_admin_web.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-admin-web"

rm -rf "$ROOT_DIR/build/web" "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --target=lib/main_admin_web.dart \
  --dart-define=ADMIN_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY="$WEB_RECAPTCHA_SITE_KEY"
mv "$ROOT_DIR/build/web" "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/finalize_web_artifact.js" admin "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=admin
