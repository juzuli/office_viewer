# Engine contract (from real code)

Derived from `lib/src/*.dart`, `packages/office_viewer_engine_pdf`, and
`packages/office_viewer_engine_lok`. Do not invent APIs that conflict with this.

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
- `id`: stable short string (`pdf`, `lok`, planned `dart`).
- `supports`: format gate; PDF engine returns false on web; LOK returns false for
  `pdf` / `unknown` / web and true for other formats on Android/iOS.

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
- `search` is stubbed (`[]`) in PDF and LOK today; Dart engine may also return `[]`.
- Controller closes the previous handle before opening a new one.

## `PartInfo`

```dart
class PartInfo {
  final int index;
  final PartKind kind; // page | sheet | slide
  final String? name;
  final Size size;           // points @ scale 1.0
  final Offset contentOrigin; // Writer virtual-page offset (LOK)
  final int lokPartIndex;     // LOK setPart index
}
```

- Size units: **points** (1/72 in). Sheets may be huge; view tiles them.
- LOK Writer: multiple virtual pages share `lokPartIndex: 0` with different
  `contentOrigin`. Pure Dart does not need LOK fields; leave defaults.

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
| `UnsupportedFormatError` | No engine / wrong format / legacy binary |
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

No numeric priority API.

## How PDF implements it

- `PdfOfficeEngine` / pdfrx; parts = pages with pdfrx page width/height (points).
- `renderTile` maps region×scale → partial page render; BGRA→premul RGBA.
- Password → `PasswordRequiredError`; oversize → `ResourceLimitError`.

## How LOK implements it

- Materialize bytes to temp file; `documentLoad` with read-only JSON options.
- Parts: Writer page rectangles → virtual pages; sheets/slides → `getDocumentSize`
  (twips÷20 → points); sheets clamped to `maxSheetExtentPoints`.
- `renderTile` rewrites `partIndex`→`lokPartIndex` and shifts region by
  `contentOrigin`; paints in twips; BGRA→RGBA when needed.
- All FFI serialized on root isolate.

## Implications for `DartOfficeEngine`

- Implement the same tile RGBA contract; ignore `contentOrigin`/`lokPartIndex`
  unless useful for internal paging.
- Use `ResourceLimitError` for limit breaches (already in core).
- Registration order: PDF → LOK (optional) → Dart.
