import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';

Uint8List _zip(Map<String, List<int>> parts) {
  final archive = Archive();
  for (final e in parts.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('truncated zip → CorruptDocumentError', () async {
    final engine = DartOfficeEngine();
    expect(
      () => engine.open(
        DocumentSource.bytes(Uint8List.fromList([1, 2, 3, 4]), fileName: 'a.docx'),
      ),
      throwsA(isA<CorruptDocumentError>()),
    );
  });

  test('oversized maxBytes → ResourceLimitError', () async {
    final engine = DartOfficeEngine();
    final bytes = Uint8List(100);
    expect(
      () => engine.open(
        DocumentSource.bytes(bytes, fileName: 'a.docx'),
        options: const OpenOptions(maxBytes: 10),
      ),
      throwsA(isA<ResourceLimitError>()),
    );
  });

  test('ResourceLimits maxEntries enforced', () {
    final parts = <String, List<int>>{
      for (var i = 0; i < 30; i++) 'p$i.txt': utf8.encode('x'),
    };
    expect(
      () => PackageReader.open(
        _zip(parts),
        limits: const ResourceLimits(maxEntries: 10),
      ),
      throwsA(isA<ResourceLimitError>()),
    );
  });
}
