import 'dart:ui';

import 'package:xml/xml.dart';

import '../theme/color.dart';
import '../theme/theme.dart';
import '../xml/units.dart';
import 'number_format.dart';

enum XlsxHorizontalAlign { general, left, center, right, fill, justify }

enum XlsxVerticalAlign { top, center, bottom, justify }

enum XlsxBorderStyle { none, thin, medium, thick, hair, dashed, dotted, double }

class XlsxFont {
  const XlsxFont({
    this.name = 'Calibri',
    this.sizePt = 11,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color = const Color(0xFF000000),
  });

  final String name;
  final double sizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final Color color;
}

class XlsxFill {
  const XlsxFill({this.pattern, this.fgColor, this.bgColor});

  final String? pattern;
  final Color? fgColor;
  final Color? bgColor;

  bool get isSolid =>
      pattern == null ||
      pattern == 'none' ||
      pattern == 'solid' ||
      pattern == 'gray125';
}

class XlsxBorderSide {
  const XlsxBorderSide({
    this.style = XlsxBorderStyle.none,
    this.color = const Color(0xFF000000),
  });

  final XlsxBorderStyle style;
  final Color color;
}

class XlsxBorder {
  const XlsxBorder({
    this.left = const XlsxBorderSide(),
    this.right = const XlsxBorderSide(),
    this.top = const XlsxBorderSide(),
    this.bottom = const XlsxBorderSide(),
  });

  final XlsxBorderSide left;
  final XlsxBorderSide right;
  final XlsxBorderSide top;
  final XlsxBorderSide bottom;
}

class XlsxCellXf {
  const XlsxCellXf({
    this.fontId = 0,
    this.fillId = 0,
    this.borderId = 0,
    this.numFmtId = 0,
    this.hAlign = XlsxHorizontalAlign.general,
    this.vAlign = XlsxVerticalAlign.bottom,
    this.wrapText = false,
    this.applyAlignment = false,
  });

  final int fontId;
  final int fillId;
  final int borderId;
  final int numFmtId;
  final XlsxHorizontalAlign hAlign;
  final XlsxVerticalAlign vAlign;
  final bool wrapText;
  final bool applyAlignment;

  XlsxFont font(XlsxStylesheet sheet) =>
      sheet.fonts[fontId.clamp(0, sheet.fonts.length - 1)];

  XlsxFill fill(XlsxStylesheet sheet) =>
      sheet.fills[fillId.clamp(0, sheet.fills.length - 1)];

  XlsxBorder border(XlsxStylesheet sheet) =>
      sheet.borders[borderId.clamp(0, sheet.borders.length - 1)];

  String numFmtCode(XlsxStylesheet sheet) =>
      NumberFormat.resolveCode(numFmtId, sheet.numFmts);
}

class XlsxStylesheet {
  XlsxStylesheet({
    required this.fonts,
    required this.fills,
    required this.borders,
    required this.numFmts,
    required this.cellXfs,
    this.warnings = const [],
  });

  final List<XlsxFont> fonts;
  final List<XlsxFill> fills;
  final List<XlsxBorder> borders;
  final Map<int, String> numFmts;
  final List<XlsxCellXf> cellXfs;
  final List<String> warnings;

  XlsxCellXf xf(int? index) {
    if (index == null || index < 0 || index >= cellXfs.length) {
      return cellXfs.isNotEmpty ? cellXfs.first : const XlsxCellXf();
    }
    return cellXfs[index];
  }

  static XlsxStylesheet empty = XlsxStylesheet(
    fonts: const [XlsxFont()],
    fills: const [
      XlsxFill(),
      XlsxFill(pattern: 'gray125', fgColor: Color(0xFFFFFFFF)),
    ],
    borders: const [XlsxBorder()],
    numFmts: const {},
    cellXfs: const [XlsxCellXf()],
  );

  static XlsxStylesheet parse(
    String? xmlText, {
    ThemeColorScheme? theme,
    List<String> warnings = const [],
  }) {
    theme ??= ThemeColorScheme.defaults;
    final w = List<String>.from(warnings);
    if (xmlText == null || xmlText.isEmpty) {
      w.add('Missing xl/styles.xml');
      return XlsxStylesheet.empty.copyWith(warnings: w);
    }
    try {
      final doc = XmlDocument.parse(xmlText);
      XmlElement? root;
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'styleSheet') {
          root = el;
          break;
        }
      }
      if (root == null) {
        w.add('styles.xml: no styleSheet element');
        return XlsxStylesheet.empty.copyWith(warnings: w);
      }

      final resolver = ThemeColorResolver(theme);

      List<XlsxFont> fonts = const [XlsxFont()];
      final fontsEl = _child(root, 'fonts');
      if (fontsEl != null) {
        fonts = fontsEl.childElements
            .where((e) => e.name.local == 'font')
            .map((e) => _parseFont(e, resolver))
            .toList();
        if (fonts.isEmpty) fonts = const [XlsxFont()];
      }

      List<XlsxFill> fills = const [
        XlsxFill(),
        XlsxFill(pattern: 'gray125', fgColor: Color(0xFFFFFFFF)),
      ];
      final fillsEl = _child(root, 'fills');
      if (fillsEl != null) {
        fills = fillsEl.childElements
            .where((e) => e.name.local == 'fill')
            .map((e) => _parseFill(e, resolver))
            .toList();
        if (fills.isEmpty) fills = XlsxStylesheet.empty.fills;
      }

      List<XlsxBorder> borders = const [XlsxBorder()];
      final bordersEl = _child(root, 'borders');
      if (bordersEl != null) {
        borders = bordersEl.childElements
            .where((e) => e.name.local == 'border')
            .map(_parseBorder)
            .toList();
        if (borders.isEmpty) borders = const [XlsxBorder()];
      }

      final numFmts = <int, String>{};
      final numFmtsEl = _child(root, 'numFmts');
      if (numFmtsEl != null) {
        for (final nf in numFmtsEl.childElements) {
          if (nf.name.local != 'numFmt') continue;
          final id = int.tryParse(nf.getAttribute('numFmtId') ?? '');
          final code = nf.getAttribute('formatCode');
          if (id != null && code != null) {
            numFmts[id] = code;
          }
        }
      }

      List<XlsxCellXf> xfs = const [XlsxCellXf()];
      final xfsEl = _child(root, 'cellXfs');
      if (xfsEl != null) {
        xfs = xfsEl.childElements
            .where((e) => e.name.local == 'xf')
            .map(_parseXf)
            .toList();
        if (xfs.isEmpty) xfs = const [XlsxCellXf()];
      }

      return XlsxStylesheet(
        fonts: fonts,
        fills: fills,
        borders: borders,
        numFmts: numFmts,
        cellXfs: xfs,
        warnings: w,
      );
    } catch (e) {
      w.add('styles.xml parse failed: $e');
      return XlsxStylesheet.empty.copyWith(warnings: w);
    }
  }

  XlsxStylesheet copyWith({
    List<XlsxFont>? fonts,
    List<XlsxFill>? fills,
    List<XlsxBorder>? borders,
    Map<int, String>? numFmts,
    List<XlsxCellXf>? cellXfs,
    List<String>? warnings,
  }) {
    return XlsxStylesheet(
      fonts: fonts ?? this.fonts,
      fills: fills ?? this.fills,
      borders: borders ?? this.borders,
      numFmts: numFmts ?? this.numFmts,
      cellXfs: cellXfs ?? this.cellXfs,
      warnings: warnings ?? this.warnings,
    );
  }

  static XmlElement? _child(XmlElement parent, String local) {
    for (final c in parent.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static XlsxFont _parseFont(XmlElement font, ThemeColorResolver resolver) {
    var name = 'Calibri';
    var sizePt = 11.0;
    var bold = false;
    var italic = false;
    var underline = false;
    var strike = false;
    var color = const Color(0xFF000000);

    for (final child in font.childElements) {
      switch (child.name.local) {
        case 'name':
          name = child.getAttribute('val') ?? name;
        case 'sz':
          final half = double.tryParse(child.getAttribute('val') ?? '');
          if (half != null) sizePt = halfPointToPt(half);
        case 'b':
          bold = child.getAttribute('val') != '0';
        case 'i':
          italic = child.getAttribute('val') != '0';
        case 'u':
          underline = child.getAttribute('val') != 'none';
        case 'strike':
          strike = child.getAttribute('val') != '0';
        case 'color':
          color = _parseColorEl(child, resolver, color);
      }
    }
    return XlsxFont(
      name: name,
      sizePt: sizePt,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      color: color,
    );
  }

  static XlsxFill _parseFill(XmlElement fill, ThemeColorResolver resolver) {
    for (final pattern in fill.childElements) {
      if (pattern.name.local != 'patternFill') continue;
      final type = pattern.getAttribute('patternType') ?? 'none';
      Color? fg;
      Color? bg;
      for (final c in pattern.childElements) {
        if (c.name.local == 'fgColor') {
          fg = _parseColorEl(c, resolver, const Color(0xFF000000));
        } else if (c.name.local == 'bgColor') {
          bg = _parseColorEl(c, resolver, const Color(0xFFFFFFFF));
        }
      }
      return XlsxFill(pattern: type, fgColor: fg, bgColor: bg);
    }
    return const XlsxFill();
  }

  static XlsxBorder _parseBorder(XmlElement border) {
    XlsxBorderSide side(XmlElement? el) {
      if (el == null) return const XlsxBorderSide();
      var style = XlsxBorderStyle.none;
      final st = el.getAttribute('style');
      if (st != null) style = _borderStyle(st);
      var color = const Color(0xFF000000);
      for (final c in el.childElements) {
        if (c.name.local == 'color') {
          color = _parseColorEl(c, ThemeColorResolver(ThemeColorScheme.defaults), color);
        }
      }
      return XlsxBorderSide(style: style, color: color);
    }

    return XlsxBorder(
      left: side(_child(border, 'left')),
      right: side(_child(border, 'right')),
      top: side(_child(border, 'top')),
      bottom: side(_child(border, 'bottom')),
    );
  }

  static XlsxBorderStyle _borderStyle(String name) {
    switch (name) {
      case 'thin':
        return XlsxBorderStyle.thin;
      case 'medium':
        return XlsxBorderStyle.medium;
      case 'thick':
        return XlsxBorderStyle.thick;
      case 'hair':
        return XlsxBorderStyle.hair;
      case 'dashed':
        return XlsxBorderStyle.dashed;
      case 'dotted':
        return XlsxBorderStyle.dotted;
      case 'double':
        return XlsxBorderStyle.double;
      default:
        return XlsxBorderStyle.thin;
    }
  }

  static XlsxCellXf _parseXf(XmlElement xf) {
    final fontId = int.tryParse(xf.getAttribute('fontId') ?? '') ?? 0;
    final fillId = int.tryParse(xf.getAttribute('fillId') ?? '') ?? 0;
    final borderId = int.tryParse(xf.getAttribute('borderId') ?? '') ?? 0;
    final numFmtId = int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0;
    final applyAlignment = xf.getAttribute('applyAlignment') == '1';

    var h = XlsxHorizontalAlign.general;
    var v = XlsxVerticalAlign.bottom;
    var wrap = false;
    for (final child in xf.childElements) {
      if (child.name.local != 'alignment') continue;
      h = _hAlign(child.getAttribute('horizontal'));
      v = _vAlign(child.getAttribute('vertical'));
      wrap = child.getAttribute('wrapText') == '1';
    }

    return XlsxCellXf(
      fontId: fontId,
      fillId: fillId,
      borderId: borderId,
      numFmtId: numFmtId,
      hAlign: h,
      vAlign: v,
      wrapText: wrap,
      applyAlignment: applyAlignment,
    );
  }

  static XlsxHorizontalAlign _hAlign(String? raw) {
    switch (raw) {
      case 'left':
        return XlsxHorizontalAlign.left;
      case 'center':
        return XlsxHorizontalAlign.center;
      case 'right':
        return XlsxHorizontalAlign.right;
      case 'fill':
        return XlsxHorizontalAlign.fill;
      case 'justify':
        return XlsxHorizontalAlign.justify;
      default:
        return XlsxHorizontalAlign.general;
    }
  }

  static XlsxVerticalAlign _vAlign(String? raw) {
    switch (raw) {
      case 'top':
        return XlsxVerticalAlign.top;
      case 'center':
        return XlsxVerticalAlign.center;
      case 'justify':
        return XlsxVerticalAlign.justify;
      default:
        return XlsxVerticalAlign.bottom;
    }
  }

  static Color _parseColorEl(
    XmlElement color,
    ThemeColorResolver resolver,
    Color fallback,
  ) {
    final rgb = color.getAttribute('rgb');
    if (rgb != null && rgb.length >= 6) {
      final hex = rgb.length == 8 ? rgb.substring(2) : rgb;
      if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return Color(0xFF000000 | v);
      }
    }
    final themeIdx = int.tryParse(color.getAttribute('theme') ?? '');
    if (themeIdx != null) {
      final names = [
        'lt1',
        'dk1',
        'lt2',
        'dk2',
        'accent1',
        'accent2',
        'accent3',
        'accent4',
        'accent5',
        'accent6',
        'hlink',
        'folHlink',
      ];
      if (themeIdx >= 0 && themeIdx < names.length) {
        var base = resolver.scheme.resolveScheme(names[themeIdx]);
        final tint = double.tryParse(color.getAttribute('tint') ?? '');
        if (tint != null && tint != 0) {
          base = _applyTint(base, tint);
        }
        return base;
      }
    }
    final indexed = int.tryParse(color.getAttribute('indexed') ?? '');
    if (indexed != null) {
      return _indexedColor(indexed, fallback);
    }
    return fallback;
  }

  static Color _applyTint(Color base, double tint) {
    final r = base.r;
    final g = base.g;
    final b = base.b;
    if (tint > 0) {
      return Color.fromARGB(
        (base.a * 255).round(),
        ((r + (1 - r) * tint) * 255).round().clamp(0, 255),
        ((g + (1 - g) * tint) * 255).round().clamp(0, 255),
        ((b + (1 - b) * tint) * 255).round().clamp(0, 255),
      );
    }
    final f = 1 + tint;
    return Color.fromARGB(
      (base.a * 255).round(),
      (r * f * 255).round().clamp(0, 255),
      (g * f * 255).round().clamp(0, 255),
      (b * f * 255).round().clamp(0, 255),
    );
  }

  static Color _indexedColor(int index, Color fallback) {
    const palette = <int>[
      0xFF000000,
      0xFFFFFFFF,
      0xFFFF0000,
      0xFF00FF00,
      0xFF0000FF,
      0xFFFFFF00,
      0xFFFF00FF,
      0xFF00FFFF,
    ];
    if (index >= 0 && index < palette.length) {
      return Color(palette[index]);
    }
    return fallback;
  }
}
