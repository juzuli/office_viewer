import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

/// Thin FFI surface over Office Oxide C API used for legacy → OOXML convert.
final class OfficeOxideBindings {
  OfficeOxideBindings._(this._lib) {
    _version = _lib.lookupFunction<_VersionNative, _Version>(
      'office_oxide_version',
    );
    _openFromBytes = _lib.lookupFunction<
        _OpenFromBytesNative, _OpenFromBytes>(
      'office_document_open_from_bytes',
    );
    _saveAs = _lib.lookupFunction<_SaveAsNative, _SaveAs>(
      'office_document_save_as',
    );
    _free = _lib.lookupFunction<_FreeNative, _Free>('office_document_free');
  }

  static OfficeOxideBindings? _instance;

  /// Lazily opens the native library. Throws [StateError] if unavailable.
  static OfficeOxideBindings get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final created = OfficeOxideBindings._(openOfficeOxideLibrary());
    _instance = created;
    return created;
  }

  /// True when the shared library loads and exports required symbols.
  static bool get isAvailable {
    try {
      instance;
      return true;
    } on Object {
      return false;
    }
  }

  /// Test helper — reset cached singleton.
  static void debugReset() => _instance = null;

  final DynamicLibrary _lib;
  late final _Version _version;
  late final _OpenFromBytes _openFromBytes;
  late final _SaveAs _saveAs;
  late final _Free _free;

  String get version => _version().cast<Utf8>().toDartString();

  /// Opens [bytes] as [format] (`doc`/`xls`/`ppt`/…), writes OOXML to [outPath].
  ///
  /// Throws [OfficeOxideFfiException] on native failure.
  void convertToFile({
    required Uint8List bytes,
    required String format,
    required String outPath,
  }) {
    final data = calloc<Uint8>(bytes.length);
    final err = calloc<Int32>();
    final formatPtr = format.toNativeUtf8();
    final outPtr = outPath.toNativeUtf8();
    Pointer<Void> handle = nullptr;
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      handle = _openFromBytes(data, bytes.length, formatPtr, err);
      final openCode = err.value;
      if (handle == nullptr || openCode != 0) {
        throw OfficeOxideFfiException('open_from_bytes', openCode);
      }
      err.value = 0;
      final rc = _saveAs(handle, outPtr, err);
      final saveCode = err.value;
      if (rc != 0 || saveCode != 0) {
        throw OfficeOxideFfiException('save_as', saveCode != 0 ? saveCode : rc);
      }
    } finally {
      if (handle != nullptr) {
        _free(handle);
      }
      calloc.free(data);
      calloc.free(err);
      malloc.free(formatPtr);
      malloc.free(outPtr);
    }
  }
}

/// Native FFI failure with Office Oxide error code.
final class OfficeOxideFfiException implements Exception {
  OfficeOxideFfiException(this.operation, this.code);

  final String operation;
  final int code;

  @override
  String toString() => 'OfficeOxideFfiException($operation, code=$code)';
}

typedef _VersionNative = Pointer<Utf8> Function();
typedef _Version = Pointer<Utf8> Function();

typedef _OpenFromBytesNative = Pointer<Void> Function(
  Pointer<Uint8> data,
  IntPtr len,
  Pointer<Utf8> format,
  Pointer<Int32> errorCode,
);
typedef _OpenFromBytes = Pointer<Void> Function(
  Pointer<Uint8> data,
  int len,
  Pointer<Utf8> format,
  Pointer<Int32> errorCode,
);

typedef _SaveAsNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> path,
  Pointer<Int32> errorCode,
);
typedef _SaveAs = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> path,
  Pointer<Int32> errorCode,
);

typedef _FreeNative = Void Function(Pointer<Void> handle);
typedef _Free = void Function(Pointer<Void> handle);
