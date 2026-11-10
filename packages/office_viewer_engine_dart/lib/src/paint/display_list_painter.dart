import 'dart:ui';

import '../fonts/font_registry.dart';
import '../model/display_list.dart';

class DisplayListPainter {
  const DisplayListPainter();

  static void paint(Canvas canvas, DisplayList list) {
    final painter = DisplayListPainter();
    painter._paint(canvas, list);
  }

  void _paint(Canvas canvas, DisplayList list) {
    for (final op in list.ops) {
      switch (op) {
        case FillRectOp(:final rect, :final color):
          final paint = Paint()..color = color;
          canvas.drawRect(rect, paint);
        case StrokePathOp(:final path, :final color, :final strokeWidth):
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth;
          canvas.drawPath(path, paint);
        case FillPathOp(:final path, :final color):
          final paint = Paint()..color = color;
          canvas.drawPath(path, paint);
        case DrawParagraphOp(:final offset, :final paragraph):
          canvas.drawParagraph(paragraph, offset);
        case DrawTextRawOp(
            :final text,
            :final box,
            :final fontFamily,
            :final fontSizePt,
            :final bold,
            :final italic,
            :final color,
            :final align,
            :final maxLines,
            :final underline,
          ):
          final paragraph = _buildParagraph(
            text: text,
            fontFamily: fontFamily,
            fontSize: fontSizePt,
            bold: bold,
            italic: italic,
            color: color,
            align: align,
            maxWidth: box.width,
            maxLines: maxLines,
            underline: underline,
          );
          canvas.drawParagraph(paragraph, Offset(box.left, box.top));
        case DrawImageOp(:final rect, :final image, :final opacity):
          final paint = Paint()..color = Color.fromRGBO(255, 255, 255, opacity);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            rect,
            paint,
          );
        case DrawImageBytesOp(:final rect):
          // Prefer TileRenderer resolving bytes → DrawImageOp first.
          canvas.drawRect(rect, Paint()..color = const Color(0xFFE0E0E0));
        case PushClipOp(:final rect):
          canvas.save();
          canvas.clipRect(rect);
        case PopClipOp():
          canvas.restore();
        case PushTransformOp(:final matrix):
          canvas.save();
          canvas.transform(matrix);
        case PopTransformOp():
          canvas.restore();
        case PushOpacityOp(:final opacity):
          canvas.saveLayer(
            null,
            Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
          );
        case PopOpacityOp():
          canvas.restore();
      }
    }
  }

  static Paragraph _buildParagraph({
    required String text,
    required String fontFamily,
    required double fontSize,
    required bool bold,
    required bool italic,
    required Color color,
    required TextAlign align,
    required double maxWidth,
    int? maxLines,
    bool underline = false,
  }) {
    final family = FontRegistry.instance.familyFor(fontFamily);
    final builder = ParagraphBuilder(
      ParagraphStyle(
        textAlign: align,
        maxLines: maxLines,
        fontFamily: family,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    )
      ..pushStyle(
        TextStyle(
          color: color,
          fontFamily: family,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration:
              underline ? TextDecoration.underline : TextDecoration.none,
        ),
      )
      ..addText(text);

    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    return paragraph;
  }
}
