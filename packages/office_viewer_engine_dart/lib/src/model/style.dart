import 'dart:ui';

/// Resolved character / run styling in points.
class ComputedRunStyle {
  const ComputedRunStyle({
    this.fontFamily = 'Liberation Sans',
    this.fontSizePt = 11,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = const Color(0xFF000000),
    this.strike = false,
  });

  final String fontFamily;
  final double fontSizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final Color color;
}

/// Resolved paragraph styling.
class ComputedParaStyle {
  const ComputedParaStyle({
    this.alignment = TextAlign.left,
    this.lineSpacingMultiple = 1.15,
    this.lineSpacingExactPt,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.indentLeftPt = 0,
    this.indentRightPt = 0,
    this.indentFirstPt = 0,
    this.contextualSpacing = false,
    this.borderBottomColor,
    this.borderBottomWidthPt = 0,
    this.borderBottomSpacePt = 0,
  });

  final TextAlign alignment;
  /// For `lineRule=auto`: multiplier of font size (240 twips = 1.0).
  final double lineSpacingMultiple;
  /// For `lineRule=exact` / `atLeast`: absolute line box height in points.
  final double? lineSpacingExactPt;
  final double spaceBeforePt;
  final double spaceAfterPt;
  final double indentLeftPt;
  final double indentRightPt;
  final double indentFirstPt;
  final bool contextualSpacing;
  final Color? borderBottomColor;
  final double borderBottomWidthPt;
  final double borderBottomSpacePt;
}
