/// The markup of a whole card's text (ADR 0068): `{{c::answer}}` marks a
/// blank, and lines that each start and end with `|` make a table, its
/// header rows above a line of `---` cells.
library;

/// A run of a whole card's text: plain text, or a blank and what fills it.
sealed class MarkupRun {
  const MarkupRun();
}

final class PlainRun extends MarkupRun {
  const PlainRun(this.text);

  final String text;
}

final class BlankRun extends MarkupRun {
  const BlankRun(this.answer);

  final String answer;
}

/// A table's rows of cells, each row as long as the longest, and how many of
/// them head it.
typedef MarkupTable = ({List<List<String>> rows, int headerRows});

final _blank = RegExp(r'\{\{c::([^{}\n]+)\}\}');
const _blankOpening = '{{c::';
final _separatorCell = RegExp(r'^:?-{3,}:?$');

/// Whether [text] holds a blank: a card with such a front is drawn whole,
/// the front with its blanks, rather than split into front and back.
bool hasBlanks(String text) =>
    _blank.allMatches(text).any((match) => match[1]!.trim().isNotEmpty);

/// Whether [text] opens a blank that does not close as one, or one with
/// nothing in it.
bool hasMalformedBlank(String text) =>
    _blank.allMatches(text).any((match) => match[1]!.trim().isEmpty) ||
    text.replaceAll(_blank, '').contains(_blankOpening);

/// [text] with every blank filled: a whole card's back.
String filled(String text) =>
    text.replaceAllMapped(_blank, (match) => match[1]!.trim());

/// [text] as its plain runs and its blanks, in order.
List<MarkupRun> runsOf(String text) {
  final runs = <MarkupRun>[];
  var start = 0;
  for (final match in _blank.allMatches(text)) {
    if (match.start > start) {
      runs.add(PlainRun(text.substring(start, match.start)));
    }
    runs.add(BlankRun(match[1]!.trim()));
    start = match.end;
  }
  if (start < text.length) runs.add(PlainRun(text.substring(start)));
  return runs;
}

/// [text] as a table, when each of its lines, at least two, starts and ends
/// with `|`; otherwise null. A row of `---` cells under the first rows makes
/// them its header and is not itself a row.
MarkupTable? tableOf(String text) {
  final lines = text.trim().split('\n').map((line) => line.trim()).toList();
  if (lines.length < 2 ||
      !lines.every(
        (line) =>
            line.length >= 2 && line.startsWith('|') && line.endsWith('|'),
      )) {
    return null;
  }
  final rows = <List<String>>[];
  var headerRows = 0;
  for (final line in lines) {
    final cells = [
      for (final cell in line.substring(1, line.length - 1).split('|'))
        cell.trim(),
    ];
    if (headerRows == 0 &&
        rows.isNotEmpty &&
        cells.every(_separatorCell.hasMatch)) {
      headerRows = rows.length;
      continue;
    }
    rows.add(cells);
  }
  final width = rows.fold(
    0,
    (widest, row) => row.length > widest ? row.length : widest,
  );
  return (
    rows: [
      for (final row in rows)
        [...row, for (var i = row.length; i < width; i++) ''],
    ],
    headerRows: headerRows,
  );
}

/// [text] as a screen reader reads it: each blank as its answer when
/// [revealed], else as [blank]; a table row by row, its cells joined by
/// commas.
String spoken(String text, {required bool revealed, required String blank}) {
  String line(String line) => [
    for (final run in runsOf(line))
      switch (run) {
        PlainRun(:final text) => text,
        BlankRun(:final answer) => revealed ? answer : blank,
      },
  ].join();
  final table = tableOf(text);
  if (table == null) return line(text);
  return [
    for (final row in table.rows)
      row.where((cell) => cell.isNotEmpty).map(line).join(', '),
  ].join('. ');
}
