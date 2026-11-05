#!/usr/bin/env bash
# Build CPiOS LOK static engine for iOS device arm64.
# Resumable: re-run after failures; does not live inside the Flutter tree.
set -euo pipefail

BUILD_ROOT="${LO_IOS_BUILD_ROOT:-$HOME/lo-ios-build}"
# Neutral checkout dir; reuse legacy folder if already present.
if [[ -d "${BUILD_ROOT}/lok-online/.git" ]]; then
  REPO="${BUILD_ROOT}/lok-online"
elif [[ -d "${BUILD_ROOT}/collabora-office/.git" ]]; then
  REPO="${BUILD_ROOT}/collabora-office"
else
  REPO="${BUILD_ROOT}/lok-online"
fi
ENGINE="${REPO}/engine"
JOBS="${LO_IOS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# GNU make ≥4.2 (Apple /usr/bin/make is too old), gperf ≥3.1, libtool, tar.
for gnubin in \
  /opt/homebrew/opt/make/libexec/gnubin \
  /opt/homebrew/opt/libtool/libexec/gnubin \
  /opt/homebrew/opt/gnu-tar/libexec/gnubin
do
  [[ -d "${gnubin}" ]] && export PATH="${gnubin}:$PATH"
done
[[ -d /opt/homebrew/opt/gperf/bin ]] && export PATH="/opt/homebrew/opt/gperf/bin:$PATH"

need() { command -v "$1" >/dev/null || { echo "FATAL: missing $1 — brew install $2" >&2; exit 1; }; }
need make make
need gperf gperf
need meson meson
need ninja ninja
make --version | head -1 | grep -q 'GNU Make' || {
  echo "FATAL: PATH make is not GNU Make 4.x" >&2
  exit 1
}

mkdir -p "${BUILD_ROOT}"

if [[ ! -d "${REPO}/.git" ]]; then
  echo "Cloning upstream online monorepo into ${REPO}…"
  # Upstream Gerrit host for the online/engine tree used by CPiOS builds.
  git clone --progress --depth 1 https://gerrit.collaboraoffice.com/online "${REPO}"
fi

if [[ ! -d "${ENGINE}" ]]; then
  echo "FATAL: ${ENGINE} missing — monorepo layout changed?" >&2
  exit 1
fi

cd "${ENGINE}"

if [[ ! -f autogen.input ]]; then
  cat > autogen.input <<'EOF'
# Minimal iOS device arm64 engine for office_viewer LOK spike.
# Comment out debug flags for smaller/faster release-oriented builds.
--enable-debug
--with-distro=CPiOS
--with-lang=en-US
EOF
  echo "Wrote ${ENGINE}/autogen.input"
fi

if [[ ! -f config_host.mk ]]; then
  echo "Running ./autogen.sh…"
  ./autogen.sh
fi

echo "Building engine with -j${JOBS} (this takes many hours)…"
echo "Log: ${BUILD_ROOT}/engine-make.log"
make -j"${JOBS}" 2>&1 | tee "${BUILD_ROOT}/engine-make.log"

LIST="${ENGINE}/workdir/CustomTarget/ios/ios-all-static-libs.list"
if [[ -f "${LIST}" ]]; then
  echo "OK: static libs list at ${LIST}"
  wc -l "${LIST}"
else
  echo "WARN: ${LIST} not found yet — check engine-make.log" >&2
  exit 1
fi
