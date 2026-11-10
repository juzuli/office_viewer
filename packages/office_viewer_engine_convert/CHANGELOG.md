## 0.1.0

* Initial release: `ConvertOfficeEngine` converts DOC / XLS / PPT to OOXML via
  Office Oxide FFI, then opens with `DartOfficeEngine` (`^0.1.1` for convert
  list/sheet layout fixes).
* Android arm64 + macOS arm64 + iOS XCFramework (device/sim dynamic prebuilds).
* iOS: `tool/build_ios_oxide.sh` builds a dynamic `OfficeOxide.xcframework`;
  Dart opens `OfficeOxide.framework/OfficeOxide`.
* View-only: temp convert path never overwrites the source file.
