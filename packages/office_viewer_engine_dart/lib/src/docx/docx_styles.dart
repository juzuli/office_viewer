import 'dart:ui';

import 'package:xml/xml.dart';

import '../model/style.dart';
import '../theme/color.dart';
import '../theme/theme.dart';
import '../xml/units.dart';
import 'docx_model.dart';
import 'docx_xml.dart';

const _maxBasedOnDepth = 32;

/// Resolved character style defaults for a paragraph/run.
class DocxCharStyleProps {
  const DocxCharStyleProps({
    this.fontFamily,
    this.themeFont,
    this.fontSizeHalfPt,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.color,
  });

  final String? fontFamily;
  /// `major` / `minor` from asciiTheme / hAnsiTheme when no explicit typeface.
  final String? themeFont;
  final int? fontSizeHalfPt;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final Color? color;

  DocxCharStyleProps merge(DocxCharStyleProps other) => DocxCharStyleProps(
        fontFamily: other.fontFamily ?? fontFamily,
        themeFont: other.themeFont ?? themeFont,
        fontSizeHalfPt: other.fontSizeHalfPt ?? fontSizeHalfPt,
        bold: other.bold ?? bold,
        italic: other.italic ?? italic,
        underline: other.underline ?? underline,
        strike: other.strike ?? strike,
        color: other.color ?? color,
      );
}

class DocxParaStyleProps {
  const DocxParaStyleProps({
    this.alignment,
    this.spaceBeforeTwip,
    this.spaceAfterTwip,
    this.lineSpacingTwip,
    this.lineRule,
    this.indentLeftTwip,
    this.indentRightTwip,
    this.indentFirstTwip,
    this.numId,
    this.ilvl,
    this.contextualSpacing,
    this.borderBottomColor,
    this.borderBottomSzEighthPt,
    this.borderBottomSpacePt,
    this.pStyleForRun,
  });

  final TextAlign? alignment;
  final int? spaceBeforeTwip;
  final int? spaceAfterTwip;
  final int? lineSpacingTwip;
  /// `auto` | `exact` | `atLeast`
  final String? lineRule;
  final int? indentLeftTwip;
  final int? indentRightTwip;
  final int? indentFirstTwip;
  final int? numId;
  final int? ilvl;
  final bool? contextualSpacing;
  final Color? borderBottomColor;
  final int? borderBottomSzEighthPt;
  final double? borderBottomSpacePt;
  final DocxCharStyleProps? pStyleForRun;

  DocxParaStyleProps merge(DocxParaStyleProps other) => DocxParaStyleProps(
        alignment: other.alignment ?? alignment,
        spaceBeforeTwip: other.spaceBeforeTwip ?? spaceBeforeTwip,
        spaceAfterTwip: other.spaceAfterTwip ?? spaceAfterTwip,
        lineSpacingTwip: other.lineSpacingTwip ?? lineSpacingTwip,
        lineRule: other.lineRule ?? lineRule,
        indentLeftTwip: other.indentLeftTwip ?? indentLeftTwip,
        indentRightTwip: other.indentRightTwip ?? indentRightTwip,
        indentFirstTwip: other.indentFirstTwip ?? indentFirstTwip,
        numId: other.numId ?? numId,
        ilvl: other.ilvl ?? ilvl,
        contextualSpacing: other.contextualSpacing ?? contextualSpacing,
        borderBottomColor: other.borderBottomColor ?? borderBottomColor,
        borderBottomSzEighthPt:
            other.borderBottomSzEighthPt ?? borderBottomSzEighthPt,
        borderBottomSpacePt: other.borderBottomSpacePt ?? borderBottomSpacePt,
        pStyleForRun: other.pStyleForRun != null
            ? (pStyleForRun?.merge(other.pStyleForRun!) ?? other.pStyleForRun)
            : pStyleForRun,
      );
}

class DocxStyleDef {
  const DocxStyleDef({
    required this.styleId,
    this.basedOn,
    this.type,
    this.defaultPara = const DocxParaStyleProps(),
    this.defaultChar = const DocxCharStyleProps(),
  });

  final String styleId;
  final String? basedOn;
  final String? type;
  final DocxParaStyleProps defaultPara;
  final DocxCharStyleProps defaultChar;
}

class DocxStyleSheet {
  DocxStyleSheet({
    required this.styles,
    required this.docDefaultsChar,
    required this.docDefaultsPara,
    required this.colorResolver,
    required this.fontScheme,
    this.tableBordersByStyle = const {},
    this.warnings = const [],
  });

  final Map<String, DocxStyleDef> styles;
  final DocxCharStyleProps docDefaultsChar;
  final DocxParaStyleProps docDefaultsPara;
  final ThemeColorResolver colorResolver;
  final ThemeFontScheme fontScheme;
  /// Table style `tblBorders` keyed by styleId (e.g. TableGrid).
  final Map<String, DocTableBorders> tableBordersByStyle;
  final List<String> warnings;

  static DocxStyleSheet empty(OfficeTheme theme) => DocxStyleSheet(
        styles: const {},
        docDefaultsChar: const DocxCharStyleProps(fontSizeHalfPt: 22),
        docDefaultsPara: const DocxParaStyleProps(),
        colorResolver: ThemeColorResolver(theme.colorScheme),
        fontScheme: theme.fontScheme,
      );

  static DocxStyleSheet parse(String? xmlText, OfficeTheme theme) {
    if (xmlText == null) return DocxStyleSheet.empty(theme);
    final warnings = <String>[];
    final resolver = ThemeColorResolver(theme.colorScheme);
    final styles = <String, DocxStyleDef>{};
    final tableBorders = <String, DocTableBorders>{};

    try {
      final doc = XmlDocument.parse(xmlText);
      DocxCharStyleProps docChar = const DocxCharStyleProps(fontSizeHalfPt: 22);
      DocxParaStyleProps docPara = const DocxParaStyleProps();

      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'docDefaults') {
          final rPr = docxChild(el, 'rPrDefault');
          if (rPr != null) {
            final rPrEl = docxChild(rPr, 'rPr');
            if (rPrEl != null) {
              docChar = _parseCharProps(rPrEl, resolver, theme.fontScheme)
                  .merge(docChar);
            }
          }
          final pPr = docxChild(el, 'pPrDefault');
          if (pPr != null) {
            final pPrEl = docxChild(pPr, 'pPr');
            if (pPrEl != null) {
              docPara = _parseParaProps(
                pPrEl,
                resolver,
                theme.fontScheme,
                null,
              ).merge(docPara);
            }
          }
        }
      }

      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local != 'style') continue;
        final styleId = docxAttr(el, 'styleId');
        if (styleId == null) continue;
        final type = docxAttr(el, 'type');
        final basedOn = docxAttr(docxChild(el, 'basedOn'), 'val');
        var para = const DocxParaStyleProps();
        var ch = const DocxCharStyleProps();
        final pPr = docxChild(el, 'pPr');
        if (pPr != null) {
          para = _parseParaProps(pPr, resolver, theme.fontScheme, null);
        }
        final rPr = docxChild(el, 'rPr');
        if (rPr != null) {
          ch = _parseCharProps(rPr, resolver, theme.fontScheme);
        }
        styles[styleId] = DocxStyleDef(
          styleId: styleId,
          basedOn: basedOn,
          type: type,
          defaultPara: para,
          defaultChar: ch,
        );
        if (type == 'table') {
          final tblPr = docxChild(el, 'tblPr');
          final bordersEl = tblPr != null ? docxChild(tblPr, 'tblBorders') : null;
          if (bordersEl != null) {
            tableBorders[styleId] = _parseTableBorders(bordersEl, resolver);
          }
        }
      }

      return DocxStyleSheet(
        styles: styles,
        docDefaultsChar: docChar,
        docDefaultsPara: docPara,
        colorResolver: resolver,
        fontScheme: theme.fontScheme,
        tableBordersByStyle: tableBorders,
        warnings: warnings,
      );
    } catch (e) {
      warnings.add('styles.xml parse failed: $e');
      return DocxStyleSheet.empty(theme).copyWarnings(warnings);
    }
  }

  DocxStyleSheet copyWarnings(List<String> w) => DocxStyleSheet(
        styles: styles,
        docDefaultsChar: docDefaultsChar,
        docDefaultsPara: docDefaultsPara,
        colorResolver: colorResolver,
        fontScheme: fontScheme,
        tableBordersByStyle: tableBordersByStyle,
        warnings: [...warnings, ...w],
      );

  DocxParaStyleProps resolvePara(String? styleId) {
    if (styleId == null) return docDefaultsPara;
    final resolved = _resolveStyle(styleId);
  if (resolved == null) return docDefaultsPara;
    return docDefaultsPara.merge(resolved.defaultPara);
  }

  DocxCharStyleProps resolveChar(String? paraStyleId, String? rStyleId) {
    var base = docDefaultsChar;
    final paraDef = paraStyleId != null ? _resolveStyle(paraStyleId) : null;
    if (paraDef?.defaultPara.pStyleForRun != null) {
      base = base.merge(paraDef!.defaultPara.pStyleForRun!);
    }
    if (paraDef != null) {
      base = _mergeCharXor(base, paraDef.defaultChar);
    }
    final runDef = rStyleId != null ? _resolveStyle(rStyleId) : null;
    if (runDef != null) {
      base = _mergeCharXor(base, runDef.defaultChar);
    }
    return base;
  }

  DocxStyleDef? _resolveStyle(String styleId) {
    final def = styles[styleId];
    if (def == null) return null;
    var chain = <DocxStyleDef>[def];
    var current = def;
    var depth = 0;
    while (current.basedOn != null && depth < _maxBasedOnDepth) {
      final parent = styles[current.basedOn];
      if (parent == null) break;
      chain.insert(0, parent);
      current = parent;
      depth++;
    }
    if (depth >= _maxBasedOnDepth) {
      warnings.add('Style basedOn chain truncated at $styleId');
    }
    var para = const DocxParaStyleProps();
    var ch = const DocxCharStyleProps();
    for (final s in chain) {
      para = para.merge(s.defaultPara);
      ch = _mergeCharXor(ch, s.defaultChar);
    }
    return DocxStyleDef(
      styleId: styleId,
      basedOn: def.basedOn,
      type: def.type,
      defaultPara: para,
      defaultChar: ch,
    );
  }

  DocxCharStyleProps _mergeCharXor(
    DocxCharStyleProps base,
    DocxCharStyleProps overlay,
  ) {
    return DocxCharStyleProps(
      fontFamily: overlay.fontFamily ?? base.fontFamily,
      themeFont: overlay.themeFont ?? base.themeFont,
      fontSizeHalfPt: overlay.fontSizeHalfPt ?? base.fontSizeHalfPt,
      bold: overlay.bold != null
          ? applyToggleXor(base.bold, overlay.bold, false)
          : base.bold,
      italic: overlay.italic != null
          ? applyToggleXor(base.italic, overlay.italic, false)
          : base.italic,
      underline: overlay.underline != null
          ? applyToggleXor(base.underline, overlay.underline, false)
          : base.underline,
      strike: overlay.strike != null
          ? applyToggleXor(base.strike, overlay.strike, false)
          : base.strike,
      color: overlay.color ?? base.color,
    );
  }

  ComputedRunStyle toRunStyle(
    DocxCharStyleProps props, {
    DocxCharStyleProps? direct,
  }) {
    var p = props;
    if (direct != null) {
      p = _mergeCharXor(p, direct);
    }
    final family = p.fontFamily ??
        (p.themeFont == 'major'
            ? fontScheme.majorLatin
            : fontScheme.minorLatin);
    final sizePt = halfPointToPt(p.fontSizeHalfPt ?? 22);
    return ComputedRunStyle(
      fontFamily: _mapFontFamily(family),
      fontSizePt: sizePt,
      bold: p.bold ?? false,
      italic: p.italic ?? false,
      underline: p.underline ?? false,
      strike: p.strike ?? false,
      color: p.color ?? const Color(0xFF000000),
    );
  }

  ComputedParaStyle toParaStyle(DocxParaStyleProps props) {
    final align = props.alignment ?? TextAlign.left;
    final rule = props.lineRule ?? 'auto';
    final lineTwip = props.lineSpacingTwip;
    double multiple = 1.15;
    double? exactPt;
    if (lineTwip != null) {
      if (rule == 'exact' || rule == 'atLeast') {
        exactPt = twipToPt(lineTwip);
      } else {
        // auto: 240 twips = single spacing
        multiple = lineTwip / 240.0;
      }
    }
    final borderSz = props.borderBottomSzEighthPt;
    return ComputedParaStyle(
      alignment: align,
      lineSpacingMultiple: multiple,
      lineSpacingExactPt: exactPt,
      spaceBeforePt: props.spaceBeforeTwip != null
          ? twipToPt(props.spaceBeforeTwip!)
          : 0,
      spaceAfterPt: props.spaceAfterTwip != null
          ? twipToPt(props.spaceAfterTwip!)
          : 0,
      indentLeftPt: props.indentLeftTwip != null
          ? twipToPt(props.indentLeftTwip!)
          : 0,
      indentRightPt: props.indentRightTwip != null
          ? twipToPt(props.indentRightTwip!)
          : 0,
      indentFirstPt: props.indentFirstTwip != null
          ? twipToPt(props.indentFirstTwip!)
          : 0,
      contextualSpacing: props.contextualSpacing ?? false,
      borderBottomColor: props.borderBottomColor,
      borderBottomWidthPt: borderSz != null ? borderSz / 8.0 : 0,
      borderBottomSpacePt: props.borderBottomSpacePt ?? 0,
    );
  }
}

String _mapFontFamily(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('courier') ||
      lower.contains('consolas') ||
      lower.contains('mono')) {
    return 'Liberation Mono';
  }
  if (lower.contains('cambria') ||
      lower.contains('georgia') ||
      lower.contains('garamond') ||
      lower.contains('times') ||
      lower.contains('serif') ||
      lower.contains('roman')) {
    return 'Liberation Serif';
  }
  if (lower.contains('calibri') ||
      lower.contains('carlito') ||
      lower.contains('arial') ||
      lower.contains('helvetica') ||
      lower.contains('sans')) {
    return 'Liberation Sans';
  }
  return 'Liberation Sans';
}

DocxParaStyleProps _parseParaProps(
  XmlElement pPr,
  ThemeColorResolver resolver,
  ThemeFontScheme fonts,
  DocxCharStyleProps? linkRun,
) {
  TextAlign? align;
  final jc = docxChild(pPr, 'jc');
  if (jc != null) {
    switch (docxAttr(jc, 'val')) {
      case 'center':
        align = TextAlign.center;
      case 'right':
        align = TextAlign.right;
      case 'both':
        align = TextAlign.justify;
      case 'left':
      default:
        align = TextAlign.left;
    }
  }
  final numPr = docxChild(pPr, 'numPr');
  final hanging = docxIntAttr(docxChild(pPr, 'ind'), 'hanging');
  final spacing = docxChild(pPr, 'spacing');
  Color? borderBottomColor;
  int? borderBottomSz;
  double? borderBottomSpace;
  final pBdr = docxChild(pPr, 'pBdr');
  if (pBdr != null) {
    final bottom = docxChild(pBdr, 'bottom');
    if (bottom != null && docxAttr(bottom, 'val') != 'nil') {
      borderBottomSz = docxIntAttr(bottom, 'sz');
      final space = docxIntAttr(bottom, 'space');
      borderBottomSpace = space != null ? space.toDouble() : 0;
      final attrs = {for (final a in bottom.attributes) a.name.local: a.value};
      borderBottomColor = resolver.resolveColorElement(attrs, const []);
    }
  }
  return DocxParaStyleProps(
    alignment: align,
    spaceBeforeTwip: docxIntAttr(spacing, 'before'),
    spaceAfterTwip: docxIntAttr(spacing, 'after'),
    lineSpacingTwip: docxIntAttr(spacing, 'line'),
    lineRule: docxAttr(spacing, 'lineRule'),
    indentLeftTwip: docxIntAttr(docxChild(pPr, 'ind'), 'left'),
    indentRightTwip: docxIntAttr(docxChild(pPr, 'ind'), 'right'),
    indentFirstTwip: docxIntAttr(docxChild(pPr, 'ind'), 'firstLine') ??
        (hanging != null ? -hanging : null),
    numId: numPr != null ? docxIntAttr(docxChild(numPr, 'numId'), 'val') : null,
    ilvl: numPr != null ? docxIntAttr(docxChild(numPr, 'ilvl'), 'val') : null,
    contextualSpacing: docxChild(pPr, 'contextualSpacing') != null,
    borderBottomColor: borderBottomColor,
    borderBottomSzEighthPt: borderBottomSz,
    borderBottomSpacePt: borderBottomSpace,
    pStyleForRun: linkRun,
  );
}

DocTableBorders _parseTableBorders(
  XmlElement bordersEl,
  ThemeColorResolver resolver,
) {
  DocBorder? parseSide(String name) {
    final el = docxChild(bordersEl, name);
    if (el == null) return null;
    final val = docxAttr(el, 'val');
    if (val == null || val == 'nil' || val == 'none') {
      return const DocBorder(
        color: Color(0xFF000000),
        style: DocBorderStyle.none,
      );
    }
    final sz = docxIntAttr(el, 'sz') ?? 4;
    final attrs = {for (final a in el.attributes) a.name.local: a.value};
    final color = resolver.resolveColorElement(attrs, const []);
    return DocBorder(
      color: color,
      widthPt: (sz / 8.0).clamp(0.5, 6.0),
      style: DocBorderStyle.single,
    );
  }

  return DocTableBorders(
    top: parseSide('top'),
    left: parseSide('left'),
    bottom: parseSide('bottom'),
    right: parseSide('right'),
    insideH: parseSide('insideH'),
    insideV: parseSide('insideV'),
  );
}

DocxCharStyleProps _parseCharProps(
  XmlElement rPr,
  ThemeColorResolver resolver,
  ThemeFontScheme fonts,
) {
  String? family;
  String? themeFont;
  final rFonts = docxChild(rPr, 'rFonts');
  if (rFonts != null) {
    family = docxAttr(rFonts, 'ascii') ??
        docxAttr(rFonts, 'hAnsi') ??
        docxAttr(rFonts, 'cs');
    final themeHint = docxAttr(rFonts, 'asciiTheme') ??
        docxAttr(rFonts, 'hAnsiTheme') ??
        docxAttr(rFonts, 'cstheme');
    if (themeHint != null) {
      final lower = themeHint.toLowerCase();
      if (lower.contains('major')) {
        themeFont = 'major';
        family ??= fonts.majorLatin;
      } else if (lower.contains('minor')) {
        themeFont = 'minor';
        family ??= fonts.minorLatin;
      }
    }
  }
  Color? color;
  final colorEl = docxChild(rPr, 'color');
  if (colorEl != null) {
    final attrs = {for (final a in colorEl.attributes) a.name.local: a.value};
    color = resolver.resolveColorElement(attrs, docxColorChildren(colorEl));
  }
  return DocxCharStyleProps(
    fontFamily: family,
    themeFont: themeFont,
    fontSizeHalfPt: docxIntAttr(docxChild(rPr, 'sz'), 'val'),
    bold: docxToggle(docxChild(rPr, 'b')),
    italic: docxToggle(docxChild(rPr, 'i')),
    underline: docxToggle(docxChild(rPr, 'u')),
    strike: docxToggle(docxChild(rPr, 'strike')),
    color: color,
  );
}
