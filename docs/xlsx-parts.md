# XLSX parts (Dart engine)

Spreadsheet workbooks map to **one viewer part per visible worksheet**.

## Part mapping

| Source | Viewer `PartInfo` |
|--------|-------------------|
| `xl/workbook.xml` `<sheet>` with `state` absent or `visible` | One part, `PartKind.sheet`, `name` = sheet name |
| `state="hidden"` or `state="veryHidden"` | **No part** — skipped |

Parse entry: `XlsxParser.parse(PackageReader)` → `XlsxWorkbook.sheets`.

## Part size

`PartInfo.size` is the **used range** of the sheet in **points** at scale 1.0 (same contract as PDF / Dart engines).

Computed by `XlsxLayout.partSize(sheet)`:

1. **Used range** — from `dimension/@ref`, grown from sparse `c/@r` cells if needed (`CellRange`).
2. **Column width** — Excel character width → points  
   `widthPt = widthChars × maxDigitWidthPt + paddingPt`  
   with `maxDigitWidthPt = 7 × (72/96)` (Calibri 11 @ 96 dpi) and  
   `paddingPt = 5 × (72/96)`. Default column width **8.43** characters.
3. **Row height** — `row/@ht` in points when present; default **15 pt**.
4. **Sheet size** — sum of column widths and row heights over the used range.

Tiles use `PartInfo.size` like any other format (`TileRequest.region` in points).

## Painting

`XlsxPainter.paint(sheet, styles, workbook)` → `DisplayList`:

- Cell fills (pattern/solid from `xl/styles.xml` `cellXfs`)
- Grid lines (light default) plus styled borders from xfs
- Text: shared strings, numbers via `NumberFormat` (1900/1904 date systems), alignment from xfs

## Limits

`ResourceLimits.maxTableCells` (default 100 000): if a sheet has more populated cells, parsing **soft-fails** — keeps cells already read and adds a warning. Merge count capped by `maxMergedRanges`.

## Files

| File | Role |
|------|------|
| `lib/src/xlsx/xlsx_parser.dart` | OPC → workbook, sheets, cells, merges, dims |
| `lib/src/xlsx/xlsx_styles.dart` | `styles.xml` fonts, fills, borders, numFmts, cellXfs |
| `lib/src/xlsx/number_format.dart` | Display formatting + section colors |
| `lib/src/xlsx/xlsx_layout.dart` | Used-range size in points |
| `lib/src/xlsx/xlsx_painter.dart` | `DisplayList` builder |
