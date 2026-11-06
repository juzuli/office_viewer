import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/src/viewer_limits.dart';

void main() {
  test('sheet cull mounts only overlapping tiles', () {
    final regions = computeMountedTileRegions(
      partSize: const Size(10000, 20000),
      tilePoints: 256,
      cullToViewport: true,
      visible: const Rect.fromLTWH(0, 0, 800, 600),
      maxMounted: 24,
    );
    expect(regions, isNotEmpty);
    expect(regions.length, lessThanOrEqualTo(24));
    expect(regions.every((r) => r.overlaps(const Rect.fromLTWH(0, 0, 800, 600))),
        isTrue);
  });

  test('huge non-culled part mounts a bounded window', () {
    final regions = computeMountedTileRegions(
      partSize: const Size(8000, 8000),
      tilePoints: 256,
      cullToViewport: false,
      maxMounted: 24,
    );
    expect(regions.length, lessThanOrEqualTo(24));
  });

  test('clampSheetExtent caps runaway used-area', () {
    final s = clampSheetExtent(const Size(1e6, 1e6));
    expect(s.width, OfficeViewerLimits.maxSheetExtentPoints);
    expect(s.height, OfficeViewerLimits.maxSheetExtentPoints);
  });

  test('clipTileRegionToPart shrinks last-column / last-row cells', () {
    // Letter page 612×792 with 256pt tiles → last column is 100pt wide.
    final lastCol = clipTileRegionToPart(
      const Rect.fromLTWH(512, 0, 256, 256),
      const Size(612, 792),
    );
    expect(lastCol, const Rect.fromLTWH(512, 0, 100, 256));

    final lastRow = clipTileRegionToPart(
      const Rect.fromLTWH(0, 768, 256, 256),
      const Size(612, 792),
    );
    expect(lastRow, const Rect.fromLTWH(0, 768, 256, 24));

    final full = clipTileRegionToPart(
      const Rect.fromLTWH(0, 0, 256, 256),
      const Size(612, 792),
    );
    expect(full, const Rect.fromLTWH(0, 0, 256, 256));
  });

  test('clampedTileLayoutSize scales clipped content', () {
    final layout = clampedTileLayoutSize(
      region: const Rect.fromLTWH(512, 0, 256, 256),
      partSize: const Size(612, 792),
      tilePoints: 256,
      scale: 2,
    );
    expect(layout, const Size(200, 512));
  });
}
