import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_convert/office_viewer_engine_convert.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';
import 'package:office_viewer_engine_convert/src/bindings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixtures = Directory('test/fixtures');
  final haveNative = () {
    try {
      return OfficeOxideBindings.isAvailable;
    } on Object {
      return false;
    }
  }();

  group('LegacyConverter mapping', () {
    test('supports only doc/xls/ppt', () {
      expect(LegacyConverter.supports(OfficeFormat.doc), isTrue);
      expect(LegacyConverter.supports(OfficeFormat.xls), isTrue);
      expect(LegacyConverter.supports(OfficeFormat.ppt), isTrue);
      expect(LegacyConverter.supports(OfficeFormat.docx), isFalse);
      expect(LegacyConverter.supports(OfficeFormat.pdf), isFalse);
    });

    test('rejects non-OLE bytes', () async {
      if (!haveNative) {
        // ignore: avoid_print
        print('SKIP non-OLE reject — native lib unavailable');
        return;
      }
      final c = LegacyConverter();
      await expectLater(
        c.convert(
          Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          OfficeFormat.doc,
        ),
        throwsA(isA<UnsupportedFormatError>()),
      );
    });
  });

  group('ConvertOfficeEngine.supports', () {
    test('legacy only, not web', () {
      final e = ConvertOfficeEngine();
      expect(e.id, 'convert');
      expect(e.supports(OfficeFormat.doc), isTrue);
      expect(e.supports(OfficeFormat.xls), isTrue);
      expect(e.supports(OfficeFormat.ppt), isTrue);
      expect(e.supports(OfficeFormat.docx), isFalse);
      expect(e.supports(OfficeFormat.xlsx), isFalse);
    });
  });

  group('ConvertOfficeEngine.open messaging', () {
    test('iOS-style unavailable path is EngineUnavailableError', () async {
      // On macOS host this exercises the missing-native / convert failure
      // path only when bindings are absent; always verify registry no longer
      // needs supports=false to avoid "No engine supports".
      final e = ConvertOfficeEngine();
      expect(e.supports(OfficeFormat.doc), isTrue);
      if (haveNative) return;
      await expectLater(
        e.open(
          DocumentSource.bytes(
            Uint8List.fromList([
              0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
            ]),
            fileName: 'a.doc',
          ),
        ),
        throwsA(isA<EngineUnavailableError>()),
      );
    });
  });

  group('convert → Dart tiles', () {
    for (final entry in [
      ('sample.doc', OfficeFormat.doc, PartKind.page),
      ('sample.xls', OfficeFormat.xls, PartKind.sheet),
      ('sample.ppt', OfficeFormat.ppt, PartKind.slide),
    ]) {
      final (name, format, kind) = entry;
      test('$name converts and tiles', () async {
        if (!haveNative) {
          // ignore: avoid_print
          print('SKIP $name — native lib unavailable');
          return;
        }
        final file = File('${fixtures.path}/$name');
        expect(file.existsSync(), isTrue, reason: name);

        final engine = ConvertOfficeEngine(ooxmlEngine: DartOfficeEngine());
        final handle = await engine.open(
          DocumentSource.bytes(await file.readAsBytes(), fileName: name),
        );
        addTearDown(handle.close);

        expect(handle.parts, isNotEmpty);
        expect(handle.parts.first.kind, kind);

        final tile = await handle.renderTile(
          TileRequest(
            partIndex: 0,
            region: Rect.fromLTWH(
              0,
              0,
              handle.parts.first.size.width.clamp(1, 256),
              handle.parts.first.size.height.clamp(1, 256),
            ),
            scale: 1.0,
          ),
        );
        expect(tile.width, greaterThan(0));
        expect(tile.height, greaterThan(0));
        expect(tile.rgba.length, tile.width * tile.height * 4);
      });
    }
  });
}
