#!/usr/bin/env bash
# Publish office_viewer then office_viewer_engine_dart to pub.dev.
# Order: core 0.0.8 first (engines depend on it).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${FLUTTER_PATH:-$HOME/fvm/versions/3.47.9/bin}:$PATH"

echo "==> Publishing office_viewer from repo root"
flutter pub publish "$@"

echo "==> Publishing office_viewer_engine_dart (root .pubignore temporarily moved)"
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

cd packages/office_viewer_engine_dart
flutter pub publish "$@"
cd "$ROOT"
echo "==> Done"
