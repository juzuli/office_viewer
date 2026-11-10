# Engine contract (from real code)

Derived from `lib/src/*.dart`, `packages/office_viewer_engine_pdf`,
`packages/office_viewer_engine_dart`, and
`packages/office_viewer_engine_convert`. Do not invent APIs that conflict with
this.

## `OfficeEngine`

```dart
abstract class OfficeEngine {
  String get id;
  bool supports(OfficeFormat format);
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  });
}
```

- Hosts register engines on `OfficeEngineRegistry.instance` (first match wins).
- `id`: stable short string (`pdf`, `convert`, `dart`).
- `supports`: format gate; PDF engine returns false on web; Convert returns true
  for `doc` / `xls` / `ppt` on mobile/desktop (false on web); missing native
  lib → `EngineUnavailableError` in `open`; Dart returns true for
  `docx` / `xlsx` / `pptx` on Android/iOS and false on web.
- Registration order: **PDF → Convert (optional) → Dart**.

## `OfficeDocumentHandle`

```dart
abstract class OfficeDocumentHandle {
  OfficeFormat get format;
  List<PartInfo> get parts;
  Future<RenderedTile> renderTile(TileRequest request);
  Future<List<SearchHit>> search(String query);
  Future<void> close();
}
```

- `parts` must be known after `open` (sizes in logical points).
- `search` is stubbed (`[]`) in PDF and Dart today.
- Controller closes the previous handle before opening a new one.

## `PartInfo`

```dart
class PartInfo {
  final int index;
  final PartKind kind; // page | sheet | slide
  final String? name;
  final Size size; // points @ scale 1.0
}
```

- Size units: **points** (1/72 in). Sheets may be huge; view tiles them.

## `TileRequest` / `RenderedTile`

```dart
class TileRequest {
  final int partIndex;
  final Rect region;   // part coordinates, points
  final double scale;  // pixels per point
}

class RenderedTile {
  final Uint8List rgba; // premultiplied RGBA8888, row-major, no stride
  final int width;
  final int height;
}
```

View pipeline (`OfficeDocumentView`):

- Tile grid: 256 pt squares.
- `fit = viewportWidth / part.size.width`
- Paint scale ≈ `min(fit * zoom * dpr, 2.0 sheets / 3.0 else)`
- Caps from `OfficeViewerLimits` (`maxMountedTiles=24`, `maxPaintPx=1024`,
  `maxSheetPaintPx=768`, `maxSheetExtentPoints=24000`).

## `DocumentSource` / `OpenOptions`

```dart
sealed class DocumentSource {
  final String? fileName;
  // FileSource(path) | BytesSource(bytes, {fileName})
}

class OpenOptions {
  final String? password;
  final int maxBytes; // default 50 * 1024 * 1024
}
```

Controller picks format via `OfficeFormat.fromName(source.fileName)` **without**
head bytes today — engines should still sniff content when opening.

## Errors (`sealed OfficeError`)

| Type | Use |
|------|-----|
| `UnsupportedFormatError` | No engine / wrong format / non-OLE legacy input |
| `PasswordRequiredError` | Encrypted; fixed message |
| `CorruptDocumentError` | Truncated / bad XML / open failure |
| `ResourceLimitError` | Oversize / decompression / complexity caps |
| `EngineUnavailableError` | Engine init failed / none registered |

## Registry

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(...); // first supports(format) wins
```

No numeric priority API. Registration order: **PDF → Convert (optional) → Dart**.

## How PDF implements it

- `PdfOfficeEngine` / pdfrx; parts = pages with pdfrx page width/height (points).
- `renderTile` maps region×scale → partial page render; BGRA→premul RGBA.
- Password → `PasswordRequiredError`; oversize → `ResourceLimitError`.

## How Convert implements it

- `ConvertOfficeEngine` / Office Oxide FFI; supports `doc` / `xls` / `ppt`.
- View-only: writes OOXML to a private temp file, reads bytes, deletes temp —
  never overwrites the source path.
- Delegates `open` of converted bytes to `DartOfficeEngine` (injectable).
- Missing native lib → `EngineUnavailableError`. Non-OLE → `UnsupportedFormatError`.

## How Dart implements it

- OPC/zip read with size and decompression guards; sniff DOCX / XLSX / PPTX.
- Build display lists per part; `renderTile` paints the clipped region to RGBA.
- Encrypted OOXML → `PasswordRequiredError` (no decrypt in v1).
- Legacy binary Office → `UnsupportedFormatError` (use Convert engine instead).
- Use `ResourceLimitError` for limit breaches.
