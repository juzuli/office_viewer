# Performance budgets (`office_viewer_engine_dart`)

Targets from the OOXML engine plan (mid-range Android / older iPhone).

| Metric | Budget |
|--------|--------|
| Peak RSS growth for ~5 MB DOCX/PPTX or ~100k-cell XLSX | < 150 MB |
| Image cache default | 64 MB |
| Display-list cache default | 32 MB |
| First tile of page/slide 1 for typical (<1 MB) docs | < 1.5 s |
| Steady-state tile paint (cached part) | < 50 ms |

## Measurement

Run device benches from `packages/office_viewer_engine_dart/tool/bench/` (open
time, first-tile time, steady-state tile time, peak RSS). Record results here
as numbers land.

## Guards

`ResourceLimits` in the Dart engine enforce zip-bomb, XML depth/element, shape,
and cell caps. Exceeding a limit throws `ResourceLimitError` (or
`CorruptDocumentError` when the input is malformed).
