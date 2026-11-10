import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/src/xlsx/number_format.dart';

void main() {
  test('General and numeric formats', () {
    expect(
      NumberFormat.format(value: 42, formatCode: 'General', date1904: false)
          .text,
      '42',
    );
    expect(
      NumberFormat.format(value: 0.5, formatCode: '0%', date1904: false).text,
      contains('50'),
    );
    final decimals = NumberFormat.format(
      value: 1234.5,
      formatCode: '0.00',
      date1904: false,
    ).text;
    expect(decimals, anyOf('1234.50', '1234.5'));
  });

  test('Excel 1900 date serial produces non-empty date string', () {
    final formatted = NumberFormat.format(
      value: 1,
      formatCode: 'yyyy-mm-dd',
      date1904: false,
    ).text;
    expect(formatted, isNotEmpty);
  });

  test('text format passthrough', () {
    expect(
      NumberFormat.format(value: 'hello', formatCode: '@', date1904: false)
          .text,
      'hello',
    );
  });
}
