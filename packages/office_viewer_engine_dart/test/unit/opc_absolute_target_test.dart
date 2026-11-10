import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';

/// Regression: workbook rel Target="/xl/worksheets/sheet1.xml" must not become
/// xl/xl/worksheets/sheet1.xml.
void main() {
  test('absolute worksheet Target resolves under xl/', () {
    final archive = Archive();
    void add(String path, String text) {
      final data = utf8.encode(text);
      archive.addFile(ArchiveFile(path, data.length, data));
    }

    add('[Content_Types].xml', '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''');
    add('_rels/.rels', '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
    add('xl/workbook.xml', '''
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
    add('xl/_rels/workbook.xml.rels', '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml"/>
</Relationships>''');
    add('xl/worksheets/sheet1.xml', '''
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Hi</t></is></c></row></sheetData>
</worksheet>''');

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final wb = const XlsxParser().parse(PackageReader.open(bytes));
    expect(wb.sheets, isNotEmpty);
    expect(wb.sheets.first.name, 'Data');
    expect(wb.sheets.first.cells, isNotEmpty);
  });

  test('example large_sheet.xlsx sheet name is Data', () async {
    final path =
        '${Directory.current.path}/../../example_app/assets/large_sheet.xlsx';
    final bytes = await File(path).readAsBytes();
    final wb = const XlsxParser().parse(PackageReader.open(bytes));
    expect(wb.sheets.single.name, 'Data');
    expect(wb.sheets.single.cells.length, greaterThan(5));
  });
}
