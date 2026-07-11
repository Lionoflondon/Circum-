#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

"$FLUTTER_BIN" test --no-pub test/hosting_isolation_test.dart
node --test test/hosting_manifest_test.js
rm -rf build/web build/web_main
"$FLUTTER_BIN" build web --release --no-wasm-dry-run
mv build/web build/web_main
node scripts/hosting_manifest.js prepare public
scripts/verify_hosting_build.sh public

"$FIREBASE_BIN" deploy --only hosting:public,hosting:app --project circum-2797c
scripts/verify_hosting_domains.sh
