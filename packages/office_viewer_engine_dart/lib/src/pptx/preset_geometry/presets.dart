import 'dart:math' as math;
import 'dart:ui';

/// Build a shape path for OOXML preset geometry names (bounds in points).
Path presetPath(
  String? preset,
  Rect bounds, {
  Map<String, double> adjust = const {},
}) {
  final name = preset ?? 'rect';
  switch (name) {
    case 'rect':
    case 'flowChartProcess':
    case 'plainText':
      return Path()..addRect(bounds);
    case 'roundRect':
      return _roundRect(bounds, adjust);
    case 'ellipse':
    case 'oval':
      return Path()..addOval(bounds);
    case 'triangle':
      return _triangle(bounds);
    case 'rtTriangle':
      return _rightTriangle(bounds);
    case 'diamond':
      return _diamond(bounds);
    case 'rightArrow':
    case 'arrow':
      return _rightArrow(bounds);
    case 'line':
      return _line(bounds);
    default:
      return Path()..addRect(bounds);
  }
}

Path _roundRect(Rect r, Map<String, double> adjust) {
  final w = r.width;
  final h = r.height;
  final adj = adjust['adj'] ?? 16667;
  final radius = math.min(w, h) * (adj / 100000.0) * 0.5;
  return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
}

Path _triangle(Rect r) {
  return Path()
    ..moveTo(r.left + r.width / 2, r.top)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..close();
}

Path _rightTriangle(Rect r) {
  return Path()
    ..moveTo(r.left, r.top)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..close();
}

Path _diamond(Rect r) {
  final cx = r.left + r.width / 2;
  final cy = r.top + r.height / 2;
  return Path()
    ..moveTo(cx, r.top)
    ..lineTo(r.right, cy)
    ..lineTo(cx, r.bottom)
    ..lineTo(r.left, cy)
    ..close();
}

Path _rightArrow(Rect r) {
  final shaftH = r.height * 0.5;
  final headW = r.width * 0.35;
  final shaftTop = r.top + (r.height - shaftH) / 2;
  final shaftBot = shaftTop + shaftH;
  final shaftRight = r.right - headW;

  return Path()
    ..moveTo(r.left, shaftTop)
    ..lineTo(shaftRight, shaftTop)
    ..lineTo(shaftRight, r.top)
    ..lineTo(r.right, r.top + r.height / 2)
    ..lineTo(shaftRight, r.bottom)
    ..lineTo(shaftRight, shaftBot)
    ..lineTo(r.left, shaftBot)
    ..close();
}

Path _line(Rect r) {
  return Path()
    ..moveTo(r.left, r.top + r.height / 2)
    ..lineTo(r.right, r.top + r.height / 2);
}
