#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Project: circum-2797c"
echo "Surface: Sender App Web"
echo "Entrypoint: lib/main_sender_web.dart"
echo "Output: build/sender_app_web"
echo "Hosting target: hosting:app"
echo "Expected identity: circum-sender-web"

"$ROOT_DIR/scripts/deploy_isolated.sh" sender "$@"
