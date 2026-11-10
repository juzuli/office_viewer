import 'package:flutter/foundation.dart';

import 'cell_ref.dart';
import 'xlsx_styles.dart';

/// Single parsed worksheet cell.
class XlsxCell {
  const XlsxCell({
    required this.ref,
    required this.col,
    required this.row,
    this.rawValue,
    this.type,
    this.styleIndex,
    this.formula,
    this.inlineText,
  });

  final CellRef ref;
  final int col;
  final int row;
  final String? rawValue;
  /// OOXML `t` attribute: b, d, e, inlineStr, n, s, str.
  final String? type;
  final int? styleIndex;
  final String? formula;
  final String? inlineText;
}

class XlsxColumnWidth {
  const XlsxColumnWidth({
    required this.minCol,
    required this.maxCol,
    required this.width,
    this.hidden = false,
    this.customWidth = false,
  });

  final int minCol;
  final int maxCol;
  final double width;
  final bool hidden;
  final bool customWidth;
}

class XlsxRowHeight {
  const XlsxRowHeight({
    required this.row,
    required this.heightPt,
    this.hidden = false,
    this.customHeight = false,
  });

  final int row;
  final double heightPt;
  final bool hidden;
  final bool customHeight;
}

/// Chart anchored on a worksheet via `xdr:oneCellAnchor` / `twoCellAnchor`.
@immutable
class XlsxFloatingChart {
  const XlsxFloatingChart({
    required this.fromCol,
    required this.fromRow,
    required this.colOffPt,
    required this.rowOffPt,
    required this.widthPt,
    required this.heightPt,
    required this.chartXml,
  });

  /// 0-based anchor column / row (`xdr:from`).
  final int fromCol;
  final int fromRow;
  final double colOffPt;
  final double rowOffPt;
  final double widthPt;
  final double heightPt;
  final String chartXml;
}

@immutable
class XlsxSheet {
  const XlsxSheet({
    required this.index,
    required this.name,
    required this.partPath,
    required this.usedRange,
    required this.cells,
    required this.merges,
    required this.columnWidths,
    required this.rowHeights,
    this.charts = const [],
    this.truncated = false,
  });

  final int index;
  final String name;
  final String partPath;
  final CellRange usedRange;
  final Map<String, XlsxCell> cells;
  final List<MergeRange> merges;
  final List<XlsxColumnWidth> columnWidths;
  final List<XlsxRowHeight> rowHeights;
  final List<XlsxFloatingChart> charts;
  final bool truncated;

  String cellKey(int col, int row) => '${CellRef.colToLetters(col)}${row + 1}';
}

@immutable
class XlsxWorkbook {
  const XlsxWorkbook({
    required this.sheets,
    required this.styles,
    required this.sharedStrings,
    required this.date1904,
    required this.warnings,
    this.themeXml,
  });

  final List<XlsxSheet> sheets;
  final XlsxStylesheet styles;
  final List<String> sharedStrings;
  final bool date1904;
  final List<String> warnings;
  final String? themeXml;
}
