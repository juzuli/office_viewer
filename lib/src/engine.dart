import 'dart:typed_data';
import 'dart:ui';

import 'format.dart';
import 'source.dart';

/// One addressable unit of a document: a page, a sheet or a slide.
class PartInfo {
  const PartInfo({
    required this.index,
    required this.kind,
    required this.size,
    this.name,
  });

  final int index;
  final PartKind kind;

  /// Display name, e.g. the sheet tab name. Null for pages.
  final String? name;

  /// Size in logical points (1/72 in) at scale 1.0. For sheets this is the
  /// used-area size, which can be very large; that is why rendering is tiled.
  final Size size;
}

/// A request for one rectangle of one part, in part coordinates (points).
class TileRequest {
  const TileRequest({
    required this.partIndex,
    required this.region,
    required this.scale,
  });

  final int partIndex;
  final Rect region;

  /// Pixels per point. Multiply by device pixel ratio for sharp output.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is TileRequest &&
      other.partIndex == partIndex &&
      other.region == region &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(partIndex, region, scale);
}

/// Raw premultiplied RGBA pixels, row-major, no padding.
class RenderedTile {
  const RenderedTile({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class SearchHit {
  const SearchHit({required this.partIndex, required this.rects});
  final int partIndex;
  final List<Rect> rects;
}

class OpenOptions {
  /// Default [maxBytes] is 50 MB — enough for typical office files on phones.
  const OpenOptions({
    this.password,
    this.maxBytes = 50 * 1024 * 1024,
  });
  final String? password;

  /// Guards against oversized or decompression-bomb inputs.
  final int maxBytes;
}

/// An opened document. Engines may only support one open handle at a time
/// (LibreOfficeKit is effectively single-threaded); the registry enforces it.
abstract class OfficeDocumentHandle {
  OfficeFormat get format;
  List<PartInfo> get parts;
  Future<RenderedTile> renderTile(TileRequest request);
  Future<List<SearchHit>> search(String query);
  Future<void> close();
}

/// A rendering backend. Implementations: LibreOfficeKit over FFI, a WebView
/// with bundled JS engines, PDFium, and the in-memory fake used by tests.
abstract class OfficeEngine {
  String get id;
  bool supports(OfficeFormat format);
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  });
}
