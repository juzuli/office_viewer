#!/usr/bin/env bash
# One-shot status for the CPiOS engine build. Re-run anytime.
set -euo pipefail
ROOT="${LO_IOS_BUILD_ROOT:-$HOME/lo-ios-build}"
LOG="${ROOT}/engine-make.log"
if [[ -d "${ROOT}/lok-online/engine" ]]; then
  ENGINE="${ROOT}/lok-online/engine"
else
  ENGINE="${ROOT}/collabora-office/engine"
fi
TB="$ENGINE/external/tarballs"
WD="$ENGINE/workdir"
WDB="$ENGINE/workdir_for_build"
LIST="$WD/CustomTarget/ios/ios-all-static-libs.list"

echo "=== CPiOS build status @ $(date '+%Y-%m-%d %H:%M:%S') ==="

MAKE_PID=$(pgrep -f "^make -j" 2>/dev/null | head -1 || true)
if [[ -n "${MAKE_PID}" ]]; then
  echo "make: RUNNING  pid=$MAKE_PID  elapsed=$(ps -p "$MAKE_PID" -o etime= | tr -d ' ')"
else
  echo "make: NOT RUNNING"
fi

if [[ -f "$LIST" ]]; then
  echo "phase: DONE — $LIST exists ($(wc -l < "$LIST" | tr -d ' ') libs)"
  exit 0
fi

# Prefer log markers; fall back to dirs. Note: redirected make stdout is often
# block-buffered, so engine-make.log can lag while subproject build.log grows.
LAST_BUILD=$(grep -E '\[build (PAT|UPK|PRJ|LNK|CXX|CCL|C|DEP)\]' "$LOG" 2>/dev/null | tail -1 || true)
CLANG_N=$(pgrep -f 'clang|clang\+\+' 2>/dev/null | wc -l | tr -d ' ' || true)
CLANG_N=${CLANG_N:-0}
ICU_LOG="$WDB/UnpackedTarball/icu/source/build.log"

# Cross builds: host tools land in workdir_for_build first; iOS objects in workdir.
if pgrep -f 'UnpackedTarball/icu' >/dev/null 2>&1 || [[ -f "$ICU_LOG" && ! -f "$WDB/ExternalProject/icu/build" ]]; then
  echo "phase: BUILD host tools (ICU / externals)"
elif [[ -d "$WD/CxxObject" ]] || grep -qE '\[build CXX\].*/(vcl|sw|sc|sd|svx)/' "$LOG" 2>/dev/null; then
  echo "phase: COMPILING LO (device/cross)"
elif [[ -n "${LAST_BUILD}" ]] || [[ -d "$WDB" ]] || [[ "${CLANG_N}" -gt 0 ]]; then
  echo "phase: BUILD (host tools / externals)"
elif [[ -d "$WD" ]]; then
  echo "phase: BUILD (workdir present)"
else
  echo "phase: FETCHING external tarballs"
fi

[[ -n "${LAST_BUILD}" ]] && echo "last_build_tag: ${LAST_BUILD}"

ARCH=$(find "$TB" -maxdepth 1 -type f \( -name '*.tar*' -o -name '*.zip' -o -name '*.tgz' -o -name '*.tbz2' \) 2>/dev/null | wc -l | tr -d ' ')
echo "fetched: ${ARCH} archives  ($(du -sh "$TB" 2>/dev/null | awk '{print $1}'))"
echo "disk: workdir=$(du -sh "$WD" 2>/dev/null | awk '{print $1}')  workdir_for_build=$(du -sh "$WDB" 2>/dev/null | awk '{print $1}')  free=$(df -h /System/Volumes/Data | awk 'NR==2{print $4}')"

# --- active download? (tmp/ races with mv — tolerate missing file) ---
PARTIAL=""
shopt -s nullglob
tmp_files=("$TB"/tmp/*)
shopt -u nullglob
if ((${#tmp_files[@]} > 0)); then PARTIAL="${tmp_files[0]}"; fi

if [[ -n "${PARTIAL}" && -f "${PARTIAL}" ]]; then
  NAME=$(basename "$PARTIAL")
  S1=$(stat -f%z "$PARTIAL" 2>/dev/null || echo "")
  if [[ -z "${S1}" ]]; then
    echo "current: $NAME  (finished during probe)"
    echo "verdict: MOVING"
  else
    sleep 2
    if [[ ! -f "${PARTIAL}" ]]; then
      echo "current: $NAME  (completed + moved during probe)"
      echo "verdict: MOVING"
    else
      S2=$(stat -f%z "$PARTIAL" 2>/dev/null || echo "")
      if [[ -z "${S2}" ]]; then
        echo "current: $NAME  (finished during probe)"
        echo "verdict: MOVING"
      else
        DELTA=$((S2 - S1))
        WANT=$(grep -B1 "Saving to: .*/${NAME}" "$LOG" 2>/dev/null \
          | grep Length | tail -1 | sed -n 's/.*Length: \([0-9]*\).*/\1/p' || true)
        if [[ -n "${WANT}" ]]; then
          echo "current: $NAME  ${S2}/${WANT} bytes ($((S2 * 100 / WANT))%)  Δ2s=${DELTA}"
        else
          echo "current: $NAME  size=${S2}  Δ2s=${DELTA}"
        fi
        if [[ "$DELTA" -gt 0 ]]; then echo "verdict: MOVING"; else echo "verdict: STALLED (no growth in 2s)"; fi
      fi
    fi
  fi
elif [[ -f "$ICU_LOG" ]] && pgrep -f 'UnpackedTarball/icu' >/dev/null 2>&1; then
  # ICU (and similar) redirect into their own build.log — that is the live signal.
  B1=$(stat -f%z "$ICU_LOG" 2>/dev/null || echo 0)
  sleep 2
  B2=$(stat -f%z "$ICU_LOG" 2>/dev/null || echo 0)
  echo "current: building ICU (host)  build.log ${B1}→${B2} bytes (Δ2s=$((B2 - B1)))"
  echo "  $(tail -1 "$ICU_LOG" 2>/dev/null | tr -d '\r' | cut -c1-100)"
  if [[ "$B2" -gt "$B1" ]] || [[ "${CLANG_N}" -gt 0 ]]; then
    echo "verdict: MOVING  (clang processes: ${CLANG_N})"
  else
    echo "verdict: STALLED?  ICU log quiet and no clang"
  fi
elif [[ "${CLANG_N}" -gt 0 ]]; then
  echo "current: compiling (clang processes: ${CLANG_N})"
  echo "verdict: MOVING"
elif [[ -n "${MAKE_PID}" ]]; then
  echo "current: make alive, no tmp download / no visible clang"
  echo "verdict: check subproject logs under workdir_for_build/UnpackedTarball/*/build.log"
else
  echo "current: idle"
  echo "verdict: make not running"
fi

if [[ -f "$LOG" ]]; then
  log_mtime=$(stat -f '%Sm' "$LOG")
  echo "main_log: $LOG  (mtime ${log_mtime}; may lag due to stdout buffering)"
  echo "last_main_lines:"
  tail -3 "$LOG" | sed 's/^/  /'
fi
