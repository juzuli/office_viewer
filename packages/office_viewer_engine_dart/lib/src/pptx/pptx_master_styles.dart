import 'dart:ui';

import 'package:xml/xml.dart';

import '../model/style.dart';
import '../theme/color.dart';
import '../theme/theme.dart';
import '../xml/units.dart';

/// Per-level body defaults from slide master `bodyStyle` / `lvlNpPr`.
class PptxLevelStyle {
  const PptxLevelStyle({
    required this.run,
    this.align = TextAlign.left,
    this.bullet,
    this.marginLeftPt = 0,
  });

  final ComputedRunStyle run;
  final TextAlign align;
  final String? bullet;
  final double marginLeftPt;
}

/// Text defaults from slide master `titleStyle` / `bodyStyle` / `otherStyle`.
class PptxMasterStyles {
  const PptxMasterStyles({
    this.title = const ComputedRunStyle(fontSizePt: 44),
    this.titleAlign = TextAlign.center,
    this.bodyLevels = const [
      PptxLevelStyle(
        run: ComputedRunStyle(fontSizePt: 32),
        bullet: '•',
        marginLeftPt: 27,
      ),
    ],
    this.other = const ComputedRunStyle(fontSizePt: 18),
    this.otherAlign = TextAlign.left,
  });

  final ComputedRunStyle title;
  final TextAlign titleAlign;
  /// Body placeholder levels (index 0 = `lvl1pPr`, 1 = `lvl2pPr`, …).
  final List<PptxLevelStyle> bodyLevels;
  final ComputedRunStyle other;
  final TextAlign otherAlign;

  ComputedRunStyle get body =>
      bodyLevels.isNotEmpty ? bodyLevels.first.run : const ComputedRunStyle(fontSizePt: 32);

  TextAlign get bodyAlign =>
      bodyLevels.isNotEmpty ? bodyLevels.first.align : TextAlign.left;

  String? get bodyBullet =>
      bodyLevels.isNotEmpty ? bodyLevels.first.bullet : '•';

  static const PptxMasterStyles defaults = PptxMasterStyles();

  PptxLevelStyle levelForBody(int level) {
    if (bodyLevels.isEmpty) {
      return PptxLevelStyle(
        run: const ComputedRunStyle(fontSizePt: 32),
        bullet: '•',
        marginLeftPt: 27.0 + level * 24.0,
      );
    }
    if (level < bodyLevels.length) return bodyLevels[level];
    final last = bodyLevels.last;
    return PptxLevelStyle(
      run: last.run,
      align: last.align,
      bullet: last.bullet,
      marginLeftPt: last.marginLeftPt + (level - bodyLevels.length + 1) * 24.0,
    );
  }

  static PptxMasterStyles parse(
    String? masterXml,
    ThemeColorResolver colors,
    ThemeFontScheme fonts,
  ) {
    if (masterXml == null || masterXml.isEmpty) return defaults;
    try {
      final doc = XmlDocument.parse(masterXml);
      ComputedRunStyle? title;
      TextAlign? titleAlign;
      List<PptxLevelStyle>? bodyLevels;
      ComputedRunStyle? other;
      TextAlign? otherAlign;

      for (final el in doc.descendants.whereType<XmlElement>()) {
        final local = el.name.local;
        if (local == 'titleStyle') {
          final parsed = _parseLevel(
            el,
            colors,
            fonts,
            fallbackSize: 44,
            major: true,
            levelIndex: 0,
          );
          if (parsed != null) {
            title = parsed.run;
            titleAlign = parsed.align;
          }
        } else if (local == 'bodyStyle') {
          bodyLevels = _parseAllLevels(
            el,
            colors,
            fonts,
            fallbackSize: 32,
            major: false,
          );
        } else if (local == 'otherStyle') {
          final parsed = _parseLevel(
            el,
            colors,
            fonts,
            fallbackSize: 18,
            major: false,
            levelIndex: 0,
          );
          if (parsed != null) {
            other = parsed.run;
            otherAlign = parsed.align;
          }
        }
      }

      return PptxMasterStyles(
        title: title ?? defaults.title,
        titleAlign: titleAlign ?? defaults.titleAlign,
        bodyLevels: bodyLevels ?? defaults.bodyLevels,
        other: other ?? defaults.other,
        otherAlign: otherAlign ?? defaults.otherAlign,
      );
    } catch (_) {
      return defaults;
    }
  }

  (ComputedRunStyle, TextAlign?) _styleForPlaceholder(String? type) {
    switch (type) {
      case 'title':
      case 'ctrTitle':
        return (title, titleAlign);
      case 'body':
      case 'obj':
        return (body, bodyAlign);
      case 'subTitle':
        return (other, TextAlign.center);
      default:
        return (other, otherAlign);
    }
  }

  /// Defaults for a placeholder type (size/color/font + alignment).
  (ComputedRunStyle style, TextAlign align) defaultsFor(String? type) {
    final (style, align) = _styleForPlaceholder(type);
    return (style, align ?? TextAlign.left);
  }
}

List<PptxLevelStyle> _parseAllLevels(
  XmlElement block,
  ThemeColorResolver colors,
  ThemeFontScheme fonts, {
  required double fallbackSize,
  required bool major,
}) {
  final byIndex = <int, PptxLevelStyle>{};
  for (final child in block.descendants.whereType<XmlElement>()) {
    final local = child.name.local;
    final match = RegExp(r'^lvl(\d+)pPr$').firstMatch(local);
    if (match == null) continue;
    final idx = int.parse(match.group(1)!) - 1;
    if (idx < 0) continue;
    final parsed = _parseLevelElement(
      child,
      colors,
      fonts,
      fallbackSize: (fallbackSize - idx * 4).clamp(12, fallbackSize).toDouble(),
      major: major,
    );
    byIndex[idx] = parsed;
  }
  if (byIndex.isEmpty) {
    return [
      PptxLevelStyle(
        run: ComputedRunStyle(
          fontSizePt: fallbackSize,
          fontFamily: major ? fonts.majorLatin : fonts.minorLatin,
        ),
        bullet: '•',
        marginLeftPt: 27,
      ),
    ];
  }
  final max = byIndex.keys.reduce((a, b) => a > b ? a : b);
  return [for (var i = 0; i <= max; i++) byIndex[i] ?? byIndex[0]!];
}

PptxLevelStyle? _parseLevel(
  XmlElement block,
  ThemeColorResolver colors,
  ThemeFontScheme fonts, {
  required double fallbackSize,
  required bool major,
  required int levelIndex,
}) {
  final levels = _parseAllLevels(
    block,
    colors,
    fonts,
    fallbackSize: fallbackSize,
    major: major,
  );
  if (levels.isEmpty) return null;
  return levelIndex < levels.length ? levels[levelIndex] : levels.last;
}

PptxLevelStyle _parseLevelElement(
  XmlElement lvl,
  ThemeColorResolver colors,
  ThemeFontScheme fonts, {
  required double fallbackSize,
  required bool major,
}) {
  final fallbackFamily = major ? fonts.majorLatin : fonts.minorLatin;

  TextAlign align = TextAlign.left;
  final algn = lvl.getAttribute('algn');
  if (algn != null) {
    align = switch (algn) {
      'ctr' => TextAlign.center,
      'r' => TextAlign.right,
      'just' => TextAlign.justify,
      _ => TextAlign.left,
    };
  }

  final marL = int.tryParse(lvl.getAttribute('marL') ?? '') ?? 0;
  final marginLeftPt = marL > 0 ? emuToPt(marL) : 0.0;

  String? bullet;
  var hasBuNone = false;
  XmlElement? defRPr;
  for (final child in lvl.childElements) {
    final local = child.name.local;
    if (local == 'defRPr') {
      defRPr = child;
    } else if (local == 'buChar') {
      bullet = child.getAttribute('char') ?? '•';
    } else if (local == 'buNone') {
      hasBuNone = true;
    }
  }
  if (hasBuNone) bullet = null;

  var size = fallbackSize;
  var bold = false;
  var italic = false;
  var family = fallbackFamily;
  var color = const Color(0xFF000000);

  if (defRPr != null) {
    final sz = defRPr.getAttribute('sz');
    if (sz != null) {
      final parsed = int.tryParse(sz);
      if (parsed != null) size = parsed / 100.0;
    }
    if (defRPr.getAttribute('b') == '1') bold = true;
    if (defRPr.getAttribute('i') == '1') italic = true;

    for (final child in defRPr.childElements) {
      if (child.name.local == 'latin') {
        final tf = child.getAttribute('typeface');
        if (tf != null && tf.isNotEmpty) {
          family = _resolveThemeTypeface(tf, fonts, major: major);
        }
      }
      if (child.name.local == 'solidFill') {
        final c = _parseSolid(child, colors);
        if (c != null) color = c;
      }
    }
  }

  return PptxLevelStyle(
    run: ComputedRunStyle(
      fontFamily: family,
      fontSizePt: size,
      bold: bold,
      italic: italic,
      color: color,
    ),
    align: align,
    bullet: bullet,
    marginLeftPt: marginLeftPt,
  );
}

String _resolveThemeTypeface(
  String typeface,
  ThemeFontScheme fonts, {
  required bool major,
}) {
  switch (typeface) {
    case '+mj-lt':
      return fonts.majorLatin;
    case '+mn-lt':
      return fonts.minorLatin;
    default:
      return typeface.startsWith('+')
          ? (major ? fonts.majorLatin : fonts.minorLatin)
          : typeface;
  }
}

Color? _parseSolid(XmlElement solidFill, ThemeColorResolver colors) {
  for (final child in solidFill.childElements) {
    return colors.resolveColorElement(
      {for (final a in child.attributes) a.name.local: a.value},
      [
        for (final g in child.childElements)
          XmlColorChild(
            name: g.name.local,
            attrs: {for (final a in g.attributes) a.name.local: a.value},
          ),
      ],
    );
  }
  return null;
}
