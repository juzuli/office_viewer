import '../model/geometry.dart';
import 'docx_model.dart';

/// Lays out a [DocTable] into drawable cell rectangles (fixed grid).
class DocxTableLayout {
  const DocxTableLayout();

  List<DocTableLayoutCell> layout(
    DocTable table,
    double availableWidthPt,
  ) {
    final colWidths = _resolveColumnWidths(table, availableWidthPt);
    final gridCols = colWidths.length;
    if (gridCols == 0) return const [];

    final placements = <DocTableLayoutCell>[];
    final vMergeHeight = List<double>.filled(gridCols, 0);
    var rowTop = 0.0;
    var rowIndex = 0;

    for (final row in table.rows) {
      var col = 0;
      var rowHeight =
          row.heightPt ?? _estimateRowHeight(row, colWidths);
      var colOffset = 0.0;

      for (final cell in row.cells) {
        while (col < gridCols && vMergeHeight[col] > rowTop + 0.01) {
          col++;
          colOffset = _sumWidths(colWidths, 0, col);
        }
        if (col >= gridCols) break;

        final span = cell.gridSpan.clamp(1, gridCols - col);
        final cellWidth = _sumWidths(colWidths, col, col + span);
        final left = colOffset;
        var height = rowHeight;

        if (cell.vMerge == DocVMerge.continue_) {
          col += span;
          colOffset = left + cellWidth;
          continue;
        }
        if (cell.vMerge == DocVMerge.restart) {
          for (var c = col; c < col + span; c++) {
            vMergeHeight[c] = rowTop + height;
          }
        }

        placements.add(
          DocTableLayoutCell(
            cell: cell,
            rect: RectD.fromLTWH(left, rowTop, cellWidth, height),
            row: rowIndex,
            col: col,
            colSpan: span,
          ),
        );

        col += span;
        colOffset = left + cellWidth;
      }

      rowTop += rowHeight;
      rowIndex++;
    }

    return placements;
  }

  List<double> _resolveColumnWidths(DocTable table, double widthPt) {
    if (table.columnWidthsPt.isNotEmpty) {
      var total = 0.0;
      for (final w in table.columnWidthsPt) {
        total += w;
      }
      if (total > 0) {
        final scale = widthPt / total;
        return table.columnWidthsPt.map((w) => w * scale).toList();
      }
      return List<double>.from(table.columnWidthsPt);
    }
    final cols = _inferColumnCount(table);
    if (cols <= 0) return [widthPt];
    final each = widthPt / cols;
    return List<double>.filled(cols, each);
  }

  int _inferColumnCount(DocTable table) {
    var max = 0;
    for (final row in table.rows) {
      var n = 0;
      for (final cell in row.cells) {
        n += cell.gridSpan;
      }
      if (n > max) max = n;
    }
    return max;
  }

  double _sumWidths(List<double> widths, int from, int to) {
    var s = 0.0;
    for (var i = from; i < to && i < widths.length; i++) {
      s += widths[i];
    }
    return s;
  }

  /// Estimate wrap height from text length and column widths (points).
  double _estimateRowHeight(DocTableRow row, List<double> colWidths) {
    var maxH = 22.0;
    var col = 0;
    for (final cell in row.cells) {
      final span = cell.gridSpan.clamp(1, colWidths.length - col);
      final width = _sumWidths(colWidths, col, col + span).clamp(24.0, 2000.0);
      final text = StringBuffer();
      for (final block in cell.blocks) {
        if (block is DocParagraph) {
          for (final r in block.runs) {
            text.write(r.text);
            if (r.brKind == DocBreakKind.line) text.write('\n');
          }
          text.write('\n');
        }
      }
      final content = text.toString().trim();
      // ~6.5 pt average glyph width at 11 pt sans.
      final charsPerLine = (width / 6.5).clamp(4.0, 120.0);
      final hardLines = content.isEmpty ? 1 : content.split('\n').length;
      var wrapLines = 0;
      for (final line in content.split('\n')) {
        wrapLines += (line.length / charsPerLine).ceil().clamp(1, 30);
      }
      if (content.isEmpty) wrapLines = 1;
      final h = (wrapLines.clamp(hardLines, 40)) * 14.0 + 10.0;
      if (h > maxH) maxH = h;
      col += span;
    }
    if (row.heightPt != null && row.heightPt! > maxH) return row.heightPt!;
    return maxH;
  }
}

class DocTableLayoutCell {
  const DocTableLayoutCell({
    required this.cell,
    required this.rect,
    required this.row,
    required this.col,
    required this.colSpan,
  });

  final DocTableCell cell;
  final RectD rect;
  final int row;
  final int col;
  final int colSpan;
}

void paintTableBorders(
  List<DisplayBorderOp> out,
  DocTableLayoutCell placement, {
  DocTableBorders tableBorders = const DocTableBorders(),
  int rowCount = 1,
  int colCount = 1,
}) {
  final cellBorders = placement.cell.borders;
  final row = placement.row;
  final col = placement.col;
  final lastRow = rowCount <= 1 || row >= rowCount - 1;
  final lastCol = col + placement.colSpan >= colCount;

  DocBorder? resolve(DocBorder? cellSide, DocBorder? outer, DocBorder? inner) {
    if (cellSide != null) return cellSide;
    return outer ?? inner;
  }

  final top = resolve(
    cellBorders.top,
    row == 0 ? tableBorders.top : null,
    tableBorders.insideH,
  );
  final bottom = resolve(
    cellBorders.bottom,
    lastRow ? tableBorders.bottom : null,
    tableBorders.insideH,
  );
  final left = resolve(
    cellBorders.left,
    col == 0 ? tableBorders.left : null,
    tableBorders.insideV,
  );
  final right = resolve(
    cellBorders.right,
    lastCol ? tableBorders.right : null,
    tableBorders.insideV,
  );

  void add(RectD rect, DocBorder? b) {
    if (b == null || b.style == DocBorderStyle.none) return;
    out.add(DisplayBorderOp(rect: rect, border: b));
  }

  final box = placement.rect;
  final tw = top?.widthPt ?? 0.75;
  final bw = bottom?.widthPt ?? 0.75;
  final lw = left?.widthPt ?? 0.75;
  final rw = right?.widthPt ?? 0.75;
  add(RectD(box.left, box.top, box.right, box.top + tw), top);
  add(RectD(box.left, box.bottom - bw, box.right, box.bottom), bottom);
  add(RectD(box.left, box.top, box.left + lw, box.bottom), left);
  add(RectD(box.right - rw, box.top, box.right, box.bottom), right);
}

class DisplayBorderOp {
  const DisplayBorderOp({required this.rect, required this.border});

  final RectD rect;
  final DocBorder border;
}
