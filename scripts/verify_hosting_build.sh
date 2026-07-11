#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
cd "$ROOT_DIR"
node scripts/hosting_manifest.js verify "$MODE"
