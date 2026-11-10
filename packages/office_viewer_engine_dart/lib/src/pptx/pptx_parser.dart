import 'dart:ui';

import 'package:xml/xml.dart';

import '../drawing/shapes.dart';
import '../opc/package_reader.dart';
import '../opc/relationships.dart';
import '../theme/color.dart';
import '../theme/theme.dart';
import '../xml/units.dart';
import '../model/style.dart';
import 'pptx_ir.dart';
import 'pptx_master_styles.dart';
import 'pptx_part_paths.dart';

const _relLayout =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout';
const _relMaster =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster';
const _relTheme =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme';
/// Parses PPTX package parts into [PptxDocument] IR.
class PptxParser {
  const PptxParser();

  Future<PptxDocument> parse(PackageReader pkg) async {
    final warnings = List<String>.from(pkg.warnings);

    final presPath = _findPresentationPart(pkg);
    if (presPath == null) {
      warnings.add('Missing presentation.xml');
      return PptxDocument(
        slideSize: const Size(960, 540),
        slides: const [],
        theme: PptxThemeParts(),
        warnings: warnings,
      );
    }

    final presText = pkg.readPartUtf8(presPath);
    if (presText == null) {
      warnings.add('Unreadable $presPath');
      return PptxDocument(
        slideSize: const Size(960, 540),
        slides: const [],
        theme: PptxThemeParts(),
        warnings: warnings,
      );
    }

    final presRels = pkg.relationshipsForPart(presPath);
  final themeParts = _loadTheme(pkg, presRels, warnings);
    final colorResolver = ThemeColorResolver(
      themeParts.themeXml != null
          ? ThemeColorScheme.parse(themeParts.themeXml!)
          : ThemeColorScheme.defaults,
    );

    final presDoc = XmlDocument.parse(presText);
    final slideSize = _readSlideSize(presDoc) ?? const Size(960, 540);
    final slideEntries = _readSlideList(presDoc, presRels, presPath, warnings);

    final slides = <PptxSlide>[];
    var idx = 0;
    for (final entry in slideEntries) {
      final slidePath = entry.path;
      final slideText = pkg.readPartUtf8(slidePath);
      if (slideText == null) {
        warnings.add('Missing slide part $slidePath');
        continue;
      }

      final slideRels = pkg.relationshipsForPart(slidePath);
      final layoutPath = _firstRelTarget(slideRels, _relLayout, slidePath);
      final layoutRels =
          layoutPath != null ? pkg.relationshipsForPart(layoutPath) : null;
      final masterPath = layoutRels != null
          ? _firstRelTarget(layoutRels, _relMaster, layoutPath!)
          : null;

      final themeFonts = ThemeFontScheme.parse(themeParts.themeXml ?? '');
      final layoutShapes = layoutPath != null
          ? _parseSpTreeFromPart(pkg, layoutPath, colorResolver, warnings)
          : <PptxShapeNode>[];
      final masterShapes = masterPath != null
          ? _parseSpTreeFromPart(pkg, masterPath, colorResolver, warnings)
          : <PptxShapeNode>[];
      final masterXml =
          masterPath != null ? pkg.readPartUtf8(masterPath) : null;
      final masterStyles = PptxMasterStyles.parse(
        masterXml,
        colorResolver,
        themeFonts,
      );

      final slideDoc = XmlDocument.parse(slideText);
      final bg = _parseSlideBackground(slideDoc, colorResolver);
      final shapes = _parseSpTree(
        slideDoc,
        colorResolver,
        pkg,
        slideRels,
        slidePath,
        warnings,
        defaultTextSize: 18,
        themeFonts: themeFonts,
      );

      slides.add(PptxSlide(
        index: idx,
        partPath: slidePath,
        size: slideSize,
        shapes: shapes,
        backgroundFill: bg,
        layoutPartPath: layoutPath,
        masterPartPath: masterPath,
        layoutShapes: layoutShapes,
        masterShapes: masterShapes,
        masterStyles: masterStyles,
        name: 'Slide ${idx + 1}',
      ));
      idx++;
    }

    return PptxDocument(
      slideSize: slideSize,
      slides: slides,
      theme: themeParts,
      warnings: warnings,
    );
  }

  static String? _findPresentationPart(PackageReader pkg) {
    for (final name in pkg.partNames) {
      if (name.endsWith('/presentation.xml') || name == 'ppt/presentation.xml') {
        return name;
      }
    }
    return pkg.readPartBytes('ppt/presentation.xml') != null
        ? 'ppt/presentation.xml'
        : null;
  }

  static PptxThemeParts _loadTheme(
    PackageReader pkg,
    Relationships presRels,
    List<String> warnings,
  ) {
    Relationship? themeRel;
    for (final r in presRels.items) {
      if (r.type == _relTheme && !r.external) {
        themeRel = r;
        break;
      }
    }
    if (themeRel == null) {
      for (final rel in presRels.items) {
        if (rel.type.contains('/theme')) {
          final path = resolveOpcTarget('ppt/presentation.xml', rel.target);
          final xml = pkg.readPartUtf8(path);
          if (xml != null) return PptxThemeParts(themeXml: xml);
        }
      }
      return PptxThemeParts();
    }
    final path = resolveOpcTarget('ppt/presentation.xml', themeRel.target);
    final xml = pkg.readPartUtf8(path);
    if (xml == null) warnings.add('Theme part missing: $path');
    return PptxThemeParts(themeXml: xml);
  }

  static Size? _readSlideSize(XmlDocument presDoc) {
    for (final el in presDoc.descendants.whereType<XmlElement>()) {
      if (el.name.local != 'sldSz') continue;
      final cx = int.tryParse(el.getAttribute('cx') ?? '') ?? 0;
      final cy = int.tryParse(el.getAttribute('cy') ?? '') ?? 0;
      if (cx > 0 && cy > 0) {
        return Size(emuToPt(cx), emuToPt(cy));
      }
    }
    return null;
  }

  static List<_SlideEntry> _readSlideList(
    XmlDocument presDoc,
    Relationships presRels,
    String presPath,
    List<String> warnings,
  ) {
    final out = <_SlideEntry>[];
    for (final el in presDoc.descendants.whereType<XmlElement>()) {
      if (el.name.local != 'sldId') continue;
      final show = el.getAttribute('show');
      if (show == '0' || show == 'false') continue;

      final rid = _relationshipId(el);
      if (rid == null) continue;
      final rel = presRels.byId(rid);
      if (rel == null || rel.external) {
        warnings.add('Unresolved slide relationship $rid');
        continue;
      }
      final path = resolveOpcTarget(presPath, rel.target);
      out.add(_SlideEntry(path));
    }
    return out;
  }

  static String? _relationshipId(XmlElement el) {
    for (final a in el.attributes) {
      if (a.name.local == 'id' && a.name.prefix == 'r') return a.value;
    }
    return el.getAttribute('r:id');
  }

  static String? _firstRelTarget(
    Relationships rels,
    String type,
    String sourcePart,
  ) {
    for (final r in rels.items) {
      if (r.type == type && !r.external) {
        return resolveOpcTarget(sourcePart, r.target);
      }
    }
    return null;
  }

  static List<PptxShapeNode> _parseSpTreeFromPart(
    PackageReader pkg,
    String partPath,
    ThemeColorResolver colors,
    List<String> warnings,
  ) {
    final text = pkg.readPartUtf8(partPath);
    if (text == null) return const [];
    try {
      final doc = XmlDocument.parse(text);
      final rels = pkg.relationshipsForPart(partPath);
      return _parseSpTree(
        doc,
        colors,
        pkg,
        rels,
        partPath,
        warnings,
        defaultTextSize: 18,
        themeFonts: ThemeFontScheme.defaults,
      );
    } catch (e) {
      warnings.add('Failed parsing $partPath: $e');
      return const [];
    }
  }

  static SolidShapeFill? _parseSlideBackground(
    XmlDocument slideDoc,
    ThemeColorResolver colors,
  ) {
    for (final cSld in slideDoc.descendants.whereType<XmlElement>()) {
      if (cSld.name.local != 'cSld') continue;
      for (final bg in cSld.childElements) {
        if (bg.name.local != 'bg') continue;
        for (final child in bg.childElements) {
          if (child.name.local == 'solidFill') {
            final c = _parseFillColor(child, colors);
            if (c != null) return SolidShapeFill(c);
          }
          if (child.name.local == 'bgPr') {
            for (final inner in child.childElements) {
              if (inner.name.local == 'solidFill') {
                final c = _parseFillColor(inner, colors);
                if (c != null) return SolidShapeFill(c);
              }
            }
          }
        }
      }
    }
    return null;
  }

  static List<PptxShapeNode> _parseSpTree(
    XmlDocument doc,
    ThemeColorResolver colors,
    PackageReader pkg,
    Relationships partRels,
    String partPath,
    List<String> warnings, {
    required double defaultTextSize,
    required ThemeFontScheme themeFonts,
  }) {
    XmlElement? spTree;
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'spTree') {
        spTree = el;
        break;
      }
    }
    if (spTree == null) return const [];

    final nodes = <PptxShapeNode>[];
    for (final child in spTree.childElements) {
      final local = child.name.local;
      if (local == 'sp') {
        final shape = _parseShape(
          child,
          colors,
          defaultTextSize: defaultTextSize,
          themeFonts: themeFonts,
        );
        if (shape != null) nodes.add(shape);
      } else if (local == 'pic') {
        final pic = _parsePicture(child, colors, pkg, partRels, partPath, warnings);
        if (pic != null) nodes.add(pic);
      } else if (local == 'grpSp') {
        final group = _parseGroup(
          child,
          colors,
          pkg,
          partRels,
          partPath,
          warnings,
          defaultTextSize: defaultTextSize,
          themeFonts: themeFonts,
        );
        if (group != null) nodes.add(group);
      } else if (local == 'graphicFrame') {
        final frame = _parseGraphicFrame(
          child,
          colors,
          pkg,
          partRels,
          partPath,
          warnings,
          themeFonts: themeFonts,
        );
        if (frame != null) nodes.add(frame);
      }
    }
    return nodes;
  }

  static PptxShape? _parseShape(
    XmlElement sp,
    ThemeColorResolver colors, {
    required double defaultTextSize,
    required ThemeFontScheme themeFonts,
  }) {
    final ph = _parsePlaceholder(sp);
    var hidden = false;
    for (final el in sp.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'cNvPr') {
        if (el.getAttribute('hidden') == '1') hidden = true;
      }
    }

    XmlElement? spPr;
    XmlElement? txBody;
    for (final child in sp.childElements) {
      if (child.name.local == 'spPr') spPr = child;
      if (child.name.local == 'txBody') txBody = child;
    }
    if (spPr == null) return null;

    final xfrm = parseXfrm(spPr) ?? const ShapeTransform();
    final preset = parsePresetGeometryName(spPr) ?? 'rect';
    final adj = parseAdjustValues(spPr);
    final fill = parseShapeFill(spPr, colors);
    final outline = parseShapeOutline(spPr, colors);
    final text = txBody != null
        ? _parseTxBody(txBody, colors, defaultTextSize, themeFonts)
        : null;

    return PptxShape(
      transform: xfrm,
      placeholderType: ph?.type,
      placeholderIdx: ph?.idx,
      presetGeometry: preset,
      adjustValues: adj,
      fill: fill,
      outline: outline,
      textBody: text,
      hidden: hidden,
    );
  }

  static PptxPicture? _parsePicture(
    XmlElement pic,
    ThemeColorResolver colors,
    PackageReader pkg,
    Relationships partRels,
    String partPath,
    List<String> warnings,
  ) {
    final ph = _parsePlaceholder(pic);
    XmlElement? spPr;
    for (final child in pic.childElements) {
      if (child.name.local == 'spPr') spPr = child;
    }
    if (spPr == null) return null;
    final xfrm = parseXfrm(spPr) ?? const ShapeTransform();

    String? imagePath;
    for (final blip in pic.descendants.whereType<XmlElement>()) {
      if (blip.name.local != 'blip') continue;
      String? embed;
      for (final a in blip.attributes) {
        if (a.name.local == 'embed') embed = a.value;
      }
      if (embed == null) continue;
      final rel = partRels.byId(embed);
      if (rel == null) continue;
      imagePath = resolveOpcTarget(partPath, rel.target);
      break;
    }

    if (imagePath == null) {
      warnings.add('Picture without embed in $partPath');
      return null;
    }

    final bytes = pkg.readPartBytes(imagePath);
    return PptxPicture(
      transform: xfrm,
      imagePartPath: imagePath,
      imageBytes: bytes,
      placeholderType: ph?.type,
      placeholderIdx: ph?.idx,
    );
  }

  static PptxGroup? _parseGroup(
    XmlElement grpSp,
    ThemeColorResolver colors,
    PackageReader pkg,
    Relationships partRels,
    String partPath,
    List<String> warnings, {
    required double defaultTextSize,
    required ThemeFontScheme themeFonts,
  }) {
    final ph = _parsePlaceholder(grpSp);
    XmlElement? grpSpPr;
    for (final child in grpSp.childElements) {
      if (child.name.local == 'grpSpPr') grpSpPr = child;
    }
    final xfrm = grpSpPr != null
        ? parseXfrm(grpSpPr) ?? const ShapeTransform()
        : const ShapeTransform();

    final children = <PptxShapeNode>[];
    for (final child in grpSp.childElements) {
      final local = child.name.local;
      if (local == 'sp') {
        final s = _parseShape(
          child,
          colors,
          defaultTextSize: defaultTextSize,
          themeFonts: themeFonts,
        );
        if (s != null) children.add(s);
      } else if (local == 'pic') {
        final p = _parsePicture(child, colors, pkg, partRels, partPath, warnings);
        if (p != null) children.add(p);
      } else if (local == 'grpSp') {
        final g = _parseGroup(
          child,
          colors,
          pkg,
          partRels,
          partPath,
          warnings,
          defaultTextSize: defaultTextSize,
          themeFonts: themeFonts,
        );
        if (g != null) children.add(g);
      } else if (local == 'graphicFrame') {
        final frame = _parseGraphicFrame(
          child,
          colors,
          pkg,
          partRels,
          partPath,
          warnings,
          themeFonts: themeFonts,
        );
        if (frame != null) children.add(frame);
      }
    }

    return PptxGroup(
      transform: xfrm,
      children: children,
      placeholderType: ph?.type,
      placeholderIdx: ph?.idx,
    );
  }

  static _PlaceholderRef? _parsePlaceholder(XmlElement shapeEl) {
    for (final ph in shapeEl.descendants.whereType<XmlElement>()) {
      if (ph.name.local != 'ph') continue;
      final type = ph.getAttribute('type');
      final idx = int.tryParse(ph.getAttribute('idx') ?? '');
      return _PlaceholderRef(type: type, idx: idx);
    }
    return null;
  }

  static const _uriTable =
      'http://schemas.openxmlformats.org/drawingml/2006/table';
  static const _uriChart =
      'http://schemas.openxmlformats.org/drawingml/2006/chart';

  static PptxShapeNode? _parseGraphicFrame(
    XmlElement frame,
    ThemeColorResolver colors,
    PackageReader pkg,
    Relationships partRels,
    String partPath,
    List<String> warnings, {
    required ThemeFontScheme themeFonts,
  }) {
    final xfrm = parseXfrm(frame) ?? const ShapeTransform();
    String? uri;
    XmlElement? graphicData;
    for (final el in frame.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'graphicData') {
        graphicData = el;
        uri = el.getAttribute('uri');
        break;
      }
    }
    if (graphicData == null) return null;

    if (uri == _uriTable) {
      return _parseTable(graphicData, xfrm, colors, themeFonts);
    }
    if (uri == _uriChart) {
      return _parseChart(graphicData, xfrm, pkg, partRels, partPath, warnings);
    }
    warnings.add('Unsupported graphicFrame uri=$uri in $partPath');
    return null;
  }

  static PptxTable? _parseTable(
    XmlElement graphicData,
    ShapeTransform xfrm,
    ThemeColorResolver colors,
    ThemeFontScheme themeFonts,
  ) {
    XmlElement? tbl;
    for (final el in graphicData.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'tbl') {
        tbl = el;
        break;
      }
    }
    if (tbl == null) return null;

    var firstRow = false;
    var bandRow = false;
    String? styleId;
    for (final child in tbl.childElements) {
      if (child.name.local != 'tblPr') continue;
      firstRow = child.getAttribute('firstRow') == '1';
      bandRow = child.getAttribute('bandRow') == '1';
      for (final idEl in child.childElements) {
        if (idEl.name.local == 'tableStyleId') {
          final id = idEl.innerText.trim();
          if (id.isNotEmpty) styleId = id;
        }
      }
    }

    final colWidths = <double>[];
    for (final child in tbl.childElements) {
      if (child.name.local != 'tblGrid') continue;
      for (final col in child.childElements) {
        if (col.name.local != 'gridCol') continue;
        final w = int.tryParse(col.getAttribute('w') ?? '') ?? 0;
        colWidths.add(emuToPt(w));
      }
    }

    final rows = <PptxTableRow>[];
    for (final child in tbl.childElements) {
      if (child.name.local != 'tr') continue;
      final h = emuToPt(int.tryParse(child.getAttribute('h') ?? '') ?? 0);
      final cells = <PptxTableCell>[];
      for (final tc in child.childElements) {
        if (tc.name.local != 'tc') continue;
        var text = '';
        var style = ComputedRunStyle(
          fontSizePt: 14,
          fontFamily: themeFonts.minorLatin,
        );
        Color? cellFill;
        for (final part in tc.childElements) {
          if (part.name.local == 'tcPr') {
            for (final fill in part.childElements) {
              if (fill.name.local != 'solidFill') continue;
              cellFill = _parseFillColor(fill, colors);
            }
          } else if (part.name.local == 'txBody') {
            final body = _parseTxBody(part, colors, 14, themeFonts);
            if (body == null || body.paragraphs.isEmpty) continue;
            text = body.paragraphs
                .map((p) => p.runs.map((r) => r.text).join())
                .where((t) => t.isNotEmpty)
                .join('\n');
            if (body.paragraphs.first.runs.isNotEmpty) {
              style = body.paragraphs.first.runs.first.style;
            }
          }
        }
        cells.add(PptxTableCell(text: text, style: style, fill: cellFill));
      }
      rows.add(PptxTableRow(heightPt: h > 0 ? h : 24, cells: cells));
    }

    if (rows.isEmpty) return null;
    if (colWidths.isEmpty) {
      final n = rows.first.cells.length;
      final w = xfrm.width > 0 && n > 0 ? xfrm.width / n : 80.0;
      colWidths.addAll(List.filled(n, w));
    }
    return PptxTable(
      transform: xfrm,
      columnWidthsPt: colWidths,
      rows: rows,
      firstRow: firstRow,
      bandRow: bandRow,
      styleId: styleId,
    );
  }

  static PptxChart? _parseChart(
    XmlElement graphicData,
    ShapeTransform xfrm,
    PackageReader pkg,
    Relationships partRels,
    String partPath,
    List<String> warnings,
  ) {
    String? rid;
    for (final el in graphicData.descendants.whereType<XmlElement>()) {
      if (el.name.local != 'chart') continue;
      rid = _relationshipId(el);
      if (rid != null) break;
    }
    if (rid == null) {
      warnings.add('Chart graphicFrame missing r:id in $partPath');
      return null;
    }
    final rel = partRels.byId(rid);
    if (rel == null || rel.external) {
      warnings.add('Unresolved chart relationship $rid in $partPath');
      return null;
    }
    final chartPath = resolveOpcTarget(partPath, rel.target);
    final chartXml = pkg.readPartUtf8(chartPath);
    if (chartXml == null) {
      warnings.add('Missing chart part $chartPath');
      return null;
    }
    return PptxChart(transform: xfrm, chartXml: chartXml);
  }

  static PptxTextBody? _parseTxBody(
    XmlElement txBody,
    ThemeColorResolver colors,
    double defaultSize,
    ThemeFontScheme themeFonts,
  ) {
    ComputedRunStyle? listRun;
    TextAlign? listAlign;
    for (final child in txBody.childElements) {
      if (child.name.local != 'lstStyle') continue;
      for (final lvl in child.childElements) {
        if (lvl.name.local != 'lvl1pPr') continue;
        final algn = lvl.getAttribute('algn');
        if (algn != null) listAlign = _textAlign(algn);
        for (final def in lvl.childElements) {
          if (def.name.local != 'defRPr') continue;
          listRun = _parseRunProperties(
            def,
            colors,
            ComputedRunStyle(
              fontSizePt: defaultSize,
              fontFamily: themeFonts.minorLatin,
            ),
          );
        }
        break;
      }
    }

    final paragraphs = <PptxParagraph>[];
    for (final p in txBody.childElements) {
      if (p.name.local != 'p') continue;
      final (paraStyle, level) = _parseParaProperties(p, colors);
      final paraDefault = _parseParaDefRPr(p, colors, defaultSize, themeFonts);
      final runs = <PptxTextRun>[];
      for (final child in p.descendants.whereType<XmlElement>()) {
        if (child.name.local == 'r') {
          runs.add(
            _parseRun(child, colors, defaultSize, themeFonts, paraDefault),
          );
        } else if (child.name.local == 'br' &&
            child.parent is XmlElement &&
            (child.parent as XmlElement).name.local == 'p') {
          runs.add(PptxTextRun(text: '\n', style: paraDefault));
        }
      }
      if (runs.isEmpty) {
        final text = _collectText(p);
        if (text.isNotEmpty) {
          runs.add(PptxTextRun(text: text, style: paraDefault));
        }
      }
      if (runs.isNotEmpty) {
        paragraphs.add(
          PptxParagraph(runs: runs, style: paraStyle, level: level),
        );
      }
    }
    if (paragraphs.isEmpty && listRun == null && listAlign == null) {
      return null;
    }
    if (paragraphs.isEmpty) {
      return PptxTextBody(
        paragraphs: const [],
        listStyleRun: listRun,
        listStyleAlign: listAlign,
      );
    }
    return PptxTextBody(
      paragraphs: paragraphs,
      listStyleRun: listRun,
      listStyleAlign: listAlign,
    );
  }

  static (ComputedParaStyle, int) _parseParaProperties(
    XmlElement p,
    ThemeColorResolver colors,
  ) {
    TextAlign align = TextAlign.left;
    var level = 0;
    for (final pPr in p.childElements) {
      if (pPr.name.local != 'pPr') continue;
      for (final child in pPr.childElements) {
        if (child.name.local == 'algn') {
          align = _textAlign(child.getAttribute('val'));
        }
      }
      final algn = pPr.getAttribute('algn');
      if (algn != null) align = _textAlign(algn);
      final lvl = pPr.getAttribute('lvl');
      if (lvl != null) {
        level = int.tryParse(lvl) ?? 0;
      }
    }
    return (ComputedParaStyle(alignment: align), level);
  }

  /// End-paragraph / paragraph default run props (`a:pPr/a:defRPr`).
  static ComputedRunStyle _parseParaDefRPr(
    XmlElement p,
    ThemeColorResolver colors,
    double defaultSize,
    ThemeFontScheme themeFonts,
  ) {
    var style = ComputedRunStyle(
      fontSizePt: defaultSize,
      fontFamily: themeFonts.minorLatin,
    );
    for (final pPr in p.childElements) {
      if (pPr.name.local != 'pPr') continue;
      for (final child in pPr.childElements) {
        if (child.name.local != 'defRPr') continue;
        style = _parseRunProperties(child, colors, style);
      }
    }
    return style;
  }

  static PptxTextRun _parseRun(
    XmlElement r,
    ThemeColorResolver colors,
    double defaultSize,
    ThemeFontScheme themeFonts,
    ComputedRunStyle paraDefault,
  ) {
    var style = paraDefault;
    for (final child in r.childElements) {
      if (child.name.local == 'rPr') {
        style = _parseRunProperties(child, colors, style);
      }
    }
    final text = _collectText(r);
    return PptxTextRun(text: text, style: style);
  }

  static ComputedRunStyle _parseRunProperties(
    XmlElement rPr,
    ThemeColorResolver colors,
    ComputedRunStyle base,
  ) {
    var fontSize = base.fontSizePt;
    var bold = base.bold;
    var italic = base.italic;
    var underline = base.underline;
    var strike = base.strike;
    var family = base.fontFamily;
    var color = base.color;

    final sz = rPr.getAttribute('sz');
    if (sz != null) {
      fontSize = int.tryParse(sz) != null ? int.parse(sz) / 100.0 : fontSize;
    }
    if (rPr.getAttribute('b') == '1') bold = true;
    if (rPr.getAttribute('i') == '1') italic = true;
    if (rPr.getAttribute('u') == 'sng') underline = true;
    if (rPr.getAttribute('strike') == 'sngStrike') strike = true;

    for (final child in rPr.childElements) {
      if (child.name.local == 'latin') {
        family = child.getAttribute('typeface') ?? family;
      }
      if (child.name.local == 'solidFill') {
        final c = _parseFillColor(child, colors);
        if (c != null) color = c;
      }
    }

    return ComputedRunStyle(
      fontFamily: family,
      fontSizePt: fontSize,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      color: color,
    );
  }

  static String _collectText(XmlElement root) {
    final buf = StringBuffer();
    for (final t in root.descendants.whereType<XmlElement>()) {
      if (t.name.local == 't') {
        buf.write(t.innerText);
      }
    }
    return buf.toString();
  }

  static Color? _parseFillColor(XmlElement solidFill, ThemeColorResolver colors) {
    for (final child in solidFill.childElements) {
      // Pass tint/shade/etc. as modifiers on the color element itself.
      return colors.resolveColorElement(
        {for (final a in child.attributes) a.name.local: a.value},
        _colorChildren(child),
      );
    }
    return colors.resolveColorElement(const {}, _colorChildren(solidFill));
  }

  static List<XmlColorChild> _colorChildren(XmlElement parent) {
    return [
      for (final el in parent.childElements)
        XmlColorChild(
          name: el.name.local,
          attrs: {for (final a in el.attributes) a.name.local: a.value},
          children: _colorChildren(el),
        ),
    ];
  }

  static TextAlign _textAlign(String? val) {
    switch (val) {
      case 'ctr':
        return TextAlign.center;
      case 'r':
        return TextAlign.right;
      case 'just':
        return TextAlign.justify;
      default:
        return TextAlign.left;
    }
  }
}

class _SlideEntry {
  const _SlideEntry(this.path);
  final String path;
}

class _PlaceholderRef {
  const _PlaceholderRef({this.type, this.idx});
  final String? type;
  final int? idx;
}
