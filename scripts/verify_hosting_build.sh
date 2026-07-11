#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
cd "$ROOT_DIR"

case "$MODE" in
  admin)
    TARGET_ALIAS="admin"
    EXPECTED_SITE="circum-admin-2797c"
    OUTPUT="build/web_admin"
    MARKER="admin"
    REQUIRED_BUNDLE_MARKER="CIRCUM_ADMIN_PORTAL_CANONICAL_V1"
    FORBIDDEN_COPY="Send anything across town"
    ;;
  public)
    TARGET_ALIAS="public"
    EXPECTED_SITE="circum-2797c"
    OUTPUT="build/web_main"
    MARKER="sender"
    REQUIRED_BUNDLE_MARKER="Send anything across town"
    FORBIDDEN_COPY="CIRCUM_ADMIN_PORTAL_CANONICAL_V1"
    ;;
  *)
    echo "Usage: $0 admin|public" >&2
    exit 2
    ;;
esac

if ! grep -Fq "\"$TARGET_ALIAS\"" .firebaserc ||
   ! grep -Fq "\"$EXPECTED_SITE\"" .firebaserc; then
  echo "Refusing deployment: hosting:$TARGET_ALIAS is not mapped to $EXPECTED_SITE." >&2
  exit 1
fi

if [ ! -f "$OUTPUT/circum-build-target.txt" ] ||
   [ "$(cat "$OUTPUT/circum-build-target.txt")" != "$MARKER" ]; then
  echo "Refusing deployment: $OUTPUT has the wrong build marker." >&2
  exit 1
fi

if [ ! -s "$OUTPUT/main.dart.js" ] || [ ! -s "$OUTPUT/index.html" ]; then
  echo "Refusing deployment: $OUTPUT is not a complete Flutter web build." >&2
  exit 1
fi

if ! grep -Fq "$REQUIRED_BUNDLE_MARKER" "$OUTPUT/main.dart.js"; then
  echo "Refusing deployment: $OUTPUT does not contain $REQUIRED_BUNDLE_MARKER." >&2
  exit 1
fi

if grep -Fq "$FORBIDDEN_COPY" "$OUTPUT/main.dart.js"; then
  echo "Refusing deployment: $OUTPUT contains forbidden cross-surface content." >&2
  exit 1
fi

echo "Verified hosting:$TARGET_ALIAS -> $EXPECTED_SITE using $OUTPUT."
