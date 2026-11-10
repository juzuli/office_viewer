# Contributing

Thanks for helping with `office_viewer`. Pub packages:

- [`office_viewer`](https://pub.dev/packages/office_viewer) — viewer shell
- [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf) — PDF
- [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart) — DOCX / XLSX / PPTX

Local development uses path deps in [`example_app/`](example_app/) and
`packages/office_viewer_engine_dart/pubspec_overrides.yaml`.

```bash
flutter pub get && flutter analyze && flutter test
```

## Example hosts

Full PDF + Dart OOXML host:

```bash
cd example_app
flutter pub get
flutter run -d <android-or-ios-device>
# or:
./tool/run_dart_engine.sh
```

`example_app` registers `PdfOfficeEngine` first, then `DartOfficeEngine`.
Bundled samples: [`example_app/README.md`](example_app/README.md).

Minimal PDF-only sample (pub-friendly): [`example/`](example/).

## Dart engine package

```bash
cd packages/office_viewer_engine_dart
flutter pub get
flutter test
```

Register with the viewer:

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  ..register(DartOfficeEngine());
```

## Publishing (maintainers)

Order matters — core first, then engines that depend on it:

```bash
# 1) office_viewer
flutter pub publish

# 2) office_viewer_engine_dart (after 0.0.8 is on pub.dev)
cd packages/office_viewer_engine_dart
flutter pub publish

# PDF engine is already on pub; bump separately when needed
```

`pubspec_overrides.yaml` is local-only and is not published.

## Known gaps (contributor)

User-facing limits live in the README **Support** / **Limitations** sections.
Internal notes:

- Memory: viewport-culled sheet tiles; clamp sheet extent
- PDF uses pdfrx — register it before the Dart engine
- Still open: huge-sheet heap tuning; broader formats; OOXML password decrypt
