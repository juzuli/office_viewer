import 'package:xml/xml.dart';

/// Parsed `[Content_Types].xml` defaults and overrides.
class ContentTypes {
  ContentTypes({
    required Map<String, String> defaults,
    required Map<String, String> overrides,
  })  : defaults = Map.unmodifiable(defaults),
        overrides = Map.unmodifiable(overrides);

  final Map<String, String> defaults;
  final Map<String, String> overrides;

  /// Content type for [partPath] (e.g. `word/document.xml` or `/word/document.xml`).
  String? contentTypeForPart(String partPath) {
    final normalized = _normalizePartName(partPath);
    final withSlash = '/$normalized';
    final override = overrides[withSlash];
    if (override != null) return override;
    final dot = normalized.lastIndexOf('.');
    if (dot >= 0 && dot < normalized.length - 1) {
      final ext = normalized.substring(dot + 1).toLowerCase();
      return defaults[ext];
    }
    return null;
  }

  bool hasMainPartType(String fragment) {
    for (final value in overrides.values) {
      if (value.contains(fragment)) return true;
    }
    return false;
  }

  static ContentTypes parse(String xmlText) {
    final defaults = <String, String>{};
    final overrides = <String, String>{};
    try {
      final doc = XmlDocument.parse(xmlText);
      final root = doc.rootElement;
      for (final el in root.childElements) {
        final local = el.name.local;
        if (local == 'Default') {
          final ext = el.getAttribute('Extension');
          final ct = el.getAttribute('ContentType');
          if (ext != null && ct != null) {
            defaults[ext.toLowerCase()] = ct;
          }
        } else if (local == 'Override') {
          final part = el.getAttribute('PartName');
          final ct = el.getAttribute('ContentType');
          if (part != null && ct != null) {
            overrides[part] = ct;
          }
        }
      }
    } on XmlException {
      // Caller maps empty / invalid to corrupt via warnings.
    }
    return ContentTypes(defaults: defaults, overrides: overrides);
  }

  static String _normalizePartName(String partPath) {
    var p = partPath.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p;
  }
}
