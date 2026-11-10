import 'dart:typed_data';
import 'dart:ui';

import '../drawing/shapes.dart';
import '../model/style.dart';
import 'pptx_master_styles.dart';

/// Intermediate representation for a parsed PPTX deck.
class PptxDocument {
  PptxDocument({
    required this.slideSize,
    required this.slides,
    required this.theme,
    this.warnings = const [],
  });

  final Size slideSize;
  final List<PptxSlide> slides;
  final PptxThemeParts theme;
  final List<String> warnings;
}

class PptxThemeParts {
  PptxThemeParts({
    this.themeXml,
    this.colorSchemeXml,
    this.fontSchemeXml,
  });

  final String? themeXml;
  final String? colorSchemeXml;
  final String? fontSchemeXml;
}

class PptxSlide {
  PptxSlide({
    required this.index,
    required this.partPath,
    required this.size,
    required this.shapes,
    this.backgroundFill,
    this.layoutPartPath,
    this.masterPartPath,
    this.layoutShapes = const [],
    this.masterShapes = const [],
    this.masterStyles = PptxMasterStyles.defaults,
    this.name,
  });

  final int index;
  final String partPath;
  final Size size;
  final List<PptxShapeNode> shapes;
  final SolidShapeFill? backgroundFill;
  final String? layoutPartPath;
  final String? masterPartPath;
  final List<PptxShapeNode> layoutShapes;
  final List<PptxShapeNode> masterShapes;
  final PptxMasterStyles masterStyles;
  final String? name;
}

sealed class PptxShapeNode {
  const PptxShapeNode({required this.transform, this.placeholderType, this.placeholderIdx});

  final ShapeTransform transform;
  final String? placeholderType;
  final int? placeholderIdx;
}

class PptxShape extends PptxShapeNode {
  PptxShape({
    required super.transform,
    super.placeholderType,
    super.placeholderIdx,
    this.presetGeometry,
    this.adjustValues = const {},
    this.fill,
    this.outline,
    this.textBody,
    this.hidden = false,
  });

  final String? presetGeometry;
  final Map<String, double> adjustValues;
  final ShapeFill? fill;
  final ShapeOutline? outline;
  final PptxTextBody? textBody;
  final bool hidden;
}

class PptxPicture extends PptxShapeNode {
  PptxPicture({
    required super.transform,
    required this.imagePartPath,
    this.imageBytes,
    super.placeholderType,
    super.placeholderIdx,
  });

  final String imagePartPath;
  final Uint8List? imageBytes;
}

class PptxGroup extends PptxShapeNode {
  PptxGroup({
    required super.transform,
    required this.children,
    super.placeholderType,
    super.placeholderIdx,
  });

  final List<PptxShapeNode> children;
}

/// Inline DrawingML table from `p:graphicFrame` / `a:tbl`.
class PptxTable extends PptxShapeNode {
  PptxTable({
    required super.transform,
    required this.columnWidthsPt,
    required this.rows,
    this.firstRow = false,
    this.bandRow = false,
    this.styleId,
  });

  final List<double> columnWidthsPt;
  final List<PptxTableRow> rows;
  /// From `a:tblPr/@firstRow` — style header row.
  final bool firstRow;
  /// From `a:tblPr/@bandRow` — zebra-stripe body rows.
  final bool bandRow;
  /// Built-in / custom table style GUID when present.
  final String? styleId;
}

class PptxTableRow {
  PptxTableRow({required this.heightPt, required this.cells});

  final double heightPt;
  final List<PptxTableCell> cells;
}

class PptxTableCell {
  PptxTableCell({
    required this.text,
    this.style = const ComputedRunStyle(),
    this.fill,
  });

  final String text;
  final ComputedRunStyle style;
  /// Explicit `a:tcPr/a:solidFill` when present.
  final Color? fill;
}

/// Chart frame referencing chart part XML (cached values).
class PptxChart extends PptxShapeNode {
  PptxChart({
    required super.transform,
    required this.chartXml,
    this.titleFallback,
  });

  final String chartXml;
  final String? titleFallback;
}

class PptxTextBody {
  PptxTextBody({
    required this.paragraphs,
    this.listStyleRun,
    this.listStyleAlign,
  });

  final List<PptxParagraph> paragraphs;
  /// Defaults from `a:lstStyle/a:lvl1pPr` when present (layout placeholders).
  final ComputedRunStyle? listStyleRun;
  final TextAlign? listStyleAlign;
}

class PptxParagraph {
  PptxParagraph({
    required this.runs,
    this.style = const ComputedParaStyle(),
    this.bullet,
    this.level = 0,
  });

  final List<PptxTextRun> runs;
  final ComputedParaStyle style;
  /// Optional bullet glyph inherited from master body style.
  final String? bullet;
  /// OOXML `a:pPr/@lvl` (0-based nesting level).
  final int level;
}

class PptxTextRun {
  PptxTextRun({
    required this.text,
    this.style = const ComputedRunStyle(),
  });

  final String text;
  final ComputedRunStyle style;
}
