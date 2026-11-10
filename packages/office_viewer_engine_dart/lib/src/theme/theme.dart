import 'dart:ui';

import 'package:xml/xml.dart';

/// Theme color slots from `theme/theme1.xml`.
class ThemeColorScheme {
  ThemeColorScheme({
    required this.dk1,
    required this.lt1,
    required this.dk2,
    required this.lt2,
    required this.accent1,
    required this.accent2,
    required this.accent3,
    required this.accent4,
    required this.accent5,
    required this.accent6,
    required this.hlink,
    required this.folHlink,
  });

  final Color dk1;
  final Color lt1;
  final Color dk2;
  final Color lt2;
  final Color accent1;
  final Color accent2;
  final Color accent3;
  final Color accent4;
  final Color accent5;
  final Color accent6;
  final Color hlink;
  final Color folHlink;

  Color resolveScheme(String name) {
    switch (name) {
      case 'dk1':
      case 'tx1':
      case 'text1':
        return dk1;
      case 'lt1':
      case 'bg1':
      case 'background1':
        return lt1;
      case 'dk2':
      case 'tx2':
      case 'text2':
        return dk2;
      case 'lt2':
      case 'bg2':
      case 'background2':
        return lt2;
      case 'accent1':
        return accent1;
      case 'accent2':
        return accent2;
      case 'accent3':
        return accent3;
      case 'accent4':
        return accent4;
      case 'accent5':
        return accent5;
      case 'accent6':
        return accent6;
      case 'hlink':
        return hlink;
      case 'folHlink':
        return folHlink;
      default:
        return dk1;
    }
  }

  static ThemeColorScheme defaults = ThemeColorScheme(
    dk1: const Color(0xFF000000),
    lt1: const Color(0xFFFFFFFF),
    dk2: const Color(0xFF1F1F1F),
    lt2: const Color(0xFFE7E6E6),
    accent1: const Color(0xFF4472C4),
    accent2: const Color(0xFFED7D31),
    accent3: const Color(0xFFA5A5A5),
    accent4: const Color(0xFFFFC000),
    accent5: const Color(0xFF5B9BD5),
    accent6: const Color(0xFF70AD47),
    hlink: const Color(0xFF0563C1),
    folHlink: const Color(0xFF954F72),
  );

  static ThemeColorScheme parse(String xmlText) {
    try {
      final doc = XmlDocument.parse(xmlText);
      XmlElement? clrScheme;
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'clrScheme') {
          clrScheme = el;
          break;
        }
      }
      if (clrScheme == null) return defaults;

      Color slot(String localName, Color fallback) {
        for (final child in clrScheme!.childElements) {
          if (child.name.local != localName) continue;
          for (final colorEl in child.childElements) {
            final hex = colorEl.getAttribute('val');
            if (colorEl.name.local == 'srgbClr' && hex != null && hex.length == 6) {
              return Color(0xFF000000 | int.parse(hex, radix: 16));
            }
            if (colorEl.name.local == 'sysClr') {
              final last = colorEl.getAttribute('lastClr');
              if (last != null && last.length == 6) {
                return Color(0xFF000000 | int.parse(last, radix: 16));
              }
            }
          }
        }
        return fallback;
      }

      final base = defaults;
      return ThemeColorScheme(
        dk1: slot('dk1', base.dk1),
        lt1: slot('lt1', base.lt1),
        dk2: slot('dk2', base.dk2),
        lt2: slot('lt2', base.lt2),
        accent1: slot('accent1', base.accent1),
        accent2: slot('accent2', base.accent2),
        accent3: slot('accent3', base.accent3),
        accent4: slot('accent4', base.accent4),
        accent5: slot('accent5', base.accent5),
        accent6: slot('accent6', base.accent6),
        hlink: slot('hlink', base.hlink),
        folHlink: slot('folHlink', base.folHlink),
      );
    } catch (_) {
      return defaults;
    }
  }
}

class ThemeFontScheme {
  const ThemeFontScheme({
    required this.majorLatin,
    required this.minorLatin,
  });

  final String majorLatin;
  final String minorLatin;

  static const ThemeFontScheme defaults = ThemeFontScheme(
    majorLatin: 'Calibri',
    minorLatin: 'Calibri',
  );

  static ThemeFontScheme parse(String xmlText) {
    try {
      final doc = XmlDocument.parse(xmlText);
      String? major;
      String? minor;
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'majorFont') {
          major ??= _latinTypeface(el);
        } else if (el.name.local == 'minorFont') {
          minor ??= _latinTypeface(el);
        }
      }
      return ThemeFontScheme(
        majorLatin: major ?? defaults.majorLatin,
        minorLatin: minor ?? defaults.minorLatin,
      );
    } catch (_) {
      return defaults;
    }
  }

  static String? _latinTypeface(XmlElement fontBlock) {
    for (final child in fontBlock.childElements) {
      if (child.name.local == 'latin') {
        return child.getAttribute('typeface');
      }
    }
    return null;
  }
}

/// Resolved theme bundle for layout (colors + fonts).
class OfficeTheme {
  const OfficeTheme({
    required this.colorScheme,
    required this.fontScheme,
  });

  final ThemeColorScheme colorScheme;
  final ThemeFontScheme fontScheme;

  static OfficeTheme defaults = OfficeTheme(
    colorScheme: ThemeColorScheme.defaults,
    fontScheme: ThemeFontScheme.defaults,
  );
}
