import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';
import 'package:office_viewer_engine_dart/src/engine/dart_document_handle.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samplesDir = Directory(
    '${Directory.current.path}/../../example_app/assets',
  );

  Future<DartDocumentHandle> open(String name) async {
    final bytes = await File('${samplesDir.path}/$name').readAsBytes();
    return await DartOfficeEngine().open(
      DocumentSource.bytes(bytes, fileName: name),
    ) as DartDocumentHandle;
  }

  int nonWhite(RenderedTile tile) {
    var n = 0;
    final rgba = tile.rgba;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i] != 255 || rgba[i + 1] != 255 || rgba[i + 2] != 255) n++;
    }
    return n;
  }

  test('sample.docx has contentful display list and non-white tile', () async {
    final h = await open('sample.docx');
    expect(h.parts.length, greaterThanOrEqualTo(1));
    final dl = h.displayLists.first!;
    final textOps = dl.ops.whereType<DrawTextRawOp>().length;
    // ignore: avoid_print
    print('docx pages=${h.parts.length} ops=${dl.ops.length} textOps=$textOps '
        'size=${h.parts.first.size}');
    expect(dl.ops.length, greaterThan(1));
    expect(textOps, greaterThan(0));
    final tile = await h.renderTile(
      TileRequest(
        partIndex: 0,
        region: const Rect.fromLTWH(0, 0, 200, 200),
        scale: 1,
      ),
    );
    expect(nonWhite(tile), greaterThan(0));
    await h.close();
  });

  test('large_sheet.xlsx has cells painted', () async {
    final h = await open('large_sheet.xlsx');
    expect(h.parts.first.kind, PartKind.sheet);
    final dl = h.displayLists.first!;
    // ignore: avoid_print
    print('xlsx parts=${h.parts.length} ops=${dl.ops.length} '
        'size=${h.parts.first.size}');
    expect(dl.ops.length, greaterThan(1));
    final tile = await h.renderTile(
      TileRequest(
        partIndex: 0,
        region: const Rect.fromLTWH(0, 0, 200, 200),
        scale: 1,
      ),
    );
    expect(nonWhite(tile), greaterThan(0));
    await h.close();
  });

  test('sample_deck.pptx has shapes/text on slide 1', () async {
    final h = await open('sample_deck.pptx');
    expect(h.parts.first.kind, PartKind.slide);
    final dl = h.displayLists.first!;
    final textOps = dl.ops.whereType<DrawTextRawOp>().length;
    // ignore: avoid_print
    print('pptx slides=${h.parts.length} ops=${dl.ops.length} textOps=$textOps '
        'size=${h.parts.first.size}');
    expect(h.parts.length, greaterThanOrEqualTo(1));
    expect(dl.ops.length, greaterThan(1));
    // Title sits mid-slide after layout inheritance; sample that band.
    final tile = await h.renderTile(
      TileRequest(
        partIndex: 0,
        region: const Rect.fromLTWH(40, 150, 400, 220),
        scale: 1,
      ),
    );
    expect(nonWhite(tile), greaterThan(0));
    await h.close();
  });
}
