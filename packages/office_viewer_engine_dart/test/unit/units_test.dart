import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/xml/units.dart';

void main() {
  test('EMU / twip / half-point conversions', () {
    expect(emuToPt(914400), closeTo(72, 1e-9));
    expect(emuToPt(12700), closeTo(1, 1e-9));
    expect(ptToEmu(1), closeTo(12700, 1e-6));
    expect(twipToPt(1440), closeTo(72, 1e-9));
    expect(twipToPt(20), closeTo(1, 1e-9));
    expect(halfPointToPt(24), 12);
    expect(eighthPointToPt(8), 1);
    expect(percent1000(100000), 100);
    expect(angle60000(5400000), 90);
  });
}
