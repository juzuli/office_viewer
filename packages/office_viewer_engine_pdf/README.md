# office_viewer_engine_pdf

PDFium-backed PDF engine for [`office_viewer`](../..) via [pdfrx](https://pub.dev/packages/pdfrx).

Register **before** `LokOfficeEngine` so PDFs never hit LibreOfficeKit (hard
UNO asserts / process abort on some files — BUG-004).

```dart
registry
  ..register(PdfOfficeEngine())
  ..register(LokOfficeEngine());
```

Supports `OfficeFormat.pdf` on Android and iOS only.
