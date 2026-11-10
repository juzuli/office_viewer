import 'dart:io';
import 'dart:typed_data';

import 'package:office_viewer/office_viewer.dart';
import 'package:path/path.dart' as p;

import 'bindings.dart';

/// Converts legacy OLE Office bytes to OOXML bytes (view-only; never mutates source).
class LegacyConverter {
  LegacyConverter({
    OfficeOxideBindings? bindings,
    this.tempRoot,
  }) : _bindings = bindings ?? OfficeOxideBindings.instance;

  final OfficeOxideBindings _bindings;
  final Directory? tempRoot;

  /// Maps legacy → modern extension / format name.
  static const Map<OfficeFormat, OfficeFormat> targetFormats = {
    OfficeFormat.doc: OfficeFormat.docx,
    OfficeFormat.xls: OfficeFormat.xlsx,
    OfficeFormat.ppt: OfficeFormat.pptx,
  };

  static bool supports(OfficeFormat format) => targetFormats.containsKey(format);

  /// Convert [bytes] of [legacyFormat] to OOXML bytes.
  ///
  /// Writes through a private temp file that is deleted afterwards. The
  /// caller's original path/file is never modified.
  Future<Uint8List> convert(
    Uint8List bytes,
    OfficeFormat legacyFormat, {
    int maxBytes = 50 * 1024 * 1024,
  }) async {
    final target = targetFormats[legacyFormat];
    if (target == null) {
      throw UnsupportedFormatError(
        'Convert engine does not support ${legacyFormat.name}.',
      );
    }
    if (bytes.length > maxBytes) {
      throw ResourceLimitError(
        'Bytes exceed maxBytes (${bytes.length} > $maxBytes)',
      );
    }
    if (bytes.length < 8 || !_isCfb(bytes)) {
      throw const UnsupportedFormatError(
        'Not a legacy OLE/CFB Office document.',
      );
    }

    Directory? tempDir;
    try {
      final root = tempRoot ?? Directory.systemTemp;
      tempDir = await Directory(
        p.join(
          root.path,
          'office_viewer_convert_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);

      final outPath = p.join(tempDir.path, 'converted.${target.name}');
      _bindings.convertToFile(
        bytes: bytes,
        format: legacyFormat.name,
        outPath: outPath,
      );

      final outFile = File(outPath);
      if (!await outFile.exists()) {
        throw const CorruptDocumentError('Converter produced no output file.');
      }
      final outLen = await outFile.length();
      if (outLen > maxBytes) {
        throw ResourceLimitError(
          'Converted bytes exceed maxBytes ($outLen > $maxBytes)',
        );
      }
      final out = await outFile.readAsBytes();
      if (out.length < 4 || out[0] != 0x50 || out[1] != 0x4B) {
        throw const CorruptDocumentError(
          'Converter output is not a ZIP/OOXML package.',
        );
      }
      return out;
    } on OfficeError {
      rethrow;
    } on OfficeOxideFfiException catch (e) {
      throw CorruptDocumentError('Legacy convert failed: $e');
    } on StateError catch (e) {
      throw EngineUnavailableError('$e');
    } catch (e) {
      throw CorruptDocumentError('Legacy convert failed: $e');
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Best-effort cleanup.
        }
      }
    }
  }

  static bool _isCfb(Uint8List head) =>
      head[0] == 0xD0 &&
      head[1] == 0xCF &&
      head[2] == 0x11 &&
      head[3] == 0xE0 &&
      head[4] == 0xA1 &&
      head[5] == 0xB1 &&
      head[6] == 0x1A &&
      head[7] == 0xE1;
}
