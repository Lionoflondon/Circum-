#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Project: circum-2797c"
echo "Surface: Admin Web"
echo "Entrypoint: lib/main.dart"
echo "Output: build/web_admin"
echo "Hosting target: hosting:admin"
echo "Expected identity: circum-admin-web"

"$ROOT_DIR/scripts/deploy_isolated.sh" admin "$@"
