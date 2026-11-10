import 'dart:ui';

import '../drawing/shapes.dart';
import '../model/style.dart';
import 'pptx_ir.dart';
import 'pptx_master_styles.dart';

/// Merges placeholder styling from layout / slide master when slide shapes lack geometry.
class PptxInheritance {
  const PptxInheritance();

  PptxSlide merge(PptxSlide slide) {
    final mergedShapes = slide.shapes
        .map(
          (n) => _mergeNode(
            n,
            slide.layoutShapes,
            slide.masterShapes,
            slide.masterStyles,
          ),
        )
        .toList();

    SolidShapeFill? bg = slide.backgroundFill;
    bg ??= _backgroundFromShapes(slide.layoutShapes);
    bg ??= _backgroundFromShapes(slide.masterShapes);

    return PptxSlide(
      index: slide.index,
      partPath: slide.partPath,
      size: slide.size,
      shapes: mergedShapes,
      backgroundFill: bg,
      layoutPartPath: slide.layoutPartPath,
      masterPartPath: slide.masterPartPath,
      layoutShapes: slide.layoutShapes,
      masterShapes: slide.masterShapes,
      masterStyles: slide.masterStyles,
      name: slide.name,
    );
  }

  PptxShapeNode _mergeNode(
    PptxShapeNode node,
    List<PptxShapeNode> layout,
    List<PptxShapeNode> master,
    PptxMasterStyles masterStyles,
  ) {
    if (node is PptxGroup) {
      return PptxGroup(
        transform: node.transform,
        placeholderType: node.placeholderType,
        placeholderIdx: node.placeholderIdx,
        children: node.children
            .map((c) => _mergeNode(c, layout, master, masterStyles))
            .toList(),
      );
    }
    if (node is! PptxShape) return node;

    // Body placeholders are often `ph idx="1"` with no type attribute.
    final isPlaceholder =
        node.placeholderType != null || node.placeholderIdx != null;
    if (!isPlaceholder) return node;

    final layoutShape =
        _findPlaceholder(layout, node.placeholderType, node.placeholderIdx);
    final masterShape =
        _findPlaceholder(master, node.placeholderType, node.placeholderIdx);
    final effectiveType = _effectivePlaceholderType(
      node.placeholderType,
      layoutShape,
      masterShape,
    );
    final inheritFrom = _pickInheritSource(node, layoutShape, masterShape);

    final transform = inheritFrom != null
        ? _mergeTransform(node.transform, inheritFrom.transform)
        : node.transform;

    final textBody = _mergeTextBody(
      slide: node.textBody,
      layout: layoutShape?.textBody,
      placeholderType: effectiveType,
      masterStyles: masterStyles,
    );

    if (inheritFrom == null) {
      return PptxShape(
        transform: transform,
        placeholderType: effectiveType ?? node.placeholderType,
        placeholderIdx: node.placeholderIdx,
        presetGeometry: node.presetGeometry,
        adjustValues: node.adjustValues,
        fill: node.fill,
        outline: node.outline,
        textBody: textBody,
        hidden: node.hidden,
      );
    }

    return PptxShape(
      transform: transform,
      placeholderType: effectiveType ?? node.placeholderType,
      placeholderIdx: node.placeholderIdx,
      presetGeometry: node.presetGeometry ?? inheritFrom.presetGeometry,
      adjustValues: node.adjustValues.isNotEmpty
          ? node.adjustValues
          : inheritFrom.adjustValues,
      fill: node.fill ?? inheritFrom.fill,
      outline: node.outline ?? inheritFrom.outline,
      textBody: textBody,
      hidden: node.hidden,
    );
  }

  String? _effectivePlaceholderType(
    String? slideType,
    PptxShape? layoutShape,
    PptxShape? masterShape,
  ) {
    if (slideType != null) return slideType;
    return layoutShape?.placeholderType ??
        masterShape?.placeholderType ??
        'body';
  }

  PptxTextBody? _mergeTextBody({
    required PptxTextBody? slide,
    required PptxTextBody? layout,
    required String? placeholderType,
    required PptxMasterStyles masterStyles,
  }) {
    if (slide == null) return layout;
    final (masterRun, masterAlign) = masterStyles.defaultsFor(placeholderType);
    final listRun = layout?.listStyleRun;
    final listAlign = layout?.listStyleAlign;
    final isBody = placeholderType == 'body' || placeholderType == 'obj';

    final paragraphs = <PptxParagraph>[];
    for (final para in slide.paragraphs) {
      final level = para.level < 0 ? 0 : para.level;
      final levelStyle = isBody ? masterStyles.levelForBody(level) : null;
      final levelRun = levelStyle?.run ?? masterRun;
      final levelAlign = levelStyle?.align ?? masterAlign;
      final bullet = isBody ? (levelStyle?.bullet ?? masterStyles.bodyBullet) : null;
      final indentLeft = isBody && para.style.indentLeftPt == 0
          ? (levelStyle?.marginLeftPt ?? 0)
          : para.style.indentLeftPt;

      var align = para.style.alignment;
      final hadExplicitAlign = _paraHasNonDefaultAlign(para);
      if (!hadExplicitAlign) {
        align = listAlign ?? levelAlign;
      }

      final runs = <PptxTextRun>[];
      for (final run in para.runs) {
        runs.add(
          PptxTextRun(
            text: run.text,
            style: _mergeRunStyle(
              run.style,
              listRun: listRun,
              masterRun: levelRun,
              placeholderType: placeholderType,
            ),
          ),
        );
      }
      paragraphs.add(
        PptxParagraph(
          runs: runs,
          style: ComputedParaStyle(
            alignment: align,
            lineSpacingMultiple: para.style.lineSpacingMultiple,
            lineSpacingExactPt: para.style.lineSpacingExactPt,
            spaceBeforePt: para.style.spaceBeforePt,
            spaceAfterPt: para.style.spaceAfterPt,
            indentLeftPt: indentLeft,
            indentRightPt: para.style.indentRightPt,
            indentFirstPt: para.style.indentFirstPt,
            contextualSpacing: para.style.contextualSpacing,
          ),
          bullet: bullet,
          level: level,
        ),
      );
    }
    return PptxTextBody(
      paragraphs: paragraphs,
      listStyleRun: listRun ?? slide.listStyleRun,
      listStyleAlign: listAlign ?? slide.listStyleAlign,
    );
  }

  bool _paraHasNonDefaultAlign(PptxParagraph para) {
    // Parser defaults to left when algn is absent; treat left as inheritable.
    return para.style.alignment != TextAlign.left;
  }

  ComputedRunStyle _mergeRunStyle(
    ComputedRunStyle slide, {
    required ComputedRunStyle? listRun,
    required ComputedRunStyle masterRun,
    required String? placeholderType,
  }) {
    final isTitle = placeholderType == 'title' || placeholderType == 'ctrTitle';
    // Slide runs without explicit rPr land on the parser default (18pt / black).
    final usesDefaultSize = (slide.fontSizePt - 18).abs() < 0.01;
    final usesDefaultColor = (slide.color.a * 255).round() == 255 &&
        (slide.color.r * 255).round() == 0 &&
        (slide.color.g * 255).round() == 0 &&
        (slide.color.b * 255).round() == 0;

    final size = usesDefaultSize
        ? (listRun != null && (listRun.fontSizePt - 18).abs() > 0.01
            ? listRun.fontSizePt
            : masterRun.fontSizePt)
        : slide.fontSizePt;

    final color = usesDefaultColor
        ? (listRun?.color ?? masterRun.color)
        : slide.color;

    final family = usesDefaultSize
        ? (listRun?.fontFamily ?? masterRun.fontFamily)
        : slide.fontFamily;

    final bold = slide.bold ||
        (usesDefaultSize && (listRun?.bold == true || (isTitle && masterRun.bold)));

    return ComputedRunStyle(
      fontFamily: family,
      fontSizePt: size,
      bold: bold || (isTitle && usesDefaultSize),
      italic: slide.italic || (listRun?.italic ?? false),
      underline: slide.underline,
      strike: slide.strike,
      color: color,
    );
  }

  PptxShape? _pickInheritSource(
    PptxShape slideShape,
    PptxShape? layoutShape,
    PptxShape? masterShape,
  ) {
    // Layout placeholders often omit xfrm (`<p:spPr/>`); skip zero-size sources.
    bool usable(PptxShape? s) =>
        s != null && s.transform.width > 0 && s.transform.height > 0;

    if (_needsInherit(slideShape)) {
      if (usable(layoutShape)) return layoutShape;
      if (usable(masterShape)) return masterShape;
    }
    if (usable(layoutShape)) return layoutShape;
    if (usable(masterShape)) return masterShape;
    return layoutShape ?? masterShape;
  }

  bool _needsInherit(PptxShape s) =>
      s.fill == null ||
      s.transform.width <= 0 ||
      s.transform.height <= 0 ||
      s.presetGeometry == null;

  ShapeTransform _mergeTransform(ShapeTransform slide, ShapeTransform inherit) {
    var t = slide;
    if (t.width <= 0 || t.height <= 0) {
      t = t.copyWith(width: inherit.width, height: inherit.height);
    }
    if (t.x == 0 && t.y == 0 && (inherit.x != 0 || inherit.y != 0)) {
      t = t.copyWith(x: inherit.x, y: inherit.y);
    }
    return t;
  }

  PptxShape? _findPlaceholder(
    List<PptxShapeNode> nodes,
    String? type,
    int? idx,
  ) {
    for (final n in nodes) {
      final found = _findPlaceholderInTree(n, type, idx);
      if (found != null) return found;
    }
    if (type != null) {
      final alt = _altPlaceholderType(type);
      if (alt != null) {
        for (final n in nodes) {
          final found = _findPlaceholderInTree(n, alt, idx);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  String? _altPlaceholderType(String type) {
    switch (type) {
      case 'title':
        return 'ctrTitle';
      case 'ctrTitle':
        return 'title';
      default:
        return null;
    }
  }

  PptxShape? _findPlaceholderInTree(
    PptxShapeNode node,
    String? type,
    int? idx,
  ) {
    if (node is PptxGroup) {
      for (final c in node.children) {
        final found = _findPlaceholderInTree(c, type, idx);
        if (found != null) return found;
      }
      return null;
    }
    if (node is! PptxShape) return null;
    if (node.placeholderType == null && node.placeholderIdx == null) {
      return null;
    }

    if (idx != null && node.placeholderIdx != null) {
      if (node.placeholderIdx == idx) {
        if (type == null ||
            node.placeholderType == null ||
            node.placeholderType == type) {
          return node;
        }
      }
      // Idx present on both but mismatched → not a match.
      if (node.placeholderIdx != idx) return null;
    }

    if (type != null) {
      if (node.placeholderType == type) return node;
      return null;
    }

    // Type omitted on slide (common for body): prefer idx match already handled.
    return null;
  }

  SolidShapeFill? _backgroundFromShapes(List<PptxShapeNode> nodes) {
    for (final n in nodes) {
      if (n is PptxShape && n.fill is SolidShapeFill) {
        return n.fill! as SolidShapeFill;
      }
    }
    return null;
  }
}
