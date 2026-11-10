import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// M0 proofs: FontLoader measure, PictureRecorder→RGBA tile, isolate strategy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FontLoader registers Liberation Sans and Paragraph measures', () async {
    final data = await rootBundle.load('fonts/LiberationSans-Regular.ttf');
    final loader = FontLoader('SpikeLiberationSans')
      ..addFont(Future.value(data));
    await loader.load();

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: 'SpikeLiberationSans', fontSize: 12),
    )..addText('Hello Office Viewer');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 200));

    expect(paragraph.maxIntrinsicWidth, greaterThan(10));
    expect(paragraph.height, greaterThan(8));
  });

  test('PictureRecorder display list paints RGBA tile for TileRequest-like region',
      () async {
    const region = ui.Rect.fromLTWH(0, 0, 256, 256);
    const scale = 2.0;
    final width = (region.width * scale).round();
    final height = (region.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      region,
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    canvas.drawCircle(
      const ui.Offset(128, 128),
      40,
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    expect(byteData, isNotNull);
    final rgba = byteData!.buffer.asUint8List();
    expect(rgba.length, width * height * 4);
    // Center-ish pixel should be green-ish from the circle.
    final cx = width ~/ 2;
    final cy = height ~/ 2;
    final i = (cy * width + cx) * 4;
    expect(rgba[i + 1], greaterThan(200)); // G
  });

  test('Background isolate can parse bytes; UI isolate must paint/measure',
      () async {
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final parsed = await Isolate.run(() {
      // Pure Dart work is fine off-UI.
      var sum = 0;
      for (final b in bytes) {
        sum += b;
      }
      return sum;
    });
    expect(parsed, greaterThan(0));

    // dart:ui ParagraphBuilder is not safely usable in a plain background
    // isolate without RootIsolateToken + init; prove UI-isolate path works.
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 14),
    )..addText('ui-isolate');
    final p = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 100));
    expect(p.height, greaterThan(0));
  });
}
