import 'package:flutter/services.dart';

/// Maps Office typeface names to bundled OFL families and loads assets.
class FontRegistry {
  FontRegistry._();

  static final FontRegistry instance = FontRegistry._();

  static const Map<String, String> substitution = {
    'Arial': 'Liberation Sans',
    'Helvetica': 'Liberation Sans',
    'Times New Roman': 'Liberation Serif',
    'Times': 'Liberation Serif',
    'Courier New': 'Liberation Mono',
    'Courier': 'Liberation Mono',
    'Calibri': 'Carlito',
    'Cambria': 'Caladea',
  };

  static const _assetFamilies = <String, List<String>>{
    'Liberation Sans': [
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSans-Regular.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSans-Bold.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSans-Italic.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSans-BoldItalic.ttf',
    ],
    'Liberation Serif': [
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSerif-Regular.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSerif-Bold.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSerif-Italic.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationSerif-BoldItalic.ttf',
    ],
    'Liberation Mono': [
      'packages/office_viewer_engine_dart/assets/fonts/LiberationMono-Regular.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationMono-Bold.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationMono-Italic.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/LiberationMono-BoldItalic.ttf',
    ],
    'Carlito': [
      'packages/office_viewer_engine_dart/assets/fonts/Carlito-Regular.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Carlito-Bold.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Carlito-Italic.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Carlito-BoldItalic.ttf',
    ],
    'Caladea': [
      'packages/office_viewer_engine_dart/assets/fonts/Caladea-Regular.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Caladea-Bold.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Caladea-Italic.ttf',
      'packages/office_viewer_engine_dart/assets/fonts/Caladea-BoldItalic.ttf',
    ],
  };

  final Set<String> _loaded = {};

  String familyFor(String? officeName) {
    if (officeName == null || officeName.isEmpty) {
      return 'Liberation Sans';
    }
    final key = officeName.trim();
    return substitution[key] ?? key;
  }

  Future<void> ensureRegistered() async {
    for (final entry in _assetFamilies.entries) {
      if (_loaded.contains(entry.key)) continue;
      await _registerFamily(entry.key, entry.value);
      _loaded.add(entry.key);
    }
  }

  Future<void> _registerFamily(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final path in assets) {
      try {
        final data = await rootBundle.load(path);
        loader.addFont(Future.value(data));
      } catch (_) {
        // Skip missing glyph files; substitution still works with regular.
      }
    }
    try {
      await loader.load();
    } catch (_) {
      // Never crash view on font load failure.
    }
  }
}
