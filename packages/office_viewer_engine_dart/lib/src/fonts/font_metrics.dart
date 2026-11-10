/// Rough glyph width estimates until full shaping exists.
class FontMetricsHelper {
  const FontMetricsHelper();

  /// Placeholder: assumes fixed digit width at 0.6 × font size (points).
  double digitWidth(double fontSizePt) => fontSizePt * 0.6;

  double averageCharWidth(double fontSizePt, {double factor = 0.5}) =>
      fontSizePt * factor;
}
