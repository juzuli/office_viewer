# office_viewer

Tile-based **document viewer** for Flutter (**iOS + Android**).  
**Publisher:** Leafpane — open the file, leave it alone.  
Package id: `office_viewer` (`flutter pub add office_viewer`).

Scope is open → paint → pan/zoom local files. No edit, search, or print — host
apps own sharing and chrome.

## Status (pub.dev — PDF first)

| Package | On pub.dev plan | What works |
|---|---|---|
| `office_viewer` | **0.0.1** | Viewer API, controller, tiles |
| `office_viewer_engine_pdf` | **0.0.1** | **Real PDF** via pdfrx |
| `office_viewer_engine_lok` | Not yet | DOCX/XLSX/PPTX — private binary spike; Office-on-pub later (WebView OSS or redistributable native) |

```dart
OfficeEngineRegistry.instance.register(PdfOfficeEngine());
await controller.load(DocumentSource.bytes(bytes, fileName: 'a.pdf'));
```

```bash
flutter pub get && flutter analyze && flutter test
```

## Concepts

- **Part**: a page, sheet, or slide. `PartInfo.size` is in points.
- **Tile**: a rectangle of one part rendered to RGBA at a given scale (`TileRequest`).
- **Engine**: `OfficeEngine.open()` returns an `OfficeDocumentHandle` that renders tiles.
- **Registry**: first registered engine that supports a format wins. Register the
  high-fidelity engine first, the light fallback after it.

## Controller & interaction locks

Own an `OfficeDocumentController` outside the view. Pan/zoom gesture locks and
fit-width zoom bounds live on `OfficeViewOptions`:

```dart
final controller = OfficeDocumentController(
  viewOptions: const OfficeViewOptions(
    panEnabled: true,
    zoomEnabled: true, // pinch / double-tap
    minZoom: 1.0,      // fit page width (+ padding)
    maxZoom: 5.0,
  ),
);

await controller.load(DocumentSource.bytes(bytes, fileName: 'a.docx'));
// Encrypted files: catch PasswordRequiredError and retry with:
// await controller.load(source, options: OpenOptions(password: pwd));

// Runtime locks — host chrome still can call setZoom / goToPart:
controller.lockZoom(); // or lockPan(), setInteraction(panEnabled: false)
controller.setZoom(1.5);

OfficeDocumentView(controller: controller);
// optional widget overrides: OfficeDocumentView(controller: c, zoomEnabled: false)
```

## Engines

| Engine package | Formats | Notes |
|---|---|---|
| `office_viewer_engine_pdf` | pdf | PDFium via pdfrx (register first). **Pub-ready.** |
| `office_viewer_engine_lok` | docx/xlsx/pptx/doc/xls/ppt/odf | LOK tiles — **not** PDF. Private binaries; not on pub yet. |
| `office_viewer_engine_web` | docx/xlsx/pptx | Planned (WebView OSS) for pub-safe Office. |

## Phase 0 — LOK (`LOK_HOME`)

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

## Viewer bar (ship checklist)

- Open + readable tiles for DOCX / XLSX / PPTX / PDF on Android arm64 and iOS arm64
- Fit-width zoom, pinch, pan clamp, part/sheet switching
- Soft-fail corrupt/password docs; host passes `OpenOptions(password:)` (example shows a dialog)
- Memory: viewport-culled sheet tiles; slim iOS resources by default
- PDF uses pdfrx (LOK excluded) — no more LO abort on PDF open
- Still open: redistribute license + store size; huge-sheet native heap
