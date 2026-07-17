#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

echo "Project: circum-2797c"
echo "Surface: Public Web"
echo "Entrypoint: lib/main_public_web.dart"
echo "Output: build/public_web"
echo "Hosting target: hosting:public"
echo "Expected identity: circum-public-web"

"$ROOT_DIR/scripts/build_public_web.sh"
"$FIREBASE_BIN" deploy --only hosting:public --project circum-2797c
