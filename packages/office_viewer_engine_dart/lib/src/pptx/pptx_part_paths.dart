/// Resolve OPC relationship targets relative to [sourcePart] (lower-case).
String resolveOpcTarget(String sourcePart, String target) {
  var t = target.replaceAll('\\', '/');
  if (t.startsWith('/')) {
    return _normalize(t.substring(1)).toLowerCase();
  }
  final base = sourcePart.replaceAll('\\', '/').toLowerCase();
  final slash = base.lastIndexOf('/');
  final dir = slash >= 0 ? base.substring(0, slash + 1) : '';
  return _normalize('$dir$t').toLowerCase();
}

String _normalize(String path) {
  final parts = <String>[];
  for (final seg in path.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}
