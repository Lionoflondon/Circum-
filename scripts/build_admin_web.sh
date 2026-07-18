#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/web_admin"
echo "Project: circum-2797c"
echo "Surface: Admin Web"
echo "Entrypoint: lib/main.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-admin-web"

rm -rf "$ROOT_DIR/build/web" "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --target=lib/main.dart \
  --dart-define=CIRCUM_ADMIN_HOSTING=true
mv "$ROOT_DIR/build/web" "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/finalize_web_artifact.js" admin "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=admin
