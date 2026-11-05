#!/usr/bin/env bash
# Full iOS LOK run — links CPiOS static engine (~1GB app, slow install).
# Requires: packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-}"
export OFFICE_VIEWER_LINK_LOK_IOS=1
# Slim resources in Debug (drops ~180MB thesaurus/gallery/spell).
export OFFICE_VIEWER_IOS_SLIM_RESOURCES="${OFFICE_VIEWER_IOS_SLIM_RESOURCES:-1}"
cd "$ROOT"
flutter pub get
(
  cd ios
  pod install
)
ARGS=(run)
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi
exec flutter "${ARGS[@]}"
