import 'dart:math' as math;
import 'dart:ui';

/// Hard limits for a phone-first Office *viewer* (no edit / search / print).
///
/// Keep native LO and Flutter tile memory predictable on mid-range devices.
abstract final class OfficeViewerLimits {
  /// Max tiles mounted for one part at a time (sheets use viewport cull).
  static const int maxMountedTiles = 24;

  /// Cap device-pixel canvas edge for a single paintTile call.
  static const int maxPaintPx = 1024;

  /// Sheets: never ask LOK for a canvas larger than this (per side).
  static const int maxSheetPaintPx = 768;

  /// Probe at most this many parts for size/name (huge PDFs / decks).
  static const int maxPartProbe = 48;

  /// Soft-cap reported sheet extent so tile grids stay finite.
  /// Content beyond remains in the LO model but is not scrolled/painted.
  static const double maxSheetExtentPoints = 24000;

  /// Default open size guard (~50 MB) — enough for typical office files.
  static const int defaultMaxBytes = 50 * 1024 * 1024;

  /// Read-only + macros-off options for LOK `documentLoadWithOptions`.
  static const String lokLoadOptions =
      '{"ReadOnly":{"type":"boolean","value":"true"},'
      '"MacroExecutionMode":{"type":"long","value":"0"}}';
}

/// Compute tile rectangles to mount for [partSize].
///
/// When [cullToViewport] is true and [visible] is set, only overlapping tiles
/// are returned (row-major, capped at [maxMounted]).
List<Rect> computeMountedTileRegions({
  required Size partSize,
  required double tilePoints,
  required bool cullToViewport,
  Rect? visible,
  int maxMounted = OfficeViewerLimits.maxMountedTiles,
}) {
  final tp = tilePoints;
  final cols = (partSize.width / tp).ceil().clamp(1, 512);
  final rows = (partSize.height / tp).ceil().clamp(1, 512);

  if (cullToViewport && visible != null) {
    final c0 = math.max(0, (visible.left / tp).floor());
    final r0 = math.max(0, (visible.top / tp).floor());
    // ceil(edge/tp)-1 so we don't mount a tile that only touches the edge.
    final c1 = math.min(cols - 1, math.max(c0, (visible.right / tp).ceil() - 1));
    final r1 = math.min(rows - 1, math.max(r0, (visible.bottom / tp).ceil() - 1));
    final out = <Rect>[];
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        out.add(Rect.fromLTWH(c * tp, r * tp, tp, tp));
        if (out.length >= maxMounted) return out;
      }
    }
    return out;
  }

  // Non-culled (pages/slides): mount a bounded top-left window only when huge.
  if (cols * rows > maxMounted) {
    final showCols = math.min(cols, 8);
    final showRows = math.min(rows, math.max(1, maxMounted ~/ showCols));
    final out = <Rect>[];
    for (var r = 0; r < showRows; r++) {
      for (var c = 0; c < showCols; c++) {
        out.add(Rect.fromLTWH(c * tp, r * tp, tp, tp));
      }
    }
    return out;
  }

  final out = <Rect>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      out.add(Rect.fromLTWH(c * tp, r * tp, tp, tp));
    }
  }
  return out;
}


/// Clip a full grid [region] so it does not extend past [partSize].
///
/// Tile grids emit full [tilePoints] cells; the last column/row may be shorter.
/// Engines and layout must use the clipped rect so bitmaps match the
/// [Positioned] box (avoids [BoxFit.fill] right-edge stretch on PDF).
Rect clipTileRegionToPart(Rect region, Size partSize) {
  final right = math.min(region.right, partSize.width);
  final bottom = math.min(region.bottom, partSize.height);
  if (right <= region.left || bottom <= region.top) {
    return Rect.fromLTWH(region.left, region.top, 0, 0);
  }
  return Rect.fromLTRB(region.left, region.top, right, bottom);
}

/// Layout size for a (possibly already clipped) tile [region] at [scale].
Size clampedTileLayoutSize({
  required Rect region,
  required Size partSize,
  required double tilePoints,
  required double scale,
}) {
  final clipped = clipTileRegionToPart(region, partSize);
  return Size(clipped.width * scale, clipped.height * scale);
}

Size clampSheetExtent(Size size) {
  return Size(
    math.min(size.width, OfficeViewerLimits.maxSheetExtentPoints),
    math.min(size.height, OfficeViewerLimits.maxSheetExtentPoints),
  );
}
