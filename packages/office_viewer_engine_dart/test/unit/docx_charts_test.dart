import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/docx/docx_layout.dart';
import 'package:office_viewer_engine_dart/src/docx/docx_model.dart';
import 'package:office_viewer_engine_dart/src/docx/docx_parser.dart';
import 'package:office_viewer_engine_dart/src/drawing/charts/chart_painter.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';

void main() {
  test('sample_chart.docx parses chart with axis titles and right-side legend',
      () async {
    final bytes =
        await File('test/fixtures/sample_chart.docx').readAsBytes();
    final doc = const DocxParser().parse(PackageReader.open(bytes));

    final charts = <DocChart>[];
    void collect(List<DocBodyBlock> blocks) {
      for (final b in blocks) {
        if (b is DocParagraph) {
          for (final r in b.runs) {
            if (r.chart != null) charts.add(r.chart!);
          }
        } else if (b is DocTable) {
          for (final row in b.rows) {
            for (final cell in row.cells) {
              collect(cell.blocks);
            }
          }
        }
      }
    }

    collect(doc.body);
    expect(charts, isNotEmpty, reason: doc.warnings.join('; '));

    final chart = charts.first;
    expect(chart.widthPt, greaterThan(100));
    expect(chart.heightPt, greaterThan(80));

    final painted = const ChartPainter().paintCachedChart(
      chart.chartXml,
      size: Size(chart.widthPt, chart.heightPt),
    );
    final texts =
        painted.ops.whereType<DrawTextRawOp>().map((t) => t.text).toSet();

    expect(texts.contains('Revenue vs. Cost'), isTrue);
    expect(texts.contains('Month'), isTrue);
    expect(texts.contains('USD thousands'), isTrue);
    expect(texts.contains('Revenue'), isTrue);
    expect(texts.contains('Cost'), isTrue);
    expect(texts.any((t) => t.contains('no cached')), isFalse);

    // Axis titles force right-side legend: labels sit to the right of the plot.
    final legendOps = painted.ops.whereType<DrawTextRawOp>().where(
          (t) => t.text == 'Revenue' || t.text == 'Cost',
        );
    expect(legendOps, isNotEmpty);
    expect(
      legendOps.every((t) => t.box.left > chart.widthPt * 0.55),
      isTrue,
    );

    final pages = const DocxLayout().layout(doc);
    expect(pages, isNotEmpty);
    final pageTexts = pages
        .expand((p) => p.ops.whereType<DrawTextRawOp>())
        .map((t) => t.text)
        .toSet();
    expect(pageTexts.contains('Month'), isTrue);
    expect(pageTexts.contains('USD thousands'), isTrue);
    expect(pageTexts.contains('Embedded chart'), isTrue);
  });
}
