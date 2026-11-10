import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/drawing/charts/chart_painter.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';

void main() {
  test('honors sparse pt idx order for categories and values', () {
    const xml = '''
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <c:chart><c:plotArea>
    <c:barChart>
      <c:ser>
        <c:tx><c:v>S1</c:v></c:tx>
        <c:cat><c:strRef><c:strCache>
          <c:pt idx="2"><c:v>C</c:v></c:pt>
          <c:pt idx="0"><c:v>A</c:v></c:pt>
          <c:pt idx="1"><c:v>B</c:v></c:pt>
        </c:strCache></c:strRef></c:cat>
        <c:val><c:numRef><c:numCache>
          <c:pt idx="2"><c:v>30</c:v></c:pt>
          <c:pt idx="0"><c:v>10</c:v></c:pt>
          <c:pt idx="1"><c:v>20</c:v></c:pt>
        </c:numCache></c:numRef></c:val>
      </c:ser>
      <c:axId val="1"/><c:axId val="2"/>
    </c:barChart>
    <c:catAx><c:axId val="1"/></c:catAx>
    <c:valAx><c:axId val="2"/></c:valAx>
  </c:plotArea></c:chart>
</c:chartSpace>
''';
    final painted = const ChartPainter().paintCachedChart(
      xml,
      size: const Size(320, 220),
    );
    final texts =
        painted.ops.whereType<DrawTextRawOp>().map((t) => t.text).toList();
    expect(texts.contains('A'), isTrue);
    expect(texts.contains('B'), isTrue);
    expect(texts.contains('C'), isTrue);
    // Data labels in category order after idx sorting.
    final labels = texts.where((t) => t == '10' || t == '20' || t == '30').toList();
    expect(labels, ['10', '20', '30']);
  });

  test('legendPos r places legend to the right of the plot', () {
    const xml = '''
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <c:chart>
    <c:plotArea>
      <c:barChart>
        <c:ser>
          <c:tx><c:v>Revenue</c:v></c:tx>
          <c:cat><c:strRef><c:strCache>
            <c:pt idx="0"><c:v>Jan</c:v></c:pt>
          </c:strCache></c:strRef></c:cat>
          <c:val><c:numRef><c:numCache>
            <c:pt idx="0"><c:v>42</c:v></c:pt>
          </c:numCache></c:numRef></c:val>
        </c:ser>
        <c:axId val="1"/><c:axId val="2"/>
      </c:barChart>
      <c:catAx><c:axId val="1"/></c:catAx>
      <c:valAx><c:axId val="2"/></c:valAx>
    </c:plotArea>
    <c:legend><c:legendPos val="r"/></c:legend>
  </c:chart>
</c:chartSpace>
''';
    const size = Size(400, 240);
    final painted = const ChartPainter().paintCachedChart(xml, size: size);
    final legend = painted.ops
        .whereType<DrawTextRawOp>()
        .where((t) => t.text == 'Revenue')
        .toList();
    expect(legend, isNotEmpty);
    expect(legend.first.box.left, greaterThan(size.width * 0.55));
  });

  test('negative values produce tick labels below zero', () {
    const xml = '''
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">
  <c:chart><c:plotArea>
    <c:barChart>
      <c:ser>
        <c:tx><c:v>S</c:v></c:tx>
        <c:cat><c:strRef><c:strCache>
          <c:pt idx="0"><c:v>A</c:v></c:pt>
          <c:pt idx="1"><c:v>B</c:v></c:pt>
        </c:strCache></c:strRef></c:cat>
        <c:val><c:numRef><c:numCache>
          <c:pt idx="0"><c:v>10</c:v></c:pt>
          <c:pt idx="1"><c:v>-8</c:v></c:pt>
        </c:numCache></c:numRef></c:val>
      </c:ser>
      <c:axId val="1"/><c:axId val="2"/>
    </c:barChart>
    <c:catAx><c:axId val="1"/></c:catAx>
    <c:valAx><c:axId val="2"/></c:valAx>
  </c:plotArea></c:chart>
</c:chartSpace>
''';
    final painted = const ChartPainter().paintCachedChart(
      xml,
      size: const Size(300, 220),
    );
    final texts =
        painted.ops.whereType<DrawTextRawOp>().map((t) => t.text).toSet();
    expect(texts.any((t) => t.startsWith('-')), isTrue);
    expect(texts.contains('-8') || texts.contains('10'), isTrue);
  });
}
