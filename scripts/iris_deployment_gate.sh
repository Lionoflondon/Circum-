#!/usr/bin/env bash
set -euo pipefail

export FLUTTER_DISABLE_ANALYTICS=true
export HOME="${HOME:-$PWD}"

FLUTTER_BIN="${FLUTTER_BIN:-../../flutter-arm64-sdk/flutter/bin/flutter}"

"$FLUTTER_BIN" test --no-pub test/iris_protected_baseline_test.dart
"$FLUTTER_BIN" test --no-pub test/iris_weight_estimator_test.dart
"$FLUTTER_BIN" test --no-pub test/delivery_pricing_test.dart
"$FLUTTER_BIN" test --no-pub
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" build web --release --no-wasm-dry-run
