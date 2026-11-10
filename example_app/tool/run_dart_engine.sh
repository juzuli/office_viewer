#!/usr/bin/env bash
# Run example_app with LOK disabled so Office files use DartOfficeEngine.
# Usage: ./tool/run_dart_engine.sh [device-id]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
# Avoid linking/building LOK on iOS for a faster Dart-only loop.
export OFFICE_VIEWER_LINK_LOK_IOS=0
cd "$ROOT"
flutter pub get
if [[ "$(uname -s)" == "Darwin" ]] && [[ -d ios ]]; then
  (cd ios && pod install)
fi
ARGS=(run --dart-define=OFFICE_VIEWER_USE_LOK=false)
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi
exec flutter "${ARGS[@]}"
