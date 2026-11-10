#!/usr/bin/env bash
# Publish core + engines to pub.dev.
# Order: office_viewer → office_viewer_engine_dart → office_viewer_engine_convert
# (engines depend on core; convert depends on dart).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${FLUTTER_PATH:-$HOME/fvm/versions/3.47.9/bin}:$PATH"

echo "==> Publishing office_viewer from repo root"
flutter pub publish "$@"

PUBIGNORE_BAK=
if [[ -f .pubignore ]]; then
  mv .pubignore .pubignore.publish_bak
  PUBIGNORE_BAK=1
fi
cleanup() {
  if [[ -n "${PUBIGNORE_BAK:-}" && -f .pubignore.publish_bak ]]; then
    mv .pubignore.publish_bak .pubignore
  fi
}
trap cleanup EXIT

echo "==> Publishing office_viewer_engine_dart (root .pubignore temporarily moved)"
cd packages/office_viewer_engine_dart
flutter pub publish "$@"
cd "$ROOT"

echo "==> Publishing office_viewer_engine_convert"
cd packages/office_viewer_engine_convert
flutter pub publish "$@"
cd "$ROOT"

echo "==> Done"
