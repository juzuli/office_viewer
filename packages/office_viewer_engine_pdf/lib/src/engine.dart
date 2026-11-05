import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDFium (pdfrx) engine — used for PDF so LOK never loads PDFs
/// (avoids hard UNO asserts that abort the process).
class PdfOfficeEngine implements OfficeEngine {
  @override
  String get id => 'pdf';

  @override
  bool supports(OfficeFormat format) {
    if (kIsWeb) return false;
    return format == OfficeFormat.pdf;
  }

  @override
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    try {
      final PdfDocument doc;
      switch (source) {
        case FileSource(:final path):
          final f = File(path);
          if (!await f.exists()) {
            throw CorruptDocumentError('File not found: $path');
          }
          final len = await f.length();
          if (len > options.maxBytes) {
            throw ResourceLimitError(
                'File exceeds maxBytes ($len > ${options.maxBytes})');
          }
          doc = await PdfDocument.openFile(
            path,
            passwordProvider: createSimplePasswordProvider(options.password),
            firstAttemptByEmptyPassword: options.password == null,
          );
        case BytesSource(:final bytes, :final fileName):
          if (bytes.length > options.maxBytes) {
            throw ResourceLimitError(
                'Bytes exceed maxBytes (${bytes.length} > ${options.maxBytes})');
          }
          doc = await PdfDocument.openData(
            bytes,
            passwordProvider: createSimplePasswordProvider(options.password),
            firstAttemptByEmptyPassword: options.password == null,
            sourceName: fileName ?? 'document.pdf',
          );
      }

      final parts = <PartInfo>[
        for (var i = 0; i < doc.pages.length; i++)
          PartInfo(
            index: i,
            kind: PartKind.page,
            name: 'Page ${i + 1}',
            size: ui.Size(doc.pages[i].width, doc.pages[i].height),
          ),
      ];

      return _PdfDocumentHandle(doc: doc, parts: parts);
    } on OfficeError {
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password')) {
        throw const PasswordRequiredError();
      }
      throw CorruptDocumentError('PDF open failed: $e');
    }
  }
}

class _PdfDocumentHandle implements OfficeDocumentHandle {
  _PdfDocumentHandle({required this.doc, required this.parts});

  final PdfDocument doc;
  bool _closed = false;

  @override
  OfficeFormat get format => OfficeFormat.pdf;

  @override
  final List<PartInfo> parts;

  @override
  Future<RenderedTile> renderTile(TileRequest request) async {
    if (_closed) {
      throw const CorruptDocumentError('Document already closed');
    }
    if (request.partIndex < 0 || request.partIndex >= doc.pages.length) {
      throw CorruptDocumentError('Bad page index ${request.partIndex}');
    }

    final page = doc.pages[request.partIndex];
    final scale = request.scale.clamp(0.05, 4.0);
    final fullW = math.max(1.0, page.width * scale);
    final fullH = math.max(1.0, page.height * scale);

    var x = (request.region.left * scale).floor();
    var y = (request.region.top * scale).floor();
    var w = (request.region.width * scale).ceil().clamp(1, 2048);
    var h = (request.region.height * scale).ceil().clamp(1, 2048);

    if (x < 0) {
      w += x;
      x = 0;
    }
    if (y < 0) {
      h += y;
      y = 0;
    }
    if (x >= fullW || y >= fullH || w <= 0 || h <= 0) {
      return RenderedTile(rgba: _emptyRgba, width: 1, height: 1);
    }
    w = math.min(w, (fullW - x).ceil());
    h = math.min(h, (fullH - y).ceil());

    final image = await page.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: fullW,
      fullHeight: fullH,
    );
    if (image == null) {
      throw const CorruptDocumentError('PDF render returned null');
    }
    try {
      final rgba = image.format == ui.PixelFormat.bgra8888
          ? _bgraToRgba(image.pixels)
          : Uint8List.fromList(image.pixels);
      return RenderedTile(rgba: rgba, width: image.width, height: image.height);
    } finally {
      image.dispose();
    }
  }

  @override
  Future<List<SearchHit>> search(String query) async => const [];

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await doc.dispose();
  }

  static final Uint8List _emptyRgba = Uint8List(4);

  static Uint8List _bgraToRgba(Uint8List bgra) {
    final out = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      out[i] = bgra[i + 2];
      out[i + 1] = bgra[i + 1];
      out[i + 2] = bgra[i];
      out[i + 3] = bgra[i + 3];
    }
    return out;
  }
}
