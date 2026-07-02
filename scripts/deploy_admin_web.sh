#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/web_admin
"$FLUTTER_BIN" build web \
  --release \
  --no-wasm-dry-run \
  --dart-define=CIRCUM_ADMIN_HOSTING=true
mv build/web build/web_admin
printf "admin\n" > build/web_admin/circum-build-target.txt

if [ "$(cat build/web_admin/circum-build-target.txt)" != "admin" ]; then
  echo "Refusing to deploy: build/web_admin is not marked as admin." >&2
  exit 1
fi

"$FIREBASE_BIN" deploy --only hosting:admin --project circum-2797c
