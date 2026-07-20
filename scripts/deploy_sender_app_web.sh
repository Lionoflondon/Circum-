#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/firebase_tools.sh"

echo "Project: circum-2797c"
echo "Surface: Sender App"
echo "Entrypoint: lib/app/sender_mobile/sender_mobile_preview.dart"
echo "Output: build/sender_app_web"
echo "Hosting target: hosting:app"
echo "Expected identity: circum-sender-web"

node "$ROOT_DIR/scripts/verify_sender_deployment_governance.js" --prebuild
"$ROOT_DIR/scripts/build_sender_app_web.sh"
node "$ROOT_DIR/scripts/verify_sender_deployment_governance.js" --postbuild --clean-clone
"$FIREBASE_BIN" deploy --only hosting:app --project circum-2797c
