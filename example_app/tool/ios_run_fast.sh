#!/usr/bin/env bash
# Fast iOS UI iteration for example_app (PDF + Dart OOXML).
# Prefer ./tool/run_dart_engine.sh for the same loop with optional device id.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
cd "$ROOT"
flutter pub get
(
  cd ios
  pod install
)
if [[ -n "$DEVICE" ]]; then
  exec flutter run -d "$DEVICE"
else
  exec flutter run
fi
