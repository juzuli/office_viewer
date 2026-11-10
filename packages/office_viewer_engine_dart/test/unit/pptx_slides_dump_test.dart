import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/opc/package_reader.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_parser.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_inheritance.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_ir.dart';
import 'package:office_viewer_engine_dart/src/pptx/pptx_layout.dart';
import 'package:office_viewer_engine_dart/src/theme/theme.dart';
import 'package:office_viewer_engine_dart/src/model/display_list.dart';

void main() {
  test('dump slides', () async {
    final bytes = await File('../../example_app/assets/sample_deck.pptx').readAsBytes();
    final doc = await const PptxParser().parse(PackageReader.open(bytes));
    final theme = OfficeTheme(
      colorScheme: doc.theme.themeXml != null
          ? ThemeColorScheme.parse(doc.theme.themeXml!)
          : ThemeColorScheme.defaults,
      fontScheme: doc.theme.themeXml != null
          ? ThemeFontScheme.parse(doc.theme.themeXml!)
          : ThemeFontScheme.defaults,
    );
    for (var i = 0; i < doc.slides.length; i++) {
      final raw = doc.slides[i];
      final slide = const PptxInheritance().merge(raw);
      print('--- slide $i shapes=${slide.shapes.length} layout=${slide.layoutPartPath}');
      for (final n in slide.shapes) {
        if (n is PptxShape) {
          final texts = n.textBody?.paragraphs
                  .map((p) => p.runs.map((r) => r.text).join())
                  .where((t) => t.trim().isNotEmpty)
                  .toList() ??
              [];
          final st = n.textBody?.paragraphs.isNotEmpty == true &&
                  n.textBody!.paragraphs.first.runs.isNotEmpty
              ? n.textBody!.paragraphs.first.runs.first.style
              : null;
          print(
              '  shape ph=${n.placeholderType}/${n.placeholderIdx} '
              't=${n.transform.x.toStringAsFixed(1)},${n.transform.y.toStringAsFixed(1)},'
              '${n.transform.width.toStringAsFixed(1)}x${n.transform.height.toStringAsFixed(1)} '
              'size=${st?.fontSizePt} bold=${st?.bold} fam=${st?.fontFamily} '
              'paras=${texts.length} "${texts.take(2).join(" | ")}"');
        } else {
          print('  other ${n.runtimeType}');
        }
      }
      final dl = const PptxLayout().layout(slide, theme, applyInheritance: false);
      final texts = dl.ops.whereType<DrawTextRawOp>().length;
      print('  displayList ops=${dl.ops.length} textOps=$texts');
    }
  });
}
