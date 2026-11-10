import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/xlsx/cell_ref.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_chart_resolver.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_models.dart';
import 'package:office_viewer_engine_dart/src/xlsx/xlsx_styles.dart';

XlsxCell _cell(String a1, {String? raw, String? inline, String? type}) {
  final ref = CellRef.parse(a1)!;
  return XlsxCell(
    ref: ref,
    col: ref.col,
    row: ref.row,
    rawValue: raw,
    inlineText: inline,
    type: type,
  );
}

XlsxWorkbook _wb({
  required String sheetName,
  required Map<String, XlsxCell> cells,
  List<XlsxSheet> extraSheets = const [],
}) {
  final sheet = XlsxSheet(
    index: 0,
    name: sheetName,
    partPath: 'xl/worksheets/sheet1.xml',
    usedRange: const CellRange(minCol: 0, minRow: 0, maxCol: 2, maxRow: 5),
    cells: cells,
    merges: const [],
    columnWidths: const [],
    rowHeights: const [],
  );
  return XlsxWorkbook(
    sheets: [sheet, ...extraSheets],
    styles: XlsxStylesheet.empty,
    sharedStrings: const [],
    date1904: false,
    warnings: const [],
  );
}

void main() {
  test('numbers keeps slots aligned with blanks', () {
    final wb = _wb(
      sheetName: 'Data',
      cells: {
        'B2': _cell('B2', raw: '10', type: 'n'),
        'B4': _cell('B4', raw: '30', type: 'n'),
      },
    );
    final r = XlsxChartRangeResolver(wb);
    final nums = r.numbers(r'Data!$B$2:$B$4');
    expect(nums.length, 3);
    expect(nums[0], 10);
    expect(nums[1].isNaN, isTrue);
    expect(nums[2], 30);
  });

  test('sheet lookup is case-insensitive and fails closed', () {
    final other = XlsxSheet(
      index: 1,
      name: 'Other',
      partPath: 'xl/worksheets/sheet2.xml',
      usedRange: const CellRange(minCol: 0, minRow: 0, maxCol: 0, maxRow: 0),
      cells: {'A1': _cell('A1', raw: '99', type: 'n')},
      merges: const [],
      columnWidths: const [],
      rowHeights: const [],
    );
    final wb = _wb(
      sheetName: 'Data',
      cells: {
        'A1': _cell('A1', raw: '1', type: 'n'),
        'A2': _cell('A2', raw: '2', type: 'n'),
      },
      extraSheets: [other],
    );
    final r = XlsxChartRangeResolver(wb);
    expect(r.numbers(r'DATA!$A$1:$A$2'), [1.0, 2.0]);
    expect(r.numbers(r'Missing!$A$1'), isEmpty);
  });

  test('parses sheet names with dots and hyphens', () {
    final sheet = XlsxSheet(
      index: 0,
      name: 'Q1.Data-2024',
      partPath: 'xl/worksheets/sheet1.xml',
      usedRange: const CellRange(minCol: 0, minRow: 0, maxCol: 0, maxRow: 0),
      cells: {'A1': _cell('A1', raw: '7', type: 'n')},
      merges: const [],
      columnWidths: const [],
      rowHeights: const [],
    );
    final wb = XlsxWorkbook(
      sheets: [sheet],
      styles: XlsxStylesheet.empty,
      sharedStrings: const [],
      date1904: false,
      warnings: const [],
    );
    final r = XlsxChartRangeResolver(wb);
    expect(r.numbers(r'Q1.Data-2024!$A$1'), [7.0]);
    expect(r.numbers(r"'Q1.Data-2024'!$A$1"), [7.0]);
  });

  test('strings preserve empty cells for category alignment', () {
    final wb = _wb(
      sheetName: 'Data',
      cells: {
        'A2': _cell('A2', inline: 'Jan', type: 'inlineStr'),
        'A4': _cell('A4', inline: 'Mar', type: 'inlineStr'),
      },
    );
    final r = XlsxChartRangeResolver(wb);
    final cats = r.strings(r'Data!$A$2:$A$4');
    expect(cats, ['Jan', '', 'Mar']);
  });
}
