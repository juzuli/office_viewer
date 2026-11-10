import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/drawing/charts/chart_painter.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';

void main() {
  test('chart slide paints bars, axes labels, and legend', () async {
    final bytes =
        await File('test/fixtures/sample_deck.pptx').readAsBytes();
    final doc = await const PptxParser().parse(PackageReader.open(bytes));
    final chart = doc.slides[4].shapes.whereType<PptxChart>().single;
    final painted = const ChartPainter().paintCachedChart(
      chart.chartXml,
      size: const Size(400, 300),
    );
    final fills = painted.ops.whereType<FillRectOp>().length;
    final strokes = painted.ops.whereType<StrokePathOp>().length;
    final texts =
        painted.ops.whereType<DrawTextRawOp>().map((t) => t.text).toSet();

    expect(fills, greaterThan(2));
    expect(strokes, greaterThan(5)); // frame + axes + bar outlines + grid
    expect(texts.contains('Q1'), isTrue);
    expect(texts.contains('Product A'), isTrue);
    expect(texts.contains('Product B'), isTrue);
    expect(texts.any((t) => t.contains('no cached')), isFalse);
    // Data labels present (one of the known values).
    expect(texts.contains('19.2') || texts.contains('26.1'), isTrue);
  });
}
