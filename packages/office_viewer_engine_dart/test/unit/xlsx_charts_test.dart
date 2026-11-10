import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_layout.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_painter.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_parser.dart';

void main() {
  test('large_sheet.xlsx paints expanded grid and two charts', () async {
    final bytes =
        await File('test/fixtures/large_sheet.xlsx').readAsBytes();
    final wb = const XlsxParser().parse(PackageReader.open(bytes));
    expect(wb.sheets, isNotEmpty);
    final sheet = wb.sheets.first;
    expect(sheet.charts.length, 2);
    expect(sheet.usedRange.colCount, 3);
    final paint = XlsxLayout.paintRangeFor(sheet);
    expect(paint.colCount, greaterThan(3));
    expect(paint.rowCount, greaterThan(7));

    final dl = XlsxPainter().paint(sheet, wb.styles, wb);
    expect(dl.size.width, greaterThan(200));
    expect(dl.size.height, greaterThan(200));
    final texts = dl.ops.whereType<DrawTextRawOp>().map((t) => t.text).toSet();
    expect(texts.contains('Revenue vs. Cost'), isTrue);
    expect(texts.contains('Revenue trend'), isTrue);
    expect(texts.contains('Month'), isTrue);
    expect(texts.contains('USD thousands'), isTrue);
    expect(texts.contains('Revenue') || texts.contains('Cost'), isTrue);
    expect(dl.ops.whereType<FillRectOp>().length, greaterThan(10));
  });
}
