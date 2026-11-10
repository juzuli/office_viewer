import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_inheritance.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_layout.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';

void main() {
  test('Project Goals nested levels indent and use en-dash bullets', () async {
    final bytes =
        await File('../../example_app/assets/sample_deck.pptx').readAsBytes();
    final doc = await const PptxParser().parse(PackageReader.open(bytes));
    final slide = const PptxInheritance().merge(doc.slides[2]);
    final body = slide.shapes.whereType<PptxShape>().firstWhere(
          (s) => s.placeholderType == 'body',
        );
    final paras = body.textBody!.paragraphs
        .where((p) => p.runs.any((r) => r.text.trim().isNotEmpty))
        .toList();

    expect(paras.map((p) => p.level).toList(), [0, 1, 1, 0, 1, 1]);
    expect(paras[0].bullet, '•');
    expect(paras[1].bullet, '–');
    expect(paras[1].style.indentLeftPt, greaterThan(paras[0].style.indentLeftPt));
    expect(paras[1].runs.first.style.fontSizePt,
        lessThan(paras[0].runs.first.style.fontSizePt));

    final theme = OfficeTheme(
      colorScheme: ThemeColorScheme.parse(doc.theme.themeXml!),
      fontScheme: ThemeFontScheme.parse(doc.theme.themeXml!),
    );
    final dl = const PptxLayout().layout(slide, theme, applyInheritance: false);
    final texts = dl.ops.whereType<DrawTextRawOp>().map((t) => t.text).toList();
    expect(texts.any((t) => t.startsWith('–')), isTrue);
    expect(texts.any((t) => t.startsWith('•')), isTrue);
  });
}
