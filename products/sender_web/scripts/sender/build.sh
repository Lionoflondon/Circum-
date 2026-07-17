#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
flutter build web --release --no-wasm-dry-run --target lib/main.dart
if [[ -e build/web_sender ]]; then
  echo "build/web_sender must be absent before build" >&2
  exit 1
fi
mv build/web build/web_sender
node scripts/sender/manifest.js
node scripts/sender/validate_sender.js
