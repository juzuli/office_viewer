import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/xlsx/cell_ref.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_layout.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_models.dart';

XlsxSheet _sheet(CellRange used) => XlsxSheet(
      index: 0,
      name: 'Sheet1',
      partPath: 'xl/worksheets/sheet1.xml',
      usedRange: used,
      cells: const {},
      merges: const [],
      columnWidths: const [],
      rowHeights: const [],
    );

void main() {
  test('tiny usedRange still paints a sheet-like min grid', () {
    final sheet = _sheet(
      const CellRange(minCol: 0, minRow: 0, maxCol: 1, maxRow: 3),
    );

    final paint = XlsxLayout.paintRangeFor(sheet);
    // min 10×25 plus one empty margin col/row
    expect(paint.colCount, greaterThanOrEqualTo(XlsxLayout.minPaintCols + 1));
    expect(paint.rowCount, greaterThanOrEqualTo(XlsxLayout.minPaintRows + 1));

    final layout = XlsxLayout.layoutSheet(sheet);
    expect(layout.size.width, greaterThan(400));
    expect(layout.size.height, greaterThan(300));
  });

  test('larger usedRange is not shrunk by the min floor', () {
    final sheet = _sheet(
      const CellRange(minCol: 0, minRow: 0, maxCol: 19, maxRow: 49),
    );

    final paint = XlsxLayout.paintRangeFor(sheet);
    expect(paint.colCount, 21); // 20 data cols + margin
    expect(paint.rowCount, 51); // 50 data rows + margin
  });
}
