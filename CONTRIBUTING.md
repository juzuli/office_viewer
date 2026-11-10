# Contributing

Thanks for helping with `office_viewer`. Pub users only need PDF via
[`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf).
Office formats (DOCX / XLSX / PPTX) use the in-repo Dart OOXML engine in
[`packages/office_viewer_engine_dart`](packages/office_viewer_engine_dart) and
the host in [`example_app/`](example_app/).

```bash
flutter pub get && flutter analyze && flutter test
```

## Example host (PDF + Dart OOXML)

```bash
cd example_app
flutter pub get
flutter run -d <android-or-ios-device>
# or:
./tool/run_dart_engine.sh
```

`example_app` registers `PdfOfficeEngine` first, then `DartOfficeEngine`.
Bundled samples and notes: [`example_app/README.md`](example_app/README.md).

Minimal PDF-only sample (pub-friendly): [`example/`](example/).

## Dart engine package

```bash
cd packages/office_viewer_engine_dart
dart pub get
dart test
```

Register with the viewer:

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  ..register(DartOfficeEngine());
```

## Known gaps (contributor)

User-facing limits live in the README **Support** / **Limitations** sections.
Internal notes:

- Memory: viewport-culled sheet tiles; clamp sheet extent
- PDF uses pdfrx — register it before the Dart engine
- Still open: publish Dart engine to pub.dev; huge-sheet heap tuning; broader formats
