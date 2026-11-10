#!/usr/bin/env bash
# Fast iOS UI iteration — stub plugin (no 375 LO archives, ~seconds not minutes).
# Still registers DartOfficeEngine for Office if you pass
#   --dart-define=OFFICE_VIEWER_USE_LOK=false
# Prefer ./tool/run_dart_engine.sh for a Dart-only Office loop.
# For real LOK tiles use ios_run_lok.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
export OFFICE_VIEWER_LINK_LOK_IOS=0
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
