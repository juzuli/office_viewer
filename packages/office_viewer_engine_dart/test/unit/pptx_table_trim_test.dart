import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/drawing/shapes.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_layout.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';

void main() {
  test('trimTrailingEmptyTable drops sparse trailing cols/rows', () {
    final rows = [
      PptxTableRow(
        heightPt: 20,
        cells: [
          PptxTableCell(text: 'A'),
          PptxTableCell(text: ''),
          PptxTableCell(text: ''),
        ],
      ),
      PptxTableRow(
        heightPt: 20,
        cells: [
          PptxTableCell(text: 'B'),
          PptxTableCell(text: ''),
          PptxTableCell(text: ''),
        ],
      ),
      PptxTableRow(
        heightPt: 20,
        cells: [
          PptxTableCell(text: ''),
          PptxTableCell(text: ''),
          PptxTableCell(text: ''),
        ],
      ),
    ];
    final trimmed = PptxParser.trimTrailingEmptyTable([40, 40, 40], rows);
    expect(trimmed.colWidths, [40]);
    expect(trimmed.rows.length, 2);
    expect(trimmed.rows[0].cells.single.text, 'A');
    expect(trimmed.rows[1].cells.single.text, 'B');
  });

  test('table paint scales to graphicFrame size', () {
    final table = PptxTable(
      transform: const ShapeTransform(
        x: 0,
        y: 0,
        width: 200,
        height: 100,
      ),
      columnWidthsPt: const [400, 400],
      rows: [
        PptxTableRow(
          heightPt: 80,
          cells: [
            PptxTableCell(text: 'H1'),
            PptxTableCell(text: 'H2'),
          ],
        ),
        PptxTableRow(
          heightPt: 80,
          cells: [
            PptxTableCell(text: 'A'),
            PptxTableCell(text: 'B'),
          ],
        ),
      ],
      firstRow: true,
      bandRow: true,
    );
    final slide = PptxSlide(
      index: 0,
      partPath: 'ppt/slides/slide1.xml',
      size: const Size(960, 540),
      shapes: [table],
    );
    final theme = OfficeTheme(
      colorScheme: ThemeColorScheme.defaults,
      fontScheme: ThemeFontScheme.defaults,
    );
    final dl = const PptxLayout().layout(
      slide,
      theme,
      applyInheritance: false,
    );
    final fills = dl.ops.whereType<FillRectOp>().where((op) {
      return op.rect.width < 900;
    }).toList();
    expect(fills, isNotEmpty);
    final maxRight =
        fills.map((f) => f.rect.right).reduce((a, b) => a > b ? a : b);
    final maxBottom =
        fills.map((f) => f.rect.bottom).reduce((a, b) => a > b ? a : b);
    expect(maxRight, closeTo(200, 0.5));
    expect(maxBottom, closeTo(100, 0.5));
  });
}
