#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

rm -rf build/web build/web_main
"$FLUTTER_BIN" build web --release --no-wasm-dry-run
mv build/web build/web_main
"$FIREBASE_BIN" deploy --only hosting:public,hosting:app --project circum-2797c
