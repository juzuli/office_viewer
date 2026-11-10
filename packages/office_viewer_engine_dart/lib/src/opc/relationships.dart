import 'package:xml/xml.dart';

/// One OPC relationship from a `.rels` part.
class Relationship {
  const Relationship({
    required this.id,
    required this.type,
    required this.target,
    this.external = false,
  });

  final String id;
  final String type;
  final String target;
  final bool external;
}

class Relationships {
  Relationships(List<Relationship> items) : items = List.unmodifiable(items);

  final List<Relationship> items;

  Relationship? byId(String id) {
    for (final r in items) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<Relationship> byType(String typeUri) =>
      items.where((r) => r.type == typeUri).toList();

  static Relationships parse(String xmlText) {
    final out = <Relationship>[];
    try {
      final doc = XmlDocument.parse(xmlText);
      for (final el in doc.rootElement.childElements) {
        if (el.name.local != 'Relationship') continue;
        final id = el.getAttribute('Id');
        final type = el.getAttribute('Type');
        final target = el.getAttribute('Target');
        if (id == null || type == null || target == null) continue;
        final mode = el.getAttribute('TargetMode');
        out.add(Relationship(
          id: id,
          type: type,
          target: target,
          external: mode == 'External',
        ));
      }
    } on XmlException {
      // Return partial / empty; caller records warning.
    }
    return Relationships(out);
  }

  /// Package-internal path to the `.rels` file for [partPath].
  static String relsPathForPart(String partPath) {
    var normalized = partPath.replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    final slash = normalized.lastIndexOf('/');
    if (slash < 0) {
      return '_rels/$normalized.rels';
    }
    final dir = normalized.substring(0, slash);
    final base = normalized.substring(slash + 1);
    return '$dir/_rels/$base.rels';
  }
}
