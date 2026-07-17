#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

OUTPUT_DIR="$ROOT_DIR/build/sender_app_web"
echo "Project: circum-2797c"
echo "Surface: Sender App Web"
echo "Entrypoint: lib/main_sender_web.dart"
echo "Output: $OUTPUT_DIR"
echo "Identity: circum-sender-web"

rm -rf "$OUTPUT_DIR"
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --dart-define=CIRCUM_WEB_SURFACE=sender \
  --target=lib/main_sender_web.dart \
  --output="$OUTPUT_DIR"
node "$ROOT_DIR/scripts/finalize_web_artifact.js" sender "$OUTPUT_DIR"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=sender
