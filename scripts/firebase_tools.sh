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

if [[ -z "${FLUTTER_BIN:-}" ]]; then
  FLUTTER_ROOT="$(resolve_tool flutter)"
  if [[ -d "$FLUTTER_ROOT" && -x "$FLUTTER_ROOT/bin/flutter" ]]; then
    FLUTTER_BIN="$FLUTTER_ROOT/bin/flutter"
  else
    FLUTTER_BIN="$FLUTTER_ROOT"
  fi
fi
if [[ -z "${FIREBASE_BIN:-}" ]]; then
  FIREBASE_BIN="$(resolve_tool firebase)"
fi
export FLUTTER_BIN
export FIREBASE_BIN
