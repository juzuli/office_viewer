import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Subset of LibreOfficeKit C vtables used by the Phase 0 spike.
/// Layout matches include/LibreOfficeKit/LibreOfficeKit.h (unstable API).

final class LibreOfficeKit extends Struct {
  external Pointer<LibreOfficeKitClass> pClass;
}

final class LibreOfficeKitClass extends Struct {
  @IntPtr()
  external int nSize;

  external Pointer<
          NativeFunction<Void Function(Pointer<LibreOfficeKit>)>>
      destroy;

  external Pointer<
      NativeFunction<
          Pointer<LibreOfficeKitDocument> Function(
              Pointer<LibreOfficeKit>, Pointer<Utf8>)>> documentLoad;

  external Pointer<
          NativeFunction<Pointer<Utf8> Function(Pointer<LibreOfficeKit>)>>
      getError;

  external Pointer<
      NativeFunction<
          Pointer<LibreOfficeKitDocument> Function(
              Pointer<LibreOfficeKit>, Pointer<Utf8>, Pointer<Utf8>)>>
      documentLoadWithOptions;

  external Pointer<NativeFunction<Void Function(Pointer<Utf8>)>> freeError;
}

final class LibreOfficeKitDocument extends Struct {
  external Pointer<LibreOfficeKitDocumentClass> pClass;
}

final class LibreOfficeKitDocumentClass extends Struct {
  @IntPtr()
  external int nSize;

  external Pointer<
          NativeFunction<Void Function(Pointer<LibreOfficeKitDocument>)>>
      destroy;

  // saveAs skipped for layout — we only need offsets through paintTile.
  // After destroy: saveAs, getDocumentType, then unstable block.
  external Pointer<
      NativeFunction<
          Int32 Function(Pointer<LibreOfficeKitDocument>, Pointer<Utf8>,
              Pointer<Utf8>, Pointer<Utf8>)>> saveAs;

  external Pointer<
          NativeFunction<Int32 Function(Pointer<LibreOfficeKitDocument>)>>
      getDocumentType;

  external Pointer<
          NativeFunction<Int32 Function(Pointer<LibreOfficeKitDocument>)>>
      getParts;

  external Pointer<
          NativeFunction<Pointer<Utf8> Function(Pointer<LibreOfficeKitDocument>)>>
      getPartPageRectangles;

  external Pointer<
          NativeFunction<Int32 Function(Pointer<LibreOfficeKitDocument>)>>
      getPart;

  external Pointer<
          NativeFunction<Void Function(Pointer<LibreOfficeKitDocument>, Int32)>>
      setPart;

  external Pointer<
      NativeFunction<
          Pointer<Utf8> Function(
              Pointer<LibreOfficeKitDocument>, Int32)>> getPartName;

  external Pointer<
          NativeFunction<Void Function(Pointer<LibreOfficeKitDocument>, Int32)>>
      setPartMode;

  external Pointer<
      NativeFunction<
          Void Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32)>> paintTile;

  external Pointer<
          NativeFunction<Int32 Function(Pointer<LibreOfficeKitDocument>)>>
      getTileMode;

  external Pointer<
      NativeFunction<
          Void Function(Pointer<LibreOfficeKitDocument>, Pointer<IntPtr>,
              Pointer<IntPtr>)>> getDocumentSize;

  external Pointer<
      NativeFunction<
          Void Function(
              Pointer<LibreOfficeKitDocument>, Pointer<Utf8>)>>
      initializeForRendering;
}

typedef _DocumentLoadNative = Pointer<LibreOfficeKitDocument> Function(
    Pointer<LibreOfficeKit>, Pointer<Utf8>);
typedef _DocumentLoadWithOptionsNative = Pointer<LibreOfficeKitDocument> Function(
    Pointer<LibreOfficeKit>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetErrorNative = Pointer<Utf8> Function(Pointer<LibreOfficeKit>);
typedef _FreeErrorNative = void Function(Pointer<Utf8>);
typedef _DestroyDocNative = void Function(Pointer<LibreOfficeKitDocument>);
typedef _GetPartsNative = int Function(Pointer<LibreOfficeKitDocument>);
typedef _SetPartNative = void Function(Pointer<LibreOfficeKitDocument>, int);
typedef _GetPartNameNative = Pointer<Utf8> Function(
    Pointer<LibreOfficeKitDocument>, int);
typedef _GetPartPageRectanglesNative = Pointer<Utf8> Function(
    Pointer<LibreOfficeKitDocument>);
typedef _GetDocumentSizeNative = void Function(
    Pointer<LibreOfficeKitDocument>, Pointer<IntPtr>, Pointer<IntPtr>);
typedef _PaintTileNative = void Function(
    Pointer<LibreOfficeKitDocument>,
    Pointer<Uint8>,
    int,
    int,
    int,
    int,
    int,
    int);
typedef _InitRenderNative = void Function(
    Pointer<LibreOfficeKitDocument>, Pointer<Utf8>);
typedef _GetDocumentTypeNative = int Function(Pointer<LibreOfficeKitDocument>);

class LokBindings {
  LokBindings(this.officeAddress, {required this.iosBridge});

  /// Opaque office pointer from native bootstrap (LibreOfficeKit* / iOS static kit).
  final int officeAddress;
  final bool iosBridge;

  Pointer<LibreOfficeKit> get office =>
      Pointer<LibreOfficeKit>.fromAddress(officeAddress);

  static DynamicLibrary openLibrary() {
    if (Platform.isIOS) {
      // Symbols linked into the app via CPiOS -filelist.
      return DynamicLibrary.process();
    }
    // Already loaded by Kotlin System.loadLibrary("lo-native-code").
    return DynamicLibrary.open('liblo-native-code.so');
  }

  static LokBindings fromOfficePtr(int ptr) {
    return LokBindings(ptr, iosBridge: Platform.isIOS);
  }

  late final DynamicLibrary _lib = openLibrary();

  LibreOfficeKitClass get _kitClass => office.ref.pClass.ref;
  LibreOfficeKitDocumentClass _docClass(Pointer<LibreOfficeKitDocument> doc) =>
      doc.ref.pClass.ref;

  Pointer<LibreOfficeKitDocument> documentLoad(String url, {String? options}) {
    if (iosBridge) {
      final urlPtr = url.toNativeUtf8();
      try {
        if (options != null && options.isNotEmpty) {
          final optPtr = options.toNativeUtf8();
          try {
            final fn = _lib.lookupFunction<
                IntPtr Function(IntPtr, Pointer<Utf8>, Pointer<Utf8>),
                int Function(int, Pointer<Utf8>, Pointer<Utf8>)>(
              'office_viewer_lok_ios_document_load_with_options',
            );
            return Pointer.fromAddress(fn(officeAddress, urlPtr, optPtr));
          } finally {
            malloc.free(optPtr);
          }
        }
        final fn = _lib.lookupFunction<
            IntPtr Function(IntPtr, Pointer<Utf8>),
            int Function(int, Pointer<Utf8>)>(
          'office_viewer_lok_ios_document_load',
        );
        return Pointer.fromAddress(fn(officeAddress, urlPtr));
      } finally {
        malloc.free(urlPtr);
      }
    }
    final urlPtr = url.toNativeUtf8();
    try {
      if (options != null && options.isNotEmpty) {
        final optPtr = options.toNativeUtf8();
        try {
          final withOpts = _kitClass.documentLoadWithOptions
              .asFunction<_DocumentLoadWithOptionsNative>();
          return withOpts(office, urlPtr, optPtr);
        } finally {
          malloc.free(optPtr);
        }
      }
      final fn = _kitClass.documentLoad.asFunction<_DocumentLoadNative>();
      return fn(office, urlPtr);
    } finally {
      malloc.free(urlPtr);
    }
  }

  String? getError() {
    if (iosBridge) {
      final get = _lib.lookupFunction<
          Pointer<Utf8> Function(IntPtr),
          Pointer<Utf8> Function(int)>('office_viewer_lok_ios_get_error');
      final free = _lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('office_viewer_lok_ios_free_error');
      final err = get(officeAddress);
      if (err == nullptr) return null;
      final text = err.toDartString();
      free(err);
      return text;
    }
    final fn = _kitClass.getError.asFunction<_GetErrorNative>();
    final err = fn(office);
    if (err == nullptr) return null;
    final text = err.toDartString();
    final free = _kitClass.freeError.asFunction<_FreeErrorNative>();
    free(err);
    return text;
  }

  void destroyDocument(Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      _lib.lookupFunction<Void Function(IntPtr), void Function(int)>(
          'office_viewer_lok_ios_document_destroy')(doc.address);
      return;
    }
    final fn = _docClass(doc).destroy.asFunction<_DestroyDocNative>();
    fn(doc);
  }

  int getParts(Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      return _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'office_viewer_lok_ios_get_parts')(doc.address);
    }
    return _docClass(doc).getParts.asFunction<_GetPartsNative>()(doc);
  }

  void setPart(Pointer<LibreOfficeKitDocument> doc, int part) {
    if (iosBridge) {
      _lib.lookupFunction<Void Function(IntPtr, Int32), void Function(int, int)>(
          'office_viewer_lok_ios_set_part')(doc.address, part);
      return;
    }
    _docClass(doc).setPart.asFunction<_SetPartNative>()(doc, part);
  }

  String? getPartName(Pointer<LibreOfficeKitDocument> doc, int part) {
    if (iosBridge) {
      final get = _lib.lookupFunction<
          Pointer<Utf8> Function(IntPtr, Int32),
          Pointer<Utf8> Function(int, int)>('office_viewer_lok_ios_get_part_name');
      final free = _lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('office_viewer_lok_ios_free_error');
      final ptr = get(doc.address, part);
      if (ptr == nullptr) return null;
      final name = ptr.toDartString();
      free(ptr);
      return name;
    }
    final ptr =
        _docClass(doc).getPartName.asFunction<_GetPartNameNative>()(doc, part);
    if (ptr == nullptr) return null;
    // Part names are owned by LOK; do not free with freeError.
    return ptr.toDartString();
  }

  /// Writer page rectangles as `"x, y, w, h; ..."` in twips, or null.
  String? getPartPageRectangles(Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      final get = _lib.lookupFunction<
          Pointer<Utf8> Function(IntPtr),
          Pointer<Utf8> Function(
              int)>('office_viewer_lok_ios_get_part_page_rectangles');
      final free = _lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('office_viewer_lok_ios_free_error');
      final ptr = get(doc.address);
      if (ptr == nullptr) return null;
      final value = ptr.toDartString();
      free(ptr);
      return value;
    }
    final ptr = _docClass(doc)
        .getPartPageRectangles
        .asFunction<_GetPartPageRectanglesNative>()(doc);
    if (ptr == nullptr) return null;
    final value = ptr.toDartString();
    // LOK allocates this string — free via freeError (same as getError).
    _kitClass.freeError.asFunction<_FreeErrorNative>()(ptr);
    return value;
  }

  ({int widthTwips, int heightTwips}) getDocumentSize(
      Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      final w = calloc<Int64>();
      final h = calloc<Int64>();
      try {
        _lib.lookupFunction<
                Void Function(IntPtr, Pointer<Int64>, Pointer<Int64>),
                void Function(int, Pointer<Int64>, Pointer<Int64>)>(
            'office_viewer_lok_ios_get_document_size')(doc.address, w, h);
        return (widthTwips: w.value, heightTwips: h.value);
      } finally {
        calloc.free(w);
        calloc.free(h);
      }
    }
    final w = calloc<IntPtr>();
    final h = calloc<IntPtr>();
    try {
      _docClass(doc).getDocumentSize.asFunction<_GetDocumentSizeNative>()(
          doc, w, h);
      return (widthTwips: w.value, heightTwips: h.value);
    } finally {
      calloc.free(w);
      calloc.free(h);
    }
  }

  int getDocumentType(Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      return _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'office_viewer_lok_ios_get_document_type')(doc.address);
    }
    return _docClass(doc).getDocumentType.asFunction<_GetDocumentTypeNative>()(
        doc);
  }

  /// 0 = RGBA, 1 = BGRA. Android LOK tiles are BGRA; iOS static kit is usually RGBA.
  int getTileMode(Pointer<LibreOfficeKitDocument> doc) {
    if (iosBridge) {
      return _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'office_viewer_lok_ios_get_tile_mode')(doc.address);
    }
    return 1; // Android LOK path historically BGRA.
  }

  void initializeForRendering(
      Pointer<LibreOfficeKitDocument> doc, String args) {
    if (iosBridge) {
      final p = args.toNativeUtf8();
      try {
        _lib.lookupFunction<
                Void Function(IntPtr, Pointer<Utf8>),
                void Function(int, Pointer<Utf8>)>(
            'office_viewer_lok_ios_initialize_for_rendering')(doc.address, p);
      } finally {
        malloc.free(p);
      }
      return;
    }
    final p = args.toNativeUtf8();
    try {
      _docClass(doc)
          .initializeForRendering
          .asFunction<_InitRenderNative>()(doc, p);
    } finally {
      malloc.free(p);
    }
  }

  void paintTile(
    Pointer<LibreOfficeKitDocument> doc, {
    required Pointer<Uint8> buffer,
    required int canvasWidth,
    required int canvasHeight,
    required int tilePosX,
    required int tilePosY,
    required int tileWidth,
    required int tileHeight,
  }) {
    if (iosBridge) {
      _lib.lookupFunction<
          Void Function(
              IntPtr, Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32, Int32),
          void Function(int, Pointer<Uint8>, int, int, int, int, int, int)>(
          'office_viewer_lok_ios_paint_tile')(
        doc.address,
        buffer,
        canvasWidth,
        canvasHeight,
        tilePosX,
        tilePosY,
        tileWidth,
        tileHeight,
      );
      return;
    }
    _docClass(doc).paintTile.asFunction<_PaintTileNative>()(
      doc,
      buffer,
      canvasWidth,
      canvasHeight,
      tilePosX,
      tilePosY,
      tileWidth,
      tileHeight,
    );
  }
}

bool get isAndroid => !Platform.isIOS && Platform.isAndroid;
