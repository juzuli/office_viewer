# office_viewer_engine_convert

Optional engine for [`office_viewer`](https://pub.dev/packages/office_viewer): convert legacy **DOC / XLS / PPT** to **DOCX / XLSX / PPTX** in a private temp workspace, then render with [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart).

- **View only** — the original file is never overwritten.
- **Native** — [Office Oxide](https://github.com/yfedoseev/office_oxide) via FFI (MIT OR Apache-2.0).
- **Platforms** — Android (arm64 `.so`), iOS (dynamic `OfficeOxide.xcframework`), macOS arm64 (tests/desktop).

### iOS native library

```bash
# From this package (needs Rust + Xcode):
./tool/build_ios_oxide.sh
cd ../../example_app/ios && pod install
```

That writes `ios/Frameworks/OfficeOxide.xcframework` (device + sim dynamic
`OfficeOxide.framework` slices). Dart opens `OfficeOxide.framework/OfficeOxide`.

## Install

```bash
flutter pub add office_viewer_engine_convert
```

Register **PDF → Convert → Dart**:

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  ..register(ConvertOfficeEngine())
  ..register(DartOfficeEngine());
```

## Fidelity

Conversion preserves content shape (paragraphs, tables, sheets, slides, basic runs). Charts, WordArt, formula expressions, and encrypted legacy files are out of scope — see Office Oxide docs.

## License

MIT for this package. Native Office Oxide binaries: MIT OR Apache-2.0 — [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
