# M0 spike findings

Spike location: `tool/dart_engine_spike/` (throwaway; not published).
Tests: `flutter test` with Flutter 3.47.9 / Dart 3.13.7 — all three proofs green.

## 1. Threading / text measurement

**Decision:** Parse and style resolution run in a **background isolate** (`Isolate.run`
or a long-lived worker). **Text measurement** (`ParagraphBuilder` / `TextPainter`)
and **tile painting** (`PictureRecorder` → `toImage`) stay on the **UI / root
isolate**, time-sliced when layout is heavy.

**Why:** Plain background isolates can do pure Dart work on bytes/XML, but
`dart:ui` text APIs are not safely usable there without `RootIsolateToken` +
engine bindings. The spike proved UI-isolate paragraph layout works; background
isolate summed bytes fine. Prefer the simpler split over relying on
`RootIsolateToken` for every layout call.

## 2. Tile rendering

**Decision:** Build an immutable display list in points → paint with
`Canvas`/`PictureRecorder` at `TileRequest.scale` (pixels per point) →
`Picture.toImage(w,h)` → `ImageByteFormat.rawStraightRgba` or premul as required
by the contract (`RenderedTile` expects **premultiplied** RGBA). Convert to
premul if using straight RGBA.

Spike painted a 256×256 pt region at scale 2.0 (512×512 px) and verified pixel
contents.

## 3. Font loading

**Decision:** Bundle OFL fonts as Flutter assets; register once via `FontLoader`
at engine open / first use. Measure with the registered family name.
Spike used Liberation Sans Regular 2.1.5 (OFL) successfully.

Production package will ship Liberation Sans/Serif/Mono + Carlito (+ Caladea when
sourced) with entries in `THIRD_PARTY_LICENSES.md`.

## Locked for M1+

| Topic | Choice |
|-------|--------|
| Parse/XML | Background isolate |
| Measure + paint | UI isolate |
| Tile path | DisplayList → PictureRecorder → premul RGBA |
| Fonts | Asset + FontLoader + substitution table |
