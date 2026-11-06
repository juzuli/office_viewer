Tile-based document viewer for Flutter on **iOS** and **Android**.
Open a local file, paint tiles, pan and zoom — host apps own chrome, sharing, and navigation.
No edit, search, or print.

Publisher: [Leafpane](https://github.com/juzuli/office_viewer).

| Word | Excel |
|:----:|:-----:|
| ![Word](https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/word.png) | ![Excel](https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/excel.png) |

| PowerPoint | PDF |
|:----------:|:---:|
| ![PowerPoint](https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/powerpoint.png) | ![PDF](https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/pdf.png) |

## Features

- Fit-width zoom with pinch / double-tap and pan clamp
- Part switching (pages, sheets, slides)
- Soft-fail on corrupt or password-protected docs (`OpenOptions(password:)`)
- Pluggable engines via `OfficeEngineRegistry` (first match wins)
- PDF on pub.dev today via [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf) (pdfrx / PDFium)

## Platforms

| Package | pub.dev | Formats | Notes |
|---|---|---|---|
| `office_viewer` | **0.0.3** | — | Viewer API, controller, tiles |
| `office_viewer_engine_pdf` | **0.0.1** | PDF | Real rendering via pdfrx |
| `office_viewer_engine_lok` | Not yet | DOCX / XLSX / PPTX / ODF | Private binary spike; Office-on-pub later |

Android and iOS only for now.

## Install

```bash
flutter pub add office_viewer office_viewer_engine_pdf
```

```dart
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';
```

## Getting started

Register an engine once at startup, then load bytes (or another `DocumentSource`) into a controller you own:

```dart
void main() {
  OfficeEngineRegistry.instance
    ..clear()
    ..register(PdfOfficeEngine());
  runApp(const MyApp());
}

// Inside a widget:
final controller = OfficeDocumentController();
await controller.load(
  DocumentSource.bytes(pdfBytes, fileName: 'doc.pdf'),
);

OfficeDocumentView(controller: controller);
```

Packages: [`office_viewer`](https://pub.dev/packages/office_viewer) ·
[`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf)

See the runnable host in [`example/`](example/).

## Controller and view options

Own `OfficeDocumentController` outside the view. Gesture locks and zoom bounds live on `OfficeViewOptions`:

```dart
final controller = OfficeDocumentController(
  viewOptions: const OfficeViewOptions(
    panEnabled: true,
    zoomEnabled: true, // pinch / double-tap
    minZoom: 1.0,      // fit page width (+ padding)
    maxZoom: 5.0,
  ),
);

await controller.load(DocumentSource.bytes(bytes, fileName: 'a.pdf'));
// Encrypted files: catch PasswordRequiredError and retry with:
// await controller.load(source, options: OpenOptions(password: pwd));

// Runtime locks — host chrome can still call setZoom / goToPart:
controller.lockZoom(); // or lockPan(), setInteraction(panEnabled: false)
controller.setZoom(1.5);

OfficeDocumentView(controller: controller);
// Optional per-widget overrides:
// OfficeDocumentView(controller: c, zoomEnabled: false)
```

### View options

| Name | Description | Default |
|---|---|---|
| `panEnabled` | Allow pan gestures | `true` |
| `zoomEnabled` | Allow pinch / double-tap zoom | `true` |
| `minZoom` | Lower zoom bound (fit-width scale) | `1.0` |
| `maxZoom` | Upper zoom bound | `5.0` |

### Controller helpers

| Name | Description |
|---|---|
| `load` | Open a `DocumentSource` (optional `OpenOptions`) |
| `setZoom` / `goToPart` | Programmatic zoom and part navigation |
| `lockZoom` / `lockPan` / `setInteraction` | Runtime gesture locks |
| `parts` / `currentPart` / `state` | Document metadata and load state |

## Engines

| Engine package | Formats | Notes |
|---|---|---|
| `office_viewer_engine_pdf` | pdf | PDFium via pdfrx. Register **first**. Pub-ready. |
| `office_viewer_engine_lok` | docx/xlsx/pptx/doc/xls/ppt/odf | LOK tiles — not PDF. Private binaries; not on pub yet. |
| `office_viewer_engine_web` | docx/xlsx/pptx | Planned (WebView OSS) for pub-safe Office. |

## Concepts

- **Part** — a page, sheet, or slide. `PartInfo.size` is in points.
- **Tile** — a rectangle of one part rendered to RGBA at a given scale (`TileRequest`).
- **Engine** — `OfficeEngine.open()` returns an `OfficeDocumentHandle` that paints tiles.
- **Registry** — first registered engine that supports a format wins. Register the high-fidelity engine first, then any fallback.

## Contributor setup — LOK (Phase 0)

Kotlin bootstraps LOK (`AssetManager`, data/cache dirs). Dart FFI owns
`documentLoad`, parts, size, and `paintTile`. Swap binaries without API changes.

```bash
cd packages/office_viewer_engine_lok
./tool/fetch_viewer_apk.sh
./tool/install_lok_home.sh tool/cache/*-arm64.apk
./tool/verify_lok_symbols.sh third_party/lok
# optional: export LOK_HOME=/path/to/lok

cd ../../example
flutter run -d <android-arm64>
```

Record metrics in [`example/spike/phase0_notes.md`](example/spike/phase0_notes.md).
Extracted libs are for **private devices only** — do not redistribute.

Prefer a F-Droid **viewer** APK (not a full mobile suite APK) for C LOK / JNI
kit symbols; `fetch_viewer_apk.sh` pins the package id. Verify with
`verify_lok_symbols.sh` before committing to a binary.

### iOS

No IPA extract shortcut. Feasibility notes:
[`example/spike/ios_feasibility.md`](example/spike/ios_feasibility.md).
Plugin uses a stub (`ios_lok_not_built`) until a self-built static engine is
installed via `packages/office_viewer_engine_lok/tool/install_lok_home_ios.sh`.
Once installed, plain `flutter run` on a device links LOK (no dart-define).

```bash
flutter pub get && flutter analyze && flutter test
```

## Status / known gaps

- Open + readable tiles for DOCX / XLSX / PPTX / PDF on Android arm64 and iOS arm64
- Fit-width zoom, pinch, pan clamp, part/sheet switching
- Soft-fail corrupt/password docs; host passes `OpenOptions(password:)` (example shows a dialog)
- Memory: viewport-culled sheet tiles; slim iOS resources by default
- PDF uses pdfrx (LOK excluded) — no LO abort on PDF open
- Still open: redistribute license + store size; huge-sheet native heap
