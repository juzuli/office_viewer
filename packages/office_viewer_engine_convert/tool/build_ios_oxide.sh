#!/usr/bin/env bash
# Build Office Oxide as an iOS dynamic XCFramework (device + sim) for Dart FFI.
#
# Upstream release uses LTO; a static .a then embeds Rust LLVM bitcode that
# Apple's linker cannot consume. The cdylib rustc produces is a normal Mach-O
# dylib with C exports — we wrap that as OfficeOxide.framework slices.
#
# Usage:
#   ./packages/office_viewer_engine_convert/tool/build_ios_oxide.sh
#   OFFICE_OXIDE_TAG=v0.1.2 ./packages/office_viewer_engine_convert/tool/build_ios_oxide.sh
#
# Requires: Rust toolchain, Xcode, rustup targets aarch64-apple-ios{,-sim}
set -euo pipefail

TAG="${OFFICE_OXIDE_TAG:-v0.1.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_XCFRAMEWORK="$PKG_ROOT/ios/Frameworks/OfficeOxide.xcframework"
CACHE_DIR="${OFFICE_OXIDE_SRC:-$HOME/.cache/office_oxide_${TAG}}"
BUILD_ROOT="${OFFICE_OXIDE_BUILD_ROOT:-$PKG_ROOT/build/ios_oxide}"

DEVICE_TARGET=aarch64-apple-ios
SIM_TARGET=aarch64-apple-ios-sim
MIN_IOS="${OFFICE_OXIDE_MIN_IOS:-15.0}"

echo "==> Package: $PKG_ROOT"
echo "==> Tag:     $TAG"
echo "==> Source:  $CACHE_DIR"
echo "==> Output:  $OUT_XCFRAMEWORK"

if ! command -v rustup >/dev/null || ! command -v cargo >/dev/null; then
  echo "error: rustup/cargo required (https://rustup.rs)" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null; then
  echo "error: xcodebuild required (Xcode)" >&2
  exit 1
fi

rustup target add "$DEVICE_TARGET" "$SIM_TARGET"

if [[ ! -d "$CACHE_DIR/.git" ]]; then
  rm -rf "$CACHE_DIR"
  git clone --depth 1 --branch "$TAG" https://github.com/yfedoseev/office_oxide.git "$CACHE_DIR"
fi

mkdir -p "$BUILD_ROOT"

WORK="$BUILD_ROOT/src"
rm -rf "$WORK"
mkdir -p "$WORK"
rsync -a --exclude target --exclude .git "$CACHE_DIR/" "$WORK/"

# Ensure cdylib is produced (needed for the dynamic framework).
python3 - <<'PY' "$WORK/Cargo.toml"
import pathlib, sys, re
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "crate-type" in text and "cdylib" in text:
    print("Cargo.toml already requests cdylib")
else:
    if re.search(r'^\[lib\]', text, re.M):
        text = re.sub(
            r'^\[lib\]\s*\n(?:[^\[]*\n)*',
            '[lib]\ncrate-type = ["cdylib", "staticlib", "rlib"]\n',
            text,
            count=1,
            flags=re.M,
        )
    else:
        text = text.rstrip() + '\n\n[lib]\ncrate-type = ["cdylib", "staticlib", "rlib"]\n'
    path.write_text(text)
    print("Patched Cargo.toml [lib] crate-type to include cdylib")
PY

TARGET_DIR="$BUILD_ROOT/target"
export CARGO_TARGET_DIR="$TARGET_DIR"
# Prefer linkable Mach-O over LTO bitcode in intermediates.
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_STRIP=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16

cd "$WORK"
echo "==> Building $DEVICE_TARGET (CARGO_TARGET_DIR=$CARGO_TARGET_DIR)"
cargo build --release --lib -p office_oxide --target "$DEVICE_TARGET"
echo "==> Building $SIM_TARGET"
cargo build --release --lib -p office_oxide --target "$SIM_TARGET"

DEVICE_DYLIB="$TARGET_DIR/$DEVICE_TARGET/release/liboffice_oxide.dylib"
SIM_DYLIB="$TARGET_DIR/$SIM_TARGET/release/liboffice_oxide.dylib"
for f in "$DEVICE_DYLIB" "$SIM_DYLIB"; do
  if [[ ! -f "$f" ]]; then
    echo "error: missing $f" >&2
    exit 1
  fi
  ls -lh "$f"
  if ! nm -gU "$f" | grep -q '_office_oxide_version'; then
    echo "error: $f missing _office_oxide_version export" >&2
    exit 1
  fi
done

make_framework() {
  local dylib="$1"
  local out_dir="$2"
  local framework="$out_dir/OfficeOxide.framework"
  rm -rf "$framework"
  mkdir -p "$framework"
  cp "$dylib" "$framework/OfficeOxide"
  chmod +x "$framework/OfficeOxide"
  install_name_tool -id "@rpath/OfficeOxide.framework/OfficeOxide" "$framework/OfficeOxide"
  cat >"$framework/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>OfficeOxide</string>
  <key>CFBundleIdentifier</key>
  <string>com.leafpane.OfficeOxide</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>OfficeOxide</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>${TAG#v}</string>
  <key>CFBundleVersion</key>
  <string>${TAG#v}</string>
  <key>MinimumOSVersion</key>
  <string>${MIN_IOS}</string>
</dict>
</plist>
EOF
  echo "$framework"
}

FW_ROOT="$BUILD_ROOT/frameworks"
rm -rf "$FW_ROOT"
DEVICE_FW="$(make_framework "$DEVICE_DYLIB" "$FW_ROOT/device")"
SIM_FW="$(make_framework "$SIM_DYLIB" "$FW_ROOT/sim")"

rm -rf "$OUT_XCFRAMEWORK"
mkdir -p "$(dirname "$OUT_XCFRAMEWORK")"
xcodebuild -create-xcframework \
  -framework "$DEVICE_FW" \
  -framework "$SIM_FW" \
  -output "$OUT_XCFRAMEWORK"

cat >"$PKG_ROOT/ios/Frameworks/PROVENANCE.md" <<EOF
# OfficeOxide.xcframework

- Upstream: https://github.com/yfedoseev/office_oxide
- Tag: \`$TAG\`
- Built by: \`tool/build_ios_oxide.sh\`
- License: MIT OR Apache-2.0 (see package THIRD_PARTY_LICENSES.md)
- Form: dynamic \`OfficeOxide.framework\` slices (\`$DEVICE_TARGET\`, \`$SIM_TARGET\`)
- Why dynamic: Rust release LTO/staticlib emits LLVM bitcode Apple's linker
  cannot consume; the cdylib is a normal Mach-O with C FFI exports.

Dart loads via \`DynamicLibrary.open('OfficeOxide.framework/OfficeOxide')\`
(fallback: \`DynamicLibrary.process()\`).

Rebuild:
\`\`\`bash
./tool/build_ios_oxide.sh
\`\`\`
EOF

echo "==> XCFramework ready:"
du -sh "$OUT_XCFRAMEWORK"
find "$OUT_XCFRAMEWORK" -type f | head -40
echo "Done."
