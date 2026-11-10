import 'dart:ui';

/// Geometry in points (1/72 inch), aligned with LOK / PDF tooling.
class PointD {
  const PointD(this.x, this.y);
  final double x;
  final double y;

  Offset toOffset() => Offset(x, y);

  static PointD fromOffset(Offset o) => PointD(o.dx, o.dy);
}

class SizeD {
  const SizeD(this.width, this.height);
  final double width;
  final double height;

  Size toSize() => Size(width, height);

  static SizeD fromSize(Size s) => SizeD(s.width, s.height);
}

class RectD {
  const RectD(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);

  static RectD fromRect(Rect r) =>
      RectD(r.left, r.top, r.right, r.bottom);

  static RectD fromLTWH(double l, double t, double w, double h) =>
      RectD(l, t, l + w, t + h);
}
