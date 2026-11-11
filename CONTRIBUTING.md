# Contributing

Thanks for helping with `office_viewer`. Pub packages:

- [`office_viewer`](https://pub.dev/packages/office_viewer) — viewer shell
- [`office_viewer_engine_pdf`](https://pub.dev/packages/office_viewer_engine_pdf) — PDF
- [`office_viewer_engine_dart`](https://pub.dev/packages/office_viewer_engine_dart) — DOCX / XLSX / PPTX
- [`office_viewer_engine_convert`](https://pub.dev/packages/office_viewer_engine_convert) — optional DOC / XLS / PPT convert

Local development uses path deps in [`example_app/`](example_app/) and
package `pubspec_overrides.yaml` files.

```bash
flutter pub get && flutter analyze && flutter test
```

## Example hosts

Full PDF + Convert + Dart OOXML host:

```bash
cd example_app
flutter pub get
flutter run -d <android-or-ios-device>
```

`example_app` registers `PdfOfficeEngine`, then `ConvertOfficeEngine`, then
`DartOfficeEngine`. Bundled samples: [`example_app/README.md`](example_app/README.md).

Pub sample (PDF + Dart, optional convert): [`example/`](example/).

## Dart engine package

```bash
cd packages/office_viewer_engine_dart
flutter pub get
flutter test
```

## Convert engine package (legacy DOC/XLS/PPT)

```bash
cd packages/office_viewer_engine_convert
flutter pub get
flutter test
```

Native Office Oxide prebuilds (v0.1.2) ship under:

- `native/macos/arm64/lib/liboffice_oxide.dylib` (host tests)
- `android/src/main/jniLibs/arm64-v8a/liboffice_oxide.so`
- `ios/Frameworks/OfficeOxide.xcframework` (device + sim dynamic; rebuild with
  `packages/office_viewer_engine_convert/tool/build_ios_oxide.sh`)

Override desktop/Android with `OFFICE_OXIDE_LIB=/path/to/liboffice_oxide.dylib`
if needed. iOS opens `OfficeOxide.framework/OfficeOxide` from the XCFramework.

Throwaway spike: [`tool/legacy_convert_spike/`](tool/legacy_convert_spike/).

Register with the viewer:

```dart
OfficeEngineRegistry.instance
  ..clear()
  ..register(PdfOfficeEngine())
  ..register(ConvertOfficeEngine())
  ..register(DartOfficeEngine());
```

## After merging to `main` (maintainers)

Run this checklist whenever user-facing or publishable code lands on `main`.
Skip items that truly do not apply; do not skip the **Docs sync** or **Pub
example** rows if engines / install instructions changed.

### 1. Quality gate
- [ ] On `main`: `flutter pub get && flutter analyze && flutter test`
- [ ] Smoke [`example/`](example/) and/or [`example_app/`](example_app/) on a device if viewers/engines changed

### 2. Version & changelog
- [ ] Bump versions that need a pub upload (`office_viewer`, and any changed engine under `packages/`)
- [ ] Update that package’s `CHANGELOG.md` (and root `CHANGELOG.md` for the core)
- [ ] `pubspec.yaml` **description** is **60–180** characters (pub points)

### 3. Docs sync (easy to miss)
- [ ] Root [`README.md`](README.md): Install, Support matrix, Getting started registry order, Limitations, Coming next
- [ ] Engine READMEs if their public API / platforms / install changed
- [ ] This file if publish order or packages changed
- [ ] **Pub example** [`example/`](example/) matches what README tells users to install (engines + samples). `example_app/` alone is **not** enough — it is not on pub.dev
- [ ] Remove stale wording (“not published yet”, path-only engines, LOK, etc.)

### 4. Dependency floors
- [ ] Engine `office_viewer:` constraints still resolve against the version you are about to publish
- [ ] [`example/pubspec.yaml`](example/pubspec.yaml) hosted engine pins (`^x.y.z`) match published engines (path overrides are monorepo-only)

### 5. Publish to pub.dev
Order: **core → dart → convert**. PDF is separate when it changes.

```bash
# dry-run first
./tool/publish.sh --dry-run

# or publish for real
./tool/publish.sh --force

# PDF only (when bumped):
#   mv .pubignore .pubignore.publish_bak
#   (cd packages/office_viewer_engine_pdf && flutter pub publish --force)
#   mv .pubignore.publish_bak .pubignore
```

- [ ] Confirm new versions on pub.dev (`office_viewer`, then engines)
- [ ] Wait for scores / “Package validation” — description length, LICENSE, README, CHANGELOG

### 6. GitHub Release
- [ ] Tag matches the core version, e.g. `v0.0.11`
- [ ] Release notes cover core + any engines published in the same cut
- [ ] If `gh release create` fails with **workflow** scope: `gh auth refresh -h github.com -s workflow`

### 7. Downstream hosts (when relevant)
- [ ] YChat / other apps: bump to new `^` pins (drop path overrides if they were experimental)
- [ ] Confirm registry order still **PDF → Convert (optional) → Dart**
- [ ] Delete merged feature branches if still remote

### Publishing notes

`./tool/publish.sh` publishes `office_viewer` → `office_viewer_engine_dart` →
`office_viewer_engine_convert`. The root `.pubignore` excludes `packages/` so
the core tarball stays lean; the script moves that file aside for engine
publishes (otherwise pub treats the engine pubspec as hidden).

`pubspec_overrides.yaml` is local-only and is not published.

## Known gaps (contributor)

User-facing limits live in the README **Support** / **Limitations** sections.
Internal notes:

- Memory: viewport-culled sheet tiles; clamp sheet extent
- PDF uses pdfrx — register it before Convert / Dart
- Still open: ODF / CSV / TXT; OOXML password decrypt; convert fidelity (charts/images)
