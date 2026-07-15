#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

node scripts/guard_public_web_architecture.js
"$FLUTTER_BIN" test --no-pub test/hosting_isolation_test.dart
node --test test/hosting_manifest_test.js
rm -rf build/web build/web_main
"$FLUTTER_BIN" build web --release --no-wasm-dry-run --target lib/public_web/main_public.dart
mv build/web build/web_main
node scripts/prepare_public_hosting_output.js
node scripts/guard_public_web_architecture.js
node scripts/hosting_manifest.js prepare public
scripts/verify_hosting_build.sh public

"$FIREBASE_BIN" deploy --only hosting:public --project circum-2797c
scripts/verify_hosting_domains.sh
