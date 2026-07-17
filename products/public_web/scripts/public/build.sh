#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
flutter build web --release --no-wasm-dry-run --target lib/main.dart
if [[ -e build/web_public ]]; then
  echo "build/web_public must be absent before build" >&2
  exit 1
fi
mv build/web build/web_public
node scripts/public/manifest.js
node scripts/public/validate_public.js
