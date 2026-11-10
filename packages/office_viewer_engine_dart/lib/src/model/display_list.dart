import 'dart:typed_data';
import 'dart:ui';

/// Immutable paint commands in document points.
sealed class DisplayOp {
  const DisplayOp();
}

class FillRectOp extends DisplayOp {
  const FillRectOp(this.rect, this.color);
  final Rect rect;
  final Color color;
}

class StrokePathOp extends DisplayOp {
  const StrokePathOp(this.path, this.color, this.strokeWidth);
  final Path path;
  final Color color;
  final double strokeWidth;
}

class FillPathOp extends DisplayOp {
  const FillPathOp(this.path, this.color);
  final Path path;
  final Color color;
}

class DrawParagraphOp extends DisplayOp {
  const DrawParagraphOp(this.offset, this.paragraph);
  final Offset offset;
  final Paragraph paragraph;
}

/// Text drawn at paint time (paragraph built from raw styling).
class DrawTextRawOp extends DisplayOp {
  const DrawTextRawOp({
    required this.text,
    required this.box,
    this.fontFamily = 'Liberation Sans',
    this.fontSizePt = 18,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = const Color(0xFF000000),
    this.align = TextAlign.left,
    this.maxLines,
  });

  final String text;
  final Rect box;
  final String fontFamily;
  final double fontSizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final Color color;
  final TextAlign align;
  final int? maxLines;

  FontWeight get fontWeight => bold ? FontWeight.w700 : FontWeight.w400;
}

class DrawImageOp extends DisplayOp {
  const DrawImageOp(this.rect, this.image, {this.opacity = 1.0});
  final Rect rect;
  final Image image;
  final double opacity;
}

/// Image bytes decoded at tile-render time (layout stays sync).
class DrawImageBytesOp extends DisplayOp {
  const DrawImageBytesOp(this.rect, this.bytes, {this.opacity = 1.0});
  final Rect rect;
  final Uint8List bytes;
  final double opacity;
}

class PushClipOp extends DisplayOp {
  const PushClipOp(this.rect);
  final Rect rect;
}

class PopClipOp extends DisplayOp {
  const PopClipOp();
}

class PushTransformOp extends DisplayOp {
  const PushTransformOp(this.matrix);
  final Float64List matrix;
}

class PopTransformOp extends DisplayOp {
  const PopTransformOp();
}

class PushOpacityOp extends DisplayOp {
  const PushOpacityOp(this.opacity);
  final double opacity;
}

class PopOpacityOp extends DisplayOp {
  const PopOpacityOp();
}

class DisplayList {
  const DisplayList({required this.ops, required this.size});

  final List<DisplayOp> ops;
  final Size size;

  static DisplayList blankWhite(Size size) => DisplayList(
        size: size,
        ops: [
          FillRectOp(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Color(0xFFFFFFFF),
          ),
        ],
      );
}
