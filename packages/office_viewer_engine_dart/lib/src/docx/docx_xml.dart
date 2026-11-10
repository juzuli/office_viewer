import 'package:xml/xml.dart';

import '../theme/color.dart';

XmlElement? docxChild(XmlElement parent, String localName) {
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c;
  }
  return null;
}

Iterable<XmlElement> docxChildren(XmlElement parent, String localName) =>
    parent.childElements.where((c) => c.name.local == localName);

/// Reads an attribute by local name so `w:styleId` / `w:val` resolve.
String? docxAttr(XmlElement? el, String name) {
  if (el == null) return null;
  final direct = el.getAttribute(name);
  if (direct != null) return direct;
  for (final a in el.attributes) {
    if (a.name.local == name) return a.value;
  }
  return null;
}

int? docxIntAttr(XmlElement? el, String name) =>
    int.tryParse(docxAttr(el, name) ?? '');

/// OOXML on/off: absent = true; val false/0/off = false; val true/1/on = true.
bool? docxToggle(XmlElement? el) {
  if (el == null) return null;
  final val = docxAttr(el, 'val');
  if (val == null) return true;
  switch (val.toLowerCase()) {
    case '0':
    case 'false':
    case 'off':
      return false;
    case '1':
    case 'true':
    case 'on':
      return true;
    default:
      return true;
  }
}

/// Merge toggles with XOR semantics (OOXML character style inheritance).
bool applyToggleXor(bool? parent, bool? child, bool defaultValue) {
  if (child == null) return parent ?? defaultValue;
  final base = parent ?? defaultValue;
  return child ? !base : base;
}

List<XmlColorChild> docxColorChildren(XmlElement colorEl) {
  return colorEl.childElements
      .map(
        (c) => XmlColorChild(
          name: c.name.local,
          attrs: Map.fromEntries(
            c.attributes.map((a) => MapEntry(a.name.local, a.value)),
          ),
          children: docxColorChildren(c),
        ),
      )
      .toList();
}
