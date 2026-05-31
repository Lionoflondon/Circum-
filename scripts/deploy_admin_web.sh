#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

rm -rf build/web build/web_admin
../flutter/bin/flutter build web \
  --release \
  --no-wasm-dry-run \
  --dart-define=CIRCUM_ADMIN_HOSTING=true
mv build/web build/web_admin
../firebase deploy --only hosting:admin --project circum-2797c
