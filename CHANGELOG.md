## 0.0.8

* Remove LibreOfficeKit (`office_viewer_engine_lok`); Office uses `office_viewer_engine_dart` only.
* **Breaking:** drop LOK-only `PartInfo.contentOrigin` / `PartInfo.lokPartIndex` and `OfficeViewerLimits.lokLoadOptions`.
* **Breaking:** legacy binary Office (`.doc` / `.xls` / `.ppt`) and OpenDocument are no longer opened — use OOXML (`.docx` / `.xlsx` / `.pptx`) or PDF.
* Example host registers `PdfOfficeEngine` then `DartOfficeEngine` (no `OFFICE_VIEWER_USE_LOK` toggle).
* Export `OfficeViewerLimits` from the package barrel for host tile/memory caps.
* Pair with [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart) `0.1.0` for DOCX / XLSX / PPTX on pub.dev.

### Migrating from 0.0.7

1. Remove any dependency on `office_viewer_engine_lok` and stop registering `LokOfficeEngine`.
2. Register PDF first, then Dart: `..register(PdfOfficeEngine())..register(DartOfficeEngine())`.
3. Delete uses of `PartInfo.contentOrigin`, `PartInfo.lokPartIndex`, and `OfficeViewerLimits.lokLoadOptions` (tile requests use part-local coordinates only).
4. Narrow pickers / allowed extensions to formats the Dart + PDF engines support.

## 0.0.7

* Fix `OfficeDocumentController` constructor: restore public `viewOptions:` named parameter (`this._viewOptions` is illegal / `private_optional_parameter`).

## 0.0.6

* Add a minimal publishable PDF `example/` for pub points; move the private LOK host to `example_app/`.
* Attempted initializing-formal cleanup (reverted in 0.0.7).

## 0.0.5

* README: PDF-first expectations, support matrices, size/memory limits, file-open + password sample, license notes; LOK setup moved to CONTRIBUTING.md.
* Raise Flutter (`>=3.47.0`) and Dart (`>=3.12.0`) floors to match `office_viewer_engine_pdf` / pdfrx ^2.5.
* Declare `platforms: android` and `ios` for pub.dev.

## 0.0.4

* README: one-row device-width screenshot previews and a Supported / Not supported matrix.

## 0.0.3

* Use absolute GitHub raw image URLs in the README so screenshots render on pub.dev.

## 0.0.2

* User-friendly README with device screenshots for Word, Excel, PowerPoint, and PDF.
* Publish screenshots to the pub.dev package gallery.

## 0.0.1

* Initial release: tile-based Office document viewer API, controller, and registry.
