# office_viewer_engine_lok

LOK (LibreOfficeKit) tile engine for Leafpane’s [`office_viewer`](../..) package.

| Platform | Status |
|---|---|
| **Android arm64** | Phase 0 live — Kotlin bootstrap + Dart FFI tiles |
| **iOS arm64** | Linked — self-built CPiOS static engine + LOK bridge (device only). See [`../../example/spike/ios_feasibility.md`](../../example/spike/ios_feasibility.md) |

## Android — private binary (`LOK_HOME`)

Extracted Viewer libs are **not** redistributed. Private devices only.

```bash
./tool/fetch_viewer_apk.sh
./tool/install_lok_home.sh tool/cache/*-arm64.apk
./tool/verify_lok_symbols.sh "${LOK_HOME:-third_party/lok}"
```

```
$LOK_HOME/
  jniLibs/arm64-v8a/*.so
  assets/program ... assets/share ... assets/unpack ...
  SOURCE.txt
```

## iOS — self-built static engine (`LOK_HOME_IOS`)

No IPA extract. Build outside the Flutter tree, then install locally:

```bash
# many hours — see example/spike/ios_feasibility.md
./example/spike/ios_build_engine.sh
# after ios-all-static-libs.list exists:
./tool/install_lok_home_ios.sh
```

```
$LOK_HOME_IOS/
  static_libs/*.a          # symlinks into ~/lo-ios-build/… archives
  ios-all-static-libs.list
  resources/               # udkapi.rdb, share/, program/bootstraprc, …
  native-code.h
  SOURCE.txt
```

After `install_lok_home_ios.sh`, the podspec auto-detects `third_party/lok_ios`,
links via `-filelist` + system `-lsqlite3` (device `arm64` only), and rsyncs
`ios/LokIosResources` into `LokIosResources.bundle` (directory layout preserved).

Debug app with LOK ≈ **~0.7–1.1 GB** on device (static LO + resources). That is
why `flutter run` on iPhone feels heavy — **link + copy + USB install**, not Dart.

### Does this affect package users?

**No, not by default.** `OFFICE_VIEWER_LINK_LOK_IOS` is an **example/app build**
knob for our spike harness. Apps that depend on this package and ship with
`LOK_HOME_IOS` installed keep the normal linked engine (default `=1`). Dart
APIs (`OfficeDocumentView`, controller, engines) are unchanged for consumers.

Use the fast stub **only** when iterating on Flutter UI without real tiles.

### Fast UI iteration (example app only)

```bash
cd ../../example
./tool/ios_run_fast.sh <iphone-udid>   # FakeOfficeEngine — empty grid, not real docs
```

### Full LOK on device (real document tiles)

```bash
cd ../../example
./tool/ios_run_lok.sh <iphone-udid>    # links CPiOS engine; plain flutter run works after that
```

Switching fast ↔ LOK needs `pod install` (the scripts do that). Preference is
stored in `example/ios/.lok_link_enabled` so a plain `flutter run` keeps the
linked engine once `install_lok_home_ios.sh` has been run.

First-tile + RSS + license still gate go/no-go (see `example/spike/ios_feasibility.md`).

## Run the host example

```bash
cd ../../example
flutter pub get
flutter run -d <android-arm64> --release   # LOK
./tool/ios_run_fast.sh <iphone>            # UI only
./tool/ios_run_lok.sh <iphone>             # real tiles
```

Metrics: [`../../example/spike/phase0_notes.md`](../../example/spike/phase0_notes.md).
