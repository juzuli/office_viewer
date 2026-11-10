import 'dart:typed_data';
import 'dart:ui';

import 'package:xml/xml.dart';

import '../model/style.dart';
import '../opc/package_reader.dart';
import '../pptx/pptx_part_paths.dart';
import '../theme/color.dart';
import '../theme/theme.dart';
import '../xml/units.dart';
import 'docx_model.dart';
import 'docx_numbering.dart';
import 'docx_styles.dart';
import 'docx_xml.dart';

const _relImage =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';
const _relHeader =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/header';
const _relFooter =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer';
const _relFootnotes =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes';
const _relOfficeDocument =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';

class DocxParser {
  const DocxParser();

  DocxDocument parse(PackageReader package) {
    final warnings = <String>[...package.warnings];
    var theme = OfficeTheme.defaults;
    final themeText = package.readPartUtf8('word/theme/theme1.xml');
    if (themeText != null) {
      theme = OfficeTheme(
        colorScheme: ThemeColorScheme.parse(themeText),
        fontScheme: ThemeFontScheme.parse(themeText),
      );
    }

    final stylesText = package.readPartUtf8('word/styles.xml');
    final styleSheet = DocxStyleSheet.parse(stylesText, theme);
    warnings.addAll(styleSheet.warnings);

    final numberingText = package.readPartUtf8('word/numbering.xml');
    final numbering = DocxNumbering.parse(numberingText);
    warnings.addAll(numbering.warnings);

    final mainPart = _findMainDocumentPart(package);
    final documentText = package.readPartUtf8(mainPart);
    if (documentText == null) {
      warnings.add('Missing main document part');
      return DocxDocument(
        body: const [],
        sections: [_defaultSection()],
        styles: styleSheet,
        numbering: numbering,
        theme: theme,
        warnings: warnings,
      );
    }

    final docRels = package.relationshipsForPart(mainPart);
    final mediaByRelId = <String, Uint8List>{};
    for (final r in docRels.items) {
      if (r.type == _relImage && !r.external) {
        final resolved = _resolvePartTarget(mainPart, r.target);
        final bytes = package.readPartBytes(resolved);
        if (bytes != null) mediaByRelId[r.id] = bytes;
      }
    }

    final headers = <String, DocHeaderFooter>{};
    final footers = <String, DocHeaderFooter>{};
    for (final r in docRels.items) {
      if (r.type == _relHeader && !r.external) {
        final path = _resolvePartTarget(mainPart, r.target);
        final xml = package.readPartUtf8(path);
        if (xml != null) {
          headers[r.id] = DocHeaderFooter(
            blocks: _parseBodyBlocks(
              xml,
              styleSheet,
              mediaByRelId,
              warnings,
              package,
              path,
            ),
          );
        }
      } else if (r.type == _relFooter && !r.external) {
        final path = _resolvePartTarget(mainPart, r.target);
        final xml = package.readPartUtf8(path);
        if (xml != null) {
          footers[r.id] = DocHeaderFooter(
            blocks: _parseBodyBlocks(
              xml,
              styleSheet,
              mediaByRelId,
              warnings,
              package,
              path,
            ),
          );
        }
      }
    }

    final footnotes = <DocFootnote>[];
    for (final r in docRels.items) {
      if (r.type == _relFootnotes && !r.external) {
        final path = _resolvePartTarget(mainPart, r.target);
        footnotes.addAll(
          _parseFootnotes(path, package, styleSheet, mediaByRelId, warnings),
        );
      }
    }

    XmlDocument docXml;
    try {
      docXml = XmlDocument.parse(documentText);
    } catch (e) {
      warnings.add('document.xml invalid: $e');
      return DocxDocument(
        body: const [],
        sections: [_defaultSection()],
        styles: styleSheet,
        numbering: numbering,
        theme: theme,
        warnings: warnings,
      );
    }

    XmlElement? body;
    for (final el in docXml.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'body') {
        body = el;
        break;
      }
    }

    final sections = <DocSection>[];
    var defaultSection = _defaultSection();
    final blocks = <DocBodyBlock>[];

    if (body != null) {
      final sectPr = docxChild(body, 'sectPr');
      if (sectPr != null) {
        defaultSection = _parseSectPr(sectPr, defaultSection);
      }
      for (final child in body.childElements) {
        final local = child.name.local;
        if (local == 'sectPr') continue;
        if (local == 'p') {
          final p = _parseParagraph(
            child,
            styleSheet,
            mediaByRelId,
            warnings,
            package,
            mainPart,
          );
          if (p.pageBreakBefore && blocks.isNotEmpty) {
            sections.add(defaultSection);
            blocks.add(DocSectionBreak(defaultSection));
          }
          blocks.add(p);
        } else if (local == 'tbl') {
          blocks.add(
            _parseTable(
              child,
              styleSheet,
              mediaByRelId,
              warnings,
              package,
              mainPart,
            ),
          );
        }
      }
    }

    sections.add(defaultSection);
    _applyNumbering(blocks, numbering);

    return DocxDocument(
      body: blocks,
      sections: sections.isEmpty ? [defaultSection] : sections,
      styles: styleSheet,
      numbering: numbering,
      theme: theme,
      headers: headers,
      footers: footers,
      footnotes: footnotes,
      warnings: warnings,
      mediaByRelId: mediaByRelId,
    );
  }

  String _findMainDocumentPart(PackageReader package) {
    for (final name in package.partNames) {
      final ct = package.contentTypes.contentTypeForPart(name);
      if (ct != null &&
          ct.contains('wordprocessingml.document.main+xml')) {
        return name;
      }
    }
    final root = package.rootRelationships();
    for (final r in root.items) {
      if (r.type == _relOfficeDocument) {
        return _resolvePartTarget('', r.target);
      }
    }
    return 'word/document.xml';
  }

  static String _resolvePartTarget(String partPath, String target) {
    var baseDir = '';
    if (partPath.isNotEmpty) {
      final slash = partPath.lastIndexOf('/');
      if (slash >= 0) baseDir = partPath.substring(0, slash + 1);
    }
    if (target.startsWith('/')) {
      return target.substring(1).toLowerCase();
    }
    final combined = '$baseDir$target';
    final parts = <String>[];
    for (final seg in combined.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/').toLowerCase();
  }

  DocSection _defaultSection() => const DocSection.withMargins(
        pageWidthPt: 612,
        pageHeightPt: 792,
        contentLeftPt: 72,
        contentTopPt: 72,
        contentRightPt: 72,
        contentBottomPt: 72,
      );

  DocSection _parseSectPr(XmlElement sectPr, DocSection fallback) {
    var w = fallback.pageWidthPt;
    var h = fallback.pageHeightPt;
    var left = fallback.contentLeftPt;
    var top = fallback.contentTopPt;
    var right = fallback.contentRightPt;
    var bottom = fallback.contentBottomPt;
    var hdrDist = fallback.headerDistancePt;
    var ftrDist = fallback.footerDistancePt;
    String? headerRel;
    String? footerRel;

    final pgSz = docxChild(sectPr, 'pgSz');
    if (pgSz != null) {
      final twW = docxIntAttr(pgSz, 'w');
      final twH = docxIntAttr(pgSz, 'h');
      if (twW != null) w = twipToPt(twW);
      if (twH != null) h = twipToPt(twH);
    }
    final pgMar = docxChild(sectPr, 'pgMar');
    if (pgMar != null) {
      left = twipToPt(docxIntAttr(pgMar, 'left') ?? 1440);
      top = twipToPt(docxIntAttr(pgMar, 'top') ?? 1440);
      right = twipToPt(docxIntAttr(pgMar, 'right') ?? 1440);
      bottom = twipToPt(docxIntAttr(pgMar, 'bottom') ?? 1440);
      hdrDist = twipToPt(docxIntAttr(pgMar, 'header') ?? 720);
      ftrDist = twipToPt(docxIntAttr(pgMar, 'footer') ?? 720);
    }
    for (final hf in docxChildren(sectPr, 'headerReference')) {
      if (docxAttr(hf, 'type') == 'default') {
        headerRel = docxAttr(hf, 'id');
      }
    }
    for (final hf in docxChildren(sectPr, 'footerReference')) {
      if (docxAttr(hf, 'type') == 'default') {
        footerRel = docxAttr(hf, 'id');
      }
    }

    return DocSection.withMargins(
      pageWidthPt: w,
      pageHeightPt: h,
      contentLeftPt: left,
      contentTopPt: top,
      contentRightPt: right,
      contentBottomPt: bottom,
      headerDistancePt: hdrDist,
      footerDistancePt: ftrDist,
      headerRelId: headerRel,
      footerRelId: footerRel,
    );
  }

  List<DocBodyBlock> _parseBodyBlocks(
    String xml,
    DocxStyleSheet sheet,
    Map<String, Uint8List> media,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    try {
      final doc = XmlDocument.parse(xml);
      final blocks = <DocBodyBlock>[];
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'body') {
          for (final child in el.childElements) {
            final local = child.name.local;
            if (local == 'p') {
              blocks.add(
                _parseParagraph(
                  child,
                  sheet,
                  media,
                  warnings,
                  package,
                  partPath,
                ),
              );
            } else if (local == 'tbl') {
              blocks.add(
                _parseTable(
                  child,
                  sheet,
                  media,
                  warnings,
                  package,
                  partPath,
                ),
              );
            }
          }
          break;
        }
      }
      _applyNumbering(blocks, DocxNumbering.empty);
      return blocks;
    } catch (e) {
      warnings.add('Header/footer parse failed: $e');
      return const [];
    }
  }

  List<DocFootnote> _parseFootnotes(
    String path,
    PackageReader package,
    DocxStyleSheet sheet,
    Map<String, Uint8List> media,
    List<String> warnings,
  ) {
    final text = package.readPartUtf8(path);
    if (text == null) return const [];
    final out = <DocFootnote>[];
    try {
      final doc = XmlDocument.parse(text);
      for (final fn in doc.descendants.whereType<XmlElement>()) {
        if (fn.name.local != 'footnote') continue;
        final id = docxAttr(fn, 'id');
        if (id == null || id == '-1' || id == '0') continue;
        final blocks = <DocBodyBlock>[];
        for (final child in fn.childElements) {
          if (child.name.local == 'p') {
            blocks.add(
              _parseParagraph(
                child,
                sheet,
                media,
                warnings,
                package,
                path,
              ),
            );
          }
        }
        out.add(DocFootnote(id: id, blocks: blocks));
      }
    } catch (e) {
      warnings.add('footnotes parse: $e');
    }
    return out;
  }

  DocParagraph _parseParagraph(
    XmlElement p,
    DocxStyleSheet sheet,
    Map<String, Uint8List> media,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    final pPr = docxChild(p, 'pPr');
    String? pStyleId;
    int? numId;
    int? ilvl;
    var pageBreakBefore = false;
    if (pPr != null) {
      pStyleId = docxAttr(docxChild(pPr, 'pStyle'), 'val');
      final numPr = docxChild(pPr, 'numPr');
      if (numPr != null) {
        numId = docxIntAttr(docxChild(numPr, 'numId'), 'val');
        ilvl = docxIntAttr(docxChild(numPr, 'ilvl'), 'val') ?? 0;
      }
      pageBreakBefore = docxToggle(docxChild(pPr, 'pageBreakBefore')) == true;
    }

    final paraProps = sheet.resolvePara(pStyleId);
    // ListBullet / ListNumber etc. carry numPr on the style, not the paragraph.
    numId ??= paraProps.numId;
    ilvl ??= paraProps.ilvl ?? (numId != null ? 0 : null);
    final runs = <DocRun>[];

    for (final child in p.childElements) {
      final local = child.name.local;
      if (local == 'pPr') continue;
      if (local == 'r') {
        runs.addAll(
          _parseRun(child, sheet, pStyleId, media, warnings, package, partPath),
        );
      } else if (local == 'hyperlink') {
        for (final r in docxChildren(child, 'r')) {
          runs.addAll(
            _parseRun(r, sheet, pStyleId, media, warnings, package, partPath),
          );
        }
      }
    }
    if (runs.isEmpty) {
      runs.add(const DocRun(text: ''));
    }

    return DocParagraph(
      runs: runs,
      pStyleId: pStyleId,
      paraStyle: sheet.toParaStyle(paraProps),
      numId: numId,
      ilvl: ilvl,
      pageBreakBefore: pageBreakBefore,
    );
  }

  List<DocRun> _parseRun(
    XmlElement r,
    DocxStyleSheet sheet,
    String? paraStyleId,
    Map<String, Uint8List> media,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    final out = <DocRun>[];
    final rPr = docxChild(r, 'rPr');
    String? rStyleId;
    DocxCharStyleProps? direct;
    if (rPr != null) {
      rStyleId = docxAttr(docxChild(rPr, 'rStyle'), 'val');
      direct = _parseInlineChar(rPr, sheet);
    }
    final base = sheet.resolveChar(paraStyleId, rStyleId);
    final style = sheet.toRunStyle(base, direct: direct);

    for (final child in r.childElements) {
      final local = child.name.local;
      if (local == 't') {
        out.add(DocRun(text: child.innerText, style: style));
      } else if (local == 'tab') {
        out.add(DocRun(tab: true, style: style));
      } else if (local == 'br') {
        final brType = docxAttr(child, 'type');
        final kind = brType == 'page'
            ? DocBreakKind.page
            : brType == 'column'
                ? DocBreakKind.column
                : DocBreakKind.line;
        out.add(DocRun(brKind: kind, style: style));
      } else if (local == 'drawing') {
        final chart = _parseChartDrawing(
          child,
          warnings,
          package,
          partPath,
        );
        if (chart != null) {
          out.add(DocRun(chart: chart, style: style));
        } else {
          final img = _parseDrawing(child, media, warnings);
          if (img != null) out.add(DocRun(image: img, style: style));
        }
      } else if (local == 'pict') {
        // legacy VML — soft-fail
      } else if (local == 'instrText' || local == 'fldChar') {
        // field assembly handled in simpleFld? skip fragments
      } else if (local == 'sym') {
        final ch = docxAttr(child, 'char');
        if (ch != null) {
          final code = int.tryParse(ch, radix: 16);
          if (code != null) {
            out.add(DocRun(text: String.fromCharCode(code), style: style));
          }
        }
      }
    }

    final fld = docxChild(r, 'fldSimple');
    if (fld != null) {
      final instr = docxAttr(fld, 'instr') ?? '';
      final text = fld.innerText;
      out.add(
        DocRun(
          style: style,
          field: DocField(instruction: instr, fallback: text),
          text: _resolveFieldText(instr, text),
        ),
      );
    }

    return out;
  }

  DocxCharStyleProps _parseInlineChar(XmlElement rPr, DocxStyleSheet sheet) {
    return _charFromRPr(rPr, sheet.colorResolver, sheet.fontScheme);
  }

  DocTable _parseTable(
    XmlElement tbl,
    DocxStyleSheet sheet,
    Map<String, Uint8List> media,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    final colWidths = <double>[];
    final tblGrid = docxChild(tbl, 'tblGrid');
    if (tblGrid != null) {
      for (final gc in docxChildren(tblGrid, 'gridCol')) {
        final w = docxIntAttr(gc, 'w');
        if (w != null) colWidths.add(twipToPt(w));
      }
    }

    var borders = const DocTableBorders();
    final tblPr = docxChild(tbl, 'tblPr');
    if (tblPr != null) {
      final styleId = docxAttr(docxChild(tblPr, 'tblStyle'), 'val');
      if (styleId != null && sheet.tableBordersByStyle.containsKey(styleId)) {
        borders = sheet.tableBordersByStyle[styleId]!;
      }
      final direct = docxChild(tblPr, 'tblBorders');
      if (direct != null) {
        borders = _mergeTableBorders(
          borders,
          _parseDirectTableBorders(direct, sheet.colorResolver),
        );
      }
    }

    final rows = <DocTableRow>[];
    for (final tr in docxChildren(tbl, 'tr')) {
      double? rowH;
      final trPr = docxChild(tr, 'trPr');
      if (trPr != null) {
        final h = docxIntAttr(docxChild(trPr, 'trHeight'), 'val');
        if (h != null) rowH = twipToPt(h);
      }
      final cells = <DocTableCell>[];
      for (final tc in docxChildren(tr, 'tc')) {
        cells.add(_parseCell(tc, sheet, media, warnings, package, partPath));
      }
      rows.add(DocTableRow(cells: cells, heightPt: rowH));
    }

    return DocTable(rows: rows, columnWidthsPt: colWidths, borders: borders);
  }

  DocTableBorders _parseDirectTableBorders(
    XmlElement bordersEl,
    ThemeColorResolver resolver,
  ) {
    DocBorder? side(String name) {
      final el = docxChild(bordersEl, name);
      if (el == null) return null;
      final val = docxAttr(el, 'val');
      if (val == null || val == 'nil' || val == 'none') {
        return const DocBorder(
          color: Color(0xFF000000),
          style: DocBorderStyle.none,
        );
      }
      final sz = docxIntAttr(el, 'sz') ?? 4;
      final attrs = {for (final a in el.attributes) a.name.local: a.value};
      return DocBorder(
        color: resolver.resolveColorElement(attrs, const []),
        widthPt: (sz / 8.0).clamp(0.5, 6.0),
      );
    }

    return DocTableBorders(
      top: side('top'),
      left: side('left'),
      bottom: side('bottom'),
      right: side('right'),
      insideH: side('insideH'),
      insideV: side('insideV'),
    );
  }

  DocTableBorders _mergeTableBorders(DocTableBorders base, DocTableBorders over) {
    return DocTableBorders(
      top: over.top ?? base.top,
      left: over.left ?? base.left,
      bottom: over.bottom ?? base.bottom,
      right: over.right ?? base.right,
      insideH: over.insideH ?? base.insideH,
      insideV: over.insideV ?? base.insideV,
    );
  }

  DocTableCell _parseCell(
    XmlElement tc,
    DocxStyleSheet sheet,
    Map<String, Uint8List> media,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    var gridSpan = 1;
    DocVMerge vMerge = DocVMerge.none;
    final tcPr = docxChild(tc, 'tcPr');
    double? widthPt;
    Color? shading;

    if (tcPr != null) {
      gridSpan = docxIntAttr(docxChild(tcPr, 'gridSpan'), 'val') ?? 1;
      final vm = docxChild(tcPr, 'vMerge');
      if (vm != null) {
        final val = docxAttr(vm, 'val');
        vMerge = val == 'restart' ? DocVMerge.restart : DocVMerge.continue_;
      }
      final tcW = docxChild(tcPr, 'tcW');
      if (tcW != null) {
        final w = docxIntAttr(tcW, 'w');
        if (w != null) widthPt = twipToPt(w);
      }
      final shd = docxChild(tcPr, 'shd');
      if (shd != null) {
        final fill = docxAttr(shd, 'fill');
        if (fill != null && fill.length == 6) {
          shading = Color(0xFF000000 | int.parse(fill, radix: 16));
        }
      }
    }

    final blocks = <DocBodyBlock>[];
    for (final child in tc.childElements) {
      if (child.name.local == 'tcPr') continue;
      if (child.name.local == 'p') {
        blocks.add(
          _parseParagraph(child, sheet, media, warnings, package, partPath),
        );
      } else if (child.name.local == 'tbl') {
        blocks.add(
          _parseTable(child, sheet, media, warnings, package, partPath),
        );
      }
    }
    if (blocks.isEmpty) {
      blocks.add(DocParagraph(runs: const [DocRun(text: '')]));
    }

    return DocTableCell(
      blocks: blocks,
      gridSpan: gridSpan,
      vMerge: vMerge,
      widthPt: widthPt,
      shading: shading,
    );
  }

  DocChart? _parseChartDrawing(
    XmlElement drawing,
    List<String> warnings,
    PackageReader package,
    String partPath,
  ) {
    try {
      XmlElement? container;
      var placement = DocImagePlacement.inline;
      for (final el in drawing.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'inline') {
          container = el;
          placement = DocImagePlacement.inline;
          break;
        }
        if (el.name.local == 'anchor') {
          container = el;
          placement = DocImagePlacement.anchor;
          break;
        }
      }
      if (container == null) return null;

      String? chartRid;
      for (final el in container.descendants.whereType<XmlElement>()) {
        if (el.name.local != 'chart') continue;
        chartRid = docxAttr(el, 'id') ?? docxAttr(el, 'embed');
        if (chartRid == null) {
          for (final a in el.attributes) {
            if (a.name.local == 'id' || a.name.local == 'embed') {
              chartRid = a.value;
              break;
            }
          }
        }
        if (chartRid != null) break;
      }
      if (chartRid == null) return null;

      final rels = package.relationshipsForPart(partPath);
      final rel = rels.byId(chartRid);
      if (rel == null || rel.external) {
        warnings.add('Unresolved chart relationship $chartRid in $partPath');
        return null;
      }
      final chartPath = resolveOpcTarget(partPath, rel.target);
      final chartXml = package.readPartUtf8(chartPath);
      if (chartXml == null) {
        warnings.add('Missing chart part $chartPath');
        return null;
      }

      double wPt = 100;
      double hPt = 100;
      for (final ext in container.descendants.whereType<XmlElement>()) {
        if (ext.name.local == 'extent') {
          final cx = docxIntAttr(ext, 'cx');
          final cy = docxIntAttr(ext, 'cy');
          if (cx != null) wPt = emuToPt(cx);
          if (cy != null) hPt = emuToPt(cy);
        }
      }

      var wrap = DocWrapType.none;
      var offsetL = 0.0;
      var offsetT = 0.0;
      if (placement == DocImagePlacement.anchor) {
        for (final wp in container.descendants.whereType<XmlElement>()) {
          if (wp.name.local == 'wrapSquare') wrap = DocWrapType.square;
          if (wp.name.local == 'wrapTopAndBottom') {
            wrap = DocWrapType.topBottom;
          }
          if (wp.name.local == 'positionH') {
            final pos = docxChild(wp, 'posOffset');
            if (pos != null) {
              final emu = int.tryParse(pos.innerText);
              if (emu != null) offsetL = emuToPt(emu);
            }
          }
          if (wp.name.local == 'positionV') {
            final pos = docxChild(wp, 'posOffset');
            if (pos != null) {
              final emu = int.tryParse(pos.innerText);
              if (emu != null) offsetT = emuToPt(emu);
            }
          }
        }
      }

      return DocChart(
        placement: placement,
        widthPt: wPt,
        heightPt: hPt,
        chartXml: chartXml,
        wrap: wrap,
        offsetLeftPt: offsetL,
        offsetTopPt: offsetT,
      );
    } catch (e) {
      warnings.add('chart drawing parse: $e');
      return null;
    }
  }

  DocImage? _parseDrawing(
    XmlElement drawing,
    Map<String, Uint8List> media,
    List<String> warnings,
  ) {
    try {
      for (final el in drawing.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'inline') {
          return _parseInlineOrAnchor(el, media, DocImagePlacement.inline);
        }
        if (el.name.local == 'anchor') {
          return _parseInlineOrAnchor(el, media, DocImagePlacement.anchor);
        }
      }
    } catch (e) {
      warnings.add('drawing parse: $e');
    }
    return null;
  }

  DocImage? _parseInlineOrAnchor(
    XmlElement container,
    Map<String, Uint8List> media,
    DocImagePlacement placement,
  ) {
    double wPt = 100;
    double hPt = 100;
    for (final ext in container.descendants.whereType<XmlElement>()) {
      if (ext.name.local == 'extent') {
        final cx = docxIntAttr(ext, 'cx');
        final cy = docxIntAttr(ext, 'cy');
        if (cx != null) wPt = emuToPt(cx);
        if (cy != null) hPt = emuToPt(cy);
      }
    }

    Uint8List? bytes;
    for (final blip in container.descendants.whereType<XmlElement>()) {
      if (blip.name.local == 'blip') {
        var embed = docxAttr(blip, 'embed');
        if (embed == null) {
          for (final a in blip.attributes) {
            if (a.name.local == 'embed') {
              embed = a.value;
              break;
            }
          }
        }
        if (embed != null) bytes = media[embed];
      }
    }

    DocWrapType wrap = DocWrapType.none;
    double offsetL = 0;
    double offsetT = 0;
    if (placement == DocImagePlacement.anchor) {
      for (final wp in container.descendants.whereType<XmlElement>()) {
        if (wp.name.local == 'wrapSquare') wrap = DocWrapType.square;
        if (wp.name.local == 'wrapTopAndBottom') wrap = DocWrapType.topBottom;
        if (wp.name.local == 'positionH') {
          final pos = docxChild(wp, 'posOffset');
          if (pos != null) {
            final emu = int.tryParse(pos.innerText);
            if (emu != null) offsetL = emuToPt(emu);
          }
        }
        if (wp.name.local == 'positionV') {
          final pos = docxChild(wp, 'posOffset');
          if (pos != null) {
            final emu = int.tryParse(pos.innerText);
            if (emu != null) offsetT = emuToPt(emu);
          }
        }
      }
    }

    return DocImage(
      placement: placement,
      widthPt: wPt,
      heightPt: hPt,
      bytes: bytes,
      wrap: wrap,
      offsetLeftPt: offsetL,
      offsetTopPt: offsetT,
    );
  }

  String _resolveFieldText(String instr, String fallback) {
    final upper = instr.trim().toUpperCase();
    if (upper.contains('PAGE')) return '';
    if (upper.contains('NUMPAGES')) return '';
    return fallback;
  }

  void _applyNumbering(List<DocBodyBlock> blocks, DocxNumbering numbering) {
    final counters = <int, List<int>>{};
    for (final block in blocks) {
      if (block is! DocParagraph) continue;
      final numId = block.numId;
      if (numId == null) continue;
      final ilvl = block.ilvl ?? 0;
      final list = counters.putIfAbsent(numId, () => List<int>.filled(9, 0));
      while (list.length <= ilvl) {
        list.add(0);
      }
      list[ilvl]++;
      for (var i = ilvl + 1; i < list.length; i++) {
        list[i] = 0;
      }
      final label = numbering.formatLabel(
        numId: numId,
        ilvl: ilvl,
        counters: list,
      );
      if (label != null) {
        block.isList = true;
        block.listLabel = label;
        final ind = numbering.levelIndent(numId: numId, ilvl: ilvl);
        if (ind != null &&
            block.paraStyle.indentLeftPt == 0 &&
            block.paraStyle.indentFirstPt == 0) {
          final leftPt =
              ind.left != null ? twipToPt(ind.left!) : 0.0;
          final hangPt =
              ind.hanging != null ? twipToPt(ind.hanging!) : 0.0;
          final ps = block.paraStyle;
          block.paraStyle = ComputedParaStyle(
            alignment: ps.alignment,
            lineSpacingMultiple: ps.lineSpacingMultiple,
            lineSpacingExactPt: ps.lineSpacingExactPt,
            spaceBeforePt: ps.spaceBeforePt,
            spaceAfterPt: ps.spaceAfterPt,
            indentLeftPt: leftPt,
            indentRightPt: ps.indentRightPt,
            indentFirstPt: hangPt > 0 ? -hangPt : ps.indentFirstPt,
            contextualSpacing: ps.contextualSpacing,
            borderBottomColor: ps.borderBottomColor,
            borderBottomWidthPt: ps.borderBottomWidthPt,
            borderBottomSpacePt: ps.borderBottomSpacePt,
          );
        }
      }
    }
  }
}

DocxCharStyleProps _charFromRPr(
  XmlElement rPr,
  ThemeColorResolver resolver,
  ThemeFontScheme fonts,
) {
  String? family;
  final rFonts = docxChild(rPr, 'rFonts');
  if (rFonts != null) {
    family = docxAttr(rFonts, 'ascii') ?? docxAttr(rFonts, 'hAnsi');
  }
  Color? color;
  final colorEl = docxChild(rPr, 'color');
  if (colorEl != null) {
    final attrs = {for (final a in colorEl.attributes) a.name.local: a.value};
    color = resolver.resolveColorElement(attrs, docxColorChildren(colorEl));
  }
  return DocxCharStyleProps(
    fontFamily: family,
    fontSizeHalfPt: docxIntAttr(docxChild(rPr, 'sz'), 'val'),
    bold: docxToggle(docxChild(rPr, 'b')),
    italic: docxToggle(docxChild(rPr, 'i')),
    underline: docxToggle(docxChild(rPr, 'u')),
    strike: docxToggle(docxChild(rPr, 'strike')),
    color: color,
  );
}
