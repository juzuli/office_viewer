import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';

void main() {
  test('PdfOfficeEngine only claims PDF', () {
    final e = PdfOfficeEngine();
    expect(e.id, 'pdf');
    expect(e.supports(OfficeFormat.pdf), isTrue);
    expect(e.supports(OfficeFormat.docx), isFalse);
    expect(e.supports(OfficeFormat.xlsx), isFalse);
  });
}
