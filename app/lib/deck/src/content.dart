import 'dart:convert';

/// A typed block of card content: text, a cloze or a table. A new kind adds a
/// subclass and a discriminator value, and stored rows keep their encoding.
sealed class Content {
  const Content();
}

/// A block of plain text.
final class TextContent extends Content {
  const TextContent(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextContent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// How a cloze's [ClozeContent.text] writes each blank.
const clozeBlank = '___';

/// A line or sentence with blanks: its [text] writes each blank as
/// [clozeBlank], and [answers] fill them in order, one each (ADR 0068).
final class ClozeContent extends Content {
  const ClozeContent(this.text, this.answers);

  final String text;
  final List<String> answers;

  /// [text] with each blank filled by its answer.
  String get filled {
    final parts = text.split(clozeBlank);
    return [
      for (final (index, part) in parts.indexed) ...[
        part,
        if (index < answers.length) answers[index],
      ],
    ].join();
  }

  @override
  bool operator ==(Object other) =>
      other is ClozeContent &&
      jsonEncode(_payload(other)) == jsonEncode(_payload(this));

  @override
  int get hashCode => jsonEncode(_payload(this)).hashCode;
}

/// A cell of a [TableContent]'s rows to recall: its row and column, each
/// counted from 0.
typedef TableBlank = ({int row, int column});

/// A table as the page prints it: its column headers, its rows of cells, each
/// as many as there are columns and starting with the row's header, and the
/// cells to recall (ADR 0068).
final class TableContent extends Content {
  const TableContent({
    required this.columns,
    required this.rows,
    required this.blanks,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final List<TableBlank> blanks;

  bool isBlank(int row, int column) =>
      blanks.any((blank) => blank.row == row && blank.column == column);

  /// The table as text, every cell shown: the headers on the first line, then
  /// a line per row, cells joined by " | ", as the function composes a table
  /// card's answer.
  String get filled =>
      [columns, ...rows].map((cells) => cells.join(' | ')).join('\n');

  @override
  bool operator ==(Object other) =>
      other is TableContent &&
      jsonEncode(_payload(other)) == jsonEncode(_payload(this));

  @override
  int get hashCode => jsonEncode(_payload(this)).hashCode;
}

/// A stored block whose type this version of the app does not know, kept
/// intact so saving the card again does not lose it.
final class UnsupportedContent extends Content {
  const UnsupportedContent(this.type, this.payload);

  final String type;
  final Object? payload;
}

/// Whether a card with [front] is drawn whole, its front across the card
/// with its blanks, rather than split into front and back: whether [front]
/// holds a cloze or a table.
bool isWholeCard(List<Content> front) =>
    front.any((block) => block is ClozeContent || block is TableContent);

const _textType = 'text';
const _clozeType = 'cloze';
const _tableType = 'table';

String _type(Content block) => switch (block) {
  TextContent() => _textType,
  ClozeContent() => _clozeType,
  TableContent() => _tableType,
  UnsupportedContent(:final type) => type,
};

Object? _payload(Content block) => switch (block) {
  TextContent(:final text) => {'text': text},
  ClozeContent(:final text, :final answers) => {
    'text': text,
    'answers': answers,
  },
  TableContent(:final columns, :final rows, :final blanks) => {
    'columns': columns,
    'rows': rows,
    'blanks': [
      for (final (:row, :column) in blanks) {'row': row, 'column': column},
    ],
  },
  UnsupportedContent(:final payload) => payload,
};

/// Encodes [blocks] as a JSON array of `{type, payload}` objects.
String encodeContent(List<Content> blocks) => jsonEncode([
  for (final block in blocks)
    {'type': _type(block), 'payload': _payload(block)},
]);

/// Decodes what [encodeContent] wrote. An unknown `type` becomes
/// [UnsupportedContent]; input that is not that shape at all, or a known
/// block whose payload breaks its shape, throws [FormatException].
List<Content> decodeContent(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! List<Object?>) {
    throw FormatException('content is not a list', encoded);
  }
  return [for (final block in decoded) _decodeBlock(block, encoded)];
}

Content _decodeBlock(Object? block, String source) {
  if (block is! Map<String, Object?>) {
    throw FormatException('content block is not an object', source);
  }
  final type = block['type'];
  final payload = block['payload'];
  if (type is! String) {
    throw FormatException('content block has no string type', source);
  }
  final decoded = switch ((type, payload)) {
    (_textType, {'text': final String text}) => TextContent(text),
    (_clozeType, final Map<String, Object?> fields) => _decodeCloze(fields),
    (_tableType, final Map<String, Object?> fields) => _decodeTable(fields),
    (_textType || _clozeType || _tableType, _) => null,
    _ => UnsupportedContent(type, payload),
  };
  return decoded ??
      (throw FormatException('a $type block breaks its shape', source));
}

/// A cloze of text with one or more blanks, each with a non-empty answer;
/// null otherwise.
ClozeContent? _decodeCloze(Map<String, Object?> fields) {
  if (fields
      case {'text': final String text, 'answers': final List<Object?> answers}
      when answers.isNotEmpty &&
          answers.every(
            (answer) => answer is String && answer.trim().isNotEmpty,
          ) &&
          text.split(clozeBlank).length - 1 == answers.length) {
    return ClozeContent(text, answers.cast<String>());
  }
  return null;
}

/// A table of one or more columns and rows, each row as many cells as there
/// are columns, and one or more distinct blanks inside it, each on a cell
/// that holds text; null otherwise.
TableContent? _decodeTable(Map<String, Object?> fields) {
  List<String>? strings(Object? value) =>
      value is List<Object?> && value.every((cell) => cell is String)
      ? value.cast<String>()
      : null;
  if (fields case {
    'columns': final Object? columnsValue,
    'rows': final List<Object?> rowsValue,
    'blanks': final List<Object?> blanksValue,
  }) {
    final columns = strings(columnsValue);
    final rows = [for (final row in rowsValue) strings(row)];
    final blanks = [
      for (final blank in blanksValue)
        if (blank case {'row': final int row, 'column': final int column})
          (row: row, column: column),
    ];
    if (columns == null ||
        columns.isEmpty ||
        rows.isEmpty ||
        rows.any((row) => row == null || row.length != columns.length) ||
        blanks.isEmpty ||
        blanks.length != blanksValue.length ||
        blanks.toSet().length != blanks.length) {
      return null;
    }
    final cells = rows.cast<List<String>>();
    final inside = blanks.every(
      (blank) =>
          blank.row >= 0 &&
          blank.row < cells.length &&
          blank.column >= 0 &&
          blank.column < columns.length &&
          cells[blank.row][blank.column].trim().isNotEmpty,
    );
    return inside
        ? TableContent(columns: columns, rows: cells, blanks: blanks)
        : null;
  }
  return null;
}

/// The text of [blocks], joined by newlines: a text block's text, and a
/// cloze's and a table's filled form. The card key and a merged back read
/// it.
String plainText(List<Content> blocks) => [
  for (final block in blocks)
    switch (block) {
      TextContent(:final text) => text,
      ClozeContent(:final filled) || TableContent(:final filled) => filled,
      UnsupportedContent() => null,
    },
].nonNulls.join('\n');
