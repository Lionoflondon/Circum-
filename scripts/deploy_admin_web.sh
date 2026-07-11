#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/web_admin
"$FLUTTER_BIN" build web \
  --target lib/main_admin.dart \
  --release \
  --no-wasm-dry-run
mv build/web build/web_admin
printf "admin\n" > build/web_admin/circum-build-target.txt

scripts/verify_hosting_build.sh admin

"$FIREBASE_BIN" deploy --only hosting:admin --project circum-2797c
