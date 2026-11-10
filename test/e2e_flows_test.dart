// Host-side flow specs for office_viewer (FakeOfficeEngine).
// Device cases stay manual / log-driven — see replica/test-plan.md.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';

void main() {
  late OfficeEngineRegistry reg;

  setUp(() {
    reg = OfficeEngineRegistry.instance
      ..clear()
      ..register(FakeOfficeEngine(partCount: 3, kind: PartKind.slide));
  });

  tearDown(() {
    OfficeEngineRegistry.instance.clear();
  });

  group('F05 part switch', () {
    test('F05-H2 goToPart updates currentPart', () async {
      final c = OfficeDocumentController(registry: reg);
      await c.load(const DocumentSource.file('deck.pptx'));
      expect(c.state, OfficeLoadState.ready);
      expect(c.parts.length, 3);
      c.goToPart(2);
      expect(c.currentPart, 2);
      c.dispose();
    });

    test('F05-E1 goToPart same / OOB is a no-op', () async {
      final c = OfficeDocumentController(registry: reg);
      await c.load(const DocumentSource.file('deck.pptx'));
      c.goToPart(1);
      c.goToPart(1);
      expect(c.currentPart, 1);
      c.goToPart(-1);
      expect(c.currentPart, 1);
      c.goToPart(99);
      expect(c.currentPart, 1);
      c.dispose();
    });

    test('F05-H3 scroll sync updates part without chrome flag loop', () async {
      final c = OfficeDocumentController(registry: reg);
      await c.load(const DocumentSource.file('deck.pptx'));
      c.syncPartFromScroll(2);
      expect(c.currentPart, 2);
      expect(c.takePartSyncFromScroll(), isTrue);
      expect(c.takePartSyncFromScroll(), isFalse);
      c.dispose();
    });
  });

  group('F03 zoom', () {
    test('F03-H1 setZoom updates value', () {
      final c = OfficeDocumentController(registry: reg);
      c.setZoom(1.5);
      expect(c.zoom, 1.5);
      expect(c.tileZoom, 1.5);
      c.setZoom(1.25);
      expect(c.zoom, 1.25);
      c.dispose();
    });

    test('F03-E1 zoom clamps to minZoom..maxZoom (fit-width default)', () {
      final c = OfficeDocumentController(registry: reg);
      c.setZoom(99);
      expect(c.zoom, 5.0);
      c.setZoom(0.01);
      expect(c.zoom, 1.0); // default minZoom = fit width
      c.dispose();
    });

    test('F03-H3 pan/zoom locks via controller options', () {
      final c = OfficeDocumentController(
        registry: reg,
        viewOptions: const OfficeViewOptions(zoomEnabled: false),
      );
      expect(c.viewOptions.zoomEnabled, isFalse);
      expect(c.viewOptions.panEnabled, isTrue);
      c.lockPan();
      expect(c.viewOptions.panEnabled, isFalse);
      c.setInteraction(panEnabled: true, zoomEnabled: true);
      expect(c.viewOptions.panEnabled, isTrue);
      expect(c.viewOptions.zoomEnabled, isTrue);
      // Programmatic zoom still works while gestures would be locked.
      c.lockZoom();
      c.setZoom(2.0);
      expect(c.tileZoom, 2.0);
      c.dispose();
    });

    test('F03-H2 pinch preview does not change tileZoom until commit', () {
      final c = OfficeDocumentController(registry: reg);
      c.setZoom(1.0);
      c.previewZoom(2.0);
      expect(c.zoom, 2.0);
      expect(c.tileZoom, 1.0);
      expect(c.isZoomGestureActive, isTrue);
      c.commitZoomPreview();
      expect(c.tileZoom, 2.0);
      expect(c.isZoomGestureActive, isFalse);
      c.dispose();
    });

    test('F03-E2 load resets zoom', () async {
      final c = OfficeDocumentController(registry: reg);
      c.setZoom(2.5);
      await c.load(const DocumentSource.file('report.docx'));
      expect(c.zoom, 1.0);
      expect(c.tileZoom, 1.0);
      c.dispose();
    });
  });

  group('F02 / F04 negatives', () {
    test('F02-N1 unsupported format fails typed', () async {
      final c = OfficeDocumentController(registry: reg);
      await c.load(const DocumentSource.file('mystery.bin'));
      expect(c.state, OfficeLoadState.failed);
      expect(c.error, isA<UnsupportedFormatError>());
      c.dispose();
    });
  });

  group('F07 / F08', () {
    test('F07-H1 registry picks first supporting engine', () {
      reg.clear();
      reg.register(FakeOfficeEngine());
      expect(reg.pick(OfficeFormat.docx).id, 'fake');
    });

    test('F08-E1 dispose mid-load does not throw', () async {
      final c = OfficeDocumentController(registry: reg);
      final future = c.load(const DocumentSource.file('report.docx'));
      c.dispose();
      await future;
      expect(c.state, anyOf(OfficeLoadState.loading, OfficeLoadState.ready, OfficeLoadState.idle));
    });
  });

  test('F01-H1-ish fake tile length (smoke)', () async {
    final h = await FakeOfficeEngine().open(const DocumentSource.file('a.docx'));
    final t = await h.renderTile(const TileRequest(
      partIndex: 0,
      region: Rect.fromLTWH(0, 0, 256, 256),
      scale: 1,
    ));
    expect(t.rgba.length, 256 * 256 * 4);
    await h.close();
  });
}
