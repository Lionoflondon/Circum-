#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-changed}"
shift || true

case "$TARGET" in
  changed|sender|website|admin|functions|storage|rules|indexes|all)
    node scripts/release_orchestrator.js "$TARGET" "$@"
    ;;
  --self-test)
    node scripts/release_orchestrator.js --self-test
    ;;
  *)
    echo "Usage: ./safe_release.sh [changed|sender|website|admin|functions|storage|rules|indexes|all] [--full] [--deploy]" >&2
    echo "       ./safe_release.sh --self-test" >&2
    exit 64
    ;;
esac
