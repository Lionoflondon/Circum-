#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy_isolated.sh <website|public|admin> [--branch <ref>] [--commit <sha>]... [--patch <file>]...

Production deployments must never run from the active working tree. This script:
  1. creates a fresh temporary git worktree from the requested branch/ref;
  2. applies only explicitly approved commits/patches, if provided;
  3. verifies the deployment workspace is clean and isolated;
  4. runs validation/build/artifact gates in the deployment workspace;
  5. deploys only the requested hosting target;
  6. removes the temporary worktree.

Examples:
  scripts/deploy_isolated.sh website --branch origin/main
  scripts/deploy_isolated.sh website --branch origin/main --commit abc1234
  scripts/deploy_isolated.sh public --branch main --patch /tmp/approved.diff
USAGE
}

fail() {
  echo "ISOLATED DEPLOYMENT FAILED: $*" >&2
  exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

SURFACE="$1"
shift

REQUESTED_REF="origin/main"
APPROVED_COMMITS=()
APPROVED_PATCHES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch|--ref)
      [[ $# -ge 2 ]] || fail "$1 requires a value"
      REQUESTED_REF="$2"
      shift 2
      ;;
    --commit)
      [[ $# -ge 2 ]] || fail "--commit requires a value"
      APPROVED_COMMITS+=("$2")
      shift 2
      ;;
    --patch)
      [[ $# -ge 2 ]] || fail "--patch requires a value"
      APPROVED_PATCHES+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$SURFACE" in
  website|public)
    BUILD_SCRIPT="scripts/build_public_web.sh"
    HOSTING_TARGET="hosting:public"
    OUTPUT_DIR="build/public_web"
    ENTRYPOINT="lib/main_public_web.dart"
    EXPECTED_IDENTITY="circum-website"
    ALLOWED_PREFIXES=(
      "lib/main_public_web.dart"
      "lib/app/security/"
      "lib/web_platform_routing.dart"
      "lib/website/"
      "test/security/"
      "test/web_platform_routing_test.dart"
      "scripts/"
      "docs/"
      "README.md"
      "pubspec.yaml"
      "pubspec.lock"
    )
    FORBIDDEN_IMPORT_REGEX="main_sender_web|main_rider_web|main_admin_web|app/sender_mobile|app/admin"
    ;;
  admin)
    BUILD_SCRIPT="scripts/build_admin_web.sh"
    HOSTING_TARGET="hosting:admin"
    OUTPUT_DIR="build/web_admin"
    ENTRYPOINT="lib/main.dart"
    EXPECTED_IDENTITY="circum-admin-web"
    ALLOWED_PREFIXES=(
      "lib/main.dart"
      "lib/app/security/"
      "lib/website/shared/circum_website_app.dart"
      "test/security/"
      "test/web_platform_routing_test.dart"
      "scripts/"
      "docs/"
      "README.md"
      "pubspec.yaml"
      "pubspec.lock"
    )
    FORBIDDEN_IMPORT_REGEX="main_sender_web|main_public_web|main_rider_web"
    ;;
  *)
    fail "unknown surface '$SURFACE'. Expected website, public, or admin."
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "Active working tree is dirty. That is allowed, but it will not be deployed."
fi

git rev-parse --verify "$REQUESTED_REF^{commit}" >/dev/null ||
  fail "requested ref does not resolve to a commit: $REQUESTED_REF"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/circum-isolated-deploy.XXXXXX")"
WORKTREE="$TMP_ROOT/worktree"

cleanup() {
  set +e
  cd "$ROOT_DIR" >/dev/null 2>&1 || true
  git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "Creating isolated deployment workspace from $REQUESTED_REF"
git worktree add --detach "$WORKTREE" "$REQUESTED_REF" >/dev/null
cd "$WORKTREE"

BASE_REV="$(git rev-parse HEAD)"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  fail "deployment workspace is dirty immediately after checkout"
fi

if [[ ${#APPROVED_COMMITS[@]} -gt 0 ]]; then
  for commit in "${APPROVED_COMMITS[@]}"; do
    echo "Applying approved commit $commit"
    git cherry-pick "$commit"
  done
fi

if [[ ${#APPROVED_PATCHES[@]} -gt 0 ]]; then
  git config user.name "Circum Isolated Deployment"
  git config user.email "deploy@circum.local"
  for patch in "${APPROVED_PATCHES[@]}"; do
    [[ -f "$patch" ]] || fail "approved patch not found: $patch"
    echo "Applying approved patch $patch"
    git apply --index "$patch"
  done
  git commit -m "Apply approved isolated deployment patch"
fi

HEAD_REV="$(git rev-parse HEAD)"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  fail "deployment workspace has uncommitted changes after applying approved input"
fi

is_allowed_file() {
  local file="$1"
  local prefix
  for prefix in "${ALLOWED_PREFIXES[@]}"; do
    if [[ "$file" == "$prefix" || "$file" == "$prefix"* ]]; then
      return 0
    fi
  done
  return 1
}

CHANGED_FILES="$(git diff --name-only "$BASE_REV..$HEAD_REV")"
if [[ -n "$CHANGED_FILES" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if ! is_allowed_file "$file"; then
      fail "approved change outside $SURFACE deployment scope: $file"
    fi
  done <<< "$CHANGED_FILES"
fi

rm -rf build/web build/public_web build/sender_app_web build/web_admin .dart_tool/build

source "$WORKTREE/scripts/firebase_tools.sh"

echo "Isolated deployment"
echo "Surface: $SURFACE"
echo "Project: circum-2797c"
echo "Source ref: $REQUESTED_REF"
echo "Base revision: $BASE_REV"
echo "Deploy revision: $HEAD_REV"
echo "Entrypoint: $ENTRYPOINT"
echo "Output: $OUTPUT_DIR"
echo "Hosting target: $HOSTING_TARGET"
echo "Expected identity: $EXPECTED_IDENTITY"

if rg -n "$FORBIDDEN_IMPORT_REGEX" "$ENTRYPOINT" >/tmp/circum-isolated-imports.$$ 2>/dev/null; then
  cat /tmp/circum-isolated-imports.$$
  rm -f /tmp/circum-isolated-imports.$$
  fail "$SURFACE entrypoint imports or references a forbidden cross-surface marker"
fi
rm -f /tmp/circum-isolated-imports.$$

"$FLUTTER_BIN" clean
"$FLUTTER_BIN" pub get
ANALYZE_LOG="$(mktemp "${TMPDIR:-/tmp}/circum-flutter-analyze.XXXXXX")"
set +e
"$FLUTTER_BIN" analyze --no-fatal-warnings --no-fatal-infos 2>&1 | tee "$ANALYZE_LOG"
ANALYZE_STATUS=${PIPESTATUS[0]}
set -e
if grep -Eq '(^|[[:space:]])error •' "$ANALYZE_LOG"; then
  fail "flutter analyze reported source errors"
fi
if [[ $ANALYZE_STATUS -ne 0 ]]; then
  echo "flutter analyze exited $ANALYZE_STATUS with warnings/info only; continuing."
fi
"$FLUTTER_BIN" test
node "$WORKTREE/scripts/validate_web_artifacts.js" --config-only
"$WORKTREE/$BUILD_SCRIPT"
node "$WORKTREE/scripts/validate_web_artifacts.js" --surface="$SURFACE"
git restore \
  macos/Flutter/GeneratedPluginRegistrant.swift \
  windows/flutter/generated_plugin_registrant.cc \
  windows/flutter/generated_plugins.cmake 2>/dev/null || true

if [[ -n "$(git status --porcelain=v1 --untracked-files=all -- ':!build' ':!.dart_tool' ':!.packages')" ]]; then
  fail "deployment workspace became dirty outside generated build artifacts"
fi

"$FIREBASE_BIN" deploy --only "$HOSTING_TARGET" --project circum-2797c

echo "Isolated deployment complete for $SURFACE at $HEAD_REV"
