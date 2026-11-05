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
}
