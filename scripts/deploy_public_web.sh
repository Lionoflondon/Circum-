#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Project: circum-2797c"
echo "Surface: Circum Website"
echo "Entrypoint: lib/main_public_web.dart"
echo "Output: build/public_web"
echo "Hosting target: hosting:public"
echo "Expected identity: circum-public-web"

"$ROOT_DIR/scripts/deploy_isolated.sh" website "$@"
