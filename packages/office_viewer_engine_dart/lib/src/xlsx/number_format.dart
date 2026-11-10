import 'dart:math' as math;
import 'dart:ui';

/// Display text for a cell plus optional Excel section color hint.
class FormattedCellValue {
  const FormattedCellValue(this.text, {this.colorHint});

  final String text;
  final Color? colorHint;
}

/// Built-in Excel numFmtId → format code (subset of ECMA-376).
final Map<int, String> _builtInNumFmts = {
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  5: r'"$"#,##0_);("$"#,##0)',
  6: r'"$"#,##0_);[Red]("$"#,##0)',
  7: r'"$"#,##0.00_);("$"#,##0.00)',
  8: r'"$"#,##0.00_);[Red]("$"#,##0.00)',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'm/d/yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yy h:mm',
  37: '#,##0_);(#,##0)',
  38: '#,##0_);[Red](#,##0)',
  39: '#,##0.00_);(#,##0.00)',
  40: '#,##0.00_);[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mm:ss.0',
  49: '@',
};

class NumberFormat {
  const NumberFormat._();

  static String resolveCode(int numFmtId, Map<int, String> custom) {
    return custom[numFmtId] ?? _builtInNumFmts[numFmtId] ?? 'General';
  }

  static FormattedCellValue format({
    required Object? value,
    required String formatCode,
    required bool date1904,
    bool forceText = false,
  }) {
    if (forceText || formatCode == '@' || formatCode.contains('@')) {
      return FormattedCellValue(value?.toString() ?? '');
    }

    if (formatCode == 'General' || formatCode.isEmpty) {
      return FormattedCellValue(_formatGeneral(value));
    }

    final sections = _splitSections(formatCode);
    final numVal = _asNumber(value);
    if (numVal == null) {
      final textSection = sections.length > 3 ? sections[3] : null;
      if (textSection != null && textSection.contains('@')) {
        return FormattedCellValue(
          value?.toString() ?? '',
          colorHint: _sectionColor(textSection),
        );
      }
      return FormattedCellValue(value?.toString() ?? '');
    }

    String section;
    Color? hint;
    if (sections.length >= 4) {
      section = sections[3];
      hint = _sectionColor(section);
      return FormattedCellValue(
        _applyTextSection(section, value?.toString() ?? ''),
        colorHint: hint,
      );
    }

    if (numVal == 0 && sections.length >= 3) {
      section = sections[2];
      hint = _sectionColor(section);
      return FormattedCellValue(
        _formatWithSection(numVal, section, date1904),
        colorHint: hint,
      );
    }

    if (numVal < 0 && sections.length >= 2) {
      section = sections[1];
      hint = _sectionColor(section);
      return FormattedCellValue(
        _formatWithSection(numVal.abs(), section, date1904, negative: true),
        colorHint: hint,
      );
    }

    section = sections.first;
    hint = _sectionColor(section);
    return FormattedCellValue(
      _formatWithSection(numVal, section, date1904),
      colorHint: hint,
    );
  }

  static String _formatGeneral(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final d = value.toDouble();
      if (d == d.roundToDouble() && d.abs() < 1e15) {
        return d.round().toString();
      }
      return _trimTrailingZeros(d.toString());
    }
    return value.toString();
  }

  static String _trimTrailingZeros(String s) {
    if (!s.contains('.')) return s;
    var out = s;
    while (out.endsWith('0')) {
      out = out.substring(0, out.length - 1);
    }
    if (out.endsWith('.')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  static double? _asNumber(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static List<String> _splitSections(String code) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < code.length; i++) {
      final ch = code[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        buf.write(ch);
        continue;
      }
      if (ch == ';' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    out.add(buf.toString());
    return out;
  }

  static Color? _sectionColor(String section) {
    final m = RegExp(r'\[(Black|Blue|Cyan|Green|Magenta|Red|White|Yellow)\]',
            caseSensitive: false)
        .firstMatch(section);
    if (m == null) return null;
    switch (m.group(1)!.toLowerCase()) {
      case 'black':
        return const Color(0xFF000000);
      case 'blue':
        return const Color(0xFF0000FF);
      case 'cyan':
        return const Color(0xFF00FFFF);
      case 'green':
        return const Color(0xFF00FF00);
      case 'magenta':
        return const Color(0xFFFF00FF);
      case 'red':
        return const Color(0xFFFF0000);
      case 'white':
        return const Color(0xFFFFFFFF);
      case 'yellow':
        return const Color(0xFFFFFF00);
      default:
        return null;
    }
  }

  static String _applyTextSection(String section, String text) {
    if (section.contains('@')) return text;
    return text;
  }

  static String _formatWithSection(
    double v,
    String section,
    bool date1904, {
    bool negative = false,
  }) {
    final stripped = section.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    if (_looksLikeDate(stripped)) {
      return _formatDate(v, stripped, date1904);
    }
    if (stripped.contains('E+') || stripped.contains('E0')) {
      return _formatScientific(v, stripped, negative: negative);
    }
    if (stripped.contains('%')) {
      return _formatPercent(v, stripped, negative: negative);
    }
  return _formatNumberPattern(v, stripped, negative: negative);
  }

  static bool _looksLikeDate(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('yy') ||
        lower.contains('mm') ||
        lower.contains('dd') ||
        lower.contains('h:') ||
        lower.contains('am/pm')) {
      return !s.contains('#') && !s.contains('0.00E');
    }
    return false;
  }

  static String _formatDate(double serial, String pattern, bool date1904) {
    final dt = excelSerialToDateTime(serial, date1904: date1904);
    if (dt == null) return serial.toString();

    var out = pattern;
    final y = dt.year;
    final m = dt.month;
    final d = dt.day;
    final h = dt.hour;
    final min = dt.minute;
    final sec = dt.second;

    out = out.replaceAll(RegExp('yyyy', caseSensitive: false), y.toString());
    out = out.replaceAll(
      RegExp('yy', caseSensitive: false),
      (y % 100).toString().padLeft(2, '0'),
    );

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final mmm = months[m - 1];
    out = out.replaceAll(RegExp('mmmm', caseSensitive: false), _monthFull(m));
    out = out.replaceAll(RegExp('mmm', caseSensitive: false), mmm);
    out = out.replaceAll(
      RegExp('mm', caseSensitive: false),
      m.toString().padLeft(2, '0'),
    );
    out = out.replaceAll(RegExp('dd', caseSensitive: false), d.toString().padLeft(2, '0'));
    out = out.replaceAll(RegExp('d', caseSensitive: false), d.toString());

    var hour = h;
    var ampm = '';
    if (pattern.toLowerCase().contains('am/pm')) {
      ampm = hour >= 12 ? ' PM' : ' AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
    }
    out = out.replaceAll(
      RegExp('h:mm:ss', caseSensitive: false),
      '$hour:${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
    );
    out = out.replaceAll(
      RegExp('h:mm', caseSensitive: false),
      '$hour:${min.toString().padLeft(2, '0')}',
    );
    out = out.replaceAll(RegExp('AM/PM', caseSensitive: false), ampm.trim());

    return out + ampm;
  }

  static String _monthFull(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[m - 1];
  }

  /// Excel serial day → [DateTime] (local calendar date + time fraction).
  static DateTime? excelSerialToDateTime(double serial, {required bool date1904}) {
    if (serial.isNaN || serial.isInfinite) return null;

    // Whole-day serial 60 does not exist in the 1900 calendar (phantom Feb 29).
    final whole = serial.floor();
    if (!date1904 && whole == 60) {
      return null;
    }

    final fraction = serial - whole;
    final epoch = date1904
        ? DateTime(1904, 1, 1)
        : DateTime(1899, 12, 30); // 1900 system + leap quirk base

    var dayOffset = whole;
    if (!date1904 && whole > 60) {
      dayOffset -= 1; // skip nonexistent Feb 29 1900
    }

    final base = epoch.add(Duration(days: dayOffset));
    final seconds = (fraction * 86400).round();
    return DateTime(
      base.year,
      base.month,
      base.day,
      seconds ~/ 3600,
      (seconds % 3600) ~/ 60,
      seconds % 60,
    );
  }

  static String _formatScientific(double v, String pattern, {required bool negative}) {
    final decimals = _decimalPlaces(pattern);
    final mag = v == 0 ? 0 : (math.log(v.abs()) / math.ln10).floor();
    final mantissa = v == 0 ? 0.0 : v / math.pow(10, mag);
    final sign = negative ? '-' : (v < 0 ? '-' : '');
    final mStr = mantissa.abs().toStringAsFixed(decimals);
    final eStr = mag >= 0 ? '+$mag' : '$mag';
    return '${sign}${mStr}E$eStr';
  }

  static String _formatPercent(double v, String pattern, {required bool negative}) {
    final decimals = _decimalPlaces(pattern);
    final pct = v * 100;
    final sign = negative ? '-' : (pct < 0 ? '-' : '');
    return '$sign${pct.abs().toStringAsFixed(decimals)}%';
  }

  static String _formatNumberPattern(
    double v,
    String pattern, {
    required bool negative,
  }) {
    final decimals = _decimalPlaces(pattern);
    final useThousands = pattern.contains(',');
    final sign = negative ? '-' : (v < 0 ? '-' : '');
    var abs = v.abs();
    var formatted = abs.toStringAsFixed(decimals);
    if (useThousands) {
      final parts = formatted.split('.');
      parts[0] = _groupThousands(parts[0]);
      formatted = parts.length > 1 ? '${parts[0]}.${parts[1]}' : parts[0];
    }
    formatted = _trimTrailingZeros(formatted);
    return '$sign$formatted';
  }

  static String _groupThousands(String digits) {
    final buf = StringBuffer();
    var count = 0;
    for (var i = digits.length - 1; i >= 0; i--) {
      if (count == 3) {
        buf.write(',');
        count = 0;
      }
      buf.write(digits[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }

  static int _decimalPlaces(String pattern) {
    final dot = pattern.indexOf('.');
    if (dot < 0) return 0;
    var n = 0;
    for (var i = dot + 1; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '0' || ch == '#') {
        n++;
      } else {
        break;
      }
    }
    return n;
  }
}
