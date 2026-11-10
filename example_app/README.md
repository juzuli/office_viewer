# Leafpane example

Demo host for Leafpane’s [`office_viewer`](../) package — Word, Excel,
PowerPoint, PDF, and optional legacy DOC / XLS / PPT on Android and iOS.
Suitable for pub.dev listing screenshots.

- OOXML: [`office_viewer_engine_dart`](../packages/office_viewer_engine_dart)
- Legacy convert: [`office_viewer_engine_convert`](../packages/office_viewer_engine_convert)
- PDF: [`office_viewer_engine_pdf`](../packages/office_viewer_engine_pdf)

Registration order: PDF → Convert → Dart.

## Run

```bash
flutter pub get
flutter run -d <android-arm64>   # or an iPhone
# or:
./tool/run_dart_engine.sh        # optional: device id as first arg
```

Tap the segmented samples (including **DOC / XLS / PPT**), or **Open** for a
device file (DOCX / XLSX / PPTX / PDF / DOC / XLS / PPT).

Legacy samples need the convert engine’s native lib (Android `.so`, iOS
`OfficeOxide.xcframework` via `tool/build_ios_oxide.sh` + `pod install`,
macOS dylib for host tests).

Bundled samples: see [`assets/SAMPLES.md`](assets/SAMPLES.md).
