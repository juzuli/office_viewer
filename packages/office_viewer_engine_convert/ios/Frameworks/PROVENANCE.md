# OfficeOxide.xcframework

- Upstream: https://github.com/yfedoseev/office_oxide
- Tag: `v0.1.2`
- Built by: `tool/build_ios_oxide.sh`
- License: MIT OR Apache-2.0 (see package THIRD_PARTY_LICENSES.md)
- Form: dynamic `OfficeOxide.framework` slices (`aarch64-apple-ios`, `aarch64-apple-ios-sim`)
- Why dynamic: Rust release LTO/staticlib emits LLVM bitcode Apple's linker
  cannot consume; the cdylib is a normal Mach-O with C FFI exports.

Dart loads via `DynamicLibrary.open('OfficeOxide.framework/OfficeOxide')`
(fallback: `DynamicLibrary.process()`).

Rebuild:
```bash
./tool/build_ios_oxide.sh
```
