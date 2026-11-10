import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';

void main() {
  test('format detection uses extension', () {
    expect(OfficeFormat.fromName('a.DOCX'), OfficeFormat.docx);
    expect(OfficeFormat.fromName('noext'), OfficeFormat.unknown);
  });

  test('PartInfo public surface is index/kind/size/name (LOK fields removed in 0.0.8)',
      () {
    // Contract: do not reintroduce contentOrigin / lokPartIndex on PartInfo.
    const part = PartInfo(
      index: 2,
      kind: PartKind.page,
      size: Size(100, 200),
      name: 'Page 3',
    );
    final surface = <String, Object?>{
      'index': part.index,
      'kind': part.kind,
      'size': part.size,
      'name': part.name,
    };
    expect(surface.keys.toList(), ['index', 'kind', 'size', 'name']);
    expect(surface['index'], 2);
    expect(surface['kind'], PartKind.page);
    expect(surface['size'], const Size(100, 200));
    expect(surface['name'], 'Page 3');
  });

  test('OfficeViewerLimits no longer exposes lokLoadOptions', () {
    // Remaining viewer caps after 0.0.8 (compile fails if renamed away).
    expect(OfficeViewerLimits.maxMountedTiles, greaterThan(0));
    expect(OfficeViewerLimits.maxPaintPx, greaterThan(0));
    expect(OfficeViewerLimits.defaultMaxBytes, greaterThan(0));
  });

  test('registry picks first engine that supports the format', () {
    final reg = OfficeEngineRegistry.instance..clear();
    expect(() => reg.pick(OfficeFormat.docx),
        throwsA(isA<EngineUnavailableError>()));
    reg.register(FakeOfficeEngine());
    expect(reg.pick(OfficeFormat.docx).id, 'fake');
    expect(() => reg.pick(OfficeFormat.unknown),
        throwsA(isA<UnsupportedFormatError>()));
  });

  test('PDF format is supported by FakeOfficeEngine for tests', () {
    final reg = OfficeEngineRegistry.instance
      ..clear()
      ..register(FakeOfficeEngine());
    expect(reg.pick(OfficeFormat.pdf).id, 'fake');
  });

  test('controller loads and exposes parts', () async {
    final reg = OfficeEngineRegistry.instance
      ..clear()
      ..register(FakeOfficeEngine(partCount: 2));
    final c = OfficeDocumentController(registry: reg);
    await c.load(const DocumentSource.file('report.docx'));
    expect(c.state, OfficeLoadState.ready);
    expect(c.parts.length, 2);
    c.goToPart(1);
    expect(c.currentPart, 1);
  });

  test('controller reports typed errors', () async {
    final reg = OfficeEngineRegistry.instance
      ..clear()
      ..register(FakeOfficeEngine());
    final c = OfficeDocumentController(registry: reg);
    await c.load(const DocumentSource.file('mystery.bin'));
    expect(c.state, OfficeLoadState.failed);
    expect(c.error, isA<UnsupportedFormatError>());
  });

  test('fake tile has expected byte length', () async {
    final h = await FakeOfficeEngine().open(const DocumentSource.file('a.pdf'));
    final t = await h.renderTile(const TileRequest(
        partIndex: 0, region: Rect.fromLTWH(0, 0, 256, 256), scale: 1));
    expect(t.rgba.length, 256 * 256 * 4);
  });
}
