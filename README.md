A Flutter package to view **PDF** (and, in a private example build, Office) documents on Android and iOS.

> [!IMPORTANT]
> PDF viewing works on pub.dev today. Word, Excel, and PowerPoint are **not** published yet — their rendering engine is still private while we sort out size, licensing, and redistribution.

<p align="center">
  <img src="https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/word.png" width="180" alt="Word (DOCX) device preview" />
  <img src="https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/excel.png" width="180" alt="Excel (XLSX) device preview" />
  <img src="https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/powerpoint.png" width="180" alt="PowerPoint (PPTX) device preview" />
  <img src="https://raw.githubusercontent.com/juzuli/office_viewer/main/screenshots/pdf.png" width="180" alt="PDF device preview" />
</p>

<p align="center">
  <sub>Example app with a private Office engine (Android). Only PDF is available from pub.dev.</sub>
</p>

## Features

- Fit-width zoom with pinch / double-tap and pan clamp
- Part switching (pages, sheets, slides)
- Soft-fail on corrupt or password-protected docs (`OpenOptions(password:)`)
- Pluggable engines via `OfficeEngineRegistry` (first match wins)
- PDF on pub.dev today via [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf) (pdfrx / PDFium)

## Requirements

Required for the recommended install (`office_viewer` + `office_viewer_engine_pdf`):

| | |
|---|---|
| Flutter | `>=3.47.0` |
| Dart | `>=3.12.0 <4.0.0` |
| Platforms | **Android** and **iOS** only |
| Android `minSdk` | Flutter default (`flutter.minSdkVersion`, typically 21+) |
| iOS deployment target | **15.0+** (see `example_app/`) |

## Support

### On pub.dev

Install [`office_viewer`](https://pub.dev/packages/office_viewer) + [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf).

| | Android | iOS |
|---|:---:|:---:|
| **PDF** | ✓ | ✓ |
| **Word (DOCX)** | ✗ | ✗ |
| **Excel (XLSX)** | ✗ | ✗ |
| **PowerPoint (PPTX)** | ✗ | ✗ |
| **Pan / zoom / fit-width** | ✓ | ✓ |
| **Password-protected files** | ✓ | ✓ |

### In the example app (private Office engine)

The screenshots above use our example host. PDF still uses the pub PDF engine; Word / Excel / PowerPoint need a **private** Office engine install (not published on pub.dev).

| | Android | iOS |
|---|:---:|:---:|
| **PDF** | ✓ | ✓ |
| **Word (DOCX)** | ✓ | ✓\* |
| **Excel (XLSX)** | ✓ | ✓\* |
| **PowerPoint (PPTX)** | ✓ | ✓\* |
| **Pan / zoom / fit-width** | ✓ | ✓ |
| **Password-protected files** | ✓ | ✓\* |

\* iOS Office viewing needs a self-built engine linked into the example; without that install those Office cells are ✗.

### Limitations

- **Mobile only for now.** Web, Windows, macOS, and Linux are not available yet.
- **Word, Excel, and PowerPoint are not on pub.dev yet.** Opening DOCX / XLSX / PPTX needs a private LibreOfficeKit (**LOK**) engine. In our Android spike the **example release APK with LOK** is roughly **217 MB** (dominated by native LOK libs) and process PSS is about **250 MB** while a sheet is open — too large and too constrained by licensing / redistribution for a public package today.
- **Other file types** (older DOC / XLS / PPT, OpenDocument ODT / ODS / ODP, CSV / TXT) are also not offered on pub.dev. Some work in the private example setup; public support will follow the same Office-on-pub work.
- **Viewing only.** Edit, search, print, and annotations are out of scope — your app owns chrome and those workflows.
- **You open the file.** Pass bytes or a local path after your own download / picker; cloud open is not built into the package.
- **Large sheets.** Sheets that push process memory toward ~250 MB PSS (as in our mid-range Android spike) can pressure 2–3 GB phones; we are still tuning heap use for huge workbooks.

## Coming next

- Word / Excel / PowerPoint on **pub.dev** via [`office_viewer_engine_dart`](packages/office_viewer_engine_dart) (pure Dart OOXML; MIT-clean, no native binaries) — lower fidelity than the private LOK engine, good enough for typical decks/sheets/linear docs
- More platforms (Web first, then desktop)
- Broader file-type coverage once the pub Office path lands

## Install

```bash
flutter pub add office_viewer office_viewer_engine_pdf
```

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';
```

## Getting started

Register engines once at startup. `clear()` drops any previous registrations so hot restart / tests start from a known empty registry before you register PDF (always register PDF first).

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OfficeEngineRegistry.instance
    ..clear()
    ..register(PdfOfficeEngine());
  runApp(const MyApp());
}
```

Own an `OfficeDocumentController` in a `State`, load a file (path or bytes), handle passwords, and dispose the controller:

```dart
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key, required this.path});
  final String path; // from file_picker, cache download, etc.

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final OfficeDocumentController controller = OfficeDocumentController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    _open();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open({String? password}) async {
    // Prefer a real filename/path so format detection works.
    await controller.load(
      DocumentSource.file(widget.path),
      options: OpenOptions(password: password),
    );

    // load() does not throw OfficeError — check controller.error / state.
    if (controller.error is PasswordRequiredError) {
      final pwd = await _askPassword(); // your dialog
      if (pwd != null && pwd.isNotEmpty) {
        await _open(password: pwd);
      }
      // Cancel → leave state as failed; show retry in your chrome if needed.
      return;
    }
  }

  Future<String?> _askPassword() async => null; // host UI

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (controller.state) {
      case OfficeLoadState.idle:
      case OfficeLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case OfficeLoadState.failed:
        return Center(
          child: Text(controller.error?.message ?? 'Could not open file'),
        );
      case OfficeLoadState.ready:
        return OfficeDocumentView(controller: controller);
    }
  }
}
```

Bytes work the same way when you already have the file in memory (keep the extension in `fileName`):

```dart
final pdfBytes = await File(widget.path).readAsBytes();
await controller.load(
  DocumentSource.bytes(pdfBytes, fileName: 'doc.pdf'),
);
```

`OfficeLoadState`: `idle` → `loading` → `ready` or `failed`. On failure, read `controller.error` (`PasswordRequiredError`, `CorruptDocumentError`, `UnsupportedFormatError`, …).

Packages: [`office_viewer`](https://pub.dev/packages/office_viewer) ·
[`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf)

See the minimal PDF sample in [`example/`](example/) and the full (private LOK) host in [`example_app/`](example_app/). Issues: [github.com/juzuli/office_viewer/issues](https://github.com/juzuli/office_viewer/issues).

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

final bytes = await File('/path/to/a.pdf').readAsBytes();
await controller.load(DocumentSource.bytes(bytes, fileName: 'a.pdf'));

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
| `load` | Open a `DocumentSource` (optional `OpenOptions`); sets `state` / `error` |
| `dispose` | Release the open handle — call from your `State.dispose` |
| `setZoom` / `goToPart` | Programmatic zoom and part navigation |
| `lockZoom` / `lockPan` / `setInteraction` | Runtime gesture locks |
| `parts` / `currentPart` / `state` / `error` | Document metadata and load state |

## Engines

| Engine package | Formats | Notes |
|---|---|---|
| `office_viewer_engine_pdf` | pdf | PDFium via pdfrx. Register **first**. Pub-ready. |
| `office_viewer_engine_lok` | docx/xlsx/pptx/doc/xls/ppt/odf | LibreOfficeKit (**LOK**) tiles — not PDF. Private binaries; not on pub yet. See [CONTRIBUTING.md](CONTRIBUTING.md). |
| `office_viewer_engine_dart` | docx/xlsx/pptx | Pure Dart OOXML. Pub-safe Office path; lower fidelity than LOK. Register **after** LOK when both are present. |

## Concepts

- **Part** — a page, sheet, or slide. `PartInfo.size` is in points.
- **Tile** — a rectangle of one part rendered to RGBA at a given scale (`TileRequest`).
- **Engine** — `OfficeEngine.open()` returns an `OfficeDocumentHandle` that paints tiles.
- **Registry** — first registered engine that supports a format wins. Register the high-fidelity engine first, then any fallback. Call `clear()` before registering so hot restart does not stack duplicate engines.

## License

MIT — see [LICENSE](LICENSE).

The published packages (`office_viewer`, `office_viewer_engine_pdf`) are MIT. The private LibreOfficeKit (**LOK**) engine used only in the example app has **different** licensing and redistribution terms; do not ship those binaries in a public app without your own legal clearance. Setup for contributors: [CONTRIBUTING.md](CONTRIBUTING.md).
