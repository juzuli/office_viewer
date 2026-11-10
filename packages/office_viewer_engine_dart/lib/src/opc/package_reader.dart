import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:office_viewer/office_viewer.dart';

import '../engine/limits.dart';
import 'content_types.dart';
import 'relationships.dart';

/// Read-only OPC zip view with zip-bomb guards.
class PackageReader {
  PackageReader._({
    required this.limits,
    required Map<String, Uint8List> entries,
    required this.contentTypes,
    required List<String> warnings,
  })  : _entries = entries, // ignore: prefer_initializing_formals
        warnings = List.unmodifiable(warnings);

  final ResourceLimits limits;
  final List<String> warnings;
  final ContentTypes contentTypes;
  final Map<String, Uint8List> _entries;

  Iterable<String> get partNames => _entries.keys;

  Uint8List? readPartBytes(String partPath) {
    final key = _normalize(partPath);
    return _entries[key];
  }

  String? readPartUtf8(String partPath) {
    final bytes = readPartBytes(partPath);
    if (bytes == null) return null;
    try {
      // Must decode as UTF-8 — String.fromCharCodes treats bytes as code units
      // and corrupts multi-byte characters (e.g. smart quotes → Ã□).
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      warnings.add('Non-UTF-8 part: $partPath');
      return null;
    }
  }

  Relationships relationshipsForPart(String partPath) {
    final relsPath = Relationships.relsPathForPart(partPath);
    final text = readPartUtf8(relsPath);
    if (text == null) return Relationships(const []);
    return Relationships.parse(text);
  }

  Relationships rootRelationships() {
    final text = readPartUtf8('_rels/.rels');
    if (text == null) return Relationships(const []);
    return Relationships.parse(text);
  }

  static PackageReader open(
    Uint8List compressedBytes, {
    ResourceLimits limits = ResourceLimits.defaults,
    int? maxBytes,
  }) {
    final effectiveMax =
        maxBytes != null && maxBytes < limits.maxCompressedBytes
            ? maxBytes
            : limits.maxCompressedBytes;
    if (compressedBytes.length > effectiveMax) {
      throw ResourceLimitError(
        'Compressed package exceeds limit '
        '(${compressedBytes.length} > $effectiveMax)',
      );
    }

    final warnings = <String>[];
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(compressedBytes, verify: true);
    } catch (e) {
      throw CorruptDocumentError('Invalid ZIP package: $e');
    }

    if (archive.length > limits.maxEntries) {
      throw ResourceLimitError(
        'Too many zip entries (${archive.length} > ${limits.maxEntries})',
      );
    }

    var uncompressedTotal = 0;
    final entries = <String, Uint8List>{};

    for (final file in archive) {
      if (file.isFile != true) continue;
      final name = _normalize(file.name);
      final uncompressed =
          file.size > 0 ? file.size : file.content.length;

      uncompressedTotal += uncompressed;
      if (uncompressedTotal > limits.maxUncompressedBytes) {
        throw ResourceLimitError(
          'Uncompressed total exceeds limit '
          '($uncompressedTotal > ${limits.maxUncompressedBytes})',
        );
      }

      final Uint8List data;
      try {
        data = file.content;
      } catch (e) {
        warnings.add('Failed to read $name: $e');
        continue;
      }

      if (entries.containsKey(name)) {
        warnings.add('Duplicate zip entry: $name');
      }
      entries[name] = data;
    }

    if (compressedBytes.isNotEmpty &&
        uncompressedTotal / compressedBytes.length >
            limits.maxCompressionRatio) {
      throw ResourceLimitError(
        'Package compression ratio exceeds limit '
        '($uncompressedTotal / ${compressedBytes.length})',
      );
    }

    final ctText = entries.containsKey('[content_types].xml')
        ? utf8.decode(entries['[content_types].xml']!, allowMalformed: true)
        : entries.containsKey('[Content_Types].xml')
            ? utf8.decode(entries['[Content_Types].xml']!, allowMalformed: true)
            : null;

    ContentTypes types;
    if (ctText == null) {
      warnings.add('Missing [Content_Types].xml');
      types = ContentTypes(defaults: const {}, overrides: const {});
    } else {
      types = ContentTypes.parse(ctText);
    }

    // Case-insensitive lookup alias for content types part.
    if (!entries.containsKey('[Content_Types].xml') &&
        entries.containsKey('[content_types].xml')) {
      entries['[Content_Types].xml'] = entries['[content_types].xml']!;
    }

    return PackageReader._(
      limits: limits,
      entries: entries,
      contentTypes: types,
      warnings: warnings,
    );
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p.toLowerCase();
  }
}
