import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:xml/xml.dart';

import '../../model/display_list.dart';

/// Paints simple charts from OOXML cached values (`c:numCache` / `c:strCache`).
///
/// Unsupported chart types → titled placeholder frame.
class ChartPainter {
  const ChartPainter();

  static const _axis = Color(0xFF595959);
  static const _grid = Color(0xFFD0D0D0);
  static const _label = Color(0xFF333333);
  static const _seriesColors = [
    Color(0xFF4472C4),
    Color(0xFFED7D31),
    Color(0xFF70AD47),
    Color(0xFFFFC000),
    Color(0xFF5B9BD5),
    Color(0xFFA5A5A5),
  ];

  DisplayList paintCachedChart(
    String chartXml, {
    required Size size,
    String? titleFallback,
    ChartRangeResolver? rangeResolver,
  }) {
    // No outer frame — PowerPoint charts typically have none unless styled.
    final ops = <DisplayOp>[
      FillRectOp(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Color(0xFFFFFFFF),
      ),
    ];

    try {
      final doc = XmlDocument.parse(chartXml);
      final series = _readSeries(doc, rangeResolver);
      final kind = _detectKind(doc);
      final title = _readTitle(doc);
      final axisTitles = _readAxisTitles(doc);
      final showLegend = _els(doc, 'legend').isNotEmpty;

      var top = 10.0;
      if (title != null && title.isNotEmpty) {
        ops.add(
          DrawTextRawOp(
            text: title,
            box: Rect.fromLTWH(8, 6, size.width - 16, 18),
            fontSizePt: 11,
            color: const Color(0xFF222222),
            bold: true,
            align: TextAlign.center,
          ),
        );
        top = 28;
      }

      if (series.isEmpty) {
        ops.add(
          DrawTextRawOp(
            text: titleFallback ?? 'Chart (no cached values)',
            box: Rect.fromLTWH(8, size.height / 2 - 8, size.width - 16, 16),
            fontSizePt: 10,
            color: const Color(0xFF666666),
            align: TextAlign.center,
          ),
        );
        return DisplayList(ops: ops, size: size);
      }

      final hasAxisTitles =
          (axisTitles.x != null && axisTitles.x!.isNotEmpty) ||
          (axisTitles.y != null && axisTitles.y!.isNotEmpty);
      final legendPos = _readLegendPos(doc);
      // Prefer OOXML legendPos; fall back to right when axis titles imply Excel-style layout.
      final legendAtRight = showLegend &&
          (legendPos == 'r' ||
              legendPos == 'tr' ||
              (legendPos == null && hasAxisTitles));
      final legendAtTop = showLegend && legendPos == 't';
      final bottomLegendH =
          showLegend && !legendAtRight && !legendAtTop ? 22.0 : 4.0;
      if (legendAtTop && top < 28) top = 28;
      final yTitleW = (axisTitles.y != null && axisTitles.y!.isNotEmpty) ? 16.0 : 0.0;
      final xTitleH = (axisTitles.x != null && axisTitles.x!.isNotEmpty) ? 16.0 : 0.0;

      List<(String, Color)> legendItemsFor(List<_ChartSeries> s, _ChartKind k) {
        if (k == _ChartKind.pie && s.isNotEmpty) {
          return [
            for (var i = 0; i < s.first.categories.length; i++)
              (
                s.first.categories[i],
                _seriesColors[i % _seriesColors.length],
              ),
          ];
        }
        return [
          for (var i = 0; i < s.length; i++)
            (s[i].name, _seriesColors[i % _seriesColors.length]),
        ];
      }

      final previewItems = legendItemsFor(series, kind);
      final rightLegendW = legendAtRight
          ? _legendColumnWidth(previewItems).clamp(68.0, 120.0)
          : 0.0;
      final plotLeft = 36.0 + yTitleW;
      final plotTop = top;
      final plotW = math.max(
        40.0,
        size.width - plotLeft - (legendAtRight ? rightLegendW + 8 : 16),
      );
      final plotH = math.max(
        40.0,
        size.height - plotTop - bottomLegendH - 22 - xTitleH,
      );
      final plot = Rect.fromLTWH(plotLeft, plotTop, plotW, plotH);

      void paintLegendIfNeeded(List<(String, Color)> items) {
        if (!showLegend || items.isEmpty) return;
        if (legendAtRight) {
          _paintLegend(
            ops,
            Rect.fromLTWH(plot.right + 8, plot.top, rightLegendW, plot.height),
            items,
            vertical: true,
          );
        } else if (legendAtTop) {
          _paintLegend(
            ops,
            Rect.fromLTWH(8, 6, size.width - 16, 18),
            items,
            alignEnd: true,
          );
        } else {
          _paintLegend(
            ops,
            Rect.fromLTWH(
              8,
              size.height - bottomLegendH - 4,
              size.width - 16,
              bottomLegendH,
            ),
            items,
          );
        }
      }

      switch (kind) {
        case _ChartKind.pie:
          _paintPie(ops, plot, series.first.values);
          paintLegendIfNeeded(legendItemsFor(series, kind));
        case _ChartKind.line:
          _paintAxes(
            ops,
            plot,
            series,
            drawBars: false,
            xTitle: axisTitles.x,
            yTitle: axisTitles.y,
          );
          _paintLine(ops, plot, series);
          paintLegendIfNeeded(legendItemsFor(series, kind));
        case _ChartKind.bar:
        case _ChartKind.unknown:
          _paintAxes(
            ops,
            plot,
            series,
            drawBars: true,
            xTitle: axisTitles.x,
            yTitle: axisTitles.y,
          );
          paintLegendIfNeeded(legendItemsFor(series, kind));
      }
    } catch (_) {
      ops.add(
        DrawTextRawOp(
          text: titleFallback ?? 'Chart',
          box: Rect.fromLTWH(8, size.height / 2 - 8, size.width - 16, 16),
          fontSizePt: 10,
          color: const Color(0xFF666666),
          align: TextAlign.center,
        ),
      );
    }

    return DisplayList(ops: ops, size: size);
  }

  /// `package:xml` requires an explicit namespace (or `*`) for prefixed OOXML.
  static Iterable<XmlElement> _els(XmlNode root, String local) =>
      root.findAllElements(local, namespace: '*');

  String? _readTitle(XmlDocument doc) {
    for (final title in _els(doc, 'title')) {
      // Skip axis titles nested under catAx/valAx — only chart-level title.
      final parent = title.parent;
      if (parent is XmlElement &&
          (parent.name.local == 'catAx' ||
              parent.name.local == 'valAx' ||
              parent.name.local == 'dateAx')) {
        continue;
      }
      final text = _titleText(title);
      if (text != null) return text;
    }
    return null;
  }

  ({String? x, String? y}) _readAxisTitles(XmlDocument doc) {
    String? x;
    String? y;
    for (final ax in _els(doc, 'catAx')) {
      x ??= _axisTitleIn(ax);
    }
    for (final ax in _els(doc, 'dateAx')) {
      x ??= _axisTitleIn(ax);
    }
    for (final ax in _els(doc, 'valAx')) {
      y ??= _axisTitleIn(ax);
    }
    return (x: x, y: y);
  }

  /// OOXML `c:legendPos` values: `b` | `tr` | `l` | `r` | `t`.
  String? _readLegendPos(XmlDocument doc) {
    for (final legend in _els(doc, 'legend')) {
      for (final pos in legend.findElements('legendPos', namespace: '*')) {
        final v = pos.getAttribute('val')?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  /// Dense list sized to max `idx`, missing slots filled with [fill].
  List<String> _indexedStrings(XmlElement cache) {
    final byIdx = <int, String>{};
    var next = 0;
    for (final pt in _els(cache, 'pt')) {
      final rawIdx = pt.getAttribute('idx');
      final idx = rawIdx != null ? (int.tryParse(rawIdx) ?? next) : next;
      final v = pt.findElements('v', namespace: '*');
      byIdx[idx] = v.isEmpty ? '' : v.first.innerText;
      next = idx + 1;
    }
    if (byIdx.isEmpty) return const [];
    final maxIdx = byIdx.keys.reduce(math.max);
    return [for (var i = 0; i <= maxIdx; i++) byIdx[i] ?? ''];
  }

  /// Dense numeric list; missing/`idx` gaps are [double.nan].
  List<double> _indexedNumbers(XmlElement cache) {
    final byIdx = <int, double>{};
    var next = 0;
    for (final pt in _els(cache, 'pt')) {
      final rawIdx = pt.getAttribute('idx');
      final idx = rawIdx != null ? (int.tryParse(rawIdx) ?? next) : next;
      final v = pt.findElements('v', namespace: '*');
      if (v.isNotEmpty) {
        final n = double.tryParse(v.first.innerText);
        if (n != null) byIdx[idx] = n;
      }
      next = idx + 1;
    }
    if (byIdx.isEmpty) return const [];
    final maxIdx = byIdx.keys.reduce(math.max);
    return [
      for (var i = 0; i <= maxIdx; i++) byIdx[i] ?? double.nan,
    ];
  }

  String? _axisTitleIn(XmlElement axis) {
    for (final title in axis.findElements('title', namespace: '*')) {
      final text = _titleText(title);
      if (text != null) return text;
    }
    return null;
  }

  String? _titleText(XmlElement title) {
    for (final v in _els(title, 'v')) {
      final t = v.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    for (final tEl in _els(title, 't')) {
      final t = tEl.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  List<_ChartSeries> _readSeries(
    XmlDocument doc,
    ChartRangeResolver? resolver,
  ) {
    final out = <_ChartSeries>[];
    for (final ser in _els(doc, 'ser')) {
      var name = 'Series ${out.length + 1}';
      for (final tx in ser.findElements('tx', namespace: '*')) {
        var found = false;
        for (final v in _els(tx, 'v')) {
          final t = v.innerText.trim();
          if (t.isNotEmpty) {
            name = t;
            found = true;
            break;
          }
        }
        if (!found && resolver != null) {
          for (final f in _els(tx, 'f')) {
            final resolved = resolver.strings(f.innerText.trim());
            if (resolved.isNotEmpty) {
              name = resolved.first;
              break;
            }
          }
        }
      }

      final categories = <String>[];
      for (final cat in ser.findElements('cat', namespace: '*')) {
        // Prefer string categories; do not also append numCache (avoids doubling).
        for (final cache in _els(cat, 'strCache')) {
          categories.addAll(_indexedStrings(cache));
        }
        if (categories.isEmpty) {
          for (final cache in _els(cat, 'numCache')) {
            categories.addAll(_indexedStrings(cache));
          }
        }
        if (categories.isEmpty && resolver != null) {
          for (final f in _els(cat, 'f')) {
            categories.addAll(resolver.strings(f.innerText.trim()));
          }
        }
      }

      final values = <double>[];
      for (final val in ser.findElements('val', namespace: '*')) {
        for (final cache in _els(val, 'numCache')) {
          values.addAll(_indexedNumbers(cache));
        }
        if (values.isEmpty && resolver != null) {
          for (final f in _els(val, 'f')) {
            values.addAll(resolver.numbers(f.innerText.trim()));
          }
        }
      }
      if (values.isEmpty || values.every((v) => v.isNaN)) continue;
      out.add(_ChartSeries(name: name, categories: categories, values: values));
    }

    // Fallback: flat numCache list when `c:ser` is absent.
    if (out.isEmpty) {
      for (final cache in _els(doc, 'numCache')) {
        final pts = _indexedNumbers(cache);
        if (pts.isNotEmpty && pts.any((v) => !v.isNaN)) {
          out.add(_ChartSeries(
            name: 'Series ${out.length + 1}',
            categories: const [],
            values: pts,
          ));
        }
      }
    }
    return out;
  }

  _ChartKind _detectKind(XmlDocument doc) {
    if (_els(doc, 'pieChart').isNotEmpty ||
        _els(doc, 'doughnutChart').isNotEmpty) {
      return _ChartKind.pie;
    }
    if (_els(doc, 'lineChart').isNotEmpty) {
      return _ChartKind.line;
    }
    if (_els(doc, 'barChart').isNotEmpty ||
        _els(doc, 'bar3DChart').isNotEmpty) {
      return _ChartKind.bar;
    }
    return _ChartKind.unknown;
  }

  double _niceMax(double maxV) {
    if (maxV <= 0) return 1;
    final exp = (math.log(maxV) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final n = maxV / base;
    final nice = n <= 1
        ? 1.0
        : n <= 2
            ? 2.0
            : n <= 5
                ? 5.0
                : 10.0;
    return nice * base;
  }

  /// Inclusive Y domain that always includes 0 (Excel-like).
  ({double min, double max}) _valueDomain(List<_ChartSeries> series) {
    var minV = 0.0;
    var maxV = 0.0;
    var any = false;
    for (final s in series) {
      for (final v in s.values) {
        if (v.isNaN) continue;
        if (!any) {
          minV = maxV = v;
          any = true;
        } else {
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
    }
    if (!any) return (min: 0, max: 1);
    if (minV > 0) minV = 0;
    if (maxV < 0) maxV = 0;
    final niceMax = maxV > 0 ? _niceMax(maxV * 1.05) : 0.0;
    final niceMin = minV < 0 ? -_niceMax((-minV) * 1.05) : 0.0;
    if (niceMin == niceMax) return (min: 0, max: 1);
    return (min: niceMin, max: niceMax);
  }

  double _yForValue(double value, Rect plot, double axisMin, double axisMax) {
    final span = axisMax - axisMin;
    if (span <= 0) return plot.bottom;
    return plot.bottom - ((value - axisMin) / span) * plot.height;
  }

  void _paintAxes(
    List<DisplayOp> ops,
    Rect plot,
    List<_ChartSeries> series, {
    required bool drawBars,
    String? xTitle,
    String? yTitle,
  }) {
    final domain = _valueDomain(series);
    final axisMin = domain.min;
    final axisMax = domain.max;
    final cats = series
        .map((s) => math.max(s.categories.length, s.values.length))
        .fold<int>(series.first.values.length, math.max);
    final catLabels = series.first.categories.isNotEmpty
        ? series.first.categories
        : [for (var i = 0; i < cats; i++) '${i + 1}'];

    // Horizontal gridlines + Y tick labels.
    const ticks = 4;
    final tickLabelRight = plot.left - 4;
    for (var t = 0; t <= ticks; t++) {
      final frac = t / ticks;
      final value = axisMin + (axisMax - axisMin) * frac;
      final y = _yForValue(value, plot, axisMin, axisMax);
      final isBaseline = value == 0 || (axisMin >= 0 && t == 0);
      ops.add(StrokePathOp(
        Path()
          ..moveTo(plot.left, y)
          ..lineTo(plot.right, y),
        isBaseline ? _axis : _grid,
        isBaseline ? 1.0 : 0.6,
      ));
      final label = value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(1);
      ops.add(DrawTextRawOp(
        text: label,
        box: Rect.fromLTWH(tickLabelRight - 28, y - 7, 28, 14),
        fontSizePt: 9,
        color: _label,
        align: TextAlign.right,
      ));
    }

    // Axis lines only (left + bottom), matching default chart styling.
    ops.add(StrokePathOp(
      Path()
        ..moveTo(plot.left, plot.top)
        ..lineTo(plot.left, plot.bottom)
        ..lineTo(plot.right, plot.bottom),
      _axis,
      1.25,
    ));

    if (drawBars) {
      _paintClusteredBars(ops, plot, series, axisMin, axisMax);
    }

    // Category labels under axis.
    final groupW = plot.width / cats;
    for (var i = 0; i < cats && i < catLabels.length; i++) {
      ops.add(DrawTextRawOp(
        text: catLabels[i],
        box: Rect.fromLTWH(plot.left + i * groupW, plot.bottom + 2, groupW, 14),
        fontSizePt: 9,
        color: _label,
        align: TextAlign.center,
      ));
    }

    if (xTitle != null && xTitle.isNotEmpty) {
      ops.add(DrawTextRawOp(
        text: xTitle,
        box: Rect.fromLTWH(plot.left, plot.bottom + 16, plot.width, 14),
        fontSizePt: 9,
        color: _label,
        align: TextAlign.center,
      ));
    }

    if (yTitle != null && yTitle.isNotEmpty) {
      // Rotate -90° so the value-axis title reads bottom→top along the left.
      final anchorX = (plot.left - 34).clamp(10.0, plot.left - 12);
      final anchorY = plot.center.dy;
      ops.add(PushTransformOp(_rotationAbout(anchorX, anchorY, -math.pi / 2)));
      ops.add(DrawTextRawOp(
        text: yTitle,
        box: Rect.fromLTWH(anchorX - plot.height / 2, anchorY - 7, plot.height, 14),
        fontSizePt: 9,
        color: _label,
        align: TextAlign.center,
      ));
      ops.add(const PopTransformOp());
    }
  }

  /// Column-major 4×4 matrix: translate to [cx,cy], rotate [radians], translate back.
  static Float64List _rotationAbout(double cx, double cy, double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Float64List.fromList([
      c, s, 0, 0,
      -s, c, 0, 0,
      0, 0, 1, 0,
      cx - c * cx + s * cy,
      cy - s * cx - c * cy,
      0,
      1,
    ]);
  }

  void _paintClusteredBars(
    List<DisplayOp> ops,
    Rect plot,
    List<_ChartSeries> series,
    double axisMin,
    double axisMax,
  ) {
    final cats = series.map((s) => s.values.length).fold<int>(0, math.max);
    final span = axisMax - axisMin;
    if (cats == 0 || span <= 0) return;
    final groupW = plot.width / cats;
    final barW = groupW * 0.72 / series.length;
    final zeroY = _yForValue(0, plot, axisMin, axisMax);
    for (var i = 0; i < cats; i++) {
      for (var s = 0; s < series.length; s++) {
        if (i >= series[s].values.length) continue;
        final value = series[s].values[i];
        if (value.isNaN) continue;
        final y = _yForValue(value, plot, axisMin, axisMax);
        final top = math.min(y, zeroY);
        final h = (y - zeroY).abs().clamp(0.5, plot.height);
        final r = Rect.fromLTWH(
          plot.left + i * groupW + groupW * 0.14 + s * barW,
          top,
          barW * 0.92,
          h,
        );
        final color = _seriesColors[s % _seriesColors.length];
        // Border via outer fill so outlines survive low-DPI tile rasterization.
        ops.add(FillRectOp(r.inflate(1.1), const Color(0xFF1F4E79)));
        ops.add(FillRectOp(r, color));
        // Data label outside the bar (above positives, below negatives).
        final labelTop = value >= 0
            ? (r.top - 14).clamp(plot.top, plot.bottom - 12)
            : (r.bottom + 1).clamp(plot.top, plot.bottom - 12);
        ops.add(DrawTextRawOp(
          text: value == value.roundToDouble()
              ? value.round().toString()
              : value.toStringAsFixed(1),
          box: Rect.fromLTWH(r.left - 6, labelTop, r.width + 12, 13),
          fontSizePt: 9,
          bold: true,
          color: _label,
          align: TextAlign.center,
        ));
      }
    }
  }

  static double _legendColumnWidth(List<(String, Color)> items) {
    var maxChars = 0;
    for (final (name, _) in items) {
      if (name.length > maxChars) maxChars = name.length;
    }
    // Swatch + gap + approximate 9pt glyph width + trailing pad.
    return 10 + 6 + (maxChars * 6.2).clamp(40.0, 96.0) + 6;
  }

  void _paintLegend(
    List<DisplayOp> ops,
    Rect box,
    List<(String, Color)> items, {
    bool vertical = false,
    bool alignEnd = false,
  }) {
    if (items.isEmpty) return;
    if (vertical) {
      // Stack swatch+label rows, vertically centered beside the plot.
      const rowH = 18.0;
      final blockH = items.length * rowH;
      var y = box.top + ((box.height - blockH) / 2).clamp(0.0, box.height);
      for (final (name, color) in items) {
        final swatch = Rect.fromLTWH(box.left, y + 4, 10, 10);
        ops.add(FillRectOp(swatch, color));
        ops.add(StrokePathOp(Path()..addRect(swatch), _axis, 0.6));
        ops.add(DrawTextRawOp(
          text: name,
          box: Rect.fromLTWH(box.left + 14, y + 1, box.width - 16, 14),
          fontSizePt: 9,
          color: _label,
        ));
        y += rowH;
      }
      return;
    }
    if (alignEnd) {
      var cursor = box.right;
      for (var i = items.length - 1; i >= 0; i--) {
        final (name, color) = items[i];
        final textW = (name.length * 5.2).clamp(28.0, 90.0);
        final entryW = 10 + 4 + textW;
        cursor -= entryW;
        final swatch = Rect.fromLTWH(cursor, box.top + 4, 10, 10);
        ops.add(FillRectOp(swatch, color));
        ops.add(StrokePathOp(Path()..addRect(swatch), _axis, 0.6));
        ops.add(DrawTextRawOp(
          text: name,
          box: Rect.fromLTWH(cursor + 14, box.top + 1, textW, 14),
          fontSizePt: 9,
          color: _label,
        ));
        cursor -= 12;
      }
      return;
    }
    final slot = box.width / items.length;
    for (var i = 0; i < items.length; i++) {
      final (name, color) = items[i];
      final x = box.left + i * slot + slot / 2 - 40;
      final swatch = Rect.fromLTWH(x, box.top + 5, 10, 10);
      ops.add(FillRectOp(swatch, color));
      ops.add(StrokePathOp(Path()..addRect(swatch), _axis, 0.6));
      ops.add(DrawTextRawOp(
        text: name,
        box: Rect.fromLTWH(x + 14, box.top + 2, slot - 20, 14),
        fontSizePt: 9,
        color: _label,
      ));
    }
  }

  void _paintLine(
    List<DisplayOp> ops,
    Rect plot,
    List<_ChartSeries> series,
  ) {
    final domain = _valueDomain(series);
    final axisMin = domain.min;
    final axisMax = domain.max;
    final span = axisMax - axisMin;
    for (var s = 0; s < series.length; s++) {
      final values = series[s].values;
      if (span <= 0 || values.length < 2) continue;
      final path = Path();
      var started = false;
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        if (v.isNaN) {
          started = false;
          continue;
        }
        final x = plot.left + (i / (values.length - 1)) * plot.width;
        final y = _yForValue(v, plot, axisMin, axisMax);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (started) {
        ops.add(
          StrokePathOp(path, _seriesColors[s % _seriesColors.length], 1.75),
        );
      }
    }
  }

  void _paintPie(List<DisplayOp> ops, Rect plot, List<double> values) {
    final finite = [
      for (final v in values)
        if (!v.isNaN && v > 0) v,
    ];
    final total = finite.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    values = finite;
    final cx = plot.center.dx;
    final cy = plot.center.dy;
    final r = math.min(plot.width, plot.height) / 2;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * math.pi * 2;
      final path = Path()
        ..moveTo(cx, cy)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          start,
          sweep,
          false,
        )
        ..close();
      ops.add(FillPathOp(path, _seriesColors[i % _seriesColors.length]));
      ops.add(StrokePathOp(path, _axis, 0.75));
      start += sweep;
    }
  }
}

class _ChartSeries {
  const _ChartSeries({
    required this.name,
    required this.categories,
    required this.values,
  });

  final String name;
  final List<String> categories;
  final List<double> values;
}

enum _ChartKind { bar, line, pie, unknown }

/// Resolves chart formula references (e.g. `'Data'!\$B\$2:\$B\$7`) to values.
abstract class ChartRangeResolver {
  List<String> strings(String formula);
  List<double> numbers(String formula);
}
