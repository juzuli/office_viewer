import 'dart:ui';

import 'theme.dart';

/// OOXML color spec → [Color] (straight alpha).
class ThemeColorResolver {
  ThemeColorResolver(this.scheme);

  final ThemeColorScheme scheme;

  Color resolveColorElement(Map<String, String> attrs, List<XmlColorChild> children) {
    // Word theme colors: prefer themeColor (+ themeShade/themeTint) over the
    // cached sRGB `val` so shaded accents match the active theme.
    final themeColor = attrs['themeColor'];
    if (themeColor != null && themeColor.isNotEmpty && themeColor != 'auto') {
      final base = scheme.resolveScheme(_mapThemeColorName(themeColor));
      return _applyThemeAttrs(base, attrs);
    }

    if (attrs.containsKey('val')) {
      final val = attrs['val']!;
      if (val == 'auto') {
        return const Color(0xFF000000);
      }
      if (_isHexRgb(val)) {
        return _applyModifiers(_fromSrgb(val), children);
      }
      if (_schemeNames.contains(val) || _wordThemeNames.contains(val)) {
        return _applyThemeAttrs(scheme.resolveScheme(_mapThemeColorName(val)), attrs);
      }
      if (_prstNames.contains(val)) {
        return _applyModifiers(_prstColor(val), children);
      }
    }
    for (final c in children) {
      if (c.name == 'srgbClr' && c.attrs['val'] != null) {
        return _applyModifiers(_fromSrgb(c.attrs['val']!), c.children);
      }
      if (c.name == 'schemeClr' && c.attrs['val'] != null) {
        return _applyModifiers(
          scheme.resolveScheme(c.attrs['val']!),
          c.children,
        );
      }
      if (c.name == 'sysClr') {
        final last = c.attrs['lastClr'];
        final base = last != null
            ? _fromSrgb(last)
            : scheme.resolveScheme(c.attrs['val'] ?? 'lt1');
        return _applyModifiers(base, c.children);
      }
      if (c.name == 'prstClr' && c.attrs['val'] != null) {
        return _applyModifiers(_prstColor(c.attrs['val']!), c.children);
      }
    }
    return const Color(0xFF000000);
  }

  /// Applies Word `themeShade` / `themeTint` attributes (hex 00–FF).
  Color _applyThemeAttrs(Color base, Map<String, String> attrs) {
    var color = base;
    final shade = attrs['themeShade'];
    if (shade != null) {
      final f = (int.tryParse(shade, radix: 16) ?? 255) / 255.0;
      color = Color.fromARGB(
        (color.a * 255).round(),
        (color.r * 255 * f).round().clamp(0, 255),
        (color.g * 255 * f).round().clamp(0, 255),
        (color.b * 255 * f).round().clamp(0, 255),
      );
    }
    final tint = attrs['themeTint'];
    if (tint != null) {
      final f = (int.tryParse(tint, radix: 16) ?? 255) / 255.0;
      color = Color.fromARGB(
        (color.a * 255).round(),
        (color.r * 255 + (255 - color.r * 255) * (1 - f)).round().clamp(0, 255),
        (color.g * 255 + (255 - color.g * 255) * (1 - f)).round().clamp(0, 255),
        (color.b * 255 + (255 - color.b * 255) * (1 - f)).round().clamp(0, 255),
      );
    }
    return color;
  }

  Color _applyModifiers(Color base, List<XmlColorChild> mods) {
    var r = base.r;
    var g = base.g;
    var b = base.b;
    var a = base.a;

    for (final m in mods) {
      final local = m.name;
      final val = _parseModifierValue(m.attrs['val']);
      if (local == 'alpha') {
        a = val / 100000;
      } else if (local == 'alphaMod') {
        a *= val / 100000;
      } else if (local == 'alphaOff') {
        a = (a + val / 100000).clamp(0.0, 1.0);
      } else if (local == 'lumMod') {
        final lum = _luminance(r, g, b) * (val / 100000);
        r = g = b = lum.clamp(0.0, 1.0);
      } else if (local == 'lumOff') {
        final lum = (_luminance(r, g, b) + val / 100000).clamp(0.0, 1.0);
        r = g = b = lum;
      } else if (local == 'tint') {
        r = r + (1 - r) * (val / 100000);
        g = g + (1 - g) * (val / 100000);
        b = b + (1 - b) * (val / 100000);
      } else if (local == 'shade') {
        final f = 1 - val / 100000;
        r *= f;
        g *= f;
        b *= f;
      }
    }

    return Color.fromARGB(
      (a * 255).round().clamp(0, 255),
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  static String _mapThemeColorName(String name) {
    switch (name) {
      case 'text1':
        return 'dk1';
      case 'text2':
        return 'dk2';
      case 'background1':
        return 'lt1';
      case 'background2':
        return 'lt2';
      default:
        return name;
    }
  }

  static double _luminance(double r, double g, double b) => 0.299 * r + 0.587 * g + 0.114 * b;

  static int _parseModifierValue(String? raw) {
    if (raw == null) return 100000;
    return int.tryParse(raw) ?? 100000;
  }

  static bool _isHexRgb(String val) =>
      val.length == 6 && int.tryParse(val, radix: 16) != null;

  static Color _fromSrgb(String hex) {
    final v = int.parse(hex, radix: 16);
    return Color(0xFF000000 | v);
  }

  static const _schemeNames = {
    'dk1', 'lt1', 'dk2', 'lt2',
    'tx1', 'tx2', 'bg1', 'bg2',
    'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6',
    'hlink', 'folHlink',
  };

  static const _wordThemeNames = {
    'text1',
    'text2',
    'background1',
    'background2',
  };

  static Color _prstColor(String name) {
    switch (name) {
      case 'black':
        return const Color(0xFF000000);
      case 'white':
        return const Color(0xFFFFFFFF);
      case 'red':
        return const Color(0xFFFF0000);
      case 'green':
        return const Color(0xFF00FF00);
      case 'blue':
        return const Color(0xFF0000FF);
      default:
        return const Color(0xFF808080);
    }
  }

  static const _prstNames = {'black', 'white', 'red', 'green', 'blue', 'gray'};
}

class XmlColorChild {
  const XmlColorChild({
    required this.name,
    required this.attrs,
    this.children = const [],
  });

  final String name;
  final Map<String, String> attrs;
  final List<XmlColorChild> children;
}
