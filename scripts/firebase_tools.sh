#!/usr/bin/env bash

resolve_tool() {
  local name="$1"
  local candidate
  for candidate in "$ROOT_DIR/../$name" "$ROOT_DIR/../../$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' "$name"
}

FLUTTER_BIN="$(resolve_tool flutter)/bin/flutter"
FIREBASE_BIN="$(resolve_tool firebase)"
