#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "DEPLOYMENT BLOCKED"
echo "Sender Web is part of the Circum Website boundary."
echo "Use scripts/deploy_public_web.sh to deploy the Website."
exit 1
