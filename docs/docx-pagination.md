# DOCX pagination (Dart engine)

## Part model

Each physical page becomes one `PartInfo` with `PartKind.page` and `size` taken from the
active section’s `pgSz` (twips → points). The Dart engine’s `DocxLayout.layout` returns one
`DisplayList` per page, aligned with that contract.

## Provisional strategy

1. **Parse** — `DocxParser.parse(PackageReader)` builds a `DocxDocument`: body blocks,
   section properties (`sectPr`), styles, numbering, theme, header/footer parts (soft), and
   image bytes via document relationships.
2. **Section defaults** — The first (or trailing) `w:sectPr` sets page width/height and margins
   (`pgSz`, `pgMar`) in points via `twipToPt`.
3. **Vertical flow** — `DocxLayout` walks body blocks top-to-bottom in the content area
   (`page − margins`). Line height derives from run font size (×1.2) plus paragraph spacing.
4. **Breaks** — `w:pageBreakBefore`, `w:br type="page"`, and `DocSectionBreak` start a new page.
5. **Tables** — `DocxTableLayout` uses `tblGrid` / `tcW` for column widths, honors `gridSpan`
   and `vMerge` (continue cells skipped), paints shading and borders into the display list.
6. **Floats** — Anchored drawings with `wrapSquare` / `wrapTopAndBottom` advance the cursor
   approximately; full text wrap around floats is not yet implemented.
7. **Headers / footers** — Default `headerReference` / `footerReference` parts are flattened to
   plain text bands at `header` / `footer` margin distances.
8. **Fields** — `PAGE` in `fldSimple` renders the current page index; other fields fall back to
   text content when present.
9. **Footnotes** — Parsed from `footnotes.xml` and drawn in a simple block at the bottom of the
   last page (no per-note anchoring yet).
10. **Soft-fail** — Missing parts, unknown styles, and parse errors append to `warnings` and
    rendering continues with Liberation fallbacks.

## Integration with `DartOfficeEngine`

Today `DartOfficeEngine.open` still exposes a single provisional page until layout is wired.
The intended path:

```dart
final doc = const DocxParser().parse(package);
final lists = const DocxLayout().layout(doc);
final parts = lists.asMap().entries.map((e) => PartInfo(
  index: e.key,
  kind: PartKind.page,
  size: e.value.size,
  name: 'Page ${e.key + 1}',
)).toList();
```

## Units

All layout uses **points** (1/72 inch). OOXML twips and half-points are converted with
`lib/src/xml/units.dart` (`twipToPt`, `halfPointToPt`, `emuToPt`).
