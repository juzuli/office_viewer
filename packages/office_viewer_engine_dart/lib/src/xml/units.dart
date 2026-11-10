/// EMU (English Metric Units) per inch in OOXML.
const double emuPerInch = 914400;

/// Twips per inch (1/20 point).
const double twipsPerInch = 1440;

/// Points per inch.
const double pointsPerInch = 72;

/// EMU per point: 914400 / 72 = 12700.
const double emuPerPoint = emuPerInch / pointsPerInch;

/// Twips per point.
const double twipsPerPoint = twipsPerInch / pointsPerInch;

double emuToPt(num emu) => emu.toDouble() / emuPerPoint;

double ptToEmu(num pt) => pt.toDouble() * emuPerPoint;

double twipToPt(num twip) => twip.toDouble() / twipsPerPoint;

/// Font size in half-points (w:sz) → points.
double halfPointToPt(num halfPt) => halfPt.toDouble() / 2;

/// Line spacing in eighths of a point.
double eighthPointToPt(num eighths) => eighths.toDouble() / 8;

/// OOXML percentage in thousandths (100000 = 100%).
double percent1000(num thousandths) => thousandths.toDouble() / 1000;

/// OOXML angle in 1/60000 of a degree → degrees.
double angle60000(num units) => units.toDouble() / 60000;
