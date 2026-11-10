import '../drawing/charts/chart_painter.dart';
import 'cell_ref.dart';
import 'xlsx_models.dart';

/// Resolves chart `c:f` sheet references against workbook cell values.
class XlsxChartRangeResolver implements ChartRangeResolver {
  XlsxChartRangeResolver(this.workbook);

  final XlsxWorkbook workbook;

  /// Supports quoted sheet names (any char except `'`) and simple unquoted names
  /// including `.` / `-` (e.g. `Q1.Data`, `Sales-2024`).
  static final _formulaRe = RegExp(
    r"""(?:'(?<qsheet>[^']+)'|(?<sheet>[A-Za-z0-9_.-]+))!\$?(?<c1>[A-Za-z]+)\$?(?<r1>\d+)(?::\$?(?<c2>[A-Za-z]+)\$?(?<r2>\d+))?""",
  );

  @override
  List<String> strings(String formula) {
    final range = _parse(formula);
    if (range == null) return const [];
    final sheet = _sheetNamed(range.sheet);
    if (sheet == null) return const [];
    final out = <String>[];
    for (var r = range.minRow; r <= range.maxRow; r++) {
      for (var c = range.minCol; c <= range.maxCol; c++) {
        out.add(_display(sheet, c, r));
      }
    }
    return out;
  }

  @override
  List<double> numbers(String formula) {
    final range = _parse(formula);
    if (range == null) return const [];
    final sheet = _sheetNamed(range.sheet);
    if (sheet == null) return const [];
    // Keep one slot per cell so values stay aligned with category labels.
    final out = <double>[];
    for (var r = range.minRow; r <= range.maxRow; r++) {
      for (var c = range.minCol; c <= range.maxCol; c++) {
        out.add(_number(sheet, c, r) ?? double.nan);
      }
    }
    return out;
  }

  XlsxSheet? _sheetNamed(String name) {
    final needle = name.toLowerCase();
    for (final s in workbook.sheets) {
      if (s.name.toLowerCase() == needle) return s;
    }
    // Fail closed — never silently fall back to another worksheet.
    return null;
  }

  String _display(XlsxSheet sheet, int col, int row) {
    final key = '${CellRef.colToLetters(col)}${row + 1}';
    final cell = sheet.cells[key];
    if (cell == null) return '';
    if (cell.inlineText != null && cell.inlineText!.isNotEmpty) {
      return cell.inlineText!;
    }
    if (cell.type == 's') {
      final idx = int.tryParse(cell.rawValue ?? '');
      if (idx != null &&
          idx >= 0 &&
          idx < workbook.sharedStrings.length) {
        return workbook.sharedStrings[idx];
      }
    }
    return cell.rawValue ?? '';
  }

  double? _number(XlsxSheet sheet, int col, int row) {
    final key = '${CellRef.colToLetters(col)}${row + 1}';
    final cell = sheet.cells[key];
    if (cell == null) return null;
    final raw = cell.rawValue ?? cell.inlineText;
    return double.tryParse(raw ?? '');
  }

  ({String sheet, int minCol, int minRow, int maxCol, int maxRow})? _parse(
    String formula,
  ) {
    final m = _formulaRe.firstMatch(formula.trim());
    if (m == null) return null;
    final sheet = m.namedGroup('qsheet') ?? m.namedGroup('sheet') ?? '';
    final a = CellRef.parse('${m.namedGroup('c1')}${m.namedGroup('r1')}');
    if (a == null) return null;
    final c2 = m.namedGroup('c2');
    final r2 = m.namedGroup('r2');
    if (c2 == null || r2 == null) {
      return (
        sheet: sheet,
        minCol: a.col,
        minRow: a.row,
        maxCol: a.col,
        maxRow: a.row,
      );
    }
    final b = CellRef.parse('$c2$r2');
    if (b == null) return null;
    return (
      sheet: sheet,
      minCol: a.col < b.col ? a.col : b.col,
      minRow: a.row < b.row ? a.row : b.row,
      maxCol: a.col > b.col ? a.col : b.col,
      maxRow: a.row > b.row ? a.row : b.row,
    );
  }
}
