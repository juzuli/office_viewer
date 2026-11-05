import 'dart:typed_data';

enum OfficeFormat {
  pdf,
  docx,
  xlsx,
  pptx,
  doc,
  xls,
  ppt,
  odt,
  ods,
  odp,
  csv,
  txt,
  unknown;

  static OfficeFormat fromName(String? name, {Uint8List? head}) {
    if (head != null &&
        head.length >= 4 &&
        head[0] == 0x25 && // %PDF
        head[1] == 0x50 &&
        head[2] == 0x44 &&
        head[3] == 0x46) {
      return OfficeFormat.pdf;
    }
    final ext = (name ?? '').split('.').last.toLowerCase();
    for (final f in OfficeFormat.values) {
      if (f.name == ext) return f;
    }
    return OfficeFormat.unknown;
  }
}

/// What a "part" of a document is. Maps to the user-facing concept:
/// Writer = pages, Calc = sheets, Impress = slides.
enum PartKind { page, sheet, slide }
