/// Interaction and layout options for [OfficeDocumentView].
///
/// Hold these on [OfficeDocumentController.viewOptions] so the host app can
/// change pan/zoom locks (and related knobs) from outside the widget tree.
///
/// ```dart
/// final controller = OfficeDocumentController(
///   viewOptions: const OfficeViewOptions(zoomEnabled: false),
/// );
/// // later:
/// controller.setViewOptions(
///   controller.viewOptions.copyWith(panEnabled: false),
/// );
/// ```
class OfficeViewOptions {
  const OfficeViewOptions({
    this.panEnabled = true,
    this.zoomEnabled = true,
    this.doubleTapZoomEnabled = true,
    this.minZoom = 1.0,
    this.maxZoom = 5.0,
    this.pagePadding = 12.0,
  })  : assert(minZoom > 0),
        assert(maxZoom >= minZoom),
        assert(pagePadding >= 0);

  /// When false, vertical/horizontal scrolling is locked (content is not
  /// draggable). Programmatic [OfficeDocumentController.goToPart] still works.
  final bool panEnabled;

  /// When false, pinch-to-zoom is disabled. [OfficeDocumentController.setZoom]
  /// still works so the host can drive zoom from chrome buttons.
  final bool zoomEnabled;

  /// When false, double-tap does not toggle zoom (even if [zoomEnabled]).
  final bool doubleTapZoomEnabled;

  /// Minimum zoom. `1.0` = fit page width (+ [pagePadding]), matching common
  /// document viewers (no pinch-out into empty canvas).
  final double minZoom;

  /// Maximum zoom factor relative to fit-width.
  final double maxZoom;

  /// Inset around the page canvas (logical pixels).
  final double pagePadding;

  OfficeViewOptions copyWith({
    bool? panEnabled,
    bool? zoomEnabled,
    bool? doubleTapZoomEnabled,
    double? minZoom,
    double? maxZoom,
    double? pagePadding,
  }) {
    return OfficeViewOptions(
      panEnabled: panEnabled ?? this.panEnabled,
      zoomEnabled: zoomEnabled ?? this.zoomEnabled,
      doubleTapZoomEnabled:
          doubleTapZoomEnabled ?? this.doubleTapZoomEnabled,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      pagePadding: pagePadding ?? this.pagePadding,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OfficeViewOptions &&
      other.panEnabled == panEnabled &&
      other.zoomEnabled == zoomEnabled &&
      other.doubleTapZoomEnabled == doubleTapZoomEnabled &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.pagePadding == pagePadding;

  @override
  int get hashCode => Object.hash(
        panEnabled,
        zoomEnabled,
        doubleTapZoomEnabled,
        minZoom,
        maxZoom,
        pagePadding,
      );
}
