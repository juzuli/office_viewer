import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:office_viewer/office_viewer.dart';

import 'bootstrap.dart';
import 'lok_ffi.dart';

/// Points per twip reciprocal: 1 point = 20 twips.
const double twipsPerPoint = 20;

/// Phone-viewer caps (mirrored from office_viewer limits — keep in sync).
const int _maxPartProbe = 48;
const double _maxSheetExtentPoints = 24000;
const int _maxPaintPx = 1024;
const int _maxSheetPaintPx = 768;
String _lokLoadOptions({String? password}) {
  final buf = StringBuffer(
    '{"ReadOnly":{"type":"boolean","value":"true"},'
    '"MacroExecutionMode":{"type":"long","value":"0"}',
  );
  if (password != null && password.isNotEmpty) {
    // MediaDescriptor Password — unlock encrypted OOXML / ODF / legacy.
    final escaped = password
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    buf.write(',"Password":{"type":"string","value":"$escaped"}');
  }
  buf.write('}');
  return buf.toString();
}

bool _looksLikePasswordError(String err) {
  final lower = err.toLowerCase();
  return lower.contains('password') ||
      lower.contains('encrypted') ||
      lower.contains('passwd') ||
      lower.contains('wrong pass');
}

/// LibreOfficeKit-backed [OfficeEngine] (Android arm64 Phase 0).
///
/// All LOK FFI runs on the root isolate — the same thread affinity as JNI
/// bootstrap. A background Dart isolate deadlocks `documentLoad`/`destroy` on
/// Android (sal thread attaches and never finishes). Ops are still serialized
/// so concurrent tiles cannot race each other.
class LokOfficeEngine implements OfficeEngine {
  LokOfficeEngine({LokBootstrap? bootstrap})
      : _bootstrap = bootstrap ?? LokBootstrap();

  final LokBootstrap _bootstrap;
  LokBindings? _bindings;
  Future<void>? _starting;
  bool _initFailed = false;

  /// Chains open / paint / destroy so only one LOK call runs at a time.
  Future<void> _tail = Future<void>.value();

  @override
  String get id => 'lok';

  @override
  bool supports(OfficeFormat format) {
    // PDF is handled by office_viewer_engine_pdf (pdfrx). LOK aborts on some
    // real-world PDFs (BUG-004); keep LibreOffice for Office formats only.
    if (format == OfficeFormat.unknown ||
        format == OfficeFormat.pdf ||
        kIsWeb) {
      return false;
    }
    // Android and iOS both use LOK when the native plugin is linked.
    // iOS falls back to a stub that fails init until install_lok_home_ios.sh.
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() op) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await op());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    // Keep the chain alive even if this op failed.
    _tail = _tail.catchError((_) {});
    return done.future;
  }

  Future<void> ensureInitialized() {
    if (_bindings != null) return Future<void>.value();
    if (_initFailed) {
      return Future.error(
          const EngineUnavailableError('LOK init previously failed'));
    }
    if (_starting != null) return _starting!;

    _starting = () async {
      try {
        final ptr = await _bootstrap.init();
        _bindings = LokBindings.fromOfficePtr(ptr);
      } catch (e) {
        _initFailed = true;
        throw EngineUnavailableError('LOK init failed: $e');
      } finally {
        _starting = null;
      }
    }();
    return _starting!;
  }

  @override
  Future<OfficeDocumentHandle> open(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    await ensureInitialized();
    // Let the loading spinner paint before sync FFI stalls the isolate.
    await Future<void>.delayed(Duration.zero);
    final path = await _materialize(source, options);
    return _enqueue(() => _openSynced(path, source.fileName, options));
  }

  Future<LokDocumentHandle> _openSynced(
    String path,
    String? fileName,
    OpenOptions options,
  ) async {
    final bindings = _bindings!;
    final url = path.startsWith('file://') ? path : 'file://$path';

    debugPrint('LOK open start: $fileName path=$path');
    final sw = Stopwatch()..start();
    // Read-only + macros off (Android). Password goes in FilterOptions when set.
    // iOS bridge ignores options today but still soft-fails load exceptions.
    Pointer<LibreOfficeKitDocument> doc;
    try {
      doc = bindings.documentLoad(
        url,
        options: _lokLoadOptions(password: options.password),
      );
    } catch (e) {
      debugPrint('LOK open threw: $e');
      if (_looksLikePasswordError('$e')) {
        throw const PasswordRequiredError();
      }
      throw CorruptDocumentError('documentLoad failed: $e');
    }
    final loadMs = sw.elapsedMilliseconds;
    debugPrint('LOK open done in ${loadMs}ms doc=${doc.address}');

    if (doc == nullptr) {
      final err = bindings.getError() ?? 'documentLoad returned null';
      if (_looksLikePasswordError(err)) {
        throw const PasswordRequiredError();
      }
      throw CorruptDocumentError(err);
    }

    try {
      bindings.initializeForRendering(doc, '{}');
    } catch (e) {
      debugPrint('LOK initializeForRendering failed: $e');
      bindings.destroyDocument(doc);
      throw CorruptDocumentError('initializeForRendering failed: $e');
    }

    final type = bindings.getDocumentType(doc);
    final kind = _kindFor(type);
    var partCount = bindings.getParts(doc);
    if (partCount < 0) partCount = 0;
    // Huge PDFs/decks: keep part list bounded so open stays interactive.
    final listedParts = kind == PartKind.sheet
        ? partCount
        : math.min(partCount, 500);
    debugPrint('LOK parts=$partCount listed=$listedParts kind=$kind');

    // Large PDFs/presentations: probing every part stalls the UI isolate.
    // Sheets need real used-area sizes (few tabs) — still probe each sheet.
    final probeEach = kind == PartKind.sheet || listedParts <= _maxPartProbe;
    final parts = <PartInfo>[];

    ui.Size sizeOf(int index) {
      bindings.setPart(doc, index);
      final size = bindings.getDocumentSize(doc);
      var s = ui.Size(
        size.widthTwips / twipsPerPoint,
        size.heightTwips / twipsPerPoint,
      );
      if (kind == PartKind.sheet) {
        s = ui.Size(
          math.min(s.width, _maxSheetExtentPoints),
          math.min(s.height, _maxSheetExtentPoints),
        );
      }
      return s;
    }

    final firstSize = listedParts > 0 ? sizeOf(0) : const ui.Size(612, 792);
    for (var i = 0; i < listedParts; i++) {
      final size = probeEach ? (i == 0 ? firstSize : sizeOf(i)) : firstSize;
      final name = (!probeEach && i > 0)
          ? 'Page ${i + 1}'
          : bindings.getPartName(doc, i);
      parts.add(
        PartInfo(
          index: i,
          kind: kind,
          name: name,
          size: size,
        ),
      );
    }
    if (parts.isNotEmpty) {
      bindings.setPart(doc, 0);
    }

    return LokDocumentHandle(
      engine: this,
      bindings: bindings,
      doc: doc,
      format: OfficeFormat.fromName(fileName),
      parts: parts,
      loadMilliseconds: loadMs,
    );
  }

  Future<void> destroyDocument(Pointer<LibreOfficeKitDocument> doc) {
    return _enqueue(() async {
      debugPrint('LOK destroy start doc=${doc.address}');
      final sw = Stopwatch()..start();
      _bindings?.destroyDocument(doc);
      debugPrint('LOK destroy done in ${sw.elapsedMilliseconds}ms');
    });
  }

  Future<({RenderedTile tile, int elapsedMs})> paintTileTimed(
    Pointer<LibreOfficeKitDocument> doc,
    TileRequest request,
  ) {
    return _enqueue(() async {
      final bindings = _bindings!;
      final sw = Stopwatch()..start();
      bindings.setPart(doc, request.partIndex);

      // Sheets: tighter paint budget — large Calc used-areas OOM phones.
      final isSheet = bindings.getDocumentType(doc) == 1;
      final maxPx = isSheet ? _maxSheetPaintPx : _maxPaintPx;
      final canvasW =
          (request.region.width * request.scale).round().clamp(1, maxPx);
      final canvasH =
          (request.region.height * request.scale).round().clamp(1, maxPx);
      final tilePosX = (request.region.left * twipsPerPoint).round();
      final tilePosY = (request.region.top * twipsPerPoint).round();
      final tileW =
          (request.region.width * twipsPerPoint).round().clamp(1, 1 << 30);
      final tileH =
          (request.region.height * twipsPerPoint).round().clamp(1, 1 << 30);

      final byteCount = canvasW * canvasH * 4;
      final buffer = calloc<Uint8>(byteCount);
      try {
        bindings.paintTile(
          doc,
          buffer: buffer,
          canvasWidth: canvasW,
          canvasHeight: canvasH,
          tilePosX: tilePosX,
          tilePosY: tilePosY,
          tileWidth: tileW,
          tileHeight: tileH,
        );
        final raw = buffer.asTypedList(byteCount);
        final rgba =
            bindings.getTileMode(doc) == 1 ? _bgraToRgba(raw) : Uint8List.fromList(raw);
        return (
          tile: RenderedTile(rgba: rgba, width: canvasW, height: canvasH),
          elapsedMs: sw.elapsedMilliseconds,
        );
      } finally {
        calloc.free(buffer);
      }
    });
  }

  static PartKind _kindFor(int documentType) {
    switch (documentType) {
      case 1:
        return PartKind.sheet;
      case 2:
        return PartKind.slide;
      default:
        return PartKind.page;
    }
  }

  Future<String> _materialize(
    DocumentSource source,
    OpenOptions options,
  ) async {
    switch (source) {
      case FileSource(:final path):
        final f = File(path);
        if (!await f.exists()) {
          throw CorruptDocumentError('File not found: $path');
        }
        final len = await f.length();
        if (len > options.maxBytes) {
          throw ResourceLimitError(
              'File exceeds maxBytes ($len > ${options.maxBytes})');
        }
        return f.absolute.path;
      case BytesSource(:final bytes, :final fileName):
        if (bytes.length > options.maxBytes) {
          throw ResourceLimitError(
              'Bytes exceed maxBytes (${bytes.length} > ${options.maxBytes})');
        }
        final dir = await Directory.systemTemp.createTemp('lok_doc_');
        final name = fileName ?? 'document.bin';
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        return file.absolute.path;
    }
  }

  static Uint8List _bgraToRgba(Uint8List bgra) {
    final out = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      out[i] = bgra[i + 2];
      out[i + 1] = bgra[i + 1];
      out[i + 2] = bgra[i];
      out[i + 3] = bgra[i + 3];
    }
    return out;
  }
}

class LokDocumentHandle implements OfficeDocumentHandle {
  LokDocumentHandle({
    required this.engine,
    required this.bindings,
    required this.doc,
    required this.format,
    required this.parts,
    required this.loadMilliseconds,
  });

  final LokOfficeEngine engine;
  final LokBindings bindings;
  final Pointer<LibreOfficeKitDocument> doc;

  /// Wall time for documentLoad (metrics harness).
  final int loadMilliseconds;

  int? lastTileMilliseconds;
  bool _closed = false;

  @override
  final OfficeFormat format;

  @override
  final List<PartInfo> parts;

  @override
  Future<RenderedTile> renderTile(TileRequest request) async {
    if (_closed) {
      throw const CorruptDocumentError('Document already closed');
    }
    final result = await engine.paintTileTimed(doc, request);
    lastTileMilliseconds = result.elapsedMs;
    return result.tile;
  }

  @override
  Future<List<SearchHit>> search(String query) async => const [];

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await engine.destroyDocument(doc);
  }
}
