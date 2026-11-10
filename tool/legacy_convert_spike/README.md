# Legacy convert spike

Throwaway proof that Office Oxide FFI can turn DOC / XLS / PPT into OOXML.

```bash
# From repo root, with Flutter 3.47+ / Dart 3.12+ on PATH:
cd tool/legacy_convert_spike
dart pub get
dart run bin/convert_spike.dart
```

Expects `native/liboffice_oxide.dylib` (copied from SuiltaPico `v0.1.2` macOS arm64 prebuild) and `fixtures/sample.{doc,xls,ppt}`.

Production code lives in `packages/office_viewer_engine_convert`.
