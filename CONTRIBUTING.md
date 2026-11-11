# Contributing

Thanks for helping with `office_viewer`. Pub packages:

- [`office_viewer`](https://pub.dev/packages/office_viewer) — viewer shell
- [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf) — PDF
- [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart) — DOCX / XLSX / PPTX
- [`office_viewer_engine_convert`](https://pub.dev/packages/office_viewer_engine_convert) — optional DOC / XLS / PPT convert

Local development uses path deps in [`example_app/`](example_app/) and
package `pubspec_overrides.yaml` files.

```bash
flutter pub get && flutter analyze && flutter test
```

## Example hosts

Full PDF + Convert + Dart OOXML host:

```bash
cd example_app
flutter pub get
flutter run -d <android-or-ios-device>
```

`example_app` registers `PdfOfficeEngine`, then `ConvertOfficeEngine`, then
`DartOfficeEngine`. Bundled samples: [`example_app/README.md`](example_app/README.md).

Pub sample (PDF + Dart, optional convert): [`example/`](example/).

## Dart engine package

```bash
cd packages/office_viewer_engine_dart
flutter pub get
flutter test
```

## Convert engine package (legacy DOC/XLS/PPT)

```bash
cd packages/office_viewer_engine_convert
flutter pub get
flutter test
```

Native Office Oxide prebuilds (v0.1.2) ship under:

- `native/macos/arm64/lib/liboffice_oxide.dylib` (host tests)
- `android/src/main/jniLibs/arm64-v8a/liboffice_oxide.so`
- `ios/Frameworks/OfficeOxide.xcframework` (device + sim dynamic; rebuild with
  `packages/office_viewer_engine_convert/tool/build_ios_oxide.sh`)

Override desktop/Android with `OFFICE_OXIDE_LIB=/path/to/liboffice_oxide.dylib`
if needed. iOS opens `OfficeOxide.framework/OfficeOxide` from the XCFramework.

Throwaway spike: [`tool/legacy_convert_spike/`](tool/legacy_convert_spike/).

Register with the viewer:

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  ..register(ConvertOfficeEngine())
  ..register(DartOfficeEngine());
```

## Publishing (maintainers)

Order matters — core first, then engines that depend on it. Prefer:

```bash
./tool/publish.sh
# dry-run:
./tool/publish.sh --dry-run
```

The root `.pubignore` excludes `packages/` so the core tarball stays lean. The
script moves that file aside when publishing engine packages (otherwise
pub treats the engine pubspec as hidden).

`pubspec_overrides.yaml` is local-only and is not published. PDF / convert
engine bumps are separate under `packages/`.

## Known gaps (contributor)

User-facing limits live in the README **Support** / **Limitations** sections.
Internal notes:

- Memory: viewport-culled sheet tiles; clamp sheet extent
- PDF uses pdfrx — register it before Convert / Dart
- Still open: ODF / CSV / TXT; OOXML password decrypt; convert fidelity (charts/images)
