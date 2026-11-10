import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_inheritance.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_layout.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';

/// Regression for Office Oxide convert PPTX: CR-joined multilevel body text and
/// literal `*` paragraphs must not overlap or become `•  *`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final converted = File('../../tool/legacy_convert_spike/out/sample.pptx');

  test('converted sample.pptx splits CR levels and avoids invented bullets',
      () async {
    expect(converted.existsSync(), isTrue,
        reason: 'run convert spike first for sample.pptx');

    final doc = await const PptxParser().parse(
      PackageReader.open(await converted.readAsBytes()),
    );
    expect(doc.slides, isNotEmpty);
    expect(doc.slides.first.masterStyles.parsedBodyStyle, isFalse);

    final slide = const PptxInheritance().merge(doc.slides.first);
    final body = slide.shapes.whereType<PptxShape>().firstWhere(
          (s) =>
              s.textBody != null &&
              s.textBody!.paragraphs.any(
                (p) => p.runs.any((r) => r.text.contains('Master text')),
              ),
        );

    final paras = body.textBody!.paragraphs
        .where((p) => p.runs.any((r) => r.text.trim().isNotEmpty))
        .toList();

    // CR levels become separate paragraphs (styles / Second / Third / …).
    expect(
      paras.where((p) => p.runs.any((r) => r.text.contains('Second level'))),
      isNotEmpty,
    );
    expect(
      paras.where((p) => p.runs.any((r) => r.text.contains('Third level'))),
      isNotEmpty,
    );

    // Empty master must not invent bullets (especially not on literal "*").
    for (final p in paras) {
      expect(p.bullet, isNull, reason: p.runs.map((r) => r.text).join());
    }

    final themeXml = doc.theme.themeXml ?? '';
    final theme = OfficeTheme(
      colorScheme: themeXml.isEmpty
          ? ThemeColorScheme.defaults
          : ThemeColorScheme.parse(themeXml),
      fontScheme: themeXml.isEmpty
          ? ThemeFontScheme.defaults
          : ThemeFontScheme.parse(themeXml),
    );
    final dl = const PptxLayout().layout(slide, theme, applyInheritance: false);
    final texts = dl.ops.whereType<DrawTextRawOp>().map((t) => t.text).toList();

    expect(texts.any((t) => t.contains('\r')), isFalse);
    expect(texts.any((t) => t.startsWith('•  *')), isFalse);
    expect(texts.where((t) => t.trim() == '*').length, greaterThanOrEqualTo(1));

    // Visual lines must not share the same Y (overlap regression).
    final boxes = dl.ops.whereType<DrawTextRawOp>().toList();
    for (var i = 1; i < boxes.length; i++) {
      if (boxes[i].box.top == boxes[i - 1].box.top &&
          boxes[i].box.left == boxes[i - 1].box.left) {
        fail(
          'overlapping text at y=${boxes[i].box.top}: '
          '"${boxes[i - 1].text}" / "${boxes[i].text}"',
        );
      }
    }
  });
}
