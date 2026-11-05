# Phase 0 — LOK go/no-go notes

Private spike only. Extracted viewer APK binaries must not be redistributed.

## Environment

| Field | Value |
|---|---|
| Date | 2026-11-04 |
| Device / emulator | POCO M2 Pro (`592d4543`) — mid-range; **not** a 2–3 GB low-end phone |
| Android ABI | arm64-v8a · Android 12 (API 31) |
| Flutter version | FVM 3.38.1 |
| LOK_HOME source | F-Droid viewer APK 26.2.6.3 (`_131`) |
| `SOURCE.txt` sha256 | `751ac3836890b79a56801bf6d9a2788cda3761ab5131a4f0b6abfbad822bb475` |

## Binary gate

- [x] `tool/verify_lok_symbols.sh` PASS on `LOK_HOME`
- [x] Assets present (`program/`, `share/`, `unpack/`)
- [x] Alternate suite APK fallback: **n/a** (viewer APK passed)

## Reading the numbers

| Signal | Verdict |
|---|---|
| Load **~196–278 ms**, first tile **~28–46 ms** | Comfortably fast enough for a viewer |
| PSS **~250 MB** | Heavy on 2–3 GB phones — re-test on low-end before calling memory OK |
| APK **217 MB** | Far above what most apps can put in the base install — check Play size limits; plan **on-demand** delivery (Play Feature Delivery / asset packs) |
| Fidelity | **Not measured** — Phase 0 only proved tiles paint |

Open risks: **size, memory, iOS, fidelity**.

## Metrics (from example UI + adb)

| Metric | With LOK | Notes |
|---|---|---|
| Release APK size | **217 MB** | Dominated by `liblo-native-code.so` (~187 MB) |
| Cold start (first frame) | **~25–32 ms** | metrics bar |
| documentLoad | **196 ms** (`sample.docx`) / **274–278 ms** (`large_sheet.xlsx`) | |
| First 256² tile | **28–46 ms** | |
| Tile latency p50 / p95 | **28 / 28** (n=1) | Run **Bench tiles** for a fuller sample |
| Peak memory (TOTAL PSS) | **~250 MB** (~321 MB RSS) | Sheet open on POCO M2 Pro |

```bash
cd example && flutter build apk --release
ls -lh build/app/outputs/flutter-apk/app-release.apk
adb shell dumpsys meminfo com.example.example
```

## Calc / large sheet (weak spot — own line)

**Historical (pre rich-sample swap):** fixture was **200 data rows × 20 cols**
(`RnCm` shared strings), sheet `Sheet1`, used-area **1005 × 2563 pt**, load
**~274–278 ms**, first tile **~28 ms**, H/V scroll OK.

**Current fixture:** `example/assets/large_sheet.xlsx` is a public charts demo
(sheet `Data`, native bar + line charts). See `example/assets/SAMPLES.md`.
Re-measure load/tile metrics if citing numbers below.

| Field | Observation (historical grid fixture) |
|---|---|
| LOK used-area (`PartInfo.size`) | **1005 × 2563 pt** (`Sheet1`) |
| Parts | **1** sheet only in this fixture |
| Load | **~274–278 ms** |
| First tile | **~28 ms** |
| Vertical scroll | Works; after swipe, cells around **R64** visible with tile refill |
| Horizontal scroll | Works across columns (C1…C20 in view) |
| Sheet switching | **Not exercised** — only one sheet; UI part dropdown shows `Sheet1` |
| Blank / pop-in | Brief blank tiles until `paintTile` returns (tens of ms) |
| Crashes | None after unpacking `assets/unpack` before init (earlier miss of `udkapi.rdb` → `DeploymentException`) |

Writer smoke (`sample.docx`): used-area **640 × 820 pt**, load **~196 ms**, first tile **~46 ms**, text tile readable.

## Functional checklist

- [x] `sample.docx` opens + tile visible
- [x] `large_sheet.xlsx` opens, scrolls (H+V) via tiles
- [ ] Multi-sheet workbook + tab switch timing
- [ ] Low-end (2–3 GB) memory re-test
- [ ] Fidelity corpus (see next steps)

## Go / no-go (Android latency)

- [x] **GO on latency** — continue Android LOK path for fidelity work
- [ ] Memory / size still **conditional** (on-demand delivery + low-end test)
- [ ] **iOS feasibility is the plan threat** — resolve before more Android depth

## Ordered next steps

1. **iOS feasibility (before more Android work)** — **assessed 2026-11-04**  
   See [`ios_feasibility.md`](ios_feasibility.md).  
   - Technology: **possible** (upstream static `CPiOS` / iOS LOK, same LOK API).  
   - IPA extract: **impossible**.  
   - This Mac: **blocked** (~7 GB free; need ≥50 GB). Plugin iOS stub returns `ios_lok_not_built`.  
   - Checkpoint: free disk (or other Mac) → first `paintTile` on device → size/RSS → go/no-go; else Quick Look on iOS.

2. **Fidelity test set on Android (top product priority)** — **next once iOS path is decided or parked**  
   Phase 0 ≠ fidelity. Build 20–30 real docs vs common Office suites:
   - Calibri / Cambria / Arial + embedded fonts  
   - Tables, headers/footers, columns, floating images  
   - Charts, merged cells, frozen panes, conditional formatting  
   - Indic, CJK, RTL  
   - Slides with masters and shapes  

3. **Engine in a separate Android process**  
   Memory reclaim on close + crash isolation; FFI off the UI isolate; one ordered worker for load/tiles.

4. **Own Linux LOK build before shipping**  
   Extracted Viewer binary = private spike only. Option 4 + license review on the critical path.

5. **Size reduction**  
   On-demand font packs, ABI splits, custom build dropping unused LO modules (needs own build).
