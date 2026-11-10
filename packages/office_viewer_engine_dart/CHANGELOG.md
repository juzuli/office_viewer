# Changelog

## 0.1.0

- First pub.dev release: pure Dart OOXML engine for DOCX / XLSX / PPTX.
- Sole Office engine after removal of LibreOfficeKit (`office_viewer_engine_lok`).
- Depends on `office_viewer` `^0.0.8`.
- `DartDocumentHandle.displayLists` is a non-null `List<DisplayList>`.
- OPC reader with zip-bomb guards and typed soft-fail errors.
- PPTX: slides, shapes, text, images, basic fills, preset geometry subset.
- XLSX: streaming sparse sheets, styles, number formats, virtualized part size.
- DOCX: styles/numbering, flow pagination, tables, inline/anchor images (basic).
- Bundled OFL fonts (Liberation, Carlito, Caladea) — see `THIRD_PARTY_LICENSES.md`.
- Chart painter for cached-value bar/line/pie (placeholder otherwise).
- ResourceLimits + fuzz unit tests.
