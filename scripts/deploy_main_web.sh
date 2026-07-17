#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

cat >&2 <<'EOF'
deploy_main_web.sh is intentionally disabled.

Public Web and Sender App Web must be built and deployed as isolated artifacts.
Use one of:
  scripts/deploy_public_web.sh
  scripts/deploy_sender_app_web.sh
EOF
exit 1
