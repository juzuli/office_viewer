# Changelog

## 0.1.0-dev

- Fix OPC absolute relationship targets for XLSX (`Target="/xl/..."`).
- Initial pure Dart OOXML engine for DOCX / XLSX / PPTX.
- OPC reader with zip-bomb guards and typed soft-fail errors.
- PPTX: slides, shapes, text, images, basic fills, preset geometry subset.
- XLSX: streaming sparse sheets, styles, number formats, virtualized part size.
- DOCX: styles/numbering, flow pagination, tables, inline/anchor images (basic).
- Bundled OFL fonts (Liberation, Carlito, Caladea).
- Chart painter for cached-value bar/line/pie (placeholder otherwise).
- ResourceLimits + fuzz unit tests; fidelity threshold stubs vs LOK.
