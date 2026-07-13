#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fetch() {
  local label="$1"
  local url="$2"
  local output="$3"
  local status
  status="$(curl -sS -L -w '%{http_code}' -o "$output" "$url")"
  if [[ "$status" != "200" ]]; then
    echo "Hosting domain verification failed: $label returned HTTP $status ($url)." >&2
    exit 1
  fi
}

assert_manifest() {
  local label="$1"
  local file="$2"
  local product="$3"
  local site="$4"
  local target="$5"
  node - "$label" "$file" "$product" "$site" "$target" <<'NODE'
const fs = require('fs');
const [label, file, product, site, target] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
const expected = {product, hostingSiteId: site, targetAlias: target};
for (const [key, value] of Object.entries(expected)) {
  if (manifest[key] !== value) {
    throw new Error(`${label} served ${key}=${manifest[key]} instead of ${value}`);
  }
}
NODE
}

fetch "Admin custom domain" https://admin.circumuk.com/ "$TMP_DIR/admin-custom.html"
fetch "Admin canonical site" https://circum-admin-2797c.web.app/ "$TMP_DIR/admin-direct.html"
fetch "Circum Web custom domain" https://circumuk.com/ "$TMP_DIR/public-custom.html"
fetch "Circum Web www custom domain" https://www.circumuk.com/ "$TMP_DIR/public-www.html"
fetch "Circum Web canonical site" https://circum-2797c.web.app/ "$TMP_DIR/public-direct.html"
fetch "Circum Web manifest" https://circum-2797c.web.app/deployment-manifest.json "$TMP_DIR/public-direct-manifest.json"
fetch "Circum Web custom manifest" https://circumuk.com/deployment-manifest.json "$TMP_DIR/public-custom-manifest.json"
fetch "Circum Web www manifest" https://www.circumuk.com/deployment-manifest.json "$TMP_DIR/public-www-manifest.json"
fetch "Sender app manifest" https://circum-app-2797c.web.app/deployment-manifest.json "$TMP_DIR/sender-manifest.json"
fetch "Rider app manifest" https://circum-rider-2797c.web.app/deployment-manifest.json "$TMP_DIR/rider-manifest.json"

assert_manifest "Circum Web canonical site" "$TMP_DIR/public-direct-manifest.json" "Circum Web" "circum-2797c" "public"
assert_manifest "Circum Web custom domain" "$TMP_DIR/public-custom-manifest.json" "Circum Web" "circum-2797c" "public"
assert_manifest "Circum Web www custom domain" "$TMP_DIR/public-www-manifest.json" "Circum Web" "circum-2797c" "public"
assert_manifest "Sender app canonical site" "$TMP_DIR/sender-manifest.json" "Circum Sender App" "circum-app-2797c" "sender"
assert_manifest "Rider app canonical site" "$TMP_DIR/rider-manifest.json" "Circum Rider Web" "circum-rider-2797c" "rider"

cmp "$TMP_DIR/admin-custom.html" "$TMP_DIR/admin-direct.html"
cmp "$TMP_DIR/public-custom.html" "$TMP_DIR/public-direct.html"
cmp "$TMP_DIR/public-www.html" "$TMP_DIR/public-direct.html"

if cmp -s "$TMP_DIR/admin-custom.html" "$TMP_DIR/public-custom.html"; then
  echo "Domain isolation failed: Admin and public shells are identical." >&2
  exit 1
fi

echo "Circum Web, Sender App, Rider App and Admin Hosting domains match their canonical sites."
