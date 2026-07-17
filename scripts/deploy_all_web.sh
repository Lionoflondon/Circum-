#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/public_web build/sender_app_web build/web_admin

"$ROOT_DIR/scripts/build_public_web.sh"
"$ROOT_DIR/scripts/build_sender_app_web.sh"

"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --target=lib/main.dart \
  --dart-define=CIRCUM_ADMIN_HOSTING=true
mv build/web build/web_admin
node "$ROOT_DIR/scripts/finalize_web_artifact.js" admin "$ROOT_DIR/build/web_admin"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=admin

"$FIREBASE_BIN" deploy --only hosting:public,hosting:app,hosting:admin --project circum-2797c
