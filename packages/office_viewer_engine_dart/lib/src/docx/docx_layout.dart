import 'dart:typed_data';
import 'dart:ui' as ui;

import '../drawing/charts/chart_painter.dart';
import '../model/display_list.dart';
import '../model/style.dart';
import 'docx_model.dart';
import 'docx_table_layout.dart';

/// Paginates a [DocxDocument] into per-page display lists (points).
class DocxLayout {
  const DocxLayout();

  List<DisplayList> layout(DocxDocument doc) {
    if (doc.body.isEmpty) {
      final section = doc.sections.isNotEmpty
          ? doc.sections.first
          : const DocSection.withMargins(
              pageWidthPt: 612,
              pageHeightPt: 792,
              contentLeftPt: 72,
              contentTopPt: 72,
              contentRightPt: 72,
              contentBottomPt: 72,
            );
      return [
        DisplayList.blankWhite(
          ui.Size(section.pageWidthPt, section.pageHeightPt),
        ),
      ];
    }

    final section =
        doc.sections.isNotEmpty ? doc.sections.first : _defaultSection();
    final pages = <_PageBuilder>[];
    pages.add(_PageBuilder(section, pageNumber: 1));

    var y = section.contentTopPt;
    final contentBottom = section.pageHeightPt - section.contentBottomPt;
    final contentWidth = section.contentWidthPt;
    final contentLeft = section.contentLeftPt;
    const tableLayout = DocxTableLayout();
    DocParagraph? prevParagraph;

    void newPage() {
      final n = pages.length + 1;
      pages.add(_PageBuilder(section, pageNumber: n));
      y = section.contentTopPt;
      prevParagraph = null;
    }

    void ensureSpace(double need) {
      if (y + need > contentBottom) newPage();
    }

    for (final block in doc.body) {
      if (block is DocSectionBreak) {
        newPage();
        continue;
      }
      if (block is DocParagraph) {
        if (block.pageBreakBefore) {
          _breakPageIfNeeded(
            pages: pages,
            y: y,
            contentTop: section.contentTopPt,
            newPage: newPage,
            setY: (v) => y = v,
          );
        }

        final suppressSpacing = _contextualSuppress(prevParagraph, block);
        if (!suppressSpacing) {
          y += block.paraStyle.spaceBeforePt;
        }

        final isList = block.isList && block.listLabel != null;
        final indentLeft = block.paraStyle.indentLeftPt;
        final indentFirst = block.paraStyle.indentFirstPt;
        // List markers sit in the hanging-indent gutter; body text at indentLeft.
        final textX = contentLeft + (isList ? indentLeft : indentLeft + indentFirst);
        final markerX = contentLeft + (indentLeft + indentFirst).clamp(0.0, indentLeft);
        final boxW = (contentWidth -
                (isList ? indentLeft : indentLeft) -
                block.paraStyle.indentRightPt)
            .clamp(1.0, contentWidth);

        // Collect text; images / breaks handled inline.
        final buf = StringBuffer();
        var style = block.runs.isNotEmpty
            ? block.runs.first.style
            : const ComputedRunStyle();
        var sawPageBreak = false;
        var hadVisibleContent = false;

        for (final run in block.runs) {
          if (run.field != null &&
              run.field!.instruction.toUpperCase().contains('PAGE')) {
            buf.write('${pages.last.pageNumber}');
            style = run.style;
            hadVisibleContent = true;
            continue;
          }
          if (run.brKind == DocBreakKind.page) {
            if (buf.isNotEmpty) {
              _emitWrappedParagraph(
                pages: pages,
                text: buf.toString(),
                style: style,
                align: block.paraStyle.alignment,
                x: textX,
                yRef: () => y,
                setY: (v) => y = v,
                boxW: boxW,
                contentBottom: contentBottom,
                newPage: newPage,
                ensureSpace: ensureSpace,
                lineH: _lineHeight(block),
              );
              buf.clear();
              hadVisibleContent = true;
            }
            _breakPageIfNeeded(
              pages: pages,
              y: y,
              contentTop: section.contentTopPt,
              newPage: newPage,
              setY: (v) => y = v,
            );
            sawPageBreak = true;
            continue;
          }
          if (run.brKind == DocBreakKind.line) {
            buf.write('\n');
            continue;
          }
          if (run.image != null || run.chart != null) {
            _emitWrappedParagraph(
              pages: pages,
              text: buf.toString(),
              style: style,
              align: block.paraStyle.alignment,
              x: textX,
              yRef: () => y,
              setY: (v) => y = v,
              boxW: boxW,
              contentBottom: contentBottom,
              newPage: newPage,
              ensureSpace: ensureSpace,
              lineH: _lineHeight(block),
            );
            buf.clear();
            if (run.chart != null) {
              final chart = run.chart!;
              ensureSpace(chart.heightPt);
              final left = textX + chart.offsetLeftPt;
              final top = y + chart.offsetTopPt;
              final painted = const ChartPainter().paintCachedChart(
                chart.chartXml,
                size: ui.Size(chart.widthPt, chart.heightPt),
                titleFallback: 'Chart',
              );
              pages.last.ops.add(
                PushTransformOp(
                  Float64List.fromList([
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    left, top, 0, 1,
                  ]),
                ),
              );
              pages.last.ops.addAll(painted.ops);
              pages.last.ops.add(const PopTransformOp());
              if (chart.placement == DocImagePlacement.inline ||
                  chart.wrap == DocWrapType.topBottom) {
                y += chart.heightPt;
              }
            } else {
              final img = run.image!;
              ensureSpace(img.heightPt);
              final left = textX + img.offsetLeftPt;
              final rect = ui.Rect.fromLTWH(left, y, img.widthPt, img.heightPt);
              if (img.bytes != null && img.bytes!.isNotEmpty) {
                pages.last.ops.add(DrawImageBytesOp(rect, img.bytes!));
              } else {
                pages.last.ops.add(FillRectOp(rect, const ui.Color(0xFFE0E0E0)));
              }
              if (img.placement == DocImagePlacement.inline ||
                  img.wrap == DocWrapType.topBottom) {
                y += img.heightPt;
              }
            }
            hadVisibleContent = true;
            continue;
          }
          if (run.tab) {
            buf.write('\t');
            style = run.style;
            hadVisibleContent = true;
            continue;
          }
          if (run.text.isNotEmpty) {
            style = run.style;
            buf.write(run.text);
            hadVisibleContent = true;
          }
        }

        final pageBreakOnly = sawPageBreak && !hadVisibleContent && !isList;
        // Page-break-only paragraphs must not emit an empty line on the new page
        // (that produced a blank sheet before the next heading).
        if (!pageBreakOnly || buf.isNotEmpty || isList) {
          if (isList) {
            final label = block.listLabel!;
            ensureSpace(_lineHeight(block));
            final gutter = (textX - markerX).clamp(10.0, 48.0);
            pages.last.ops.add(
              DrawTextRawOp(
                text: label,
                box: ui.Rect.fromLTWH(
                  textX - gutter,
                  y,
                  gutter - 3,
                  _lineHeight(block),
                ),
                fontFamily: style.fontFamily,
                fontSizePt: style.fontSizePt,
                bold: style.bold,
                italic: style.italic,
                color: style.color,
                // Right-align so the marker sits just left of the text.
                align: ui.TextAlign.right,
              ),
            );
          }

          _emitWrappedParagraph(
            pages: pages,
            text: buf.toString(),
            style: style,
            align: block.paraStyle.alignment,
            x: textX,
            yRef: () => y,
            setY: (v) => y = v,
            boxW: boxW,
            contentBottom: contentBottom,
            newPage: newPage,
            ensureSpace: ensureSpace,
            lineH: _lineHeight(block),
          );

          final borderW = block.paraStyle.borderBottomWidthPt;
          final borderColor = block.paraStyle.borderBottomColor;
          if (borderW > 0 && borderColor != null) {
            y += block.paraStyle.borderBottomSpacePt;
            pages.last.ops.add(
              FillRectOp(
                ui.Rect.fromLTWH(contentLeft, y, contentWidth, borderW),
                borderColor,
              ),
            );
            y += borderW + 2;
          }

          // Peek: suppress spaceAfter when next para shares contextual list style.
          final next = _nextParagraph(doc.body, block);
          final suppressAfter =
              suppressSpacing || _contextualSuppress(block, next);
          if (!suppressAfter && !pageBreakOnly) {
            y += block.paraStyle.spaceAfterPt;
          }
        }
        prevParagraph = block;
        // Do not eagerly start a new page when y overflows — the next block's
        // ensureSpace (or an explicit page break) handles that. Eager breaks
        // before <w:br type="page"/> created blank pages.
      } else if (block is DocTable) {
        prevParagraph = null;
        final cells = tableLayout.layout(block, contentWidth);
        var tableHeight = 0.0;
        var maxCol = 0;
        for (final c in cells) {
          final b = c.rect.bottom;
          if (b > tableHeight) tableHeight = b;
          final end = c.col + c.colSpan;
          if (end > maxCol) maxCol = end;
        }
        ensureSpace(tableHeight + 8);
        final tableTop = y;
        final rowCount = block.rows.length;
        for (final placement in cells) {
          final r = placement.rect;
          final cell = placement.cell;
          final abs = ui.Rect.fromLTWH(
            contentLeft + r.left,
            tableTop + r.top,
            r.width,
            r.height,
          );
          if (cell.shading != null) {
            pages.last.ops.add(FillRectOp(abs, cell.shading!));
          }
          paintTableBorders(
            pages.last.borderOps,
            placement,
            tableBorders: block.borders,
            rowCount: rowCount,
            colCount: maxCol,
          );
          var cy = abs.top + 4;
          final cellW = abs.width <= 8
              ? abs.width.clamp(1.0, double.infinity)
              : (abs.width - 8).clamp(1.0, abs.width);
          for (final inner in cell.blocks) {
            if (inner is DocParagraph) {
              final text = inner.runs.map((e) => e.text).join();
              if (text.isEmpty) {
                cy += _lineHeight(inner);
                continue;
              }
              final st = inner.runs.isNotEmpty
                  ? inner.runs.first.style
                  : const ComputedRunStyle();
              final measured = _measureParagraph(
                text: text,
                style: st,
                align: inner.paraStyle.alignment,
                maxWidth: cellW,
              );
              final maxH = (abs.bottom - cy).clamp(0.0, double.infinity);
              final minH = _lineHeight(inner);
              final h = maxH <= 0
                  ? 0.0
                  : measured.height.clamp(
                      minH > maxH ? maxH : minH,
                      maxH,
                    );
              pages.last.ops.add(PushClipOp(abs));
              pages.last.ops.add(
                DrawTextRawOp(
                  text: text,
                  box: ui.Rect.fromLTWH(abs.left + 4, cy, cellW, h),
                  fontFamily: st.fontFamily,
                  fontSizePt: st.fontSizePt,
                  bold: st.bold,
                  italic: st.italic,
                  color: st.color,
                  align: inner.paraStyle.alignment,
                ),
              );
              pages.last.ops.add(const PopClipOp());
              cy += h;
            }
          }
        }
        for (final b in pages.last.borderOps) {
          final rect = b.rect.toRect().shift(ui.Offset(contentLeft, tableTop));
          pages.last.ops.add(
            StrokePathOp(
              _rectPath(rect),
              b.border.color,
              b.border.widthPt,
            ),
          );
        }
        pages.last.borderOps.clear();
        y = tableTop + tableHeight + 8;
      }
    }

    _paintHeadersFooters(doc, pages);
    _appendFootnotes(doc, pages, section);

    return pages
        .map(
          (p) => DisplayList(
            size: ui.Size(section.pageWidthPt, section.pageHeightPt),
            ops: [
              FillRectOp(
                ui.Rect.fromLTWH(
                  0,
                  0,
                  section.pageWidthPt,
                  section.pageHeightPt,
                ),
                const ui.Color(0xFFFFFFFF),
              ),
              ...p.ops,
            ],
          ),
        )
        .toList();
  }

  DocSection _defaultSection() => const DocSection.withMargins(
        pageWidthPt: 612,
        pageHeightPt: 792,
        contentLeftPt: 72,
        contentTopPt: 72,
        contentRightPt: 72,
        contentBottomPt: 72,
      );

  double _lineHeight(DocParagraph p) {
    final size = p.runs.isNotEmpty
        ? p.runs.first.style.fontSizePt
        : 11.0;
    final exact = p.paraStyle.lineSpacingExactPt;
    if (exact != null && exact > 0) return exact;
    return size * p.paraStyle.lineSpacingMultiple;
  }

  bool _contextualSuppress(DocParagraph? a, DocParagraph? b) {
    if (a == null || b == null) return false;
    if (!a.paraStyle.contextualSpacing && !b.paraStyle.contextualSpacing) {
      return false;
    }
    if (a.isList && b.isList && a.numId != null && a.numId == b.numId) {
      return true;
    }
    if (a.pStyleId != null && a.pStyleId == b.pStyleId) return true;
    return false;
  }

  DocParagraph? _nextParagraph(List<DocBodyBlock> body, DocParagraph current) {
    final idx = body.indexOf(current);
    if (idx < 0) return null;
    for (var i = idx + 1; i < body.length; i++) {
      final b = body[i];
      if (b is DocParagraph) return b;
      if (b is DocTable || b is DocSectionBreak) return null;
    }
    return null;
  }

  /// Starts a new page only when the current one already has content. Avoids
  /// stacking blank pages when layout overflow already advanced the page.
  void _breakPageIfNeeded({
    required List<_PageBuilder> pages,
    required double y,
    required double contentTop,
    required void Function() newPage,
    required void Function(double) setY,
  }) {
    final page = pages.last;
    final hasDrawnContent = page.ops.isNotEmpty || page.borderOps.isNotEmpty;
    final pastTop = y > contentTop + 0.5;
    if (hasDrawnContent || pastTop) {
      newPage();
    } else {
      setY(contentTop);
    }
  }

  /// Lay out [text] with real wrap height so paint-time wrapping does not
  /// overprint the next paragraph.
  void _emitWrappedParagraph({
    required List<_PageBuilder> pages,
    required String text,
    required ComputedRunStyle style,
    required ui.TextAlign align,
    required double x,
    required double Function() yRef,
    required void Function(double) setY,
    required double boxW,
    required double contentBottom,
    required void Function() newPage,
    required void Function(double) ensureSpace,
    required double lineH,
  }) {
    final trimmed = text;
    if (trimmed.isEmpty) {
      // Empty para still consumes a line (Word-like).
      ensureSpace(lineH);
      setY(yRef() + lineH);
      return;
    }

    final measured = _measureParagraph(
      text: trimmed,
      style: style,
      align: align,
      maxWidth: boxW,
      heightMultiple: lineH / (style.fontSizePt <= 0 ? 11 : style.fontSizePt),
    );
    final height = measured.height < lineH ? lineH : measured.height;
    ensureSpace(height);
    // If ensureSpace started a new page, y was reset — re-check.
    if (yRef() + height > contentBottom) {
      newPage();
    }
    final y = yRef();
    pages.last.ops.add(
      DrawTextRawOp(
        text: trimmed,
        box: ui.Rect.fromLTWH(x, y, boxW, height),
        fontFamily: style.fontFamily,
        fontSizePt: style.fontSizePt,
        bold: style.bold,
        italic: style.italic,
        underline: style.underline,
        color: style.color,
        align: align,
      ),
    );
    setY(y + height);
  }

  ui.Paragraph _measureParagraph({
    required String text,
    required ComputedRunStyle style,
    required ui.TextAlign align,
    required double maxWidth,
    double heightMultiple = 1.15,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        fontFamily: style.fontFamily,
        fontSize: style.fontSizePt,
        fontWeight: style.bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        fontStyle: style.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
        height: heightMultiple,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: style.color,
          fontFamily: style.fontFamily,
          fontSize: style.fontSizePt,
          fontWeight: style.bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
          fontStyle: style.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
          decoration: style.underline
              ? ui.TextDecoration.underline
              : ui.TextDecoration.none,
        ),
      )
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    return paragraph;
  }

  void _paintHeadersFooters(DocxDocument doc, List<_PageBuilder> pages) {
    final section = pages.first.section;
    final hdr = section.headerRelId != null
        ? doc.headers[section.headerRelId!]
        : null;
    final ftr = section.footerRelId != null
        ? doc.footers[section.footerRelId!]
        : null;

    for (final page in pages) {
      if (hdr != null) {
        final text = _blocksPlainText(hdr.blocks);
        if (text.isNotEmpty) {
          page.ops.insert(
            0,
            DrawTextRawOp(
              text: text,
              box: ui.Rect.fromLTWH(
                section.contentLeftPt,
                section.headerDistancePt,
                section.contentWidthPt,
                24,
              ),
              fontSizePt: 10,
            ),
          );
        }
      }
      if (ftr != null) {
        final text = _blocksPlainText(ftr.blocks);
        if (text.isNotEmpty) {
          page.ops.add(
            DrawTextRawOp(
              text: text,
              box: ui.Rect.fromLTWH(
                section.contentLeftPt,
                section.pageHeightPt - section.footerDistancePt - 24,
                section.contentWidthPt,
                24,
              ),
              fontSizePt: 10,
            ),
          );
        }
      }
    }
  }

  void _appendFootnotes(
    DocxDocument doc,
    List<_PageBuilder> pages,
    DocSection section,
  ) {
    if (doc.footnotes.isEmpty || pages.isEmpty) return;
    final last = pages.last;
    var y = section.pageHeightPt - section.contentBottomPt - 40;
    for (final fn in doc.footnotes) {
      final text = _blocksPlainText(fn.blocks);
      if (text.isEmpty) continue;
      last.ops.add(
        DrawTextRawOp(
          text: '${fn.id}. $text',
          box: ui.Rect.fromLTWH(section.contentLeftPt, y, section.contentWidthPt, 14),
          fontSizePt: 9,
        ),
      );
      y += 14;
    }
  }

  String _blocksPlainText(List<DocBodyBlock> blocks) {
    final buf = StringBuffer();
    for (final b in blocks) {
      if (b is DocParagraph) {
        for (final r in b.runs) {
          buf.write(r.text);
        }
        buf.write(' ');
      }
    }
    return buf.toString().trim();
  }

  ui.Path _rectPath(ui.Rect r) {
    return ui.Path()..addRect(r);
  }
}

class _PageBuilder {
  _PageBuilder(this.section, {required this.pageNumber});

  final DocSection section;
  final int pageNumber;
  final List<DisplayOp> ops = [];
  final List<DisplayBorderOp> borderOps = [];
  final List<_ImagePlaceholder> imagePlaceholders = [];
}

class _ImagePlaceholder {
  const _ImagePlaceholder({required this.rect, required this.bytes});

  final ui.Rect rect;
  final Uint8List bytes;
}
