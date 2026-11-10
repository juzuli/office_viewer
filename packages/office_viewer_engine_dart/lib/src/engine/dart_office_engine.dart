import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:office_viewer/office_viewer.dart';

import '../docx/docx_layout.dart';
import '../docx/docx_parser.dart';
import '../drawing/images.dart';
import '../fonts/font_registry.dart';
import '../model/display_list.dart';
import '../opc/encrypted_detector.dart';
import '../opc/package_reader.dart';
import '../pptx/pptx_inheritance.dart';
import '../pptx/pptx_ir.dart';
import '../pptx/pptx_layout.dart';
import '../pptx/pptx_parser.dart';
import '../theme/theme.dart';
import '../xlsx/xlsx_layout.dart';
import '../xlsx/xlsx_parser.dart';
import '../xlsx/xlsx_painter.dart';
import 'dart_document_handle.dart';
import 'limits.dart';

/// Pure Dart OOXML engine for DOCX / XLSX / PPTX.
class DartOfficeEngine implements OfficeEngine {
  DartOfficeEngine({
    this.limits = ResourceLimits.defaults,
    FontRegistry? fonts,
  }) : fonts = fonts ?? FontRegistry.instance;

  final ResourceLimits limits;
  final FontRegistry fonts;
  final OfficeImageDecoder _images = OfficeImageDecoder();

  @override
  String get id => 'dart';

  @override
  bool supports(OfficeFormat format) {
    if (kIsWeb) return false;
    return format == OfficeFormat.docx ||
        format == OfficeFormat.xlsx ||
        format == OfficeFormat.pptx;
  }

  @override
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    try {
      final bytes = await _readBytes(source, options);
      final detection = detectEncryption(bytes);
      if (detection.legacyOle) {
        throw const UnsupportedFormatError(
          'Legacy binary Office formats are not supported by the Dart engine.',
        );
      }
      if (detection.encrypted) {
        throw const PasswordRequiredError();
      }

      await fonts.ensureRegistered();

      final package = PackageReader.open(
        bytes,
        limits: limits,
        maxBytes: options.maxBytes,
      );

      final format = _sniffFormat(package, source.fileName);
      if (format == null) {
        throw const UnsupportedFormatError(
          'Not a supported OOXML package (DOCX/XLSX/PPTX).',
        );
      }

      final (parts, lists) = await _buildParts(package, format);

      return DartDocumentHandle(
        format: format,
        parts: parts,
        package: package,
        displayLists: lists,
      );
    } on OfficeError {
      rethrow;
    } catch (e) {
      throw CorruptDocumentError('Dart engine open failed: $e');
    }
  }

  Future<Uint8List> _readBytes(
    DocumentSource source,
    OpenOptions options,
  ) async {
    switch (source) {
      case FileSource(:final path):
        final file = File(path);
        if (!await file.exists()) {
          throw CorruptDocumentError('File not found: $path');
        }
        final len = await file.length();
        if (len > options.maxBytes) {
          throw ResourceLimitError(
            'File exceeds maxBytes ($len > ${options.maxBytes})',
          );
        }
        return file.readAsBytes();
      case BytesSource(:final bytes):
        if (bytes.length > options.maxBytes) {
          throw ResourceLimitError(
            'Bytes exceed maxBytes (${bytes.length} > ${options.maxBytes})',
          );
        }
        return bytes;
    }
  }

  OfficeFormat? _sniffFormat(PackageReader package, String? fileName) {
    final ct = package.contentTypes;
    if (ct.hasMainPartType('wordprocessingml')) {
      return OfficeFormat.docx;
    }
    if (ct.hasMainPartType('spreadsheetml')) {
      return OfficeFormat.xlsx;
    }
    if (ct.hasMainPartType('presentationml')) {
      return OfficeFormat.pptx;
    }

    final fromName = OfficeFormat.fromName(fileName);
    if (fromName == OfficeFormat.docx ||
        fromName == OfficeFormat.xlsx ||
        fromName == OfficeFormat.pptx) {
      return fromName;
    }
    return null;
  }

  Future<(List<PartInfo>, List<DisplayList>)> _buildParts(
    PackageReader package,
    OfficeFormat format,
  ) async {
    switch (format) {
      case OfficeFormat.xlsx:
        return _buildXlsx(package);
      case OfficeFormat.docx:
        return _buildDocx(package);
      case OfficeFormat.pptx:
        return _buildPptx(package);
      default:
        return (<PartInfo>[], <DisplayList>[]);
    }
  }

  (List<PartInfo>, List<DisplayList>) _buildXlsx(PackageReader package) {
    final workbook = const XlsxParser().parse(package);
    if (workbook.sheets.isEmpty) {
      return (
        [
          const PartInfo(
            index: 0,
            kind: PartKind.sheet,
            size: ui.Size(800, 600),
            name: 'Sheet1',
          ),
        ],
        [DisplayList.blankWhite(const ui.Size(800, 600))],
      );
    }
    final painter = XlsxPainter(fonts: fonts);
    final parts = <PartInfo>[];
    final lists = <DisplayList>[];
    for (final sheet in workbook.sheets) {
      final size = XlsxLayout.partSize(sheet);
      parts.add(
        PartInfo(
          index: sheet.index,
          kind: PartKind.sheet,
          size: size,
          name: sheet.name,
        ),
      );
      lists.add(painter.paint(sheet, workbook.styles, workbook));
    }
    return (parts, lists);
  }

  (List<PartInfo>, List<DisplayList>) _buildDocx(PackageReader package) {
    final doc = const DocxParser().parse(package);
    final pages = const DocxLayout().layout(doc);
    if (pages.isEmpty) {
      return (
        [
          const PartInfo(
            index: 0,
            kind: PartKind.page,
            size: ui.Size(612, 792),
            name: 'Page 1',
          ),
        ],
        [DisplayList.blankWhite(const ui.Size(612, 792))],
      );
    }
    final parts = <PartInfo>[
      for (var i = 0; i < pages.length; i++)
        PartInfo(
          index: i,
          kind: PartKind.page,
          size: pages[i].size,
          name: 'Page ${i + 1}',
        ),
    ];
    return (parts, pages);
  }

  Future<(List<PartInfo>, List<DisplayList>)> _buildPptx(
    PackageReader package,
  ) async {
    final doc = await const PptxParser().parse(package);
    if (doc.slides.isEmpty) {
      final size = doc.slideSize;
      return (
        [
          PartInfo(
            index: 0,
            kind: PartKind.slide,
            size: size,
            name: 'Slide 1',
          ),
        ],
        [DisplayList.blankWhite(size)],
      );
    }

    final themeXml = doc.theme.themeXml;
    final theme = OfficeTheme(
      colorScheme: themeXml != null
          ? ThemeColorScheme.parse(themeXml)
          : ThemeColorScheme.defaults,
      fontScheme: themeXml != null
          ? ThemeFontScheme.parse(themeXml)
          : ThemeFontScheme.defaults,
    );

    final decoded = <String, ui.Image>{};
    for (final slide in doc.slides) {
      await _decodeSlideImages(slide.shapes, decoded);
    }

    final inheritance = const PptxInheritance();
    final layout = const PptxLayout();
    final parts = <PartInfo>[];
    final lists = <DisplayList>[];
    for (var i = 0; i < doc.slides.length; i++) {
      final slide = inheritance.merge(doc.slides[i]);
      parts.add(
        PartInfo(
          index: i,
          kind: PartKind.slide,
          size: slide.size,
          name: slide.name ?? 'Slide ${i + 1}',
        ),
      );
      lists.add(
        layout.layout(
          slide,
          theme,
          decodedImages: decoded,
        ),
      );
    }
    return (parts, lists);
  }

  Future<void> _decodeSlideImages(
    List<PptxShapeNode> nodes,
    Map<String, ui.Image> out,
  ) async {
    for (final node in nodes) {
      switch (node) {
        case PptxPicture(:final imageBytes, :final imagePartPath):
          if (imageBytes == null || imageBytes.isEmpty) continue;
          final key = imagePartPath;
          if (out.containsKey(key)) continue;
          final img = await _images.decode(key, imageBytes);
          if (img != null) out[key] = img;
        case PptxGroup(:final children):
          await _decodeSlideImages(children, out);
        case PptxShape():
        case PptxTable():
        case PptxChart():
          break;
      }
    }
  }
}
