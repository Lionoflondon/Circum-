#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/web_admin
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --target=lib/main.dart \
  --dart-define=CIRCUM_ADMIN_HOSTING=true
mv build/web build/web_admin
node "$ROOT_DIR/scripts/finalize_web_artifact.js" admin "$ROOT_DIR/build/web_admin"
node "$ROOT_DIR/scripts/validate_web_artifacts.js" --surface=admin
"$FIREBASE_BIN" deploy --only hosting:admin --project circum-2797c
