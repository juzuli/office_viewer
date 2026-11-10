#!/usr/bin/env bash
# Build release APK and print size (run from example/ or via path).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
flutter build apk --release
APK="build/app/outputs/flutter-apk/app-release.apk"
ls -lh "${APK}"
shasum -a 256 "${APK}"
