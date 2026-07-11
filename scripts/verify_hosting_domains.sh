#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL https://admin.circumuk.com/ > "$TMP_DIR/admin-custom.html"
curl -fsSL https://circum-admin-2797c.web.app/ > "$TMP_DIR/admin-direct.html"
curl -fsSL https://circumuk.com/ > "$TMP_DIR/public-custom.html"
curl -fsSL https://www.circumuk.com/ > "$TMP_DIR/public-www.html"
curl -fsSL https://circum-2797c.web.app/ > "$TMP_DIR/public-direct.html"

cmp "$TMP_DIR/admin-custom.html" "$TMP_DIR/admin-direct.html"
cmp "$TMP_DIR/public-custom.html" "$TMP_DIR/public-direct.html"
cmp "$TMP_DIR/public-www.html" "$TMP_DIR/public-direct.html"

if cmp -s "$TMP_DIR/admin-custom.html" "$TMP_DIR/public-custom.html"; then
  echo "Domain isolation failed: Admin and public shells are identical." >&2
  exit 1
fi

echo "Admin and public custom domains match their canonical Hosting sites."
