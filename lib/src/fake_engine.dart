import 'dart:typed_data';
import 'dart:ui';

import 'engine.dart';
import 'errors.dart';
import 'format.dart';
import 'source.dart';

/// In-memory engine for tests and for developing the UI before a native
/// engine exists. Produces a visible grid so tile placement can be checked.
class FakeOfficeEngine implements OfficeEngine {
  FakeOfficeEngine({this.partCount = 3, this.kind = PartKind.page});

  final int partCount;
  final PartKind kind;

  @override
  String get id => 'fake';

  @override
  bool supports(OfficeFormat format) => format != OfficeFormat.unknown;

  @override
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    final format = OfficeFormat.fromName(source.fileName);
    if (format == OfficeFormat.unknown) {
      throw const UnsupportedFormatError('Unknown file type.');
    }
    return _FakeHandle(format, partCount, kind);
  }
}

class _FakeHandle implements OfficeDocumentHandle {
  _FakeHandle(this.format, int count, PartKind kind)
      : parts = List.generate(
          count,
          (i) => PartInfo(
            index: i,
            kind: kind,
            name: kind == PartKind.sheet ? 'Sheet${i + 1}' : null,
            size: const Size(612, 792),
          ),
        );

  @override
  final OfficeFormat format;
  @override
  final List<PartInfo> parts;

  @override
  Future<RenderedTile> renderTile(TileRequest request) async {
    final w = (request.region.width * request.scale).round().clamp(1, 4096);
    final h = (request.region.height * request.scale).round().clamp(1, 4096);
    final data = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final edge = x == 0 || y == 0;
        final o = (y * w + x) * 4;
        final v = edge ? 160 : 255;
        data[o] = v;
        data[o + 1] = v;
        data[o + 2] = v;
        data[o + 3] = 255;
      }
    }
    return RenderedTile(rgba: data, width: w, height: h);
  }

  @override
  Future<List<SearchHit>> search(String query) async => const [];

  @override
  Future<void> close() async {}
}
