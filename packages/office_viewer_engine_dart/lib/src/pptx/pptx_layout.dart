import 'dart:ui';

import '../drawing/charts/chart_painter.dart';
import '../drawing/shapes.dart';
import '../fonts/font_registry.dart';
import '../model/display_list.dart';
import '../pptx/preset_geometry/presets.dart';
import '../theme/theme.dart';
import 'pptx_inheritance.dart';
import 'pptx_ir.dart';

/// Builds [DisplayList] commands from merged PPTX slide IR.
class PptxLayout {
  const PptxLayout();

  /// Optional [decodedImages] maps image part path → decoded [Image].
  DisplayList layout(
    PptxSlide slide,
    OfficeTheme theme, {
    Map<String, Image>? decodedImages,
    bool applyInheritance = true,
  }) {
    final merged = applyInheritance ? const PptxInheritance().merge(slide) : slide;
    final ops = <DisplayOp>[];
    final size = merged.size;

    final bg = merged.backgroundFill?.color ?? const Color(0xFFFFFFFF);
    ops.add(FillRectOp(Rect.fromLTWH(0, 0, size.width, size.height), bg));

    for (final node in merged.shapes) {
      _emitNode(ops, node, decodedImages, theme);
    }

    return DisplayList(ops: ops, size: size);
  }

  void _emitNode(
    List<DisplayOp> ops,
    PptxShapeNode node,
    Map<String, Image>? decodedImages,
    OfficeTheme theme,
  ) {
    if (node is PptxGroup) {
      ops.add(PushTransformOp(transformMatrixFor(node.transform)));
      for (final child in node.children) {
        _emitChildInGroup(ops, child, node.transform, decodedImages, theme);
      }
      ops.add(const PopTransformOp());
      return;
    }
    if (node is PptxShape) {
      if (node.hidden) return;
      _emitShape(ops, node, node.transform, decodedImages);
      return;
    }
    if (node is PptxPicture) {
      _emitPicture(ops, node, decodedImages);
      return;
    }
    if (node is PptxTable) {
      _emitTable(ops, node, theme);
      return;
    }
    if (node is PptxChart) {
      _emitChart(ops, node);
    }
  }

  void _emitChildInGroup(
    List<DisplayOp> ops,
    PptxShapeNode child,
    ShapeTransform groupXfrm,
    Map<String, Image>? decodedImages,
    OfficeTheme theme,
  ) {
    final childXfrm = _childTransformInGroup(child.transform, groupXfrm);
    if (child is PptxShape) {
      if (child.hidden) return;
      _emitShape(ops, child, childXfrm, decodedImages);
    } else if (child is PptxPicture) {
      _emitPicture(ops, child.copyTransform(childXfrm), decodedImages);
    } else if (child is PptxTable) {
      _emitTable(
        ops,
        PptxTable(
          transform: childXfrm,
          columnWidthsPt: child.columnWidthsPt,
          rows: child.rows,
          firstRow: child.firstRow,
          bandRow: child.bandRow,
          styleId: child.styleId,
        ),
        theme,
      );
    } else if (child is PptxChart) {
      _emitChart(
        ops,
        PptxChart(
          transform: childXfrm,
          chartXml: child.chartXml,
          titleFallback: child.titleFallback,
        ),
      );
    } else if (child is PptxGroup) {
      ops.add(PushTransformOp(transformMatrixFor(childXfrm)));
      for (final gc in child.children) {
        _emitChildInGroup(ops, gc, childXfrm, decodedImages, theme);
      }
      ops.add(const PopTransformOp());
    }
  }

  ShapeTransform _childTransformInGroup(
    ShapeTransform child,
    ShapeTransform group,
  ) {
    final gw = group.childExtentW > 0 ? group.childExtentW : group.width;
    final gh = group.childExtentH > 0 ? group.childExtentH : group.height;
    if (gw <= 0 || gh <= 0) {
      return child.copyWith(
        x: group.x + child.x,
        y: group.y + child.y,
      );
    }
    final sx = group.width / gw;
    final sy = group.height / gh;
    return child.copyWith(
      x: group.x + (child.x - group.childOffsetX) * sx,
      y: group.y + (child.y - group.childOffsetY) * sy,
      width: child.width * sx,
      height: child.height * sy,
    );
  }

  void _emitShape(
    List<DisplayOp> ops,
    PptxShape shape,
    ShapeTransform xfrm,
    Map<String, Image>? decodedImages,
  ) {
    final rect = Rect.fromLTWH(0, 0, xfrm.width, xfrm.height);
    final path = presetPath(
      shape.presetGeometry,
      rect,
      adjust: shape.adjustValues,
    );

    ops.add(PushTransformOp(transformMatrixFor(xfrm)));

    switch (shape.fill) {
      case SolidShapeFill(:final color):
        ops.add(FillPathOp(path, color));
      case GradientShapeFill(:final stops, angleDeg: _):
        if (stops.isNotEmpty) {
          ops.add(FillPathOp(path, _averageGradientColor(stops)));
        }
      case null:
        break;
    }

    final outline = shape.outline;
    if (outline != null && outline.fill != null && outline.widthPt > 0) {
      ops.add(StrokePathOp(
        path,
        outline.fill!.color,
        outline.widthPt,
      ));
    }

    final body = shape.textBody;
    if (body != null && xfrm.width > 0 && xfrm.height > 0) {
      final contentParas = body.paragraphs
          .where((p) => p.runs.map((r) => r.text).join().trim().isNotEmpty)
          .toList();
      final lineHeights = contentParas
          .map((p) => (p.runs.isNotEmpty ? p.runs.first.style.fontSizePt : 18) *
              1.3)
          .toList();
      final totalH = lineHeights.fold<double>(0, (a, b) => a + b);
      final centerVertically = _isTitleLike(shape.placeholderType);
      final topPad = centerVertically ? ((xfrm.height - totalH) / 2) : 8.0;
      var y = topPad.isFinite && topPad > 4 ? topPad : 4.0;
      if (y > xfrm.height) y = 4.0;
      final textWidth =
          xfrm.width > 8 ? xfrm.width - 8 : xfrm.width.clamp(1.0, xfrm.width);
      for (var i = 0; i < contentParas.length; i++) {
        final para = contentParas[i];
        final raw = para.runs.map((r) => r.text).join();
        final bullet = para.bullet;
        final text = (bullet != null && bullet.isNotEmpty)
            ? '$bullet  $raw'
            : raw;
        final runStyle = para.runs.first.style;
        final lineH = lineHeights[i];
        final indent = para.style.indentLeftPt > 0
            ? para.style.indentLeftPt
            : (bullet != null ? 12.0 : 4.0);
        final box = Rect.fromLTWH(
          indent,
          y,
          (textWidth - indent).clamp(1.0, textWidth),
          lineH,
        );
        ops.add(DrawTextRawOp(
          text: text,
          box: box,
          fontFamily: FontRegistry.instance.familyFor(runStyle.fontFamily),
          fontSizePt: runStyle.fontSizePt,
          bold: runStyle.bold,
          italic: runStyle.italic,
          color: runStyle.color,
          align: para.style.alignment,
        ));
        y += lineH;
      }
    }

    ops.add(const PopTransformOp());
  }

  bool _isTitleLike(String? type) =>
      type == 'title' || type == 'ctrTitle' || type == 'subTitle';

  void _emitTable(List<DisplayOp> ops, PptxTable table, OfficeTheme theme) {
    final xfrm = table.transform;
    if (xfrm.width <= 0 || xfrm.height <= 0) return;

    final accent = theme.colorScheme.accent1;
    final headerFill = accent;
    // Medium Style 2 – Accent 1 band: ~20% tint of accent1 toward white.
    final bandFill = _tint(accent, 0.80);
    const plainFill = Color(0xFFFFFFFF);
    final grid = table.bandRow || table.firstRow
        ? const Color(0xFFFFFFFF)
        : const Color(0xFFB0B0B0);

    ops.add(PushTransformOp(transformMatrixFor(xfrm)));

    var y = 0.0;
    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      final rowH = row.heightPt > 0 ? row.heightPt : 24.0;
      final isHeader = table.firstRow && r == 0;
      final bodyIndex = table.firstRow ? r - 1 : r;
      final isBand = table.bandRow &&
          !isHeader &&
          bodyIndex >= 0 &&
          bodyIndex.isEven;
      var x = 0.0;
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        final colW = c < table.columnWidthsPt.length
            ? table.columnWidthsPt[c]
            : (xfrm.width / row.cells.length);
        final cellRect = Rect.fromLTWH(x, y, colW, rowH);
        final fill = cell.fill ??
            (isHeader
                ? headerFill
                : isBand
                    ? bandFill
                    : plainFill);
        ops.add(FillRectOp(cellRect, fill));
        ops.add(StrokePathOp(Path()..addRect(cellRect), grid, 0.75));
        if (cell.text.trim().isNotEmpty) {
          final style = cell.style;
          final textColor = isHeader
              ? const Color(0xFFFFFFFF)
              : style.color;
          ops.add(DrawTextRawOp(
            text: cell.text,
            box: Rect.fromLTWH(x + 4, y + 4, colW - 8, rowH - 6),
            fontFamily: FontRegistry.instance.familyFor(style.fontFamily),
            fontSizePt: style.fontSizePt > 0 ? style.fontSizePt : 12,
            bold: isHeader || style.bold,
            italic: style.italic,
            color: textColor,
            align: TextAlign.left,
          ));
        }
        x += colW;
      }
      y += rowH;
    }

    ops.add(const PopTransformOp());
  }

  /// Mix [color] toward white by [amount] (0 = unchanged, 1 = white).
  Color _tint(Color color, double amount) {
    final a = amount.clamp(0.0, 1.0);
    return Color.fromARGB(
      255,
      (color.r * 255 * (1 - a) + 255 * a).round().clamp(0, 255),
      (color.g * 255 * (1 - a) + 255 * a).round().clamp(0, 255),
      (color.b * 255 * (1 - a) + 255 * a).round().clamp(0, 255),
    );
  }

  void _emitChart(List<DisplayOp> ops, PptxChart chart) {
    final xfrm = chart.transform;
    if (xfrm.width <= 0 || xfrm.height <= 0) return;

    final painted = const ChartPainter().paintCachedChart(
      chart.chartXml,
      size: Size(xfrm.width, xfrm.height),
      titleFallback: chart.titleFallback ?? 'Chart',
    );

    ops.add(PushTransformOp(transformMatrixFor(xfrm)));
    ops.addAll(painted.ops);
    ops.add(const PopTransformOp());
  }

  void _emitPicture(
    List<DisplayOp> ops,
    PptxPicture pic,
    Map<String, Image>? decodedImages,
  ) {
    final image = decodedImages?[pic.imagePartPath];
    if (image == null) return;
    final rect = pic.transform.boundsRect;
    ops.add(DrawImageOp(rect, image));
  }

  Color _averageGradientColor(List<GradientStop> stops) {
    if (stops.length == 1) return stops.first.color;
    var r = 0.0, g = 0.0, b = 0.0;
    for (final s in stops) {
      r += s.color.r;
      g += s.color.g;
      b += s.color.b;
    }
    final n = stops.length;
    return Color.fromARGB(
      255,
      (r / n * 255).round().clamp(0, 255),
      (g / n * 255).round().clamp(0, 255),
      (b / n * 255).round().clamp(0, 255),
    );
  }
}

extension on PptxPicture {
  PptxPicture copyTransform(ShapeTransform t) => PptxPicture(
        transform: t,
        imagePartPath: imagePartPath,
        imageBytes: imageBytes,
        placeholderType: placeholderType,
        placeholderIdx: placeholderIdx,
      );
}
