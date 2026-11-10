import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_layout.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';

void main() {
  test('slide 4 table applies header + banded row fills', () async {
    final bytes =
        await File('../../example_app/assets/sample_deck.pptx').readAsBytes();
    final doc = await const PptxParser().parse(PackageReader.open(bytes));
    final table = doc.slides[3].shapes.whereType<PptxTable>().single;
    expect(table.firstRow, isTrue);
    expect(table.bandRow, isTrue);

    final theme = OfficeTheme(
      colorScheme: ThemeColorScheme.parse(doc.theme.themeXml!),
      fontScheme: ThemeFontScheme.parse(doc.theme.themeXml!),
    );
    final dl = const PptxLayout().layout(doc.slides[3], theme);
    final fills = dl.ops.whereType<FillRectOp>().map((f) => f.color).toSet();
    // header accent + band tint + white (+ slide bg)
    expect(fills.length, greaterThanOrEqualTo(3));
    expect(fills.contains(theme.colorScheme.accent1), isTrue);
  });
}
