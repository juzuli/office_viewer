# Leafpane example

Demo host for Leafpane’s [`office_viewer`](../) package — Word, Excel,
PowerPoint, and PDF on Android and iOS. Suitable for pub.dev listing screenshots.

## Prerequisites (native Office engine)

```bash
cd ../packages/office_viewer_engine_lok
./tool/fetch_viewer_apk.sh
./tool/install_lok_home.sh tool/cache/*-arm64.apk
# iOS (after a CPiOS engine build):
./tool/install_lok_home_ios.sh
```

## Run

```bash
flutter pub get
flutter run -d <android-arm64>   # or an iPhone
```

Tap **Word / Excel / PowerPoint / PDF** for bundled samples, or **Open** for a
file on the device.

Bundled samples: `sample.docx`, `large_sheet.xlsx`, `sample_deck.pptx`,
`sample.pdf` — see [`assets/SAMPLES.md`](assets/SAMPLES.md).
