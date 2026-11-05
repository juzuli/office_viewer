#!/usr/bin/env bash
# Populate LOK_HOME_IOS from a finished CPiOS engine build.
# Does not commit binaries into the Flutter tree — private / local only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Prefer neutral tree; fall back to legacy local path if present.
_default_engine() {
  local a="$HOME/lo-ios-build/lok-online/engine"
  local b="$HOME/lo-ios-build/collabora-office/engine"
  if [[ -d "$a" ]]; then echo "$a"
  elif [[ -d "$b" ]]; then echo "$b"
  else echo "$a"
  fi
}
ENGINE="${1:-${LO_IOS_ENGINE:-$(_default_engine)}}"
LOK_HOME_IOS="${LOK_HOME_IOS:-${PKG_ROOT}/third_party/lok_ios}"

LIST="${ENGINE}/workdir/CustomTarget/ios/ios-all-static-libs.list"
RES="${ENGINE}/workdir/CustomTarget/ios/resources"
NATIVE_H="${ENGINE}/workdir/CustomTarget/ios/native-code.h"

if [[ ! -f "${LIST}" ]]; then
  echo "FAIL: ${LIST} missing — finish CPiOS make first" >&2
  echo "  Monitor: tail -f ~/lo-ios-build/engine-make.log" >&2
  exit 1
fi
if [[ ! -d "${RES}" ]]; then
  echo "FAIL: ${RES} missing — iOS_setup custom target incomplete" >&2
  exit 1
fi

rm -rf "${LOK_HOME_IOS}"
mkdir -p "${LOK_HOME_IOS}/static_libs" "${LOK_HOME_IOS}/resources"

# Symlink each .a so we do not duplicate tens of GB of archives.
while IFS= read -r lib || [[ -n "${lib}" ]]; do
  [[ -z "${lib}" ]] && continue
  if [[ ! -f "${lib}" ]]; then
    echo "WARN: listed lib missing: ${lib}" >&2
    continue
  fi
  base="$(basename "${lib}")"
  ln -sf "${lib}" "${LOK_HOME_IOS}/static_libs/${base}"
done < "${LIST}"

cp -R "${RES}/." "${LOK_HOME_IOS}/resources/"
[[ -f "${NATIVE_H}" ]] && cp "${NATIVE_H}" "${LOK_HOME_IOS}/native-code.h"
cp "${LIST}" "${LOK_HOME_IOS}/ios-all-static-libs.list"

# iOS LOK init looks for ICU.dat (or LIBREOFFICE_ICU_DATA).
# Use a real file — iOS app bundles must not rely on symlinks for ICU.
if [[ ! -f "${LOK_HOME_IOS}/resources/ICU.dat" || -L "${LOK_HOME_IOS}/resources/ICU.dat" ]]; then
  ICU_SRC="$(find "${LOK_HOME_IOS}/resources" -maxdepth 1 -name 'icudt*.dat' | head -1 || true)"
  if [[ -n "${ICU_SRC}" ]]; then
    rm -f "${LOK_HOME_IOS}/resources/ICU.dat"
    cp "${ICU_SRC}" "${LOK_HOME_IOS}/resources/ICU.dat"
  fi
fi

{
  echo "engine=${ENGINE}"
  echo "list=${LIST}"
  echo "abi=arm64-apple-ios"
  echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "note=Private spike only. Static libs are symlinks into the LO build tree."
} > "${LOK_HOME_IOS}/SOURCE.txt"

# CocoaPods only packs resources under the ios/ pod root (no `../` globs).
POD_RES="${PKG_ROOT}/ios/LokIosResources"
rm -rf "${POD_RES}"
mkdir -p "${POD_RES}"
if rsync -a --delete --link-dest="${LOK_HOME_IOS}/resources" \
    "${LOK_HOME_IOS}/resources"/ "${POD_RES}/" 2>/dev/null; then
  :
else
  # Fallback when hardlinks across volumes fail.
  rsync -a --delete "${LOK_HOME_IOS}/resources"/ "${POD_RES}/"
fi

echo "LOK_HOME_IOS=${LOK_HOME_IOS}"
echo "static_libs: $(find "${LOK_HOME_IOS}/static_libs" -name '*.a' | wc -l | tr -d ' ') symlinks"
echo "pod resources: ${POD_RES} ($(du -sh "${POD_RES}" | awk '{print $1}'))"
echo "resources top:"
find "${LOK_HOME_IOS}/resources" -maxdepth 2 -type d | head -40
echo "Done."
echo
echo "Next: cd example && flutter run -d <iphone>"
