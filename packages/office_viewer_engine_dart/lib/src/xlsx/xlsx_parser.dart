import 'package:xml/xml.dart';

import '../engine/limits.dart';
import '../opc/package_reader.dart';
import '../opc/relationships.dart';
import '../theme/theme.dart';
import 'cell_ref.dart';
import 'xlsx_models.dart';
import 'xlsx_styles.dart';

const _officeDocumentRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';
const _stylesRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles';
const _sharedStringsRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings';
const _themeRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme';
const _drawingRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing';
const _chartRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart';

/// Parse an XLSX package into a [XlsxWorkbook] (visible sheets only).
class XlsxParser {
  const XlsxParser();

  static const double defaultColWidth = 8.43;
  static const double defaultRowHeightPt = 15.0;
  static const double _emuPerPt = 12700;

  XlsxWorkbook parse(PackageReader package) {
    final warnings = List<String>.from(package.warnings);
    final rootRels = package.rootRelationships();
    final officeRel = rootRels.items
        .where((r) => r.type == _officeDocumentRel)
        .firstOrNull;
    if (officeRel == null) {
      warnings.add('Missing officeDocument relationship');
      return XlsxWorkbook(
        sheets: const [],
        styles: XlsxStylesheet.empty,
        sharedStrings: const [],
        date1904: false,
        warnings: warnings,
      );
    }

    final workbookPath = _resolveTarget('', officeRel.target);
    final workbookXml = package.readPartUtf8(workbookPath);
    if (workbookXml == null) {
      warnings.add('Missing workbook part: $workbookPath');
      return XlsxWorkbook(
        sheets: const [],
        styles: XlsxStylesheet.empty,
        sharedStrings: const [],
        date1904: false,
        warnings: warnings,
      );
    }

    final wbRels = package.relationshipsForPart(workbookPath);
    var date1904 = false;
    final sheetEntries = <_SheetEntry>[];

    try {
      final doc = XmlDocument.parse(workbookXml);
      XmlElement? workbook;
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'workbook') {
          workbook = el;
          break;
        }
      }
      if (workbook != null) {
        for (final child in workbook.childElements) {
          if (child.name.local == 'workbookPr') {
            date1904 = child.getAttribute('date1904') == '1' ||
                child.getAttribute('date1904') == 'true';
          }
          if (child.name.local == 'sheets') {
            var idx = 0;
            for (final sheet in child.childElements) {
              if (sheet.name.local != 'sheet') continue;
              final state = sheet.getAttribute('state');
              if (state == 'hidden' || state == 'veryHidden') continue;
              final name = sheet.getAttribute('name') ?? 'Sheet${idx + 1}';
              final rid = _relationshipId(sheet);
              if (rid == null) {
                warnings.add('Sheet missing relationship id: $name');
                continue;
              }
              final rel = wbRels.byId(rid);
              if (rel == null) {
                warnings.add('Unresolved sheet rel $rid for $name');
                continue;
              }
              final part = _resolveTarget(workbookPath, rel.target);
              sheetEntries.add(_SheetEntry(index: idx, name: name, partPath: part));
              idx++;
            }
          }
        }
      }
    } catch (e) {
      warnings.add('workbook.xml parse failed: $e');
    }

    String? themeXml;
    ThemeColorScheme theme = ThemeColorScheme.defaults;
    ThemeFontScheme fonts = ThemeFontScheme.defaults;
    for (final rel in wbRels.items) {
      if (rel.type == _themeRel) {
        final themePath = _resolveTarget(workbookPath, rel.target);
        themeXml = package.readPartUtf8(themePath);
        if (themeXml != null) {
          theme = ThemeColorScheme.parse(themeXml);
          fonts = ThemeFontScheme.parse(themeXml);
        }
        break;
      }
    }

    XlsxStylesheet styles = XlsxStylesheet.empty;
    for (final rel in wbRels.items) {
      if (rel.type == _stylesRel) {
        final path = _resolveTarget(workbookPath, rel.target);
        styles = XlsxStylesheet.parse(
          package.readPartUtf8(path),
          theme: theme,
          warnings: warnings,
        );
        break;
      }
    }
    styles = _applyThemeFonts(styles, fonts);

    List<String> sharedStrings = const [];
    for (final rel in wbRels.items) {
      if (rel.type == _sharedStringsRel) {
        final path = _resolveTarget(workbookPath, rel.target);
        sharedStrings = _parseSharedStrings(package.readPartUtf8(path), warnings);
        break;
      }
    }

    final limits = package.limits;
    final sheets = <XlsxSheet>[];
    for (final entry in sheetEntries) {
      final sheet = _parseSheet(
        package,
        entry,
        limits,
        warnings,
      );
      if (sheet != null) sheets.add(sheet);
    }

    if (sheets.isEmpty && sheetEntries.isEmpty) {
      warnings.add('No visible worksheets found');
    }

    return XlsxWorkbook(
      sheets: sheets,
      styles: styles,
      sharedStrings: sharedStrings,
      date1904: date1904,
      warnings: warnings,
      themeXml: themeXml,
    );
  }

  static XlsxStylesheet _applyThemeFonts(XlsxStylesheet styles, ThemeFontScheme fonts) {
    if (styles.fonts.isEmpty) return styles;
    final updated = [
      for (final f in styles.fonts)
        f.name == 'Calibri' || f.name.isEmpty
            ? XlsxFont(
                name: fonts.minorLatin,
                sizePt: f.sizePt,
                bold: f.bold,
                italic: f.italic,
                underline: f.underline,
                strike: f.strike,
                color: f.color,
              )
            : f,
    ];
    return styles.copyWith(fonts: updated);
  }

  static List<String> _parseSharedStrings(String? xml, List<String> warnings) {
    if (xml == null || xml.isEmpty) return const [];
    final out = <String>[];
    try {
      final doc = XmlDocument.parse(xml);
      for (final si in doc.descendants.whereType<XmlElement>()) {
        if (si.name.local != 'si') continue;
        final buf = StringBuffer();
        for (final t in si.descendants.whereType<XmlElement>()) {
          if (t.name.local == 't') {
            buf.write(t.innerText);
          }
        }
        out.add(buf.toString());
      }
    } catch (e) {
      warnings.add('sharedStrings parse failed: $e');
    }
    return out;
  }

  static XlsxSheet? _parseSheet(
    PackageReader package,
    _SheetEntry entry,
    ResourceLimits limits,
    List<String> warnings,
  ) {
    final xml = package.readPartUtf8(entry.partPath);
    if (xml == null) {
      warnings.add('Missing worksheet: ${entry.partPath}');
      return null;
    }

    var usedRange = const CellRange(minCol: 0, minRow: 0, maxCol: 0, maxRow: 0);
    final cells = <String, XlsxCell>{};
    final merges = <MergeRange>[];
    final colWidths = <XlsxColumnWidth>[];
    final rowHeights = <XlsxRowHeight>[];
    var cellCount = 0;
    var truncated = false;
    String? drawingRid;

    try {
      final doc = XmlDocument.parse(xml);
      XmlElement? sheetData;
      XmlElement? dimensionEl;
      XmlElement? mergeCellsEl;
      XmlElement? colsEl;

      for (final el in doc.descendants.whereType<XmlElement>()) {
        switch (el.name.local) {
          case 'dimension':
            dimensionEl = el;
          case 'sheetData':
            sheetData = el;
          case 'mergeCells':
            mergeCellsEl = el;
          case 'cols':
            if (colsEl == null) colsEl = el;
          case 'drawing':
            drawingRid ??= _relationshipId(el);
        }
      }

      final dimRef = dimensionEl?.getAttribute('ref');
      final dim = CellRange.parseRef(dimRef);
      if (dim != null) usedRange = dim;

      if (colsEl != null) {
        for (final col in colsEl.childElements) {
          if (col.name.local != 'col') continue;
          final min = (int.tryParse(col.getAttribute('min') ?? '') ?? 1) - 1;
          final max = (int.tryParse(col.getAttribute('max') ?? '') ?? min + 1) - 1;
          final width = double.tryParse(col.getAttribute('width') ?? '') ?? defaultColWidth;
          colWidths.add(XlsxColumnWidth(
            minCol: min,
            maxCol: max,
            width: width,
            hidden: col.getAttribute('hidden') == '1',
            customWidth: col.getAttribute('customWidth') == '1',
          ));
        }
      }

      if (mergeCellsEl != null) {
        for (final mc in mergeCellsEl.childElements) {
          if (mc.name.local != 'mergeCell') continue;
          if (merges.length >= limits.maxMergedRanges) {
            warnings.add('Merge cell limit reached on ${entry.name}');
            break;
          }
          final range = CellRange.parseRef(mc.getAttribute('ref'));
          if (range == null) continue;
          merges.add(MergeRange(
            minCol: range.minCol,
            minRow: range.minRow,
            maxCol: range.maxCol,
            maxRow: range.maxRow,
          ));
        }
      }

      if (sheetData != null) {
        for (final row in sheetData.childElements) {
          if (row.name.local != 'row') continue;
          final rowIdx = (int.tryParse(row.getAttribute('r') ?? '') ?? 0) - 1;
          if (rowIdx < 0) continue;

          final ht = double.tryParse(row.getAttribute('ht') ?? '');
          if (ht != null) {
            rowHeights.add(XlsxRowHeight(
              row: rowIdx,
              heightPt: ht,
              hidden: row.getAttribute('hidden') == '1',
              customHeight: row.getAttribute('customHeight') == '1',
            ));
          }

          for (final c in row.childElements) {
            if (c.name.local != 'c') continue;

            if (cellCount >= limits.maxTableCells) {
              truncated = true;
              if (!warnings.any((w) => w.contains('cell limit'))) {
                warnings.add(
                  'Worksheet cell limit reached (${limits.maxTableCells}); '
                  'remaining cells skipped',
                );
              }
              break;
            }

            final refStr = c.getAttribute('r');
            CellRef ref;
            int col;
            int rowNum;
            if (refStr != null) {
              final parsed = CellRef.parse(refStr);
              if (parsed == null) continue;
              ref = parsed;
              col = parsed.col;
              rowNum = parsed.row;
            } else {
              col = cellCount % 16384;
              rowNum = rowIdx;
              ref = CellRef(col, rowNum);
            }

            usedRange = CellRange.grow(usedRange, col, rowNum);

            String? v;
            String? formula;
            String? inlineText;
            for (final child in c.childElements) {
              switch (child.name.local) {
                case 'v':
                  v = child.innerText;
                case 'f':
                  formula = child.innerText;
                case 'is':
                  for (final t in child.descendants.whereType<XmlElement>()) {
                    if (t.name.local == 't') inlineText = t.innerText;
                  }
              }
            }

            final styleIndex = int.tryParse(c.getAttribute('s') ?? '');
            final type = c.getAttribute('t');

            final cell = XlsxCell(
              ref: ref,
              col: col,
              row: rowNum,
              rawValue: v,
              type: type,
              styleIndex: styleIndex,
              formula: formula,
              inlineText: inlineText,
            );
            cells[refStr ?? '${CellRef.colToLetters(col)}${rowNum + 1}'] = cell;
            cellCount++;
          }
          if (truncated) break;
        }
      }

    } catch (e) {
      warnings.add('Sheet ${entry.name} parse failed: $e');
    }

    final charts = drawingRid == null
        ? const <XlsxFloatingChart>[]
        : _parseSheetCharts(
            package,
            entry.partPath,
            drawingRid,
            warnings,
          );

    return XlsxSheet(
      index: entry.index,
      name: entry.name,
      partPath: entry.partPath,
      usedRange: usedRange,
      cells: cells,
      merges: merges,
      columnWidths: colWidths,
      rowHeights: rowHeights,
      charts: charts,
      truncated: truncated,
    );
  }

  static List<XlsxFloatingChart> _parseSheetCharts(
    PackageReader package,
    String sheetPath,
    String drawingRid,
    List<String> warnings,
  ) {
    final sheetRels = package.relationshipsForPart(sheetPath);
    final drawingRel = sheetRels.byId(drawingRid);
    if (drawingRel == null || drawingRel.type != _drawingRel) {
      warnings.add('Unresolved drawing $drawingRid on $sheetPath');
      return const [];
    }
    final drawingPath = _resolveTarget(sheetPath, drawingRel.target);
    final drawingXml = package.readPartUtf8(drawingPath);
    if (drawingXml == null) {
      warnings.add('Missing drawing part $drawingPath');
      return const [];
    }

    final drawingRels = package.relationshipsForPart(drawingPath);
    final out = <XlsxFloatingChart>[];
    try {
      final doc = XmlDocument.parse(drawingXml);
      for (final el in doc.descendants.whereType<XmlElement>()) {
        final local = el.name.local;
        if (local != 'oneCellAnchor' && local != 'twoCellAnchor') continue;
        final chart = _parseChartAnchor(
          el,
          package,
          drawingPath,
          drawingRels,
          warnings,
        );
        if (chart != null) out.add(chart);
      }
    } catch (e) {
      warnings.add('Drawing parse failed ($drawingPath): $e');
    }
    return out;
  }

  static XlsxFloatingChart? _parseChartAnchor(
    XmlElement anchor,
    PackageReader package,
    String drawingPath,
    Relationships drawingRels,
    List<String> warnings,
  ) {
    int? fromCol;
    int? fromRow;
    int? toCol;
    int? toRow;
    var colOff = 0.0;
    var rowOff = 0.0;
    var toColOff = 0.0;
    var toRowOff = 0.0;
    var widthPt = 0.0;
    var heightPt = 0.0;

    for (final child in anchor.childElements) {
      if (child.name.local == 'from') {
        for (final n in child.childElements) {
          switch (n.name.local) {
            case 'col':
              fromCol = int.tryParse(n.innerText.trim());
            case 'row':
              fromRow = int.tryParse(n.innerText.trim());
            case 'colOff':
              colOff = (double.tryParse(n.innerText.trim()) ?? 0) / _emuPerPt;
            case 'rowOff':
              rowOff = (double.tryParse(n.innerText.trim()) ?? 0) / _emuPerPt;
          }
        }
      } else if (child.name.local == 'ext') {
        final cx = double.tryParse(child.getAttribute('cx') ?? '') ?? 0;
        final cy = double.tryParse(child.getAttribute('cy') ?? '') ?? 0;
        widthPt = cx / _emuPerPt;
        heightPt = cy / _emuPerPt;
      } else if (child.name.local == 'to') {
        for (final n in child.childElements) {
          switch (n.name.local) {
            case 'col':
              toCol = int.tryParse(n.innerText.trim());
            case 'row':
              toRow = int.tryParse(n.innerText.trim());
            case 'colOff':
              toColOff =
                  (double.tryParse(n.innerText.trim()) ?? 0) / _emuPerPt;
            case 'rowOff':
              toRowOff =
                  (double.tryParse(n.innerText.trim()) ?? 0) / _emuPerPt;
          }
        }
      }
    }
    if (fromCol == null || fromRow == null) return null;
    // twoCellAnchor often sizes via from/to only (no xdr:ext).
    if (widthPt <= 0 || heightPt <= 0) {
      if (toCol == null || toRow == null) return null;
      // Match XlsxLayout.excelColWidthToPoints without importing layout.
      const maxDigitWidthPt = 7 * (72 / 96);
      const colPaddingPt = 5 * (72 / 96);
      final colPt = defaultColWidth * maxDigitWidthPt + colPaddingPt;
      final rowPt = defaultRowHeightPt;
      widthPt = (toCol - fromCol) * colPt - colOff + toColOff;
      heightPt = (toRow - fromRow) * rowPt - rowOff + toRowOff;
      if (widthPt <= 0) widthPt = colPt * 6;
      if (heightPt <= 0) heightPt = rowPt * 10;
    }

    String? chartRid;
    for (final el in anchor.descendants.whereType<XmlElement>()) {
      if (el.name.local != 'chart') continue;
      chartRid = _relationshipId(el);
      if (chartRid != null) break;
    }
    if (chartRid == null) return null;
    final rel = drawingRels.byId(chartRid);
    if (rel == null || rel.type != _chartRel) {
      warnings.add('Unresolved chart $chartRid in $drawingPath');
      return null;
    }
    final chartPath = _resolveTarget(drawingPath, rel.target);
    final chartXml = package.readPartUtf8(chartPath);
    if (chartXml == null) {
      warnings.add('Missing chart part $chartPath');
      return null;
    }
    return XlsxFloatingChart(
      fromCol: fromCol,
      fromRow: fromRow,
      colOffPt: colOff,
      rowOffPt: rowOff,
      widthPt: widthPt,
      heightPt: heightPt,
      chartXml: chartXml,
    );
  }

  /// Resolve an OPC relationship [target] relative to [sourcePart].
  ///
  /// Targets that begin with `/` are package-absolute (ECMA-376).
  static String _resolveTarget(String sourcePart, String target) {
    var t = target.replaceAll('\\', '/');
    if (t.startsWith('/')) {
      while (t.startsWith('/')) {
        t = t.substring(1);
      }
      return t.toLowerCase();
    }
    final baseDir = sourcePart.contains('/')
        ? sourcePart.substring(0, sourcePart.lastIndexOf('/'))
        : '';
    final parts = <String>[];
    if (baseDir.isNotEmpty) parts.addAll(baseDir.split('/'));
    for (final seg in t.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg != '.' && seg.isNotEmpty) {
        parts.add(seg);
      }
    }
    return parts.join('/').toLowerCase();
  }
}

class _SheetEntry {
  const _SheetEntry({
    required this.index,
    required this.name,
    required this.partPath,
  });

  final int index;
  final String name;
  final String partPath;
}

String? _relationshipId(XmlElement el) {
  for (final attr in el.attributes) {
    if (attr.name.local == 'id' && attr.name.prefix == 'r') {
      return attr.value;
    }
    if (attr.name.qualified == 'r:id') return attr.value;
  }
  return el.getAttribute('r:id');
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
