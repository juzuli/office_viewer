import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lok_ffi.dart';

/// Isolate entry — no dart:ui / Flutter imports (background isolate safe).
void lokWorkerMain(SendPort mainSend) {
  final commands = ReceivePort();
  mainSend.send(commands.sendPort);

  LokBindings? bindings;
  final docs = <int, Pointer<LibreOfficeKitDocument>>{};
  var nextDocId = 1;

  // PartKind indices must match office_viewer.PartKind { page, sheet, slide }.
  const kindPage = 0;
  const kindSheet = 1;
  const kindSlide = 2;

  int kindIndex(int documentType) {
    switch (documentType) {
      case 1:
        return kindSheet;
      case 2:
        return kindSlide;
      default:
        return kindPage;
    }
  }

  String formatFromName(String? name) {
    final ext = (name ?? '').split('.').last.toLowerCase();
    const known = {
      'pdf',
      'docx',
      'xlsx',
      'pptx',
      'doc',
      'xls',
      'ppt',
      'odt',
      'ods',
      'odp',
      'csv',
      'txt',
    };
    return known.contains(ext) ? ext : 'unknown';
  }

  Uint8List bgraToRgba(Uint8List bgra) {
    final out = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      out[i] = bgra[i + 2];
      out[i + 1] = bgra[i + 1];
      out[i + 2] = bgra[i];
      out[i + 3] = bgra[i + 3];
    }
    return out;
  }

  const twipsPerPoint = 20.0;

  void replyOk(int id, [Object? value]) =>
      mainSend.send(<Object?>[id, 'ok', value]);

  void replyErr(int id, String code, String detail) =>
      mainSend.send(<Object?>[id, 'err', code, detail]);

  commands.listen((message) {
    if (message is! List || message.length < 2) return;
    final id = message[0];
    final op = message[1];
    if (id is! int || op is! String) return;
    final args = message.length > 2 && message[2] is Map
        ? Map<String, Object?>.from(message[2] as Map)
        : <String, Object?>{};

    try {
      switch (op) {
        case 'init':
          final officePtr = args['officePtr'];
          if (officePtr is! int || officePtr == 0) {
            replyErr(id, 'bad_ptr', 'officePtr missing');
            return;
          }
          LokBindings.openLibrary();
          bindings = LokBindings.fromOfficePtr(officePtr);
          replyOk(id);

        case 'open':
          final b = bindings;
          if (b == null) {
            replyErr(id, 'not_ready', 'worker not initialized');
            return;
          }
          final path = args['path'] as String;
          final fileName = args['fileName'] as String?;
          final url = path.startsWith('file://') ? path : 'file://$path';
          final sw = Stopwatch()..start();
          final doc = b.documentLoad(
            url,
            options:
                '{"ReadOnly":{"type":"boolean","value":"true"},'
                '"MacroExecutionMode":{"type":"long","value":"0"}}',
          );
          final loadMs = sw.elapsedMilliseconds;
          if (doc == nullptr) {
            final err = b.getError() ?? 'documentLoad returned null';
            final lower = err.toLowerCase();
            replyErr(
              id,
              lower.contains('password') ? 'password' : 'corrupt',
              err,
            );
            return;
          }
          b.initializeForRendering(doc, '{}');
          final type = b.getDocumentType(doc);
          final kind = kindIndex(type);
          final partCount = b.getParts(doc);
          final parts = <Map<String, Object?>>[];
          for (var i = 0; i < partCount; i++) {
            b.setPart(doc, i);
            final size = b.getDocumentSize(doc);
            parts.add({
              'index': i,
              'kind': kind,
              'name': b.getPartName(doc, i),
              'w': size.widthTwips / twipsPerPoint,
              'h': size.heightTwips / twipsPerPoint,
            });
          }
          if (parts.isNotEmpty) {
            b.setPart(doc, 0);
          }
          final docId = nextDocId++;
          docs[docId] = doc;
          replyOk(id, {
            'docId': docId,
            'parts': parts,
            'format': formatFromName(fileName),
            'loadMs': loadMs,
          });

        case 'paint':
          final b = bindings;
          final docId = args['docId'] as int;
          final doc = docs[docId];
          if (b == null || doc == null) {
            replyErr(id, 'closed', 'document $docId is closed');
            return;
          }
          final partIndex = args['partIndex'] as int;
          final left = (args['left'] as num).toDouble();
          final top = (args['top'] as num).toDouble();
          final width = (args['width'] as num).toDouble();
          final height = (args['height'] as num).toDouble();
          final scale = (args['scale'] as num).toDouble();

          final sw = Stopwatch()..start();
          b.setPart(doc, partIndex);
          final canvasW = (width * scale).round().clamp(1, 4096);
          final canvasH = (height * scale).round().clamp(1, 4096);
          final tilePosX = (left * twipsPerPoint).round();
          final tilePosY = (top * twipsPerPoint).round();
          final tileW = (width * twipsPerPoint).round().clamp(1, 1 << 30);
          final tileH = (height * twipsPerPoint).round().clamp(1, 1 << 30);
          final byteCount = canvasW * canvasH * 4;
          final buffer = calloc<Uint8>(byteCount);
          try {
            b.paintTile(
              doc,
              buffer: buffer,
              canvasWidth: canvasW,
              canvasHeight: canvasH,
              tilePosX: tilePosX,
              tilePosY: tilePosY,
              tileWidth: tileW,
              tileHeight: tileH,
            );
            final rgba = bgraToRgba(buffer.asTypedList(byteCount));
            replyOk(id, {
              'rgba': rgba,
              'width': canvasW,
              'height': canvasH,
              'elapsedMs': sw.elapsedMilliseconds,
            });
          } finally {
            calloc.free(buffer);
          }

        case 'destroy':
          final b = bindings;
          final docId = args['docId'] as int;
          final doc = docs.remove(docId);
          if (b != null && doc != null) {
            b.destroyDocument(doc);
          }
          replyOk(id);

        case 'shutdown':
          final b = bindings;
          for (final doc in docs.values) {
            b?.destroyDocument(doc);
          }
          docs.clear();
          replyOk(id);
          commands.close();
          scheduleMicrotask(() => Isolate.exit());

        default:
          replyErr(id, 'unknown', 'unknown op: $op');
      }
    } catch (e, st) {
      replyErr(id, 'exception', '$e\n$st');
    }
  });
}
