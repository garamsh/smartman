import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'spreadsheet_format.dart';

/// The largest file read, refused by its size before a byte of it is read
/// (ADR 0125).
const spreadsheetFileLimit = 5 * 1024 * 1024;

/// The most rows holding text a sheet may have.
const spreadsheetRowLimit = 1000;

/// The most a workbook part may unpack to.
const _partLimit = 50 * 1024 * 1024;

/// The columns a sheet can have, Excel's own limit.
const _columnLimit = 16384;

/// Why a file or a sheet makes no cards.
enum SpreadsheetRefusal {
  /// Neither `.xlsx` nor `.csv`.
  wrongType,

  /// Over [spreadsheetFileLimit].
  tooLarge,

  /// A CSV that is not UTF-8.
  notUtf8,

  /// A workbook that cannot be read.
  unreadable,

  /// A sheet of more than [spreadsheetRowLimit] rows.
  tooManyRows,

  /// A file the device could not hand over.
  notRead,
}

/// A cell as the sheet shows it, and whether it is text rather than a number,
/// date or other value.
final class SheetCell {
  const SheetCell(this.text, {required this.isText});

  final String text;
  final bool isText;
}

/// A row holding text in at least one cell, by its [number] in the sheet,
/// counted from 1.
final class SheetRow {
  const SheetRow(this.number, this.cells);

  final int number;
  final List<SheetCell> cells;
}

/// What reading a sheet gave.
sealed class SheetRead {
  const SheetRead();
}

/// A sheet's rows.
final class SheetRows extends SheetRead {
  const SheetRows(this.rows);

  final List<SheetRow> rows;
}

/// A sheet that makes no cards.
final class RefusedSheet extends SheetRead {
  const RefusedSheet(this.refusal);

  final SpreadsheetRefusal refusal;
}

/// What opening a file gave.
sealed class OpenedFile {
  const OpenedFile();
}

/// A file refused whole.
final class RefusedFile extends OpenedFile {
  const RefusedFile(this.refusal);

  final SpreadsheetRefusal refusal;
}

/// A file's visible sheets, in order, each already read; a CSV is one sheet
/// named for the file.
final class Spreadsheet extends OpenedFile {
  const Spreadsheet(this.name, this.sheets);

  final String name;
  final List<({String name, SheetRead read})> sheets;
}

/// Opens the file [name] of [size] bytes, refusing one over the limit before
/// calling [read], and reads it apart from the interface.
Future<OpenedFile> openSpreadsheet(
  String name,
  int size,
  Future<Uint8List> Function() read,
) async {
  if (_typeOf(name) == null) {
    return const RefusedFile(SpreadsheetRefusal.wrongType);
  }
  if (size > spreadsheetFileLimit) {
    return const RefusedFile(SpreadsheetRefusal.tooLarge);
  }
  return _parseApart(name, await read());
}

/// In a function of its own, so the isolate's closure holds only these two.
Future<OpenedFile> _parseApart(String name, Uint8List bytes) =>
    Isolate.run(() => parseSpreadsheet(name, bytes));

enum _Type { csv, xlsx }

_Type? _typeOf(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.csv')) return _Type.csv;
  if (lower.endsWith('.xlsx')) return _Type.xlsx;
  return null;
}

/// Reads the file [name] holding [bytes].
OpenedFile parseSpreadsheet(String name, Uint8List bytes) {
  switch (_typeOf(name)) {
    case null:
      return const RefusedFile(SpreadsheetRefusal.wrongType);
    case _Type.csv:
      final String text;
      try {
        // Dart's decoder drops a leading byte order mark.
        text = utf8.decode(bytes);
      } on FormatException {
        return const RefusedFile(SpreadsheetRefusal.notUtf8);
      }
      return Spreadsheet(name, [(name: name, read: _csvRows(text))]);
    case _Type.xlsx:
      try {
        return _openWorkbook(name, bytes);
        // A malformed file fails inside either package in ways they do not
        // declare, an out-of-range read among them.
      } on Object {
        return const RefusedFile(SpreadsheetRefusal.unreadable);
      }
  }
}

final _number = RegExp(
  r'^[-+]?[\d,]*\.?\d+(?:e[-+]?\d+)?%?$',
  caseSensitive: false,
);

/// A CSV's rows by RFC 4180: comma-separated, `"` quoting, `""` a quote, line
/// breaks kept inside quotes.
SheetRead _csvRows(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  void endCell() {
    record.add(cell.toString());
    cell.clear();
  }

  for (var at = 0; at < text.length; at++) {
    final char = text[at];
    final next = at + 1 < text.length ? text[at + 1] : null;
    if (quoted) {
      if (char == '"' && next == '"') {
        cell.write('"');
        at++;
      } else if (char == '"') {
        quoted = false;
      } else {
        cell.write(char);
      }
    } else if (char == '"' && cell.isEmpty) {
      quoted = true;
    } else if (char == ',') {
      endCell();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && next == '\n') at++;
      endCell();
      records.add(record);
      record = [];
    } else {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || record.isNotEmpty) {
    endCell();
    records.add(record);
  }
  return _sheetRows({
    for (final (index, cells) in records.indexed)
      index + 1: [
        for (final value in cells)
          SheetCell(value, isText: !_number.hasMatch(value.trim())),
      ],
  });
}

/// Rows holding text, trimmed with their line breaks kept; over the row
/// limit, a refusal. [rows] are by number, in order.
SheetRead _sheetRows(Map<int, List<SheetCell?>> rows) {
  final result = <SheetRow>[];
  rows.forEach((number, cells) {
    final trimmed = [
      for (final cell in cells)
        SheetCell(
          (cell?.text ?? '').replaceAll(RegExp(r'\r\n?'), '\n').trim(),
          isText: cell?.isText ?? true,
        ),
    ];
    if (trimmed.any((cell) => cell.text.isNotEmpty)) {
      result.add(SheetRow(number, trimmed));
    }
  });
  return result.length > spreadsheetRowLimit
      ? const RefusedSheet(SpreadsheetRefusal.tooManyRows)
      : SheetRows(result);
}

/// The text of the part [name] of [zip], or null when it holds none; a part
/// unpacking past the limit throws.
String? _partText(Archive zip, String name) {
  final file = zip.find(name);
  if (file == null) return null;
  if (file.size > _partLimit) throw StateError('part over the unpacked limit');
  return utf8.decode(file.content);
}

/// The part [name] of [zip] parsed, or null when it holds none.
XmlDocument? _part(Archive zip, String name) => switch (_partText(zip, name)) {
  final text? => XmlDocument.parse(text),
  null => null,
};

/// Elements by local name, whatever namespace the writer used.
Iterable<XmlElement> _elements(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((element) => element.localName == name);

Iterable<XmlElement> _children(XmlElement element, String name) => element
    .children
    .whereType<XmlElement>()
    .where((child) => child.localName == name);

OpenedFile _openWorkbook(String name, Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final workbook = _part(zip, 'xl/workbook.xml');
  final rels = _part(zip, 'xl/_rels/workbook.xml.rels');
  if (workbook == null || rels == null) {
    return const RefusedFile(SpreadsheetRefusal.unreadable);
  }
  final targets = {
    for (final rel in _elements(rels, 'Relationship'))
      rel.getAttribute('Id'): rel.getAttribute('Target'),
  };
  final date1904 = _elements(
    workbook,
    'workbookPr',
  ).any((pr) => const {'1', 'true'}.contains(pr.getAttribute('date1904')));
  final parts = [
    for (final sheet in _elements(workbook, 'sheet'))
      if (!const {'hidden', 'veryHidden'}.contains(sheet.getAttribute('state')))
        if ((sheet.getAttribute('name'), targets[_relationshipId(sheet)]) case (
          final name?,
          final target?,
        ))
          (
            name: name,
            path: target.startsWith('/') ? target.substring(1) : 'xl/$target',
          ),
  ];
  if (parts.isEmpty) return const RefusedFile(SpreadsheetRefusal.unreadable);
  final strings = switch (_part(zip, 'xl/sharedStrings.xml')) {
    final shared? => _elements(shared, 'si').map(_itemText).toList(),
    null => const <String>[],
  };
  final formats = _cellFormats(_part(zip, 'xl/styles.xml'));
  return Spreadsheet(name, [
    for (final part in parts)
      (
        name: part.name,
        read: _readPart(zip, part.path, strings, formats, date1904),
      ),
  ]);
}

SheetRead _readPart(
  Archive zip,
  String path,
  List<String> strings,
  List<String> formats,
  bool date1904,
) {
  try {
    final sheet = _partText(zip, path);
    if (sheet == null) {
      return const RefusedSheet(SpreadsheetRefusal.unreadable);
    }
    return _readSheet(sheet, strings, formats, date1904);
    // As in parseSpreadsheet: one sheet's malformed part refuses that sheet.
  } on Object {
    return const RefusedSheet(SpreadsheetRefusal.unreadable);
  }
}

String? _relationshipId(XmlElement sheet) {
  for (final attribute in sheet.attributes) {
    if (attribute.name.local == 'id' && attribute.name.prefix != null) {
      return attribute.value;
    }
  }
  return null;
}

final _escape = RegExp('_x([0-9a-f]{4})_', caseSensitive: false);

/// A string item's text: its runs' text, without phonetic runs, `_xHHHH_`
/// escapes decoded.
String _itemText(XmlElement item) => _elements(item, 't')
    .where((text) => text.parentElement?.localName != 'rPh')
    .map((text) => text.innerText)
    .join()
    .replaceAllMapped(
      _escape,
      (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
    );

/// Each cell style's number format code, by the style's index.
List<String> _cellFormats(XmlDocument? styles) {
  if (styles == null) return const [];
  final custom = {
    for (final format in _elements(styles, 'numFmt'))
      int.tryParse(format.getAttribute('numFmtId') ?? ''):
          format.getAttribute('formatCode') ?? 'General',
  };
  String codeOf(int id) =>
      custom[id] ?? spreadsheetBuiltInFormats[id] ?? 'General';
  return [
    for (final list in _elements(styles, 'cellXfs'))
      for (final style in _children(list, 'xf'))
        codeOf(int.tryParse(style.getAttribute('numFmtId') ?? '') ?? 0),
  ];
}

/// Reads [sheet] a row at a time and stops past the row limit: a sheet can
/// unpack to 50 MB, whole more than a phone holds as one parsed document.
SheetRead _readSheet(
  String sheet,
  List<String> strings,
  List<String> formats,
  bool date1904,
) {
  final rows = SplayTreeMap<int, List<SheetCell?>>();
  var next = 0;
  var open = <XmlEvent>[];
  for (final event in parseEvents(
    sheet,
    validateNesting: true,
    validateDocument: true,
  )) {
    final starts = event is XmlStartElementEvent && event.localName == 'row';
    if (starts || open.isNotEmpty) open.add(event);
    final ends = starts
        ? event.isSelfClosing
        : event is XmlEndElementEvent && event.localName == 'row';
    if (!ends) continue;
    final row = const XmlNodeDecoder().convert(open).single as XmlElement;
    open = [];
    final number = switch (row.getAttribute('r')) {
      final written? => int.parse(written),
      null => next + 1,
    };
    if (number < 1) throw const FormatException('row number');
    next = number;
    final cells = <int, SheetCell>{};
    var column = 0;
    for (final cell in _children(row, 'c')) {
      if (cell.getAttribute('r') case final reference?) {
        column = _columnIndex(reference);
      }
      cells[column] = _cellOf(cell, strings, formats, date1904);
      column++;
    }
    if (cells.values.any((cell) => cell.text.trim().isNotEmpty)) {
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      rows[number] = [for (var at = 0; at < width; at++) cells[at]];
      if (rows.length > spreadsheetRowLimit) {
        return const RefusedSheet(SpreadsheetRefusal.tooManyRows);
      }
    }
  }
  return _sheetRows(rows);
}

/// A cell reference's column, from 0: `A1` is 0, `AB7` is 27.
int _columnIndex(String reference) {
  final letters = RegExp('^[A-Z]+').stringMatch(reference.toUpperCase());
  if (letters == null) throw const FormatException('cell reference');
  var index = 0;
  for (final letter in letters.codeUnits) {
    index = index * 26 + letter - 64;
    if (index > _columnLimit) throw const FormatException('cell reference');
  }
  return index - 1;
}

/// A cell's shown text: a string as written, a formula's cached value, a
/// number or date through its format.
SheetCell _cellOf(
  XmlElement cell,
  List<String> strings,
  List<String> formats,
  bool date1904,
) {
  final type = cell.getAttribute('t') ?? 'n';
  final value = _children(cell, 'v').firstOrNull?.innerText ?? '';
  switch (type) {
    case 'inlineStr':
      final item = _children(cell, 'is').firstOrNull;
      return SheetCell(item == null ? '' : _itemText(item), isText: true);
    case 's':
      final index = int.tryParse(value);
      final text = index == null || index >= strings.length
          ? ''
          : strings[index];
      return SheetCell(text, isText: true);
    case 'str':
      return SheetCell(value, isText: true);
    case 'b':
      final text = switch (value) {
        '1' => 'TRUE',
        '0' => 'FALSE',
        _ => '',
      };
      return SheetCell(text, isText: false);
    case 'e':
      return SheetCell(value, isText: false);
  }
  if (value.isEmpty) return const SheetCell('', isText: false);
  final style = int.tryParse(cell.getAttribute('s') ?? '') ?? 0;
  final code = style < formats.length ? formats[style] : 'General';
  if (type == 'd') {
    final date = DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
    if (date == null) return SheetCell(value, isText: false);
    final epoch = date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
    final days = date.difference(epoch).inMilliseconds / 86400000;
    return SheetCell(
      shownNumber(
        code == 'General' ? 'yyyy-mm-dd' : code,
        days,
        date1904: date1904,
      ),
      isText: false,
    );
  }
  final number = double.tryParse(value);
  if (number == null || !number.isFinite) {
    return SheetCell(value, isText: false);
  }
  return SheetCell(
    shownNumber(code, number, date1904: date1904),
    isText: false,
  );
}
