import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/theme/color.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';

void main() {
  test('srgbClr resolves', () {
    final resolver = ThemeColorResolver(ThemeColorScheme.defaults);
    final c = resolver.resolveColorElement(const {}, [
      const XmlColorChild(name: 'srgbClr', attrs: {'val': 'FF0000'}),
    ]);
    expect(c, const Color(0xFFFF0000));
  });

  test('schemeClr accent1 resolves', () {
    final resolver = ThemeColorResolver(ThemeColorScheme.defaults);
    final c = resolver.resolveColorElement(const {}, [
      const XmlColorChild(name: 'schemeClr', attrs: {'val': 'accent1'}),
    ]);
    expect(c, ThemeColorScheme.defaults.accent1);
  });

  test('tint modifier lightens', () {
    final resolver = ThemeColorResolver(ThemeColorScheme.defaults);
    final c = resolver.resolveColorElement(const {}, [
      const XmlColorChild(
        name: 'srgbClr',
        attrs: {'val': '808080'},
        children: [
          XmlColorChild(name: 'tint', attrs: {'val': '50000'}),
        ],
      ),
    ]);
    expect((c.r * 255).round(), greaterThan(0x80));
  });

  test('themeColor + themeShade darkens accent', () {
    final scheme = ThemeColorScheme.defaults;
    final resolver = ThemeColorResolver(scheme);
    final c = resolver.resolveColorElement({
      'val': '4F81BD',
      'themeColor': 'accent1',
      'themeShade': 'BF',
    }, const []);
    // Shaded accent should be darker than base accent1.
    expect((c.r * 255).round(), lessThan((scheme.accent1.r * 255).round()));
  });
}
