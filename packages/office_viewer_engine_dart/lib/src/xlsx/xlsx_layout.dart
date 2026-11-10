import 'dart:ui';

import 'cell_ref.dart';
import 'xlsx_models.dart';
import 'xlsx_parser.dart';

/// Column / row metrics and sheet size in **points** (scale 1.0).
class XlsxSheetLayout {
  const XlsxSheetLayout({
    required this.size,
    required this.colLefts,
    required this.colWidths,
    required this.rowTops,
    required this.rowHeights,
    required this.paintRange,
  });

  final Size size;
  final List<double> colLefts;
  final List<double> colWidths;
  final List<double> rowTops;
  final List<double> rowHeights;
  /// Range used for the painted grid (may extend past data for charts).
  final CellRange paintRange;

  double colRight(int col) =>
      col < colLefts.length ? colLefts[col] + colWidths[col] : 0;

  double rowBottom(int row) =>
      row < rowTops.length ? rowTops[row] + rowHeights[row] : 0;

  /// Absolute sheet X for a 0-based column + EMU/pt offset.
  double absoluteX(int absCol, double colOffPt) {
    final i = absCol - paintRange.minCol;
    if (i < 0) return colOffPt;
    if (i >= colLefts.length) {
      return (colLefts.isEmpty ? 0.0 : colLefts.last + colWidths.last) + colOffPt;
    }
    return colLefts[i] + colOffPt;
  }

  /// Absolute sheet Y for a 0-based row + offset.
  double absoluteY(int absRow, double rowOffPt) {
    final i = absRow - paintRange.minRow;
    if (i < 0) return rowOffPt;
    if (i >= rowTops.length) {
      return (rowTops.isEmpty ? 0.0 : rowTops.last + rowHeights.last) + rowOffPt;
    }
    return rowTops[i] + rowOffPt;
  }

  Rect cellRect(int col, int row, {int colSpan = 1, int rowSpan = 1}) {
    final left = col < colLefts.length ? colLefts[col] : 0.0;
    final top = row < rowTops.length ? rowTops[row] : 0.0;
    var w = 0.0;
    for (var c = col; c < col + colSpan && c < colWidths.length; c++) {
      w += colWidths[c];
    }
    var h = 0.0;
    for (var r = row; r < row + rowSpan && r < rowHeights.length; r++) {
      h += rowHeights[r];
    }
    return Rect.fromLTWH(left, top, w, h);
  }
}

class XlsxLayout {
  const XlsxLayout();

  /// Calibri 11 max digit width ≈ 7 px @ 96 dpi → points via 72/96.
  static const double maxDigitWidthPt = 7 * (72 / 96);
  static const double colPaddingPt = 5 * (72 / 96);

  static double excelColWidthToPoints(double charWidth) =>
      charWidth * maxDigitWidthPt + colPaddingPt;

  static CellRange paintRangeFor(XlsxSheet sheet) {
    var range = sheet.usedRange;
    final defaultColPt = excelColWidthToPoints(XlsxParser.defaultColWidth);
    final defaultRowPt = XlsxParser.defaultRowHeightPt;
    for (final chart in sheet.charts) {
      final colsSpanned =
          ((chart.colOffPt + chart.widthPt) / defaultColPt).ceil().clamp(1, 64);
      final rowsSpanned =
          ((chart.rowOffPt + chart.heightPt) / defaultRowPt).ceil().clamp(1, 128);
      range = CellRange.grow(range, chart.fromCol, chart.fromRow);
      range = CellRange.grow(
        range,
        chart.fromCol + colsSpanned - 1,
        chart.fromRow + rowsSpanned - 1,
      );
    }
    // Keep a small empty margin like Excel's visible sheet.
    if (sheet.charts.isNotEmpty) {
      range = CellRange.grow(range, range.maxCol + 1, range.maxRow + 1);
    }
    return range;
  }

  static XlsxSheetLayout layoutSheet(XlsxSheet sheet) {
    final range = paintRangeFor(sheet);
    final colCount = range.colCount;
    final rowCount = range.rowCount;

    final colWidths = List<double>.filled(colCount, 0);
    for (var i = 0; i < colCount; i++) {
      final absCol = range.minCol + i;
      colWidths[i] = excelColWidthToPoints(XlsxParser.defaultColWidth);
      for (final cw in sheet.columnWidths) {
        if (absCol >= cw.minCol && absCol <= cw.maxCol) {
          colWidths[i] = excelColWidthToPoints(cw.width);
          break;
        }
      }
    }

    final rowHeights =
        List<double>.filled(rowCount, XlsxParser.defaultRowHeightPt);
    for (final rh in sheet.rowHeights) {
      if (rh.row < range.minRow || rh.row > range.maxRow) continue;
      rowHeights[rh.row - range.minRow] = rh.heightPt;
    }

    final colLefts = List<double>.filled(colCount, 0);
    for (var i = 1; i < colCount; i++) {
      colLefts[i] = colLefts[i - 1] + colWidths[i - 1];
    }

    final rowTops = List<double>.filled(rowCount, 0);
    for (var i = 1; i < rowCount; i++) {
      rowTops[i] = rowTops[i - 1] + rowHeights[i - 1];
    }

    final width = colLefts.isEmpty ? 0.0 : colLefts.last + colWidths.last;
    final height = rowTops.isEmpty ? 0.0 : rowTops.last + rowHeights.last;

    return XlsxSheetLayout(
      size: Size(width, height),
      colLefts: colLefts,
      colWidths: colWidths,
      rowTops: rowTops,
      rowHeights: rowHeights,
      paintRange: range,
    );
  }

  static Size partSize(XlsxSheet sheet) => layoutSheet(sheet).size;
}
