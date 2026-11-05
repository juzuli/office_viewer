#!/usr/bin/env bash
# Verify an extracted or installed LOK tree exposes the symbols Phase 0 needs.
set -euo pipefail

ROOT="${1:-}"
if [[ -z "${ROOT}" ]]; then
  echo "Usage: $0 <path-to-apk-extract-or-LOK_HOME>" >&2
  exit 2
fi

find_so() {
  local candidate
  for candidate in \
    "${ROOT}/jniLibs/arm64-v8a/liblo-native-code.so" \
    "${ROOT}/lib/arm64-v8a/liblo-native-code.so" \
    "${ROOT}/liblo-native-code.so"; do
    if [[ -f "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

SO="$(find_so)" || {
  echo "FAIL: liblo-native-code.so not found under ${ROOT}" >&2
  exit 1
}
echo "SO=${SO}"

pick_nm() {
  if [[ -n "${LLVM_NM:-}" && -x "${LLVM_NM}" ]]; then
    echo "${LLVM_NM}"
    return 0
  fi
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
  local candidate
  # Prefer newest NDK llvm-nm (sorted reverse).
  if [[ -d "${sdk}/ndk" ]]; then
    while IFS= read -r candidate; do
      if [[ -x "${candidate}" ]]; then
        echo "${candidate}"
        return 0
      fi
    done < <(ls -1d "${sdk}/ndk"/*/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | sort -V -r)
  fi
  if command -v llvm-nm >/dev/null 2>&1; then
    command -v llvm-nm
    return 0
  fi
  if command -v nm >/dev/null 2>&1; then
    command -v nm
    return 0
  fi
  return 1
}

NM="$(pick_nm)" || {
  echo "FAIL: no nm/llvm-nm found (set LLVM_NM)" >&2
  exit 1
}
echo "NM=${NM}"

SYMFILE="$(mktemp "${TMPDIR:-/tmp}/lok-syms.XXXXXX")"
cleanup() { rm -f "${SYMFILE}"; }
trap cleanup EXIT

# llvm-nm accepts -D; fall back to --dynamic / plain nm -D.
if ! "${NM}" -D "${SO}" >"${SYMFILE}" 2>/dev/null; then
  if ! "${NM}" --dynamic "${SO}" >"${SYMFILE}" 2>/dev/null; then
    "${NM}" -D "${SO}" >"${SYMFILE}"
  fi
fi
cp "${SYMFILE}" "${SO}.dynsyms.txt"

pass=true

require_regex() {
  local label="$1"
  local regex="$2"
  if grep -E -q "${regex}" "${SYMFILE}"; then
    echo "OK  ${label}"
    grep -E "${regex}" "${SYMFILE}" | head -20
  else
    echo "FAIL ${label} (no match for /${regex}/)"
    pass=false
  fi
}

require_regex "libreofficekit_* exports" 'libreofficekit_'
require_regex "JNI LibreOfficeKit bootstrap" 'Java_org_libreoffice_kit_LibreOfficeKit_'
require_regex "JNI Document entry points" 'Java_org_libreoffice_kit_Document_'

if grep -E -q 'lok_init|libreofficekit_hook' "${SYMFILE}"; then
  echo "OK  init symbol (lok_init and/or libreofficekit_hook)"
  grep -E 'lok_init|libreofficekit_hook' "${SYMFILE}" | head -20
else
  echo "WARN init symbol lok_init/libreofficekit_hook not in dynsym (JNI path may still work)"
fi

echo "---- assets inventory ----"
if [[ -d "${ROOT}/assets" ]]; then
  find "${ROOT}/assets" -maxdepth 3 -type d | head -80
elif [[ -d "${ROOT}" ]]; then
  find "${ROOT}" -maxdepth 3 \( -type d -name program -o -type d -name share -o -path '*/assets/*' \) | head -80
fi

if [[ "${pass}" == true ]]; then
  echo "PASS: required symbols present"
  exit 0
fi
echo "FAIL: missing required symbols — do not use this APK for Phase 0 FFI" >&2
exit 1
