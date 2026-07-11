#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/web_main build/web_admin

"$FLUTTER_BIN" build web --release --no-wasm-dry-run
mv build/web build/web_main
printf "sender\n" > build/web_main/circum-build-target.txt

"$FLUTTER_BIN" build web \
  --target lib/main_admin.dart \
  --release \
  --no-wasm-dry-run
mv build/web build/web_admin
printf "admin\n" > build/web_admin/circum-build-target.txt

if cmp -s build/web_main/main.dart.js build/web_admin/main.dart.js; then
  echo "Refusing to deploy: sender and admin web builds are identical." >&2
  exit 1
fi

scripts/verify_hosting_build.sh public
scripts/verify_hosting_build.sh admin

"$FIREBASE_BIN" deploy --only hosting:public,hosting:app,hosting:admin --project circum-2797c
