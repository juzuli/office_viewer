#!/usr/bin/env bash
# Run example_app with PDF + DartOfficeEngine.
# Usage: ./tool/run_dart_engine.sh [device-id]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
cd "$ROOT"
flutter pub get
if [[ "$(uname -s)" == "Darwin" ]] && [[ -d ios ]]; then
  (cd ios && pod install)
fi
ARGS=(run)
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi
exec flutter "${ARGS[@]}"
