# Third-party notices — office_viewer_engine_convert

## Office Oxide

- Project: [office_oxide](https://github.com/yfedoseev/office_oxide)
- Prebuilds (this package): [SuiltaPico/office_oxide](https://github.com/SuiltaPico/office_oxide) release `v0.1.2`
- License: MIT OR Apache-2.0
- Use: native FFI convert of DOC / XLS / PPT → DOCX / XLSX / PPTX

Bundled native libraries:

| Path | ABI |
|------|-----|
| `native/macos/arm64/lib/liboffice_oxide.dylib` | macOS Apple Silicon |
| `android/src/main/jniLibs/arm64-v8a/liboffice_oxide.so` | Android arm64-v8a |
| `ios/Frameworks/OfficeOxide.xcframework` | iOS arm64 device + arm64 simulator (dynamic framework) |

Rebuild iOS with `tool/build_ios_oxide.sh` (Office Oxide tag `v0.1.2`).

## Apache POI test fixtures

See [test/fixtures/PROVENANCE.md](test/fixtures/PROVENANCE.md). Apache License 2.0.
