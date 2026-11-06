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
/// * **Multi-page docs** use a vertical [PageView] with a hard snap per page
///   (Instagram Reels–style); chrome `goToPart` animates the same snap.
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
            // PDF pages, Writer page-rects, slides, and Excel sheets all use
            // vertical snap paging when there is more than one part.
            if (handle.parts.length > 1) {
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

/// Multi page/slide: Instagram Reels–style vertical [PageView] with a hard
/// snap stopper per page. Horizontal pan only when a page is wider than the
/// viewport (zoomed in). When zoom makes a page taller than the viewport,
/// that page can scroll vertically *within* its snap slot.
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
  late final PageController _pageController;
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
    final initial = widget.controller.currentPart
        .clamp(0, math.max(0, widget.handle.parts.length - 1))
        .toInt();
    _lastSyncedPart = initial;
    _pageController = PageController(initialPage: initial);
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant _ScrollablePartsDocument old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (old.handle != widget.handle) {
      _lastSyncedPart = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _pageController.dispose();
    super.dispose();
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
    final max = widget.handle.parts.length - 1;
    if (index < 0 || index > max) return;
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToPart(index, animate: animate);
      });
      return;
    }
    final currentPage =
        _pageController.page?.round() ?? _pageController.initialPage;
    if (currentPage == index) return;
    _programmaticScroll = true;
    try {
      if (animate) {
        await _pageController.animateToPage(
          index,
          // Slightly longer easeInOut reads less abrupt than easeOut on
          // chrome next/prev and matches Reels-style page settles.
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _pageController.jumpToPage(index);
      }
    } finally {
      _programmaticScroll = false;
    }
  }

  void _onPageChanged(int index) {
    if (_programmaticScroll) {
      _lastSyncedPart = index;
      return;
    }
    if (index != widget.controller.currentPart) {
      _lastSyncedPart = index;
      widget.controller.syncPartFromScroll(index);
    } else {
      _lastSyncedPart = index;
    }
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
      final viewportH = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : 600.0;
      final canvasW = math.max(1.0, viewportW - 2 * pad);
      final pageSlotH = math.max(1.0, viewportH);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.zoomEnabled ? onScaleStart : null,
        onScaleUpdate: widget.zoomEnabled ? onScaleUpdate : null,
        onScaleEnd: widget.zoomEnabled ? onScaleEnd : null,
        onDoubleTap: widget.zoomEnabled ? onDoubleTapZoom : null,
        child: pinchLayer(
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            allowImplicitScrolling: true,
            physics: pan
                ? const PageScrollPhysics(parent: ClampingScrollPhysics())
                : const NeverScrollableScrollPhysics(),
            itemCount: parts.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) {
              final part = parts[i];
              if (part.kind == PartKind.sheet) {
                // Sheets need 2D pan + viewport tile culling inside each
                // snap slot; page/slide slots use the simpler centered layout.
                return _SheetSnapPage(
                  key: ValueKey('sheet-slot-${part.index}'),
                  handle: widget.handle,
                  part: part,
                  panEnabled: pan,
                  tileZoom: tileZoom,
                  tileZoomEpoch: tileZoomEpoch,
                  viewportW: viewportW,
                  viewportH: pageSlotH,
                  pagePadding: pad,
                  showPartLabels:
                      widget.controller.viewOptions.showPartLabels,
                  onEdgeSwipe: (delta) {
                    final target =
                        (i + delta).clamp(0, parts.length - 1).toInt();
                    if (target == i) return;
                    // Let controller listener drive animateToPage.
                    widget.controller.goToPart(target);
                  },
                );
              }

              final fit = canvasW / part.size.width;
              final contentW = part.size.width * fit * tileZoom;
              final pageH = part.size.height * fit * tileZoom;
              final needsH = pan && contentW > canvasW + 0.5;
              final needsV = pan && pageH > (pageSlotH - 2 * pad) + 0.5;

              final showLabel =
                  widget.controller.viewOptions.showPartLabels;
              return SizedBox(
                width: viewportW,
                height: pageSlotH,
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showLabel) ...[
                        Text(
                          part.name ?? 'Part ${part.index + 1}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        SizedBox(height: pad > 0 ? 6 : 0),
                      ],
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            physics: _axisPhysics(overflow: needsV),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: _axisPhysics(overflow: needsH),
                              child: SizedBox(
                                width: contentW,
                                height: pageH,
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
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// One Excel/Calc sheet inside a vertical snap [PageView] slot.
///
/// Free 2D pan with viewport-culled tiles. Sheet-to-sheet moves use the outer
/// [PageView] (swipe or chrome next/prev).
class _SheetSnapPage extends StatefulWidget {
  const _SheetSnapPage({
    super.key,
    required this.handle,
    required this.part,
    required this.panEnabled,
    required this.tileZoom,
    required this.tileZoomEpoch,
    required this.viewportW,
    required this.viewportH,
    required this.pagePadding,
    this.showPartLabels = false,
    this.onEdgeSwipe,
  });

  final OfficeDocumentHandle handle;
  final PartInfo part;
  final bool panEnabled;
  final double tileZoom;
  final int tileZoomEpoch;
  final double viewportW;
  final double viewportH;
  final double pagePadding;
  final bool showPartLabels;

  /// Called with `-1` / `+1` when the user flings past the top/bottom edge.
  final ValueChanged<int>? onEdgeSwipe;

  @override
  State<_SheetSnapPage> createState() => _SheetSnapPageState();
}

class _SheetSnapPageState extends State<_SheetSnapPage> {
  static const double _kEdgeFlingVelocity = 700;

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  Rect _visiblePartRect = const Rect.fromLTWH(0, 0, 1024, 1024);

  @override
  void initState() {
    super.initState();
    _hScroll.addListener(_updateVisibleFromScroll);
    _vScroll.addListener(_updateVisibleFromScroll);
  }

  @override
  void didUpdateWidget(covariant _SheetSnapPage old) {
    super.didUpdateWidget(old);
    if (old.part.index != widget.part.index || old.handle != widget.handle) {
      _visiblePartRect = const Rect.fromLTWH(0, 0, 1024, 1024);
      if (_hScroll.hasClients) _hScroll.jumpTo(0);
      if (_vScroll.hasClients) _vScroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _hScroll.removeListener(_updateVisibleFromScroll);
    _vScroll.removeListener(_updateVisibleFromScroll);
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  void _updateVisibleFromScroll() {
    final pad = widget.pagePadding;
    final canvasW = widget.viewportW - 2 * pad;
    final fit = canvasW / widget.part.size.width;
    final pxPerPoint = fit * widget.tileZoom;
    if (pxPerPoint <= 0) return;
    final hx = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final vy = _vScroll.hasClients ? _vScroll.offset : 0.0;
    final region = Rect.fromLTWH(
      hx / pxPerPoint,
      vy / pxPerPoint,
      widget.viewportW / pxPerPoint,
      widget.viewportH / pxPerPoint,
    ).inflate(OfficeDocumentView.tilePoints);
    if (region == _visiblePartRect) return;
    setState(() => _visiblePartRect = region);
  }

  bool _onSheetScrollNotification(ScrollNotification notification) {
    if (widget.onEdgeSwipe == null) return false;
    if (notification is! ScrollEndNotification) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_vScroll.hasClients) return false;

    final velocity = notification.dragDetails?.primaryVelocity;
    if (velocity == null) return false;

    final atTop = _vScroll.offset <= 0.5;
    final atBottom =
        _vScroll.offset >= _vScroll.position.maxScrollExtent - 0.5;

    // Drag down (positive velocity) at top → previous sheet.
    if (atTop && velocity > _kEdgeFlingVelocity) {
      widget.onEdgeSwipe!(-1);
      return true;
    }
    // Drag up (negative velocity) at bottom → next sheet.
    if (atBottom && velocity < -_kEdgeFlingVelocity) {
      widget.onEdgeSwipe!(1);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.pagePadding;
    final canvasW = math.max(1.0, widget.viewportW - 2 * pad);
    final fit = canvasW / widget.part.size.width;
    final contentW = widget.part.size.width * fit * widget.tileZoom;
    final contentH = widget.part.size.height * fit * widget.tileZoom;
    final pan = widget.panEnabled;
    final viewW = math.max(0.0, widget.viewportW - 2 * pad);
    final viewH = math.max(0.0, widget.viewportH - 2 * pad);
    final needsH = pan && contentW > viewW + 0.5;
    final needsV = pan && contentH > viewH + 0.5;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibleFromScroll();
    });

    return SizedBox(
      width: widget.viewportW,
      height: widget.viewportH,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showPartLabels) ...[
              Text(
                widget.part.name ?? 'Sheet ${widget.part.index + 1}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              SizedBox(height: pad > 0 ? 6 : 0),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slotW = constraints.maxWidth;
                  final slotH = constraints.maxHeight;

                  return NotificationListener<ScrollNotification>(
                    onNotification: _onSheetScrollNotification,
                    child: SingleChildScrollView(
                      controller: _vScroll,
                      physics: _axisPhysics(overflow: needsV),
                      child: SizedBox(
                        // Fill the slot when the sheet is shorter/narrower so
                        // Align can center it (same as PDF/slide pages).
                        height: needsV ? contentH : slotH,
                        child: Align(
                          alignment: Alignment.center,
                          child: SingleChildScrollView(
                            controller: _hScroll,
                            scrollDirection: Axis.horizontal,
                            physics: _axisPhysics(overflow: needsH),
                            child: SizedBox(
                              width: needsH ? contentW : slotW,
                              child: Align(
                                alignment: Alignment.center,
                                child: _PartView(
                                  key: ValueKey(
                                    'sheet-tiles-${widget.part.index}-${widget.tileZoom}-${widget.tileZoomEpoch}',
                                  ),
                                  handle: widget.handle,
                                  part: widget.part,
                                  zoom: widget.tileZoom,
                                  viewportWidth: canvasW,
                                  cullToViewport: true,
                                  visiblePartRegion: _visiblePartRect,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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

      // When the page is smaller than the viewport (common at fit-width on
      // tall phones), center it — don't pin to the top-left.
      final viewW = math.max(0.0, vw - 2 * pad);
      final viewH = math.max(0.0, vh - 2 * pad);

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
              child: SizedBox(
                height: needsV ? contentH : viewH,
                child: Align(
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    physics: _axisPhysics(overflow: needsH),
                    child: SizedBox(
                      width: needsH ? contentW : viewW,
                      child: Align(
                        alignment: Alignment.center,
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
    const tp = OfficeDocumentView.tilePoints;

    // Cap DPR×zoom so a single tile paint stays under phone memory budgets.
    // Layout still uses [scale]; aspect-matched tile boxes keep BoxFit.fill
    // from distorting partial edge tiles when paintScale < scale*dpr.
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

    final tiles = <Widget>[];
    for (final region in regions) {
      final clipped = clipTileRegionToPart(region, part.size);
      if (clipped.width <= 0 || clipped.height <= 0) continue;
      tiles.add(
        Positioned(
          left: clipped.left * scale,
          top: clipped.top * scale,
          width: clipped.width * scale,
          height: clipped.height * scale,
          child: _TileView(
            handle: handle,
            request: TileRequest(
              partIndex: part.index,
              region: clipped,
              scale: paintScale,
            ),
          ),
        ),
      );
    }

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
    // fill is safe when the Positioned box matches content aspect (see
    // clampedTileLayoutSize). none+topLeft would leave letterboxing if the
    // engine returned a slightly different pixel size.
    return RawImage(
      image: _image,
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
    );
  }
}
