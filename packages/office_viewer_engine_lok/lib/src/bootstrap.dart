import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform bootstrap. Android returns LibreOfficeKit*; iOS fails until a
/// self-built static engine is linked (see ios_feasibility.md).
class LokBootstrap {
  LokBootstrap({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('office_viewer_engine_lok/bootstrap');

  final MethodChannel _channel;
  int? _officePtr;

  int? get officePtr => _officePtr;
  bool get isReady => _officePtr != null && _officePtr != 0;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<int> init() async {
    if (kIsWeb) {
      throw UnsupportedError('LokBootstrap is not available on web');
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError(
          'LokBootstrap supports Android and iOS only (iOS needs a self-build)');
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('init');
      if (result == null) {
        throw StateError('LokBootstrap.init returned null');
      }
      final ptr = result['officePtr'];
      if (ptr is! int || ptr == 0) {
        throw StateError('LokBootstrap.init did not return officePtr');
      }
      _officePtr = ptr;
      return ptr;
    } on PlatformException catch (e) {
      throw StateError('LokBootstrap.init failed: ${e.code} — ${e.message}');
    }
  }

  Future<bool> isReadyRemote() async {
    final v = await _channel.invokeMethod<bool>('isReady');
    return v ?? false;
  }
}
