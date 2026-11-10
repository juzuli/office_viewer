import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'errors.dart';
import 'format.dart';
import 'registry.dart';
import 'source.dart';
import 'view_options.dart';

enum OfficeLoadState { idle, loading, ready, failed }

/// Drives an [OfficeDocumentView]. Create one in your State (or a host
/// controller) and pass it into the view — load, zoom, part, and interaction
/// locks are all controlled from here.
///
/// ```dart
/// final controller = OfficeDocumentController(
///   viewOptions: const OfficeViewOptions(panEnabled: true, zoomEnabled: true),
/// );
///
/// await controller.load(DocumentSource.bytes(bytes, fileName: 'a.docx'));
/// controller.lockZoom();   // gestures only; setZoom still works
/// controller.lockPan();
/// ```
class OfficeDocumentController extends ChangeNotifier {
  OfficeDocumentController({
    OfficeEngineRegistry? registry,
    this._viewOptions = const OfficeViewOptions(),
  }) : _registry = registry ?? OfficeEngineRegistry.instance;

  /// Defaults used when [OfficeViewOptions] is not customized.
  static const double defaultMinZoom = 1.0;
  static const double defaultMaxZoom = 5.0;

  final OfficeEngineRegistry _registry;

  OfficeLoadState _state = OfficeLoadState.idle;
  OfficeDocumentHandle? _handle;
  OfficeError? _error;
  int _currentPart = 0;
  double _zoom = 1.0;
  /// Live pinch/button preview; tiles keep using [_zoom] until committed.
  double? _zoomPreview;
  int _loadEpoch = 0;
  bool _disposed = false;
  /// When true, the next [currentPart] notify came from scroll — view must
  /// not jump (avoids feedback loops with the dropdown).
  bool _partSyncFromScroll = false;
  OfficeViewOptions _viewOptions;

  OfficeLoadState get state => _state;
  OfficeDocumentHandle? get handle => _handle;
  OfficeError? get error => _error;
  List<PartInfo> get parts => _handle?.parts ?? const [];
  int get currentPart => _currentPart;

  /// Current interaction / layout options (pan/zoom locks, zoom range, …).
  OfficeViewOptions get viewOptions => _viewOptions;

  double get minZoom => _viewOptions.minZoom;
  double get maxZoom => _viewOptions.maxZoom;

  /// True once after a scroll-driven part sync; clears when read.
  bool takePartSyncFromScroll() {
    if (!_partSyncFromScroll) return false;
    _partSyncFromScroll = false;
    return true;
  }

  /// Display zoom (includes in-progress pinch). Prefer this for chrome / %.
  double get zoom => _zoomPreview ?? _zoom;

  /// Zoom used to size and paint tiles. Stable until a gesture commits.
  double get tileZoom => _zoom;

  bool get isZoomGestureActive => _zoomPreview != null;

  /// Replace view options and notify listeners (the view rebuilds).
  void setViewOptions(OfficeViewOptions options) {
    if (options == _viewOptions) return;
    _viewOptions = options;
    // Keep zoom inside the new range.
    final clamped = _zoom.clamp(options.minZoom, options.maxZoom);
    if (clamped != _zoom) {
      _zoom = clamped;
      _zoomPreview = null;
    }
    if (!_disposed) notifyListeners();
  }

  /// Convenience for toggling gesture locks without rebuilding the whole
  /// options object by hand.
  void setInteraction({bool? panEnabled, bool? zoomEnabled}) {
    setViewOptions(_viewOptions.copyWith(
      panEnabled: panEnabled,
      zoomEnabled: zoomEnabled,
    ));
  }

  /// Lock (or unlock) pan/scroll gestures.
  void lockPan([bool locked = true]) =>
      setInteraction(panEnabled: !locked);

  /// Lock (or unlock) pinch / double-tap zoom gestures.
  void lockZoom([bool locked = true]) =>
      setInteraction(zoomEnabled: !locked);

  Future<void> load(
    DocumentSource source, {
    OpenOptions options = const OpenOptions(),
  }) async {
    final epoch = ++_loadEpoch;

    // Drop the old handle from UI immediately so tiles stop targeting it,
    // then destroy on the engine worker without blocking the first frame.
    final previous = _handle;
    _handle = null;
    _error = null;
    _state = OfficeLoadState.loading;
    _currentPart = 0;
    _zoom = _viewOptions.minZoom;
    _zoomPreview = null;
    if (!_disposed) notifyListeners();

    if (previous != null) {
      // Let spinner paint, then destroy. Do not block forever on a wedged close.
      await Future<void>.delayed(Duration.zero);
      try {
        await previous.close().timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('OfficeDocumentController: close previous failed: $e');
      }
    }

    if (_disposed || epoch != _loadEpoch) return;

    try {
      final format = OfficeFormat.fromName(source.fileName);
      final engine = _registry.pick(format);
      debugPrint('OfficeDocumentController: opening ${source.fileName}');
      final opened = await engine.open(source, options: options);
      debugPrint('OfficeDocumentController: opened ${source.fileName}');
      if (_disposed || epoch != _loadEpoch) {
        // Superseded or disposed — release the just-opened handle.
        unawaited(opened.close());
        return;
      }
      _handle = opened;
      _currentPart = 0;
      _state = OfficeLoadState.ready;
    } on OfficeError catch (e) {
      if (_disposed || epoch != _loadEpoch) return;
      _error = e;
      _state = OfficeLoadState.failed;
    } catch (e) {
      if (_disposed || epoch != _loadEpoch) return;
      _error = EngineUnavailableError('$e');
      _state = OfficeLoadState.failed;
    }
    if (!_disposed) notifyListeners();
  }

  /// Jump from chrome (dropdown). Viewer scrolls to the part.
  void goToPart(int index) {
    if (index < 0 || index >= parts.length || index == _currentPart) return;
    _currentPart = index;
    _partSyncFromScroll = false;
    // Fresh part — drop in-flight pinch so tiles match chrome.
    _zoomPreview = null;
    notifyListeners();
  }

  /// Update current part while the user scrolls the stack. Dropdown follows;
  /// viewer does not re-scroll.
  void syncPartFromScroll(int index) {
    if (index < 0 || index >= parts.length || index == _currentPart) return;
    _currentPart = index;
    _partSyncFromScroll = true;
    notifyListeners();
  }

  /// Commits a new tile zoom (buttons, double-tap, pinch end).
  void setZoom(double value) {
    final next = value.clamp(minZoom, maxZoom);
    if (_zoomPreview == null && (next - _zoom).abs() < 0.0001) return;
    _zoom = next;
    _zoomPreview = null;
    notifyListeners();
  }

  /// Live chrome update during pinch; does not rebuild tiles.
  void previewZoom(double value) {
    final next = value.clamp(minZoom, maxZoom);
    if (_zoomPreview != null && (next - _zoomPreview!).abs() < 0.0001) return;
    _zoomPreview = next;
    notifyListeners();
  }

  /// Apply [previewZoom] as the committed tile zoom, or discard if none.
  void commitZoomPreview() {
    if (_zoomPreview == null) return;
    _zoom = _zoomPreview!;
    _zoomPreview = null;
    notifyListeners();
  }

  void cancelZoomPreview() {
    if (_zoomPreview == null) return;
    _zoomPreview = null;
    notifyListeners();
  }

  void zoomBy(double factor) => setZoom(tileZoom * factor);

  @override
  void dispose() {
    _disposed = true;
    _loadEpoch++;
    final h = _handle;
    _handle = null;
    if (h != null) {
      unawaited(h.close());
    }
    super.dispose();
  }
}
