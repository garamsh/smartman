import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A cell a test writes: text as a shared string, a number, a number drawn
/// through a format code or a built-in format's id, or a formula with its
/// cached value.
sealed class TestCell {
  const TestCell();
}

/// Text written as a shared string, or no cell where [text] is null.
final class StringCell extends TestCell {
  const StringCell(this.text);

  final String? text;
}

final class NumberCell extends TestCell {
  const NumberCell(this.number, [this.format]);

  final num number;

  /// A format code, or a built-in format's id.
  final Object? format;
}

final class FormulaCell extends TestCell {
  const FormulaCell(this.formula, this.cached);

  final String formula;

  /// A number, a string, or null for a formula saved with no cached value.
  final Object? cached;
}

/// A sheet a test writes.
final class TestSheet {
  const TestSheet(this.name, this.rows, {this.hidden = false});

  final String name;
  final List<List<TestCell>> rows;
  final bool hidden;
}

String _escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _columnName(int index) {
  var name = '';
  for (var at = index + 1; at > 0; at = (at - 1) ~/ 26) {
    name = String.fromCharCode(65 + (at - 1) % 26) + name;
  }
  return name;
}

/// An `.xlsx` workbook's bytes, written as Excel lays one out, its sheets in
/// order.
Uint8List xlsxOf(List<TestSheet> sheets, {bool date1904 = false}) {
  final strings = <String>[];
  final formats = <Object>[];
  int stringAt(String text) {
    if (!strings.contains(text)) strings.add(text);
    return strings.indexOf(text);
  }

  int styleAt(Object format) {
    if (!formats.contains(format)) formats.add(format);
    return formats.indexOf(format) + 1;
  }

  String cellXml(TestCell cell, String ref) => switch (cell) {
    StringCell(text: null) => '',
    StringCell(:final text?) =>
      '<c r="$ref" t="s"><v>${stringAt(text)}</v></c>',
    NumberCell(:final number, format: null) => '<c r="$ref"><v>$number</v></c>',
    NumberCell(:final number, :final format?) =>
      '<c r="$ref" s="${styleAt(format)}"><v>$number</v></c>',
    FormulaCell(:final formula, :final cached) =>
      '<c r="$ref"${cached is String ? ' t="str"' : ''}>'
          '<f>${_escaped(formula)}</f>'
          '${cached == null ? '' : '<v>${_escaped('$cached')}</v>'}</c>',
  };

  String sheetXml(List<List<TestCell>> rows) => [
    for (final (r, cells) in rows.indexed)
      '<row r="${r + 1}">${[for (final (c, cell) in cells.indexed) cellXml(cell, '${_columnName(c)}${r + 1}')].join()}</row>',
  ].join();

  const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const head = '<?xml version="1.0" encoding="UTF-8"?>';
  final zip = Archive();
  void add(String name, String text) =>
      zip.add(ArchiveFile.bytes(name, utf8.encode(text)));
  for (final (index, sheet) in sheets.indexed) {
    add(
      'xl/worksheets/sheet${index + 1}.xml',
      '$head<worksheet xmlns="$main"><sheetData>${sheetXml(sheet.rows)}</sheetData></worksheet>',
    );
  }
  final entries = [
    for (final (index, sheet) in sheets.indexed)
      '<sheet name="${_escaped(sheet.name)}" sheetId="${index + 1}"'
          '${sheet.hidden ? ' state="hidden"' : ''} r:id="rId${index + 1}"/>',
  ].join();
  add(
    'xl/workbook.xml',
    '$head<workbook xmlns="$main" xmlns:r="$rel">'
        '<workbookPr${date1904 ? ' date1904="1"' : ''}/>'
        '<sheets>$entries</sheets></workbook>',
  );
  final relationships = [
    for (var index = 0; index < sheets.length; index++)
      '<Relationship Id="rId${index + 1}" Type="$rel/worksheet" '
          'Target="worksheets/sheet${index + 1}.xml"/>',
  ].join();
  add(
    'xl/_rels/workbook.xml.rels',
    '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$relationships</Relationships>',
  );
  final items = [
    for (final text in strings)
      '<si><t xml:space="preserve">${_escaped(text)}</t></si>',
  ].join();
  add('xl/sharedStrings.xml', '$head<sst xmlns="$main">$items</sst>');
  final codes = [
    for (final (index, format) in formats.indexed)
      if (format is String)
        '<numFmt numFmtId="${index + 164}" formatCode="${_escaped(format)}"/>',
  ].join();
  final styles = [
    for (final (index, format) in formats.indexed)
      '<xf numFmtId="${format is int ? format : index + 164}" '
          'applyNumberFormat="1"/>',
  ].join();
  add(
    'xl/styles.xml',
    '$head<styleSheet xmlns="$main"><numFmts>$codes</numFmts>'
        '<cellXfs><xf numFmtId="0"/>$styles</cellXfs></styleSheet>',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
}
