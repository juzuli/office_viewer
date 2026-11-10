import 'package:xml/xml.dart';

import 'docx_xml.dart';

enum DocNumFmt {
  decimal,
  bullet,
  lowerRoman,
  upperRoman,
  lowerLetter,
  upperLetter,
  none,
}

class DocNumLevel {
  const DocNumLevel({
    required this.ilvl,
    required this.numFmt,
    required this.lvlText,
    required this.start,
    this.suff = '',
    this.indentLeftTwip,
    this.indentHangingTwip,
  });

  final int ilvl;
  final DocNumFmt numFmt;
  final String lvlText;
  final int start;
  final String suff;
  final int? indentLeftTwip;
  final int? indentHangingTwip;
}

class DocAbstractNum {
  const DocAbstractNum({
    required this.abstractNumId,
    required this.levels,
  });

  final int abstractNumId;
  final Map<int, DocNumLevel> levels;
}

class DocNumInstance {
  const DocNumInstance({
    required this.numId,
    required this.abstractNumId,
  });

  final int numId;
  final int abstractNumId;
}

class DocxNumbering {
  DocxNumbering({
    required this.abstractNums,
    required this.nums,
    this.warnings = const [],
  });

  final Map<int, DocAbstractNum> abstractNums;
  final Map<int, DocNumInstance> nums;
  final List<String> warnings;

  static final empty = DocxNumbering(abstractNums: const {}, nums: const {});

  static DocxNumbering parse(String? xmlText) {
    if (xmlText == null) return DocxNumbering.empty;
    final warnings = <String>[];
    final abstractNums = <int, DocAbstractNum>{};
    final nums = <int, DocNumInstance>{};

    try {
      final doc = XmlDocument.parse(xmlText);
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 'abstractNum') {
          final id = docxIntAttr(el, 'abstractNumId');
          if (id == null) continue;
          final levels = <int, DocNumLevel>{};
          for (final lvlEl in docxChildren(el, 'lvl')) {
            final ilvl = docxIntAttr(lvlEl, 'ilvl') ?? 0;
            final fmtRaw = docxAttr(docxChild(lvlEl, 'numFmt'), 'val');
            final lvlText =
                docxAttr(docxChild(lvlEl, 'lvlText'), 'val') ?? '%1.';
            final start =
                docxIntAttr(docxChild(lvlEl, 'start'), 'val') ?? 1;
            final lvlPPr = docxChild(lvlEl, 'pPr');
            final ind = lvlPPr != null ? docxChild(lvlPPr, 'ind') : null;
            levels[ilvl] = DocNumLevel(
              ilvl: ilvl,
              numFmt: _parseFmt(fmtRaw),
              lvlText: lvlText,
              start: start,
              indentLeftTwip: docxIntAttr(ind, 'left'),
              indentHangingTwip: docxIntAttr(ind, 'hanging'),
            );
          }
          abstractNums[id] = DocAbstractNum(
            abstractNumId: id,
            levels: levels,
          );
        } else if (el.name.local == 'num') {
          final numId = docxIntAttr(el, 'numId');
          final abstractId =
              docxIntAttr(docxChild(el, 'abstractNumId'), 'val');
          if (numId != null && abstractId != null) {
            nums[numId] = DocNumInstance(
              numId: numId,
              abstractNumId: abstractId,
            );
          }
        }
      }
    } catch (e) {
      warnings.add('numbering.xml parse failed: $e');
    }

    return DocxNumbering(
      abstractNums: abstractNums,
      nums: nums,
      warnings: warnings,
    );
  }

  String? formatLabel({
    required int numId,
    required int ilvl,
    required List<int> counters,
  }) {
    final inst = nums[numId];
    if (inst == null) return null;
    final abs = abstractNums[inst.abstractNumId];
    if (abs == null) return null;
    final lvl = abs.levels[ilvl] ?? abs.levels[0];
    if (lvl == null) return null;

    final value = ilvl < counters.length ? counters[ilvl] : lvl.start;
    // Symbol/Wingdings private-use bullet glyphs rarely have a font mapped;
    // render a standard bullet when the level is a bullet format.
    if (lvl.numFmt == DocNumFmt.bullet) {
      return '•';
    }
    var text = lvl.lvlText;
    for (var i = 0; i <= ilvl; i++) {
      final cv = i < counters.length ? counters[i] : 1;
      final lvlDef = abs.levels[i] ?? lvl;
      final replacement = _formatCounter(lvlDef.numFmt, cv);
      text = text.replaceAll('%${i + 1}', replacement);
    }
    if (text.contains('%')) {
      text = text.replaceAll('%1', _formatCounter(lvl.numFmt, value));
    }
    // Strip leftover private-use / Symbol bullet code points.
    text = text.replaceAll(RegExp(r'[\uF000-\uF0FF]'), '•');
    return text;
  }

  /// Indent (twips) for a numbering level, if declared on the abstract level.
  ({int? left, int? hanging})? levelIndent({
    required int numId,
    required int ilvl,
  }) {
    final inst = nums[numId];
    if (inst == null) return null;
    final abs = abstractNums[inst.abstractNumId];
    final lvl = abs?.levels[ilvl] ?? abs?.levels[0];
    if (lvl == null) return null;
    return (left: lvl.indentLeftTwip, hanging: lvl.indentHangingTwip);
  }
}

DocNumFmt _parseFmt(String? raw) {
  switch (raw) {
    case 'bullet':
      return DocNumFmt.bullet;
    case 'lowerRoman':
      return DocNumFmt.lowerRoman;
    case 'upperRoman':
      return DocNumFmt.upperRoman;
    case 'lowerLetter':
      return DocNumFmt.lowerLetter;
    case 'upperLetter':
      return DocNumFmt.upperLetter;
    case 'none':
      return DocNumFmt.none;
    case 'decimal':
    default:
      return DocNumFmt.decimal;
  }
}

String _formatCounter(DocNumFmt fmt, int value) {
  switch (fmt) {
    case DocNumFmt.bullet:
      return '•';
    case DocNumFmt.decimal:
      return '$value';
    case DocNumFmt.lowerRoman:
      return _toRoman(value).toLowerCase();
    case DocNumFmt.upperRoman:
      return _toRoman(value);
    case DocNumFmt.lowerLetter:
      return _toLetter(value, lower: true);
    case DocNumFmt.upperLetter:
      return _toLetter(value, lower: false);
    case DocNumFmt.none:
      return '';
  }
}

String _toRoman(int n) {
  if (n <= 0) return '0';
  const pairs = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  var v = n;
  final buf = StringBuffer();
  for (final (d, sym) in pairs) {
    while (v >= d) {
      buf.write(sym);
      v -= d;
    }
  }
  return buf.toString();
}

String _toLetter(int value, {required bool lower}) {
  var v = value;
  if (v <= 0) v = 1;
  final code = (v - 1) % 26;
  final ch = String.fromCharCode((lower ? 97 : 65) + code);
  return ch;
}
