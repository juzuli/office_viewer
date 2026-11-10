import 'package:office_viewer/office_viewer.dart';

import '../model/display_list.dart';
import '../opc/package_reader.dart';
import '../paint/tile_renderer.dart';

class DartDocumentHandle implements OfficeDocumentHandle {
  DartDocumentHandle({
    required this.format,
    required this.parts,
    required this.package,
    required List<DisplayList> displayLists,
    TileRenderer? tileRenderer,
  })  : _displayLists = displayLists, // ignore: prefer_initializing_formals
        _tileRenderer = tileRenderer ?? TileRenderer();

  final PackageReader package;
  final List<DisplayList> _displayLists;
  final TileRenderer _tileRenderer;
  bool _closed = false;

  @override
  final OfficeFormat format;

  @override
  final List<PartInfo> parts;

  List<DisplayList> get displayLists => _displayLists;

  @override
  Future<RenderedTile> renderTile(TileRequest request) async {
    if (_closed) {
      throw const CorruptDocumentError('Document already closed');
    }
    if (request.partIndex < 0 || request.partIndex >= parts.length) {
      throw CorruptDocumentError('Bad part index ${request.partIndex}');
    }
    return _tileRenderer.render(
      _displayLists[request.partIndex],
      request.region,
      request.scale,
    );
  }

  @override
  Future<List<SearchHit>> search(String query) async => const [];

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _displayLists.clear();
  }
}
