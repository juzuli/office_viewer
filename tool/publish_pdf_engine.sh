#!/usr/bin/env bash
# Publish office_viewer_engine_pdf from the monorepo.
# Root .pubignore lists "packages/", which also hides nested package files
# during `dart pub publish` — temporarily move it aside for this publish only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/office_viewer_engine_pdf"
IGNORE="$ROOT/.pubignore"
BACKUP="$ROOT/.pubignore.root-bak"

if [[ -f "$BACKUP" ]]; then
  echo "Found leftover $BACKUP — restore or delete it first." >&2
  exit 1
fi

cleanup() {
  if [[ -f "$BACKUP" ]]; then
    mv "$BACKUP" "$IGNORE"
    echo "Restored root .pubignore"
  fi
}
trap cleanup EXIT

mv "$IGNORE" "$BACKUP"
echo "Moved root .pubignore aside for nested publish"
cd "$PKG"
dart pub get
dart pub publish --dry-run
dart pub publish "$@"
