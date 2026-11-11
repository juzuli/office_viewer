# office_viewer example

Pub.dev sample host for [`office_viewer`](https://pub.dev/packages/office_viewer):

- PDF — [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf)
- DOCX / XLSX / PPTX — [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart)
- Optional DOC / XLS / PPT — [`office_viewer_engine_convert`](https://pub.dev/packages/office_viewer_engine_convert)

```bash
cd example
flutter pub get
flutter run
```

Use the app-bar menu to switch bundled samples (`sample.pdf`, `sample.docx`,
`large_sheet.xlsx`, `sample_deck.pptx`, `sample.doc`).

Register order in `lib/main.dart`: **PDF → Convert (optional) → Dart**. Toggle
convert with `kRegisterConvertEngine` (and remove the convert dependency if you
do not need legacy DOC/XLS/PPT).

For the fuller Leafpane host (more samples, file picker), see
[`../example_app/`](../example_app/) and [`../CONTRIBUTING.md`](../CONTRIBUTING.md).
