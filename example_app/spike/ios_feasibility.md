# iOS feasibility — LOK for `office_viewer`

Date: 2026-11-04  
Follows Phase 0 Android GO-on-latency; ordered next step #1 before more Android depth.

## Question

Can we ship the **same tile model** (`documentLoad` / parts / `paintTile`) on iOS, or must we fall back to the system preview (`QLPreviewController` / Quick Look) with different fidelity?

## Short answer

| Layer | Verdict |
|---|---|
| Technology | **Possible** — upstream builds LO as **static `.a` archives** for device `arm64` (`--with-distro=CPiOS`). Same LOK C API including `paintTile`. |
| IPA extract shortcut | **No** — App Store binaries are encrypted; there is no Android-style “unzip viewer APK” path. |
| Simulator | **No** for device-built engine (iOS vs iOS-simulator ABI). Need a **physical device**. |
| This Mac, today | **Unblocked** — disk freed; `CPiOS` configure done; `make -j8` running under `~/lo-ios-build`. |
| Effort once disk is ready | **Real build project**: many hours for first successful `make`, then Flutter FFI/plugin wiring on top. |

**Recommendation:** Treat iOS LOK as **feasible but expensive**. Engine build is in flight on this machine; gate on first-tile + size/RSS before promising store parity. Parallel track: keep Android fidelity work moving; accept **Quick Look** on iOS if LOK build/size fails the gates.

## What the build looks like (no shortcut)

1. Mac + Xcode + Apple Developer Program.
2. Clone upstream `online` monorepo (`engine/` = core) via [`ios_build_engine.sh`](ios_build_engine.sh).
3. In `engine/`: `autogen.input` with at least `--with-distro=CPiOS`, then `make` → static libs listed in `workdir/CustomTarget/ios/ios-all-static-libs.list`.
4. Link from the Flutter plugin; sign with **your** bundle id; run on a **physical** iPhone/iPad.

For `office_viewer` we need only the static LOK engine + a thin Flutter plugin that:

- Bootstraps LOK (program/share resources in the app bundle),
- Exposes the same Dart FFI surface as Android (`LokBindings`),
- Links every `.a` from `lo-all-static-libs` (store rules: no non-system dylibs).

Pixel format on iOS LOK tends toward **premultiplied RGBA** (CoreGraphics path); Android viewer APKs used BGRA — keep a platform branch in `renderTile`.

## Host check (this machine)

| Item | Status |
|---|---|
| Xcode | 27.0 (SDK iOS 27.0) |
| Free disk (`/System/Volumes/Data`) | **~81 GB** — enough to start; watch during `make` |
| RAM / CPU | 16 GB / 8 cores — usable but builds will be slow |
| Physical iOS device | Yes — Juzuli’s iPhone (USB) |
| Code signing | Apple Development identity present |
| Engine tree | `~/lo-ios-build/lok-online` (shallow clone; scripts also accept a pre-existing legacy checkout dir) |
| Toolchain (Homebrew) | GNU make 4.4, gperf 3.3, meson, ninja, libtool, gnu-tar |

## Fallback if LOK iOS is deferred

Use **Quick Look** (`QLPreviewController`) or `UIDocumentInteractionController` for docx/xlsx/pptx/pdf:

- Pros: small binary, Apple-maintained fidelity, little memory work.
- Cons: not our tile API; no shared Android/iOS rendering; limited UI chrome control; fidelity ≠ LOK.

Wire as a separate engine (`office_viewer_engine_quicklook`) implementing `OfficeEngine` with a platform view, **not** fake tiles pretending to be LOK.

## Gate criteria (decide go / no-go on iOS LOK)

- [x] ≥50 GB free (or dedicated build Mac / CI runner)
- [x] First successful `CPiOS` `make` producing `ios-all-static-libs.list` (375 libs, 2026-11-04)
- [ ] Minimal native sample: `documentLoad` + one `paintTile` on device (plugin wiring in-tree; needs device run)
- [ ] App size / RSS numbers vs Android (~217 MB APK / ~250 MB PSS)
- [ ] License review for shipping a self-built LOK static link

If the first tile sample exceeds schedule or size budget → **NO-GO** on iOS LOK; ship Quick Look on iOS + LOK on Android.

## Immediate actions (done in-repo)

- This note + resumable builder: [`ios_build_engine.sh`](ios_build_engine.sh).
- iOS plugin **stub** in `office_viewer_engine_lok` (`ios_lok_not_built`).
- `LOK_HOME_IOS` installer (post-make): [`../../packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh`](../../packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh).
- Android path unchanged.

## Build in progress (this machine) — 2026-11-04

| Item | Value |
|---|---|
| Free disk | ~81 GB |
| Build root | `~/lo-ios-build/lok-online/engine` |
| Distro | `CPiOS` (device `arm64`, iPhoneOS SDK 27.0, min iOS 15) |
| `autogen.input` | `--enable-debug --with-distro=CPiOS --with-lang=en-US` |
| Configure | **done** (`config_host.mk` present) |
| `make -j8` | **finished** exit 0 @ 2026-11-04 18:11 — `ios` module built |
| Log | `~/lo-ios-build/engine-make.log` |
| Success marker | `workdir/CustomTarget/ios/ios-all-static-libs.list` (**375** entries) |
| `LOK_HOME_IOS` | `packages/office_viewer_engine_lok/third_party/lok_ios` (via `install_lok_home_ios.sh`) |

```bash
# Monitor / resume
./example/spike/ios_build_status.sh          # MOVING vs STALLED
tail -f ~/lo-ios-build/engine-make.log
./example/spike/ios_build_engine.sh          # resume after failure

# After make finishes:
./packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh
```

### Expected `LOK_HOME_IOS` layout (after install script)

```
$LOK_HOME_IOS/
  static_libs/*.a          # symlinks into engine workdir archives
  ios-all-static-libs.list # absolute paths from the build
  resources/               # from workdir/CustomTarget/ios/resources
    udkapi.rdb offapi.rdb services.rdb …
    program/bootstraprc program/versionrc
    share/…
  native-code.h
  SOURCE.txt
```

**Wiring (in-tree):** podspec auto-links via `-filelist` when `third_party/lok_ios` exists; Swift bootstrap + ObjC++ LOK bridge (`LokIosBridge.mm`); Dart uses `DynamicLibrary.process()` on iOS. Device-only (`arm64`).

```bash
cd example
flutter pub get && (cd ios && pod install)
flutter run -d <iphone> --dart-define=OFFICE_VIEWER_LOK_IOS=true
```

Expect a long first link (many static archives). Then first-tile + size/RSS gates.

## Do not do yet

- Promise App Store parity with Android LOK without first-tile + size/RSS gates.
- Commit upstream engine sources or `.a` blobs into the Flutter repo.
