import 'dart:typed_data';
import 'dart:ui';

import '../model/style.dart';
import '../theme/theme.dart';
import 'docx_numbering.dart';
import 'docx_styles.dart';

/// Parsed DOCX document (logical model, points for layout-ready sizes).
class DocxDocument {
  const DocxDocument({
    required this.body,
    required this.sections,
    required this.styles,
    required this.numbering,
    required this.theme,
    this.headers = const {},
    this.footers = const {},
    this.footnotes = const [],
    this.warnings = const [],
    this.mediaByRelId = const {},
  });

  final List<DocBodyBlock> body;
  final List<DocSection> sections;
  final DocxStyleSheet styles;
  final DocxNumbering numbering;
  final OfficeTheme theme;
  final Map<String, DocHeaderFooter> headers;
  final Map<String, DocHeaderFooter> footers;
  final List<DocFootnote> footnotes;
  final List<String> warnings;

  /// Relationship id → raw image bytes (from document part rels).
  final Map<String, Uint8List> mediaByRelId;
}

sealed class DocBodyBlock {
  const DocBodyBlock();
}

class DocParagraph extends DocBodyBlock {
  DocParagraph({
    required this.runs,
    this.pStyleId,
    this.paraStyle = const ComputedParaStyle(),
    this.numId,
    this.ilvl,
    this.pageBreakBefore = false,
    this.isList = false,
    this.listLabel,
  });

  final List<DocRun> runs;
  final String? pStyleId;
  ComputedParaStyle paraStyle;
  final int? numId;
  final int? ilvl;
  final bool pageBreakBefore;
  bool isList;
  String? listLabel;
}

class DocTable extends DocBodyBlock {
  const DocTable({
    required this.rows,
    this.columnWidthsPt = const [],
    this.borders = const DocTableBorders(),
  });

  final List<DocTableRow> rows;
  final List<double> columnWidthsPt;
  final DocTableBorders borders;
}

class DocTableRow {
  const DocTableRow({required this.cells, this.heightPt});

  final List<DocTableCell> cells;
  final double? heightPt;
}

class DocTableCell {
  const DocTableCell({
    required this.blocks,
    this.gridSpan = 1,
    this.vMerge = DocVMerge.none,
    this.widthPt,
    this.shading,
    this.borders = const DocCellBorders(),
    this.verticalAlign = DocVerticalAlign.top,
  });

  final List<DocBodyBlock> blocks;
  final int gridSpan;
  final DocVMerge vMerge;
  final double? widthPt;
  final Color? shading;
  final DocCellBorders borders;
  final DocVerticalAlign verticalAlign;
}

enum DocVMerge { none, restart, continue_ }

enum DocVerticalAlign { top, center, bottom }

class DocTableBorders {
  const DocTableBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.insideH,
    this.insideV,
  });

  final DocBorder? top;
  final DocBorder? left;
  final DocBorder? bottom;
  final DocBorder? right;
  final DocBorder? insideH;
  final DocBorder? insideV;
}

class DocCellBorders {
  const DocCellBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
  });

  final DocBorder? top;
  final DocBorder? left;
  final DocBorder? bottom;
  final DocBorder? right;
}

class DocBorder {
  const DocBorder({
    required this.color,
    this.widthPt = 0.5,
    this.style = DocBorderStyle.single,
  });

  final Color color;
  final double widthPt;
  final DocBorderStyle style;
}

enum DocBorderStyle { none, single, double_ }

class DocSectionBreak extends DocBodyBlock {
  const DocSectionBreak(this.section);

  final DocSection section;
}

class DocSection {
  const DocSection.withMargins({
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.contentLeftPt,
    required this.contentTopPt,
    required this.contentRightPt,
    required this.contentBottomPt,
    this.headerDistancePt = 36,
    this.footerDistancePt = 36,
    this.headerRelId,
    this.footerRelId,
    this.firstHeaderRelId,
    this.firstFooterRelId,
  });

  final double pageWidthPt;
  final double pageHeightPt;
  final double contentLeftPt;
  final double contentTopPt;
  final double contentRightPt;
  final double contentBottomPt;
  final double headerDistancePt;
  final double footerDistancePt;
  final String? headerRelId;
  final String? footerRelId;
  final String? firstHeaderRelId;
  final String? firstFooterRelId;

  double get contentWidthPt =>
      pageWidthPt - contentLeftPt - contentRightPt;

  double get contentHeightPt =>
      pageHeightPt - contentTopPt - contentBottomPt;
}

class DocHeaderFooter {
  const DocHeaderFooter({required this.blocks});

  final List<DocBodyBlock> blocks;
}

class DocFootnote {
  const DocFootnote({
    required this.id,
    required this.blocks,
  });

  final String id;
  final List<DocBodyBlock> blocks;
}

class DocRun {
  const DocRun({
    this.text = '',
    this.style = const ComputedRunStyle(),
    this.image,
    this.chart,
    this.tab = false,
    this.brKind,
    this.field,
  });

  final String text;
  final ComputedRunStyle style;
  final DocImage? image;
  final DocChart? chart;
  final bool tab;

  /// null = no break; line, page, column.
  final DocBreakKind? brKind;
  final DocField? field;

  bool get hasContent =>
      text.isNotEmpty ||
      image != null ||
      chart != null ||
      tab ||
      brKind != null ||
      field != null;
}

enum DocBreakKind { line, page, column }

class DocField {
  const DocField({required this.instruction, this.fallback = ''});

  final String instruction;
  final String fallback;
}

enum DocImagePlacement { inline, anchor }

class DocImage {
  const DocImage({
    required this.placement,
    required this.widthPt,
    required this.heightPt,
    this.bytes,
    this.wrap = DocWrapType.none,
    this.offsetLeftPt = 0,
    this.offsetTopPt = 0,
    this.behindDoc = false,
  });

  final DocImagePlacement placement;
  final double widthPt;
  final double heightPt;
  final Uint8List? bytes;
  final DocWrapType wrap;
  final double offsetLeftPt;
  final double offsetTopPt;
  final bool behindDoc;
}

/// Inline/floating OOXML chart (`c:chart`) embedded in a drawing.
class DocChart {
  const DocChart({
    required this.placement,
    required this.widthPt,
    required this.heightPt,
    required this.chartXml,
    this.wrap = DocWrapType.none,
    this.offsetLeftPt = 0,
    this.offsetTopPt = 0,
  });

  final DocImagePlacement placement;
  final double widthPt;
  final double heightPt;
  final String chartXml;
  final DocWrapType wrap;
  final double offsetLeftPt;
  final double offsetTopPt;
}

enum DocWrapType { none, square, topBottom }
