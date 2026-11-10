# Deviations from replica plan

Tracked differences between
`replica/plan/plan_pure_dart_ooxml_engine_for_office_viewer.md` and real code /
implementation choices.

| Topic | Plan said | Reality / choice |
|-------|-----------|------------------|
| Limit exceeded error | Propose `LimitExceeded` subtype if needed | Core already has `ResourceLimitError` — use it |
| Engine priority API | Propose if cheap | Not needed; registration order works |
| `OpenOptions.maxBytes` | Plan §9 100 MB compressed | Core default is 50 MB; honor `options.maxBytes` and engine `ResourceLimits` |
| WebView Office path | (older README) | Replaced by pure Dart per product decision |
| `PartInfo` LOK fields | N/A | Dart leaves `contentOrigin`/`lokPartIndex` at defaults |
| Font embedding (odttf) | Optional | Deferred; substitution table only for v1 |
| `dart pub publish --dry-run` from monorepo | Should pass | Root `.pubignore` lists `packages/` so dry-run from a nested engine package reports “pubspec hidden” (same as PDF today). Publish engines from a release checkout that does not apply that ignore, or temporarily adjust ignore. |
| Carlito/Caladea | Bundle both | Bundled; Calibri→Carlito, Cambria→Caladea |

Update this file when a milestone intentionally diverges.
