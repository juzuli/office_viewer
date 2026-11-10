import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';

import 'bindings.dart';
import 'legacy_converter.dart';

/// Converts legacy DOC/XLS/PPT to OOXML in a private temp workspace, then
/// opens the result with [DartOfficeEngine]. Never overwrites the source file.
class ConvertOfficeEngine implements OfficeEngine {
  ConvertOfficeEngine({
    OfficeEngine? ooxmlEngine,
    this.converter,
  }) : _ooxml = ooxmlEngine ?? DartOfficeEngine();

  final OfficeEngine _ooxml;
  final LegacyConverter? converter;

  @override
  String get id => 'convert';

  @override
  bool supports(OfficeFormat format) {
    // Claim legacy formats on all non-web platforms so the registry does not
    // surface the generic "No engine supports doc" message. Platforms without
    // a native convert library fail clearly in [open].
    if (kIsWeb) return false;
    return LegacyConverter.supports(format);
  }

  @override
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    final format = OfficeFormat.fromName(source.fileName);
    if (!LegacyConverter.supports(format)) {
      throw UnsupportedFormatError(
        'Convert engine expected DOC/XLS/PPT, got ${format.name}.',
      );
    }

    if (!OfficeOxideBindings.isAvailable) {
      final hint = Platform.isIOS
          ? ' Run packages/office_viewer_engine_convert/tool/build_ios_oxide.sh '
              'and pod install so OfficeOxide.xcframework is linked.'
          : '';
      throw EngineUnavailableError(
        'Legacy .${format.name} convert library is not available on this device.$hint',
      );
    }

    try {
      final bytes = await _readBytes(source, options);
      final c = converter ?? LegacyConverter();
      final ooxml = await c.convert(
        bytes,
        format,
        maxBytes: options.maxBytes,
      );
      final target = LegacyConverter.targetFormats[format]!;
      final mappedName = _mappedFileName(source.fileName, target);

      return await _ooxml.open(
        DocumentSource.bytes(ooxml, fileName: mappedName),
        options: options,
      );
    } on OfficeError {
      rethrow;
    } catch (e) {
      throw CorruptDocumentError('Convert engine open failed: $e');
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

  String _mappedFileName(String? original, OfficeFormat target) {
    final base = (original ?? 'document')
        .split(Platform.pathSeparator)
        .last
        .split('/')
        .last;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    return '$stem.${target.name}';
  }
}
