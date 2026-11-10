import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:xml/xml.dart';

import '../theme/color.dart';
import '../xml/units.dart';

/// Shape transform from `a:xfrm` (points, degrees).
class ShapeTransform {
  const ShapeTransform({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.rotationDeg = 0,
    this.flipH = false,
    this.flipV = false,
    this.childOffsetX = 0,
    this.childOffsetY = 0,
    this.childExtentW = 0,
    this.childExtentH = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotationDeg;
  final bool flipH;
  final bool flipV;
  final double childOffsetX;
  final double childOffsetY;
  final double childExtentW;
  final double childExtentH;

  Rect get boundsRect => Rect.fromLTWH(x, y, width, height);

  ShapeTransform copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotationDeg,
    bool? flipH,
    bool? flipV,
    double? childOffsetX,
    double? childOffsetY,
    double? childExtentW,
    double? childExtentH,
  }) {
    return ShapeTransform(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      childOffsetX: childOffsetX ?? this.childOffsetX,
      childOffsetY: childOffsetY ?? this.childOffsetY,
      childExtentW: childExtentW ?? this.childExtentW,
      childExtentH: childExtentH ?? this.childExtentH,
    );
  }
}

sealed class ShapeFill {
  const ShapeFill();
}

class SolidShapeFill extends ShapeFill {
  const SolidShapeFill(this.color);
  final Color color;
}

class GradientStop {
  const GradientStop({required this.position, required this.color});
  final double position;
  final Color color;
}

class GradientShapeFill extends ShapeFill {
  const GradientShapeFill({
    required this.stops,
    this.angleDeg = 0,
  });

  final List<GradientStop> stops;
  final double angleDeg;
}

class ShapeOutline {
  const ShapeOutline({
    this.widthPt = 0.75,
    this.fill,
  });

  final double widthPt;
  final SolidShapeFill? fill;
}

/// Parse `a:xfrm` under spPr / grpSpPr.
ShapeTransform? parseXfrm(XmlElement? parent) {
  if (parent == null) return null;
  XmlElement? xfrm;
  for (final el in parent.descendants.whereType<XmlElement>()) {
    if (el.name.local == 'xfrm' && el.parent == parent) {
      xfrm = el;
      break;
    }
  }
  xfrm ??= _firstDescendant(parent, 'xfrm');
  if (xfrm == null) return null;

  double offX = 0, offY = 0, extW = 0, extH = 0;
  double chOffX = 0, chOffY = 0, chExtW = 0, chExtH = 0;
  var rot = 0.0;
  var flipH = false;
  var flipV = false;

  for (final child in xfrm.childElements) {
    final local = child.name.local;
    if (local == 'off') {
      offX = emuToPt(int.tryParse(child.getAttribute('x') ?? '0') ?? 0);
      offY = emuToPt(int.tryParse(child.getAttribute('y') ?? '0') ?? 0);
    } else if (local == 'ext') {
      extW = emuToPt(int.tryParse(child.getAttribute('cx') ?? '0') ?? 0);
      extH = emuToPt(int.tryParse(child.getAttribute('cy') ?? '0') ?? 0);
    } else if (local == 'chOff') {
      chOffX = emuToPt(int.tryParse(child.getAttribute('x') ?? '0') ?? 0);
      chOffY = emuToPt(int.tryParse(child.getAttribute('y') ?? '0') ?? 0);
    } else if (local == 'chExt') {
      chExtW = emuToPt(int.tryParse(child.getAttribute('cx') ?? '0') ?? 0);
      chExtH = emuToPt(int.tryParse(child.getAttribute('cy') ?? '0') ?? 0);
    }
  }

  final rotRaw = xfrm.getAttribute('rot');
  if (rotRaw != null) {
    rot = angle60000(int.tryParse(rotRaw) ?? 0);
  }
  flipH = xfrm.getAttribute('flipH') == '1';
  flipV = xfrm.getAttribute('flipV') == '1';

  return ShapeTransform(
    x: offX,
    y: offY,
    width: extW,
    height: extH,
    rotationDeg: rot,
    flipH: flipH,
    flipV: flipV,
    childOffsetX: chOffX,
    childOffsetY: chOffY,
    childExtentW: chExtW,
    childExtentH: chExtH,
  );
}

ShapeFill? parseShapeFill(
  XmlElement spPrOrSimilar,
  ThemeColorResolver colors,
) {
  for (final child in spPrOrSimilar.childElements) {
    final local = child.name.local;
    if (local == 'noFill') return null;
    if (local == 'solidFill') {
      final c = _parseColorContainer(child, colors);
      if (c != null) return SolidShapeFill(c);
    }
    if (local == 'gradFill') {
      return _parseGradFill(child, colors);
    }
  }
  return null;
}

ShapeOutline? parseShapeOutline(
  XmlElement spPrOrSimilar,
  ThemeColorResolver colors,
) {
  XmlElement? ln;
  for (final child in spPrOrSimilar.childElements) {
    if (child.name.local == 'ln') {
      ln = child;
      break;
    }
  }
  if (ln == null) return null;

  var wPt = 0.75;
  final wEmu = ln.getAttribute('w');
  if (wEmu != null) {
    wPt = emuToPt(int.tryParse(wEmu) ?? 9525);
  }

  SolidShapeFill? fill;
  for (final child in ln.childElements) {
    if (child.name.local == 'noFill') {
      return null;
    }
    if (child.name.local == 'solidFill') {
      final c = _parseColorContainer(child, colors);
      if (c != null) fill = SolidShapeFill(c);
    }
  }

  return ShapeOutline(widthPt: wPt, fill: fill);
}

String? parsePresetGeometryName(XmlElement spPr) {
  for (final child in spPr.childElements) {
    if (child.name.local == 'prstGeom') {
      return child.getAttribute('prst');
    }
  }
  return null;
}

Map<String, double> parseAdjustValues(XmlElement spPr) {
  final out = <String, double>{};
  for (final child in spPr.childElements) {
    if (child.name.local != 'prstGeom') continue;
    for (final av in child.descendants.whereType<XmlElement>()) {
      if (av.name.local == 'gd' &&
          av.parent is XmlElement &&
          (av.parent as XmlElement).name.local == 'avLst') {
        final name = av.getAttribute('name');
        final fmla = av.getAttribute('fmla');
        if (name != null && fmla != null && fmla.startsWith('val ')) {
          final v = double.tryParse(fmla.substring(4).trim());
          if (v != null) out[name] = v;
        }
      }
    }
  }
  return out;
}

Color? _parseColorContainer(XmlElement container, ThemeColorResolver colors) {
  return colors.resolveColorElement(
    Map.fromEntries(
      container.attributes.map(
        (a) => MapEntry(a.name.local, a.value),
      ),
    ),
    _colorChildren(container),
  );
}

GradientShapeFill? _parseGradFill(XmlElement gradFill, ThemeColorResolver colors) {
  XmlElement? gsLst;
  for (final child in gradFill.childElements) {
    if (child.name.local == 'gsLst') gsLst = child;
  }
  if (gsLst == null) return null;

  final stops = <GradientStop>[];
  for (final gs in gsLst.childElements) {
    if (gs.name.local != 'gs') continue;
    final posRaw = gs.getAttribute('pos');
    final pos = posRaw != null ? (int.tryParse(posRaw) ?? 0) / 100000.0 : 0.0;
    Color? c;
    for (final inner in gs.childElements) {
      if (inner.name.local == 'solidFill') {
        c = _parseColorContainer(inner, colors);
        break;
      }
      c ??= _parseColorContainer(inner, colors);
    }
    if (c != null) stops.add(GradientStop(position: pos, color: c));
  }
  if (stops.isEmpty) return null;

  var angle = 0.0;
  for (final child in gradFill.childElements) {
    if (child.name.local == 'lin') {
      final ang = child.getAttribute('ang');
      if (ang != null) angle = angle60000(int.tryParse(ang) ?? 0);
    }
  }

  return GradientShapeFill(stops: stops, angleDeg: angle);
}

List<XmlColorChild> _colorChildren(XmlElement parent) {
  return [
    for (final el in parent.childElements)
      XmlColorChild(
        name: el.name.local,
        attrs: {for (final a in el.attributes) a.name.local: a.value},
        children: _colorChildren(el),
      ),
  ];
}

XmlElement? _firstDescendant(XmlElement root, String local) {
  for (final el in root.descendants.whereType<XmlElement>()) {
    if (el.name.local == local) return el;
  }
  return null;
}

/// Apply flip/rotation around shape center; column-major 4×4 for [Canvas.transform].
Float64List transformMatrixFor(ShapeTransform t) {
  final cx = t.x + t.width / 2;
  final cy = t.y + t.height / 2;
  final rad = t.rotationDeg * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  final sx = t.flipH ? -1.0 : 1.0;
  final sy = t.flipV ? -1.0 : 1.0;

  final a = c * sx;
  final b = s * sx;
  final d = -s * sy;
  final e = c * sy;
  final tx = t.x + cx - (a * cx + d * cy);
  final ty = t.y + cy - (b * cx + e * cy);

  return Float64List.fromList([
    a, b, 0, 0,
    d, e, 0, 0,
    0, 0, 1, 0,
    tx, ty, 0, 1,
  ]);
}
