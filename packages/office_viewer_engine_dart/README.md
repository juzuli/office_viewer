# office_viewer_engine_dart

Pure Dart OOXML engine for [`office_viewer`](https://pub.dev/packages/office_viewer):
**DOCX / XLSX / PPTX** on Android and iOS without native binaries.

MIT-licensed. Register after PDF (and after private LOK when installed so LOK wins).

## Register

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  // ..register(LokOfficeEngine()) // optional private high-fidelity
  ..register(DartOfficeEngine());
```

## Fidelity tiers (honest)

- **PPTX:** typical decks (shapes, text, images, basic fills). No animations /
  transitions / SmartArt / advanced effects.
- **XLSX:** data grids with cached formula values; limited conditional formatting;
  charts from cached values (basic).
- **DOCX:** linear documents; complex floats / multi-column / heavy tables may
  paginate differently from Word.

## Limitations

- Viewing only — no edit / search / print / macros / external resources.
- Password-protected OOXML → `PasswordRequiredError` (no decrypt in v1).
- Legacy `.doc` / `.xls` / `.ppt` → `UnsupportedFormatError`.
- Web/desktop not promised (code is mostly platform-neutral).

## Relation to LOK

Private LibreOfficeKit remains the high-fidelity reference. This package is the
**pub-safe** Office tier. When both are registered, put LOK first.

## License

MIT. Fonts: Liberation (OFL), Carlito (OFL), Caladea (OFL) — see
`THIRD_PARTY_LICENSES.md`.
