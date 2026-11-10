/// A1-style cell reference (0-based column and row).
class CellRef {
  const CellRef(this.col, this.row);

  final int col;
  final int row;

  static CellRef? parse(String ref) {
  if (ref.isEmpty) return null;
    final match = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(ref.trim());
    if (match == null) return null;
    final col = _lettersToCol(match.group(1)!);
    final row = int.tryParse(match.group(2)!);
    if (col == null || row == null || row < 1) return null;
    return CellRef(col, row - 1);
  }

  static int? _lettersToCol(String letters) {
    var col = 0;
    for (var i = 0; i < letters.length; i++) {
      final c = letters.codeUnitAt(i);
      if (c < 65 || c > 90) {
        if (c >= 97 && c <= 122) {
          col = col * 26 + (c - 97 + 1);
        } else {
          return null;
        }
      } else {
        col = col * 26 + (c - 65 + 1);
      }
    }
    return col - 1;
  }

  static String colToLetters(int col) {
    var c = col + 1;
    final buf = StringBuffer();
    while (c > 0) {
      c--;
      buf.writeCharCode(65 + (c % 26));
      c ~/= 26;
    }
    return buf.toString().split('').reversed.join();
  }
}

/// Inclusive used range (0-based indices).
class CellRange {
  const CellRange({
    required this.minCol,
    required this.minRow,
    required this.maxCol,
    required this.maxRow,
  });

  final int minCol;
  final int minRow;
  final int maxCol;
  final int maxRow;

  int get colCount => maxCol - minCol + 1;
  int get rowCount => maxRow - minRow + 1;

  bool contains(int col, int row) =>
      col >= minCol && col <= maxCol && row >= minRow && row <= maxRow;

  static CellRange? parseRef(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final parts = ref.split(':');
    final start = CellRef.parse(parts.first);
    if (start == null) return null;
    if (parts.length == 1) {
      return CellRange(
        minCol: start.col,
        minRow: start.row,
        maxCol: start.col,
        maxRow: start.row,
      );
    }
    final end = CellRef.parse(parts[1]);
    if (end == null) return null;
    return CellRange(
      minCol: start.col < end.col ? start.col : end.col,
      minRow: start.row < end.row ? start.row : end.row,
      maxCol: start.col > end.col ? start.col : end.col,
      maxRow: start.row > end.row ? start.row : end.row,
    );
  }

  static CellRange grow(CellRange? current, int col, int row) {
    if (current == null) {
      return CellRange(minCol: col, minRow: row, maxCol: col, maxRow: row);
    }
    return CellRange(
      minCol: col < current.minCol ? col : current.minCol,
      minRow: row < current.minRow ? row : current.minRow,
      maxCol: col > current.maxCol ? col : current.maxCol,
      maxRow: row > current.maxRow ? row : current.maxRow,
    );
  }
}

/// Merge region (0-based, inclusive).
class MergeRange {
  const MergeRange({
    required this.minCol,
    required this.minRow,
    required this.maxCol,
    required this.maxRow,
  });

  final int minCol;
  final int minRow;
  final int maxCol;
  final int maxRow;

  bool isAnchor(int col, int row) => col == minCol && row == minRow;

  bool covers(int col, int row) =>
      col >= minCol && col <= maxCol && row >= minRow && row <= maxRow;
}
