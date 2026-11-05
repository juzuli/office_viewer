#!/usr/bin/env bash
# Extract an APK into LOK_HOME (jniLibs + assets + SOURCE.txt).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APK="${1:-}"
LOK_HOME="${LOK_HOME:-${PKG_ROOT}/third_party/lok}"

if [[ -z "${APK}" || ! -f "${APK}" ]]; then
  echo "Usage: LOK_HOME=... $0 <path-to.apk>" >&2
  exit 2
fi

VERIFY="${SCRIPT_DIR}/verify_lok_symbols.sh"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lok-apk.XXXXXX")"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

echo "Extracting ${APK} -> ${WORKDIR}"
unzip -qo "${APK}" -d "${WORKDIR}"

echo "Verifying symbols..."
"${VERIFY}" "${WORKDIR}"

ABI="arm64-v8a"
if [[ ! -d "${WORKDIR}/lib/${ABI}" ]]; then
  echo "FAIL: APK has no lib/${ABI}" >&2
  exit 1
fi

rm -rf "${LOK_HOME}"
mkdir -p "${LOK_HOME}/jniLibs/${ABI}" "${LOK_HOME}/assets"

mkdir -p "${LOK_HOME}/jniLibs/${ABI}"
# Copy only shared libraries (skip nm dump artifacts if re-run).
find "${WORKDIR}/lib/${ABI}" -maxdepth 1 -name '*.so' -exec cp {} "${LOK_HOME}/jniLibs/${ABI}/" \;

# Viewer APKs store the LOK program tree under assets/
if [[ -d "${WORKDIR}/assets" ]]; then
  cp -R "${WORKDIR}/assets/." "${LOK_HOME}/assets/"
  # App packaging owns dexopt profiles; APK copy collides in the host APK.
  rm -rf "${LOK_HOME}/assets/dexopt"
fi

SHA="$(shasum -a 256 "${APK}" | awk '{print $1}')"
{
  echo "source_apk=$(basename "${APK}")"
  echo "source_path=${APK}"
  echo "sha256=${SHA}"
  echo "abi=${ABI}"
  echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "note=Private spike only. Do not redistribute extracted binaries."
} > "${LOK_HOME}/SOURCE.txt"

echo "LOK_HOME=${LOK_HOME}"
echo "jniLibs:"
ls -la "${LOK_HOME}/jniLibs/${ABI}" | head -40
echo "assets (top):"
find "${LOK_HOME}/assets" -maxdepth 2 -type d | head -40
echo "Done."
