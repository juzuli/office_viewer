#!/usr/bin/env bash
# Download a F-Droid arm64-v8a Office viewer APK into tool/cache/ (LOK symbol source).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/cache"
mkdir -p "${CACHE_DIR}"

# F-Droid application id for the viewer APK used as a private LOK extract source.
# Override with VIEWER_APK_URL / VIEWER_PACKAGE if needed.
PACKAGE="${VIEWER_PACKAGE:-org.documentfoundation.libreoffice}"
VERSION_CODE="${VIEWER_VERSION_CODE:-131}"
VERSION_NAME="${VIEWER_VERSION_NAME:-26.2.6.3}"
DEFAULT_URL="https://f-droid.org/repo/${PACKAGE}_${VERSION_CODE}.apk"
URL="${VIEWER_APK_URL:-$DEFAULT_URL}"
OUT="${CACHE_DIR}/lok-viewer-${VERSION_NAME}-arm64.apk"

echo "Downloading ${URL}"
echo " -> ${OUT}"
curl -fL --retry 3 --retry-delay 2 -o "${OUT}" "${URL}"
shasum -a 256 "${OUT}" | tee "${OUT}.sha256"
echo "APK_PATH=${OUT}"
