import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Minimal spike: DOC/XLS/PPT bytes → OOXML via office_document_save_as.
void main(List<String> args) {
  final root = Directory.current.path;
  final libPath = p.join(root, 'native', 'liboffice_oxide.dylib');
  if (!File(libPath).existsSync()) {
    stderr.writeln('Missing $libPath');
    exit(1);
  }

  final lib = DynamicLibrary.open(libPath);
  final version = lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'office_oxide_version',
      )()
      .toDartString();
  stdout.writeln('office_oxide $version');

  final openFromBytes = lib.lookupFunction<
      Pointer<Void> Function(
        Pointer<Uint8>,
        IntPtr,
        Pointer<Utf8>,
        Pointer<Int32>,
      ),
      Pointer<Void> Function(
        Pointer<Uint8>,
        int,
        Pointer<Utf8>,
        Pointer<Int32>,
      )>('office_document_open_from_bytes');
  final saveAs = lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>),
      int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>)>(
    'office_document_save_as',
  );
  final freeDoc = lib.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('office_document_free');

  final outDir = Directory(p.join(root, 'out'))
    ..createSync(recursive: true);
  final cases = <(String, String, String)>[
    ('fixtures/sample.doc', 'doc', 'sample.docx'),
    ('fixtures/sample.xls', 'xls', 'sample.xlsx'),
    ('fixtures/sample.ppt', 'ppt', 'sample.pptx'),
  ];

  var failed = 0;
  for (final (rel, fmt, outName) in cases) {
    final src = File(p.join(root, rel));
    final bytes = src.readAsBytesSync();
    final outPath = p.join(outDir.path, outName);
    final sw = Stopwatch()..start();

    final data = calloc<Uint8>(bytes.length);
    final err = calloc<Int32>();
    final fmtPtr = fmt.toNativeUtf8();
    final outPtr = outPath.toNativeUtf8();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      final handle = openFromBytes(data, bytes.length, fmtPtr, err);
      if (handle == nullptr || err.value != 0) {
        stderr.writeln('$rel open failed code=${err.value}');
        failed++;
        continue;
      }
      err.value = 0;
      final rc = saveAs(handle, outPtr, err);
      freeDoc(handle);
      if (rc != 0 || err.value != 0) {
        stderr.writeln('$rel save_as failed rc=$rc code=${err.value}');
        failed++;
        continue;
      }
    } finally {
      calloc.free(data);
      calloc.free(err);
      malloc.free(fmtPtr);
      malloc.free(outPtr);
    }

    sw.stop();
    final out = File(outPath);
    final head = out.readAsBytesSync().sublist(0, 4);
    final isZip = head[0] == 0x50 && head[1] == 0x4B;
    stdout.writeln(
      '$rel → $outName (${out.lengthSync()} bytes, zip=$isZip, '
      '${sw.elapsedMilliseconds}ms)',
    );
    if (!isZip) failed++;
  }

  if (failed != 0) {
    stderr.writeln('spike failed ($failed)');
    exit(1);
  }
  stdout.writeln('spike ok');
}
