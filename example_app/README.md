# Leafpane example

Demo host for Leafpane’s [`office_viewer`](../) package — Word, Excel,
PowerPoint, and PDF on Android and iOS. Suitable for pub.dev listing screenshots.

Office formats use [`office_viewer_engine_dart`](../packages/office_viewer_engine_dart)
(pure Dart OOXML). PDF uses [`office_viewer_engine_pdf`](../packages/office_viewer_engine_pdf).

## Run

```bash
flutter pub get
flutter run -d <android-arm64>   # or an iPhone
# or:
./tool/run_dart_engine.sh        # optional: device id as first arg
```

Tap **Word / Excel / PowerPoint / PDF** for bundled samples, or **Open** for a
file on the device (DOCX / XLSX / PPTX / PDF only).

Bundled samples: `sample.docx`, `large_sheet.xlsx`, `sample_deck.pptx`,
`sample.pdf` — see [`assets/SAMPLES.md`](assets/SAMPLES.md).
