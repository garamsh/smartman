import 'dart:convert';

/// A typed block of card content: text, a cloze, a table or a vocabulary
/// entry's senses. A block's kind is its stored `type`, and its version its
/// `v` (ADR 0106). A new kind adds a subclass and a discriminator value, and
/// stored rows keep their encoding.
///
/// Two blocks are equal when their kind and content are; their [id]s are not
/// compared.
sealed class Content {
  const Content({this.id});

  /// The block's own id, kept across edits so a later block or an edit can
  /// name it; null until the block is first written (ADR 0106).
  final String? id;
}

/// A block of plain text.
final class TextContent extends Content {
  const TextContent(this.text, {super.id});

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
  const ClozeContent(this.text, this.answers, {super.id});

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
    super.id,
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

/// A part of speech a sense's label names, with the fixed short form every
/// card shows it as, whatever the book prints (ADR 0075).
enum PartOfSpeech {
  noun('명'),
  verb('동'),
  adjective('형'),
  adverb('부'),
  pronoun('대'),
  preposition('전'),
  conjunction('접'),
  interjection('감'),
  determiner('관'),
  numeral('수'),
  particle('조'),
  auxiliary('조동'),
  classifier('양'),
  phrase('구');

  const PartOfSpeech(this.short);

  /// The short form a card shows in brackets, as `[명]`.
  final String short;
}

/// A label the page prints for a sense: a part of speech, or any other label
/// such as a semantic class, a register or a gender. [text] is as printed,
/// without the brackets the page encloses it in.
sealed class SenseLabel {
  const SenseLabel(this.text);

  final String text;

  /// What a card shows inside the label's brackets: a part of speech's short
  /// form, or another label as printed.
  String get shown;
}

final class PartOfSpeechLabel extends SenseLabel {
  const PartOfSpeechLabel(this.category, super.text);

  final PartOfSpeech category;

  @override
  String get shown => category.short;
}

final class OtherLabel extends SenseLabel {
  const OtherLabel(super.text);

  @override
  String get shown => text;
}

/// One meaning of a vocabulary entry, a translation or a definition as
/// printed, with the labels the page prints for it, in order, and its own
/// examples.
final class CardSense {
  const CardSense({
    this.labels = const [],
    required this.meaning,
    this.examples = const [],
  });

  final List<SenseLabel> labels;
  final String meaning;
  final List<String> examples;

  /// The sense as one line of text: each label in brackets, then the
  /// meaning, one space apart, as `[명] 사과`.
  String get line =>
      [for (final label in labels) '[${label.shown}]', meaning].join(' ');

  @override
  bool operator ==(Object other) =>
      other is CardSense &&
      jsonEncode(_senseJson(other)) == jsonEncode(_senseJson(this));

  @override
  int get hashCode => jsonEncode(_senseJson(this)).hashCode;
}

/// A vocabulary entry's senses, one or more, in the page's order (ADR 0075).
final class SensesContent extends Content {
  const SensesContent(this.senses, {super.id});

  final List<CardSense> senses;

  /// One line per sense: the text a search, a screen reader and a merged back
  /// read.
  String get lines => senses.map((sense) => sense.line).join('\n');

  @override
  bool operator ==(Object other) =>
      other is SensesContent &&
      jsonEncode(_payload(other)) == jsonEncode(_payload(this));

  @override
  int get hashCode => jsonEncode(_payload(this)).hashCode;
}

/// A stored block this build cannot read: a type it does not know, or a
/// known type at a version above the one it writes. It is kept intact,
/// [stored] written back as it was read, so saving the card again does not
/// lose it, and it is shown as needing an update.
final class UnsupportedContent extends Content {
  const UnsupportedContent(this.type, this.payload, {this.stored});

  final String type;
  final Object? payload;

  /// The whole stored block as it was read, written back unchanged; null for
  /// a block made in this build.
  final Map<String, Object?>? stored;
}

/// Whether [block] is one that holds blanks to recall: a cloze or a table,
/// each stored with one or more; a cloze still being written before its
/// first blank counts, so the editor's preview draws it as it will be.
bool _hasBlank(Content block) => block is ClozeContent || block is TableContent;

/// The face a card with [front] and [back] is studied on, or null when it is
/// studied front then back (ADR 0106). A card with a blank anywhere is
/// studied on one face, its answers filled in place: the side holding the
/// blank, its front first. No stored field says which, so the content and
/// the mode cannot disagree.
List<Content>? oneFaceOf(List<Content> front, List<Content> back) =>
    front.any(_hasBlank)
    ? front
    : back.any(_hasBlank)
    ? back
    : null;

/// Whether a card whose front is [front] is drawn whole, that front across
/// the card with its blanks, rather than split: [oneFaceOf] for that front.
bool isWholeCard(List<Content> front) => oneFaceOf(front, const []) != null;

const _textType = 'text';
const _clozeType = 'cloze';
const _tableType = 'table';
const _sensesType = 'senses';
const _partOfSpeechKind = 'part_of_speech';
const _otherKind = 'other';

Map<String, Object?> _senseJson(CardSense sense) => {
  'labels': [
    for (final label in sense.labels)
      switch (label) {
        PartOfSpeechLabel(:final category, :final text) => {
          'kind': _partOfSpeechKind,
          'category': category.name,
          'text': text,
        },
        OtherLabel(:final text) => {
          'kind': _otherKind,
          'category': null,
          'text': text,
        },
      },
  ],
  'meaning': sense.meaning,
  'examples': sense.examples,
};

String _type(Content block) => switch (block) {
  TextContent() => _textType,
  ClozeContent() => _clozeType,
  TableContent() => _tableType,
  SensesContent() => _sensesType,
  UnsupportedContent(:final type) => type,
};

/// The steps that upgrade each known type's payload, one per version: the
/// first turns a v1 payload into a v2 one, and so on. The version a type is
/// written at is one more than its steps; every type is at v1 today.
const Map<String, List<Object? Function(Object? payload)>> blockUpcasters = {
  _textType: [],
  _clozeType: [],
  _tableType: [],
  _sensesType: [],
};

/// The version this build writes a block of [type] at.
int blockVersion(
  String type, {
  Map<String, List<Object? Function(Object?)>> steps = blockUpcasters,
}) => (steps[type]?.length ?? 0) + 1;

/// [payload], stored at [version] of [type], upgraded step by step to the
/// version this build writes; [version] must not be above it.
Object? upcastPayload(
  String type,
  int version,
  Object? payload, {
  Map<String, List<Object? Function(Object?)>> steps = blockUpcasters,
}) {
  var upgraded = payload;
  final typeSteps = steps[type] ?? const [];
  for (var step = version - 1; step < typeSteps.length; step++) {
    upgraded = typeSteps[step](upgraded);
  }
  return upgraded;
}

/// [block] given [id], its content unchanged; a block this build cannot read
/// is returned as it is, since it is written back unchanged.
Content withBlockId(Content block, String id) => switch (block) {
  TextContent(:final text) => TextContent(text, id: id),
  ClozeContent(:final text, :final answers) => ClozeContent(
    text,
    answers,
    id: id,
  ),
  TableContent(:final columns, :final rows, :final blanks) => TableContent(
    columns: columns,
    rows: rows,
    blanks: blanks,
    id: id,
  ),
  SensesContent(:final senses) => SensesContent(senses, id: id),
  UnsupportedContent() => block,
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
  SensesContent(:final senses) => {
    'senses': [for (final sense in senses) _senseJson(sense)],
  },
  UnsupportedContent(:final payload) => payload,
};

/// Encodes [blocks] as a JSON array of `{type, v, id, payload}` objects,
/// each at the version this build writes and `id` only when the block has
/// one; a block this build cannot read is written as it was stored.
String encodeContent(List<Content> blocks) => jsonEncode([
  for (final block in blocks)
    switch (block) {
      UnsupportedContent(:final stored?) => stored,
      UnsupportedContent(:final type, :final payload) => {
        'type': type,
        'payload': payload,
      },
      _ => {
        'type': _type(block),
        'v': blockVersion(_type(block)),
        'id': ?block.id,
        'payload': _payload(block),
      },
    },
]);

/// Decodes what [encodeContent] wrote, and the blocks of earlier builds: a
/// block with no `v` is read as v1, and an older `v` is upgraded through
/// [upcastPayload]. An unknown `type`, or a `v` above what this build
/// writes, becomes [UnsupportedContent]; input that is not that shape at
/// all, a `v` that is not a positive integer, an `id` that is not text, or a
/// known block whose payload breaks its shape, throws [FormatException].
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
  if (type is! String) {
    throw FormatException('content block has no string type', source);
  }
  final version = block['v'] ?? 1;
  if (version is! int || version < 1) {
    throw FormatException('a $type block has no positive version', source);
  }
  final id = block['id'];
  if (id != null && id is! String) {
    throw FormatException('a $type block has an id that is not text', source);
  }
  if (!blockUpcasters.containsKey(type) || version > blockVersion(type)) {
    return UnsupportedContent(type, block['payload'], stored: block);
  }
  final payload = upcastPayload(type, version, block['payload']);
  final decoded = switch ((type, payload)) {
    (_textType, {'text': final String text}) => TextContent(text),
    (_clozeType, final Map<String, Object?> fields) => _decodeCloze(fields),
    (_tableType, final Map<String, Object?> fields) => _decodeTable(fields),
    (_sensesType, {'senses': final List<Object?> senses}) => _decodeSenses(
      senses,
    ),
    _ => null,
  };
  if (decoded == null) {
    throw FormatException('a $type block breaks its shape', source);
  }
  return id is String ? withBlockId(decoded, id) : decoded;
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

/// One or more senses, each [decodeSense]'s; null otherwise.
SensesContent? _decodeSenses(List<Object?> senses) {
  final decoded = [for (final sense in senses) decodeSense(sense)];
  return decoded.isEmpty || decoded.contains(null)
      ? null
      : SensesContent(decoded.cast<CardSense>());
}

/// A sense as the `senses` block and the extraction function write it:
/// `{labels, meaning, examples}`, its meaning non-empty text, its examples
/// text, and each label `{kind, category, text}`, a `part_of_speech` with a
/// [PartOfSpeech] name or an `other` with a null category, its text
/// non-empty; null otherwise (ADR 0075).
CardSense? decodeSense(Object? sense) {
  if (sense
      case {
        'labels': final List<Object?> labels,
        'meaning': final String meaning,
        'examples': final List<Object?> examples,
      }
      when meaning.trim().isNotEmpty && examples.every((e) => e is String)) {
    final decoded = [for (final label in labels) _decodeLabel(label)];
    if (decoded.contains(null)) return null;
    return CardSense(
      labels: decoded.cast<SenseLabel>(),
      meaning: meaning,
      examples: examples.cast<String>(),
    );
  }
  return null;
}

SenseLabel? _decodeLabel(Object? label) => switch (label) {
  {
    'kind': _partOfSpeechKind,
    'category': final String category,
    'text': final String text,
  }
      when text.trim().isNotEmpty =>
    switch (PartOfSpeech.values.where((p) => p.name == category).firstOrNull) {
      final category? => PartOfSpeechLabel(category, text),
      null => null,
    },
  {'kind': _otherKind, 'category': null, 'text': final String text}
      when text.trim().isNotEmpty =>
    OtherLabel(text),
  _ => null,
};

/// The text of [blocks], joined by newlines: a text block's text, and a
/// cloze's and a table's filled form. The card key and a merged back read
/// it.
String plainText(List<Content> blocks) => [
  for (final block in blocks)
    switch (block) {
      TextContent(:final text) => text,
      ClozeContent(:final filled) || TableContent(:final filled) => filled,
      SensesContent(:final lines) => lines,
      UnsupportedContent() => null,
    },
].nonNulls.join('\n');
