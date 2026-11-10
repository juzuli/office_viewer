import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';

/// Opens the example_app bundled samples through [DartOfficeEngine].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samplesDir = Directory(
    '${Directory.current.path}/../../example_app/assets',
  );

  bool have(String name) => File('${samplesDir.path}/$name').existsSync();

  Future<void> smoke(String fileName, PartKind kind) async {
    final path = '${samplesDir.path}/$fileName';
    final bytes = await File(path).readAsBytes();
    final engine = DartOfficeEngine();
    final handle = await engine.open(
      DocumentSource.bytes(bytes, fileName: fileName),
    );
    expect(handle.parts, isNotEmpty, reason: fileName);
    expect(handle.parts.first.kind, kind);
    expect(handle.parts.first.size.width, greaterThan(0));
    expect(handle.parts.first.size.height, greaterThan(0));

    final tile = await handle.renderTile(
      TileRequest(
        partIndex: 0,
        region: Rect.fromLTWH(
          0,
          0,
          handle.parts.first.size.width.clamp(1, 128),
          handle.parts.first.size.height.clamp(1, 128),
        ),
        scale: 1,
      ),
    );
    expect(tile.rgba.length, tile.width * tile.height * 4);
    // Not a solid failure — blank white is ok for sparse docs, but size must match.
    expect(tile.width, greaterThan(0));
    await handle.close();
  }

  test('sample.docx opens and tiles', () async {
    expect(have('sample.docx'), isTrue);
    await smoke('sample.docx', PartKind.page);
  });

  test('large_sheet.xlsx opens and tiles', () async {
    expect(have('large_sheet.xlsx'), isTrue);
    await smoke('large_sheet.xlsx', PartKind.sheet);
  });

  test('sample_deck.pptx opens and tiles', () async {
    expect(have('sample_deck.pptx'), isTrue);
    await smoke('sample_deck.pptx', PartKind.slide);
  });
}
