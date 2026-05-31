#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

rm -rf build/web build/web_main
../flutter/bin/flutter build web --release --no-wasm-dry-run
mv build/web build/web_main
../firebase deploy --only hosting:main --project circum-2797c
