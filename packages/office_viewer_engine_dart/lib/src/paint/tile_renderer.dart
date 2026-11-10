import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:office_viewer/office_viewer.dart';

import '../model/display_list.dart';
import 'display_list_painter.dart';

class TileRenderer {
  TileRenderer({Map<int, ui.Image>? imageCache})
      : _imageCache = imageCache ?? {};

  final Map<int, ui.Image> _imageCache;

  Future<RenderedTile> render(
    DisplayList list,
    ui.Rect region,
    double scale,
  ) async {
    final resolved = await _resolveImageBytes(list);
    final s = scale.clamp(0.05, 4.0);
    final w = math.max(1, (region.width * s).ceil());
    final h = math.max(1, (region.height * s).ceil());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.scale(s);
    canvas.translate(-region.left, -region.top);
    DisplayListPainter.paint(canvas, resolved);

    final picture = recorder.endRecording();
  ui.Image? image;
    try {
      image = await picture.toImage(w, h);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (byteData == null) {
        return RenderedTile(rgba: _emptyRgba, width: 1, height: 1);
      }
      final straight = byteData.buffer.asUint8List();
      final premul = _straightToPremul(straight);
      return RenderedTile(rgba: premul, width: w, height: h);
    } finally {
      picture.dispose();
      image?.dispose();
    }
  }

  static Uint8List _straightToPremul(Uint8List rgba) {
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a == 255) {
        out[i] = rgba[i];
        out[i + 1] = rgba[i + 1];
        out[i + 2] = rgba[i + 2];
        out[i + 3] = 255;
      } else if (a == 0) {
        out[i] = 0;
        out[i + 1] = 0;
        out[i + 2] = 0;
        out[i + 3] = 0;
      } else {
        final af = a / 255.0;
        out[i] = (rgba[i] * af).round().clamp(0, 255);
        out[i + 1] = (rgba[i + 1] * af).round().clamp(0, 255);
        out[i + 2] = (rgba[i + 2] * af).round().clamp(0, 255);
        out[i + 3] = a;
      }
    }
    return out;
  }

  Future<DisplayList> _resolveImageBytes(DisplayList list) async {
    var changed = false;
    final ops = <DisplayOp>[];
    for (final op in list.ops) {
      if (op is DrawImageBytesOp) {
        changed = true;
        final key = Object.hash(op.bytes.length, op.bytes.isEmpty ? 0 : op.bytes[0],
            op.bytes.length > 1 ? op.bytes[1] : 0, op.rect);
        var image = _imageCache[key];
        if (image == null) {
          try {
            final codec = await ui.instantiateImageCodec(op.bytes);
            final frame = await codec.getNextFrame();
            image = frame.image;
            _imageCache[key] = image;
          } catch (_) {
            image = null;
          }
        }
        if (image != null) {
          ops.add(DrawImageOp(op.rect, image, opacity: op.opacity));
        } else {
          ops.add(FillRectOp(op.rect, const ui.Color(0xFFE0E0E0)));
        }
      } else {
        ops.add(op);
      }
    }
    if (!changed) return list;
    return DisplayList(ops: ops, size: list.size);
  }

  static final Uint8List _emptyRgba = Uint8List.fromList([255, 255, 255, 255]);
}
