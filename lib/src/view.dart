import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'engine.dart';
import 'format.dart';
import 'viewer_limits.dart';

/// Tile document viewer — production-style pan/zoom:
///
/// * **Min zoom = fit width** (one canvas width + padding); no pinch-out into
///   empty space (see [OfficeViewOptions.minZoom]).
/// * **Horizontal scroll only when content is wider than the viewport**.
/// * Pan / zoom **gesture locks** come from
///   [OfficeDocumentController.viewOptions] (or optional widget overrides).
///
/// ```dart
/// final controller = OfficeDocumentController();
/// OfficeDocumentView(controller: controller);
/// // host chrome:
/// controller.lockZoom();
/// controller.setZoom(1.5); // still works when zoom gestures are locked
/// ```
class OfficeDocumentView extends StatelessWidget {
  const OfficeDocumentView({
    super.key,
    required this.controller,
    this.panEnabled,
    this.zoomEnabled,
  });

  final OfficeDocumentController controller;

  /// Optional override for [OfficeViewOptions.panEnabled]. `null` → controller.
  final bool? panEnabled;

  /// Optional override for [OfficeViewOptions.zoomEnabled]. `null` → controller.
  final bool? zoomEnabled;

  static const double tilePoints = 256;
  static const double partGap = 12;

  bool _panEnabled() =>
      panEnabled ?? controller.viewOptions.panEnabled;
  bool _zoomEnabled() =>
      zoomEnabled ?? controller.viewOptions.zoomEnabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.state) {
          case OfficeLoadState.idle:
            return const SizedBox.shrink();
          case OfficeLoadState.loading:
            return const Center(child: CircularProgressIndicator());
          case OfficeLoadState.failed:
            return Center(child: Text(controller.error?.message ?? 'Failed'));
          case OfficeLoadState.ready:
            final handle = controller.handle!;
            final stackable = handle.parts.isNotEmpty &&
                handle.parts.first.kind != PartKind.sheet;
            if (stackable && handle.parts.length > 1) {
              return _ScrollablePartsDocument(
                key: ValueKey('stack-${identityHashCode(handle)}'),
                controller: controller,
                handle: handle,
                panEnabled: _panEnabled(),
                zoomEnabled: _zoomEnabled(),
              );
            }
            final idx =
                controller.currentPart.clamp(0, handle.parts.length - 1);
            return _SinglePartDocument(
              key: ValueKey('doc-${identityHashCode(handle)}-part-$idx'),
              controller: controller,
              handle: handle,
              part: handle.parts[idx],
              panEnabled: _panEnabled(),
              zoomEnabled: _zoomEnabled(),
            );
        }
      },
    );
  }
}

/// Pinch → preview zoom; on release commit. Scroll views own pan.
mixin _PinchToZoomMixin<T extends StatefulWidget> on State<T> {
  bool gesturing = false;
  double gestureScale = 1.0;
  int tileZoomEpoch = 0;
  Offset? _focalLocal;

  OfficeDocumentController get zoomController;
  bool get zoomGesturesEnabled;
  bool get doubleTapZoomEnabled;

  void onScaleStart(ScaleStartDetails d) {
    if (!zoomGesturesEnabled) return;
    gesturing = true;
    gestureScale = 1.0;
    _focalLocal = d.localFocalPoint;
  }

  void onScaleUpdate(ScaleUpdateDetails d) {
    if (!gesturing || !zoomGesturesEnabled) return;
    // Ignore pure pan (1 pointer); only pinch changes zoom.
    if (d.pointerCount < 2 && (d.scale - 1.0).abs() < 0.001) return;
    gestureScale = d.scale;
    _focalLocal = d.localFocalPoint;
    zoomController.previewZoom(zoomController.tileZoom * gestureScale);
    setState(() {});
  }

  void onScaleEnd(ScaleEndDetails _) {
    if (!gesturing) return;
    final scale = gestureScale;
    gesturing = false;
    gestureScale = 1.0;
    _focalLocal = null;
    if (!zoomGesturesEnabled || (scale - 1.0).abs() < 0.02) {
      zoomController.cancelZoomPreview();
      setState(() {});
      return;
    }
    final next = (zoomController.tileZoom * scale).clamp(
      zoomController.minZoom,
      zoomController.maxZoom,
    );
    tileZoomEpoch++;
    zoomController.setZoom(next);
    setState(() {});
  }

  void onDoubleTapZoom() {
    if (!zoomGesturesEnabled || !doubleTapZoomEnabled) return;
    gesturing = false;
    gestureScale = 1.0;
    final target = zoomController.tileZoom < 1.75
        ? math.min(2.0, zoomController.maxZoom)
        : zoomController.minZoom;
    tileZoomEpoch++;
    zoomController.setZoom(target);
    setState(() {});
  }

  /// Live pinch: scale around the focal point.
  Widget pinchLayer({required Widget child}) {
    if (!gesturing || (gestureScale - 1.0).abs() < 0.001) return child;
    final focal = _focalLocal ?? Offset.zero;
    final matrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(gestureScale, gestureScale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    return Transform(transform: matrix, child: child);
  }
}

ScrollPhysics _axisPhysics({required bool overflow}) => overflow
    ? const ClampingScrollPhysics()
    : const NeverScrollableScrollPhysics();

/// Multi page/slide: vertical list + H-scroll only when a page is wider than
/// the viewport (zoomed in).
class _ScrollablePartsDocument extends StatefulWidget {
  const _ScrollablePartsDocument({
    super.key,
    required this.controller,
    required this.handle,
    required this.panEnabled,
    required this.zoomEnabled,
  });

  final OfficeDocumentController controller;
  final OfficeDocumentHandle handle;
  final bool panEnabled;
  final bool zoomEnabled;

  @override
  State<_ScrollablePartsDocument> createState() =>
      _ScrollablePartsDocumentState();
}

class _ScrollablePartsDocumentState extends State<_ScrollablePartsDocument>
    with _PinchToZoomMixin<_ScrollablePartsDocument> {
  final ScrollController _vScroll = ScrollController();
  final List<GlobalKey> _partKeys = [];
  bool _programmaticScroll = false;
  int _lastSyncedPart = 0;

  @override
  OfficeDocumentController get zoomController => widget.controller;

  @override
  bool get zoomGesturesEnabled => widget.zoomEnabled;

  @override
  bool get doubleTapZoomEnabled =>
      widget.controller.viewOptions.doubleTapZoomEnabled;

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    _lastSyncedPart = widget.controller.currentPart;
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPart(widget.controller.currentPart, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant _ScrollablePartsDocument old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (old.handle != widget.handle) {
      _ensureKeys();
      _lastSyncedPart = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _vScroll.dispose();
    super.dispose();
  }

  void _ensureKeys() {
    final n = widget.handle.parts.length;
    while (_partKeys.length < n) {
      _partKeys.add(GlobalKey(debugLabel: 'part-${_partKeys.length}'));
    }
    if (_partKeys.length > n) {
      _partKeys.removeRange(n, _partKeys.length);
    }
  }

  void _onController() {
    if (gesturing) return;
    if (widget.controller.takePartSyncFromScroll()) {
      _lastSyncedPart = widget.controller.currentPart;
      return;
    }
    final target = widget.controller.currentPart;
    if (target != _lastSyncedPart) {
      _lastSyncedPart = target;
      _scrollToPart(target, animate: true);
    }
    setState(() {});
  }

  Future<void> _scrollToPart(int index, {required bool animate}) async {
    if (index < 0 || index >= _partKeys.length) return;
    final ctx = _partKeys[index].currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToPart(index, animate: animate);
      });
      return;
    }
    _programmaticScroll = true;
    try {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.05,
        duration: animate ? const Duration(milliseconds: 280) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _programmaticScroll = false;
    }
  }

  void _onScroll() {
    if (_programmaticScroll || !_vScroll.hasClients || gesturing) return;
    final visible = _indexMostVisible();
    if (visible != null && visible != widget.controller.currentPart) {
      _lastSyncedPart = visible;
      widget.controller.syncPartFromScroll(visible);
    }
  }

  int? _indexMostVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final viewport = box.localToGlobal(Offset.zero) & box.size;
    var bestIndex = 0;
    var bestOverlap = -1.0;
    for (var i = 0; i < _partKeys.length; i++) {
      final ctx = _partKeys[i].currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;
      final rect = ro.localToGlobal(Offset.zero) & ro.size;
      final overlap = rect.intersect(viewport).height;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestIndex = i;
      }
    }
    return bestOverlap > 0 ? bestIndex : null;
  }

  @override
  Widget build(BuildContext context) {
    final tileZoom = widget.controller.tileZoom;
    final parts = widget.handle.parts;
    final pad = widget.controller.viewOptions.pagePadding;
    final pan = widget.panEnabled;

    return LayoutBuilder(builder: (context, constraints) {
      final viewportW = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 400.0;
      final canvasW = viewportW - 2 * pad;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.zoomEnabled ? onScaleStart : null,
        onScaleUpdate: widget.zoomEnabled ? onScaleUpdate : null,
        onScaleEnd: widget.zoomEnabled ? onScaleEnd : null,
        onDoubleTap: widget.zoomEnabled ? onDoubleTapZoom : null,
        child: pinchLayer(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
                _onScroll();
              }
              return false;
            },
            child: ListView.separated(
              controller: _vScroll,
              physics: _axisPhysics(overflow: pan),
              padding: EdgeInsets.symmetric(vertical: pad),
              itemCount: parts.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: OfficeDocumentView.partGap),
              itemBuilder: (context, i) {
                final part = parts[i];
                final fit = canvasW / part.size.width;
                final contentW = part.size.width * fit * tileZoom;
                final needsH = pan && contentW > canvasW + 0.5;

                return KeyedSubtree(
                  key: _partKeys[i],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
                        child: Text(
                          part.name ?? 'Part ${part.index + 1}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      SizedBox(
                        height: part.size.height * fit * tileZoom,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: _axisPhysics(overflow: needsH),
                          padding: EdgeInsets.symmetric(horizontal: pad),
                          child: _PartView(
                            key: ValueKey(
                                'tiles-${part.index}-$tileZoom-$tileZoomEpoch'),
                            handle: widget.handle,
                            part: part,
                            zoom: tileZoom,
                            viewportWidth: canvasW,
                            cullToViewport: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// One part (single page / sheet) with clamped H/V scroll.
class _SinglePartDocument extends StatefulWidget {
  const _SinglePartDocument({
    super.key,
    required this.controller,
    required this.handle,
    required this.part,
    required this.panEnabled,
    required this.zoomEnabled,
  });

  final OfficeDocumentController controller;
  final OfficeDocumentHandle handle;
  final PartInfo part;
  final bool panEnabled;
  final bool zoomEnabled;

  @override
  State<_SinglePartDocument> createState() => _SinglePartDocumentState();
}

class _SinglePartDocumentState extends State<_SinglePartDocument>
    with _PinchToZoomMixin<_SinglePartDocument> {
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  /// Visible region in part-points (sheets only).
  Rect _visiblePartRect = const Rect.fromLTWH(0, 0, 1024, 1024);

  @override
  OfficeDocumentController get zoomController => widget.controller;

  @override
  bool get zoomGesturesEnabled => widget.zoomEnabled;

  @override
  bool get doubleTapZoomEnabled =>
      widget.controller.viewOptions.doubleTapZoomEnabled;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _hScroll.addListener(_updateVisibleFromScroll);
    _vScroll.addListener(_updateVisibleFromScroll);
  }

  @override
  void didUpdateWidget(covariant _SinglePartDocument old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (old.part.index != widget.part.index || old.handle != widget.handle) {
      _visiblePartRect = const Rect.fromLTWH(0, 0, 1024, 1024);
      if (_hScroll.hasClients) _hScroll.jumpTo(0);
      if (_vScroll.hasClients) _vScroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _hScroll.removeListener(_updateVisibleFromScroll);
    _vScroll.removeListener(_updateVisibleFromScroll);
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  void _onController() {
    if (gesturing) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibleFromScroll();
    });
  }

  void _updateVisibleFromScroll() {
    if (widget.part.kind != PartKind.sheet) return;
    // Approximate visible window from scroll offsets + viewport.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final tileZoom = widget.controller.tileZoom;
    final pad = widget.controller.viewOptions.pagePadding;
    final canvasW = box.size.width - 2 * pad;
    final fit = canvasW / widget.part.size.width;
    final pxPerPoint = fit * tileZoom;
    if (pxPerPoint <= 0) return;
    final hx = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final vy = _vScroll.hasClients ? _vScroll.offset : 0.0;
    final region = Rect.fromLTWH(
      hx / pxPerPoint,
      vy / pxPerPoint,
      box.size.width / pxPerPoint,
      box.size.height / pxPerPoint,
    ).inflate(OfficeDocumentView.tilePoints);
    if (region == _visiblePartRect) return;
    setState(() => _visiblePartRect = region);
  }

  @override
  Widget build(BuildContext context) {
    final tileZoom = widget.controller.tileZoom;
    final pad = widget.controller.viewOptions.pagePadding;
    final cull = widget.part.kind == PartKind.sheet;
    final pan = widget.panEnabled;

    return LayoutBuilder(builder: (context, constraints) {
      final vw =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
      final vh =
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
      final canvasW = vw - 2 * pad;
      final fit = canvasW / widget.part.size.width;
      final contentW = widget.part.size.width * fit * tileZoom;
      final contentH = widget.part.size.height * fit * tileZoom;
      final needsH = pan && contentW > canvasW + 0.5;
      final needsV = pan && contentH > (vh - 2 * pad) + 0.5;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateVisibleFromScroll();
      });

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.zoomEnabled ? onScaleStart : null,
        onScaleUpdate: widget.zoomEnabled ? onScaleUpdate : null,
        onScaleEnd: widget.zoomEnabled ? onScaleEnd : null,
        onDoubleTap: widget.zoomEnabled ? onDoubleTapZoom : null,
        child: pinchLayer(
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: SingleChildScrollView(
              controller: _vScroll,
              physics: _axisPhysics(overflow: needsV),
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                physics: _axisPhysics(overflow: needsH),
                child: _PartView(
                  key: ValueKey('tiles-$tileZoom-$tileZoomEpoch'),
                  handle: widget.handle,
                  part: widget.part,
                  zoom: tileZoom,
                  viewportWidth: canvasW,
                  cullToViewport: cull,
                  visiblePartRegion: cull ? _visiblePartRect : null,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _PartView extends StatelessWidget {
  const _PartView({
    super.key,
    required this.handle,
    required this.part,
    required this.zoom,
    required this.viewportWidth,
    this.cullToViewport = false,
    this.visiblePartRegion,
  });

  final OfficeDocumentHandle handle;
  final PartInfo part;
  final double zoom;
  final double viewportWidth;
  final bool cullToViewport;
  final Rect? visiblePartRegion;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fit = viewportWidth / part.size.width;
    final scale = fit * zoom;
    final width = part.size.width * scale;
    final height = part.size.height * scale;
    final tilePx = OfficeDocumentView.tilePoints * scale;
    const tp = OfficeDocumentView.tilePoints;

    // Cap DPR×zoom so a single tile paint stays under phone memory budgets.
    final paintScale = math.min(
      scale * dpr,
      part.kind == PartKind.sheet ? 2.0 : 3.0,
    );

    final regions = computeMountedTileRegions(
      partSize: part.size,
      tilePoints: tp,
      cullToViewport: cullToViewport,
      visible: visiblePartRegion,
    );

    final tiles = <Widget>[
      for (final region in regions)
        Positioned(
          left: region.left * scale,
          top: region.top * scale,
          width: tilePx,
          height: tilePx,
          child: _TileView(
            handle: handle,
            request: TileRequest(
              partIndex: part.index,
              region: region,
              scale: paintScale,
            ),
          ),
        ),
    ];

    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Colors.white,
        child: Stack(children: tiles),
      ),
    );
  }
}

class _TileView extends StatefulWidget {
  const _TileView({required this.handle, required this.request});
  final OfficeDocumentHandle handle;
  final TileRequest request;

  @override
  State<_TileView> createState() => _TileViewState();
}

class _TileViewState extends State<_TileView> {
  ui.Image? _image;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TileView old) {
    super.didUpdateWidget(old);
    if (old.request != widget.request) _load();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    try {
      final tile = await widget.handle.renderTile(widget.request);
      if (!mounted || gen != _loadGen) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        tile.rgba,
        tile.width,
        tile.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (!mounted || gen != _loadGen) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
    }
  }

  @override
  void dispose() {
    _loadGen++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawImage(image: _image, fit: BoxFit.fill);
  }
}
