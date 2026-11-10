# Contributing

Thanks for helping with `office_viewer`. Pub users only need PDF via
[`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf).
Everything below is for working on the **private** LibreOfficeKit (LOK) Office
engine and the example host.

```bash
flutter pub get && flutter analyze && flutter test
```

## LOK setup (Phase 0)

Kotlin bootstraps LOK (`AssetManager`, data/cache dirs). Dart FFI owns
`documentLoad`, parts, size, and `paintTile`. Swap binaries without API changes.

```bash
cd packages/office_viewer_engine_lok
./tool/fetch_viewer_apk.sh
./tool/install_lok_home.sh tool/cache/*-arm64.apk
./tool/verify_lok_symbols.sh third_party/lok
# optional: export LOK_HOME=/path/to/lok

cd ../../example_app
flutter run -d <android-arm64>
```

Record metrics in [`example_app/spike/phase0_notes.md`](example_app/spike/phase0_notes.md).
Extracted libs are for **private devices only** — do not redistribute.

Prefer a F-Droid **viewer** APK (not a full mobile suite APK) for C LOK / JNI
kit symbols; `fetch_viewer_apk.sh` pins the package id. Verify with
`verify_lok_symbols.sh` before committing to a binary.

### iOS

No IPA extract shortcut. Feasibility notes:
[`example_app/spike/ios_feasibility.md`](example_app/spike/ios_feasibility.md).
Plugin uses a stub (`ios_lok_not_built`) until a self-built static engine is
installed via `packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh`.
Once installed, plain `flutter run` on a device links LOK (no dart-define).

## Known gaps (contributor)

User-facing limits live in the README **Support** / **Limitations** sections.
Internal notes:

- Memory: viewport-culled sheet tiles; slim iOS resources by default
- PDF uses pdfrx (LOK excluded) — no LO abort on PDF open
- Still open: redistribute license + store size; huge-sheet native heap
