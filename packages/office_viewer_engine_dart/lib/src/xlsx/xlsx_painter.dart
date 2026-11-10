import 'dart:typed_data';
import 'dart:ui';

import '../drawing/charts/chart_painter.dart';
import '../fonts/font_registry.dart';
import '../model/display_list.dart';
import '../theme/theme.dart';
import 'cell_ref.dart';
import 'number_format.dart';
import 'xlsx_chart_resolver.dart';
import 'xlsx_layout.dart';
import 'xlsx_models.dart';
import 'xlsx_styles.dart';

class XlsxPainter {
  XlsxPainter({FontRegistry? fonts}) : _fonts = fonts ?? FontRegistry.instance;

  final FontRegistry _fonts;

  static const Color _gridColor = Color(0xFFD4D4D4);
  static const double _defaultBorderWidth = 0.5;

  DisplayList paint(
    XlsxSheet sheet,
    XlsxStylesheet styles,
    XlsxWorkbook workbook, {
    ThemeFontScheme? themeFonts,
  }) {
    final layout = XlsxLayout.layoutSheet(sheet);
    final range = layout.paintRange;
    final ops = <DisplayOp>[];

    ops.add(
      FillRectOp(
        Rect.fromLTWH(0, 0, layout.size.width, layout.size.height),
        const Color(0xFFFFFFFF),
      ),
    );

    final mergeForCell = _buildMergeMap(sheet.merges);

    // Pass 1: fills
    for (final entry in sheet.cells.entries) {
      final cell = entry.value;
      if (cell.col < range.minCol || cell.col > range.maxCol) continue;
      if (cell.row < range.minRow || cell.row > range.maxRow) continue;

      final merge = mergeForCell['${cell.col},${cell.row}'];
      if (merge != null && !merge.isAnchor(cell.col, cell.row)) continue;

      final xf = styles.xf(cell.styleIndex);
      final fill = xf.fill(styles);
      final color = _resolveFillColor(fill);
      if (color == null) continue;

      final colSpan = merge == null ? 1 : merge.maxCol - merge.minCol + 1;
      final rowSpan = merge == null ? 1 : merge.maxRow - merge.minRow + 1;
      final rect = layout.cellRect(
        cell.col - range.minCol,
        cell.row - range.minRow,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );
      ops.add(FillRectOp(rect, color));
    }

    // Pass 2: light grid for the full paint range (data + chart backdrop).
    for (var c = 0; c < range.colCount; c++) {
      final left = layout.colLefts[c];
      final w = layout.colWidths[c];
      for (var r = 0; r < range.rowCount; r++) {
        final top = layout.rowTops[r];
        final h = layout.rowHeights[r];
        final rect = Rect.fromLTWH(left, top, w, h);
        final path = Path()
          ..moveTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..moveTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom);
        ops.add(StrokePathOp(path, _gridColor, _defaultBorderWidth));
      }
    }

    // Pass 3: styled borders
    for (final entry in sheet.cells.entries) {
      final cell = entry.value;
      if (cell.col < range.minCol ||
          cell.col > range.maxCol ||
          cell.row < range.minRow ||
          cell.row > range.maxRow) {
        continue;
      }
      final merge = mergeForCell['${cell.col},${cell.row}'];
      if (merge != null && !merge.isAnchor(cell.col, cell.row)) continue;

      final xf = styles.xf(cell.styleIndex);
      final border = xf.border(styles);
      final colSpan = merge == null ? 1 : merge.maxCol - merge.minCol + 1;
      final rowSpan = merge == null ? 1 : merge.maxRow - merge.minRow + 1;
      final rect = layout.cellRect(
        cell.col - range.minCol,
        cell.row - range.minRow,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );
      _strokeBorder(ops, rect, border);
    }

    // Pass 4: text
    for (final entry in sheet.cells.entries) {
      final cell = entry.value;
      if (cell.col < range.minCol || cell.col > range.maxCol) continue;
      if (cell.row < range.minRow || cell.row > range.maxRow) continue;

      final merge = mergeForCell['${cell.col},${cell.row}'];
      if (merge != null && !merge.isAnchor(cell.col, cell.row)) continue;

      final display = _cellDisplayText(cell, workbook);
      if (display.text.isEmpty) continue;

      final xf = styles.xf(cell.styleIndex);
      final font = xf.font(styles);
      final family = _fonts.familyFor(font.name);

      var textColor = font.color;
      if (display.colorHint != null) textColor = display.colorHint!;

      final colSpan = merge == null ? 1 : merge.maxCol - merge.minCol + 1;
      final rowSpan = merge == null ? 1 : merge.maxRow - merge.minRow + 1;
      final rect = layout.cellRect(
        cell.col - range.minCol,
        cell.row - range.minRow,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );

      const pad = 2.0;
      final inner = rect.deflate(pad);

      final align = _textAlign(xf.hAlign);
      final styled = ParagraphBuilder(
        ParagraphStyle(
          fontFamily: family,
          fontSize: font.sizePt,
          fontWeight: font.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: font.italic ? FontStyle.italic : FontStyle.normal,
          textAlign: align,
          maxLines: xf.wrapText ? null : 1,
        ),
      )
        ..pushStyle(TextStyle(color: textColor))
        ..addText(display.text);
      final paragraph = styled.build()
        ..layout(ParagraphConstraints(width: inner.width));

      double dx = inner.left;
      double dy = inner.top;
      switch (align) {
        case TextAlign.center:
          dx = inner.left + (inner.width - paragraph.maxIntrinsicWidth) / 2;
        case TextAlign.right:
          dx = inner.right - paragraph.maxIntrinsicWidth;
        default:
          dx = inner.left;
      }

      switch (xf.vAlign) {
        case XlsxVerticalAlign.center:
          dy = inner.top + (inner.height - paragraph.height) / 2;
        case XlsxVerticalAlign.bottom:
          dy = inner.bottom - paragraph.height;
        default:
          dy = inner.top;
      }

      ops.add(DrawParagraphOp(Offset(dx, dy), paragraph));
    }

    // Pass 5: floating charts from drawing.xml
    if (sheet.charts.isNotEmpty) {
      final resolver = XlsxChartRangeResolver(workbook);
      const painter = ChartPainter();
      for (final chart in sheet.charts) {
        final x = layout.absoluteX(chart.fromCol, chart.colOffPt);
        final y = layout.absoluteY(chart.fromRow, chart.rowOffPt);
        final painted = painter.paintCachedChart(
          chart.chartXml,
          size: Size(chart.widthPt, chart.heightPt),
          rangeResolver: resolver,
        );
        ops.add(
          PushTransformOp(
            Float64List.fromList([
              1, 0, 0, 0,
              0, 1, 0, 0,
              0, 0, 1, 0,
              x, y, 0, 1,
            ]),
          ),
        );
        ops.addAll(painted.ops);
        ops.add(const PopTransformOp());
      }
    }

    return DisplayList(ops: ops, size: layout.size);
  }

  static Map<String, MergeRange> _buildMergeMap(List<MergeRange> merges) {
    final out = <String, MergeRange>{};
    for (final m in merges) {
      for (var r = m.minRow; r <= m.maxRow; r++) {
        for (var c = m.minCol; c <= m.maxCol; c++) {
          out['$c,$r'] = m;
        }
      }
    }
    return out;
  }

  static Color? _resolveFillColor(XlsxFill fill) {
    if (!fill.isSolid) return null;
    final fg = fill.fgColor;
    if (fg != null && fg.a > 0 && fg != const Color(0xFFFFFFFF)) {
      return fg;
    }
    final bg = fill.bgColor;
    if (bg != null && bg != const Color(0xFFFFFFFF)) return bg;
    return null;
  }

  static void _strokeBorder(List<DisplayOp> ops, Rect rect, XlsxBorder border) {
    void side(Rect r, Color color, double w) {
      if (w <= 0) return;
      final path = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.right, r.top);
      ops.add(StrokePathOp(path, color, w));
    }

    final topW = _borderWidth(border.top.style);
    if (topW > 0) {
      side(
        Rect.fromLTWH(rect.left, rect.top, rect.width, 0),
        border.top.color,
        topW,
      );
    }
    final botW = _borderWidth(border.bottom.style);
    if (botW > 0) {
      final path = Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.right, rect.bottom);
      ops.add(StrokePathOp(path, border.bottom.color, botW));
    }
    final leftW = _borderWidth(border.left.style);
    if (leftW > 0) {
      final path = Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.left, rect.bottom);
      ops.add(StrokePathOp(path, border.left.color, leftW));
    }
    final rightW = _borderWidth(border.right.style);
    if (rightW > 0) {
      final path = Path()
        ..moveTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.bottom);
      ops.add(StrokePathOp(path, border.right.color, rightW));
    }
  }

  static double _borderWidth(XlsxBorderStyle style) {
    switch (style) {
      case XlsxBorderStyle.none:
        return 0;
      case XlsxBorderStyle.hair:
        return 0.5;
      case XlsxBorderStyle.thin:
      case XlsxBorderStyle.dashed:
      case XlsxBorderStyle.dotted:
        return 0.75;
      case XlsxBorderStyle.medium:
        return 1.5;
      case XlsxBorderStyle.thick:
      case XlsxBorderStyle.double:
        return 2.25;
    }
  }

  static TextAlign _textAlign(XlsxHorizontalAlign h) {
    switch (h) {
      case XlsxHorizontalAlign.center:
        return TextAlign.center;
      case XlsxHorizontalAlign.right:
        return TextAlign.right;
      case XlsxHorizontalAlign.general:
      case XlsxHorizontalAlign.left:
      case XlsxHorizontalAlign.fill:
      case XlsxHorizontalAlign.justify:
        return TextAlign.left;
    }
  }

  FormattedCellValue _cellDisplayText(XlsxCell cell, XlsxWorkbook workbook) {
    final styles = workbook.styles;
    final xf = styles.xf(cell.styleIndex);
    final fmtCode = xf.numFmtCode(styles);

    Object? value;
    var forceText = false;

    switch (cell.type) {
      case 's':
        final idx = int.tryParse(cell.rawValue ?? '');
        if (idx != null && idx >= 0 && idx < workbook.sharedStrings.length) {
          value = workbook.sharedStrings[idx];
          forceText = true;
        } else {
          value = cell.rawValue ?? '';
        }
      case 'inlineStr':
      case 'str':
        value = cell.inlineText ?? cell.rawValue ?? '';
        forceText = true;
      case 'b':
        value = cell.rawValue == '1';
      case 'e':
        value = cell.rawValue ?? '#ERROR';
        forceText = true;
      default:
        if (cell.inlineText != null) {
          value = cell.inlineText;
          forceText = true;
        } else {
          value = double.tryParse(cell.rawValue ?? '') ?? cell.rawValue;
        }
    }

    return NumberFormat.format(
      value: value,
      formatCode: fmtCode,
      date1904: workbook.date1904,
      forceText: forceText,
    );
  }
}
