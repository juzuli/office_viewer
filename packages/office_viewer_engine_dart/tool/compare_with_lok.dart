/// Fidelity harness stub: compare DartOfficeEngine tiles to LOK reference.
///
/// Requires the private `office_viewer_engine_lok` package and a LOK home.
/// Not part of public CI. Usage (once fleshed out):
///
/// ```sh
/// dart run tool/compare_with_lok.dart --corpus path/to/docs --out reports/
/// ```
///
/// Reads thresholds from `tool/thresholds.yaml`. Emits `report.json` /
/// `report.md` with per-part SSIM and DOCX page-count delta.
///
/// This stub documents the contract; full PNG/SSIM pipeline lands with a
/// private LOK-enabled host.
library;

void main(List<String> args) {
  // ignore: avoid_print
  print(
    'compare_with_lok: stub. Pass --corpus and --out when LOK is available.\n'
    'Args: $args',
  );
}
