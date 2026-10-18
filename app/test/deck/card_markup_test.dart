import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/card_markup.dart';

void main() {
  test('a blank holds its trimmed answer, and a front without one is no whole card', () {
    expect(hasBlanks('The capital of France is {{c:: Paris }}.'), isTrue);
    expect(
      filled('The capital of France is {{c:: Paris }}.'),
      'The capital of France is Paris.',
    );
    expect(
      runsOf('{{c::A}} and {{c::B}}!').map(
        (run) => switch (run) {
          PlainRun(:final text) => 'plain:$text',
          BlankRun(:final answer) => 'blank:$answer',
        },
      ),
      ['blank:A', 'plain: and ', 'blank:B', 'plain:!'],
    );
    // A front without the markup, or with an empty blank, stays split.
    expect(hasBlanks('The capital of France is ___'), isFalse);
    expect(hasBlanks('{{c::  }}'), isFalse);
  });

  test('a blank that does not close, or holds nothing, is malformed, where a closed one is not', () {
    expect(hasMalformedBlank('Paris is in {{c::France'), isTrue);
    expect(hasMalformedBlank('{{c::}} and {{c:: }}'), isTrue);
    expect(hasMalformedBlank('{{c::a{{c::b}}'), isTrue);
    // The control: the same text closed.
    expect(hasMalformedBlank('Paris is in {{c::France}}'), isFalse);
    expect(hasMalformedBlank('no blank at all'), isFalse);
  });

  test('pipe lines are a table, its rows above a --- row its header, short rows filled out', () {
    final table = tableOf('''
| 품사 | 예 |
| --- | :---: |
| 명사 | {{c::사과}} |
| 동사 |
''');
    expect(table, isNotNull);
    expect(table!.headerRows, 1);
    expect(table.rows, [
      ['품사', '예'],
      ['명사', '{{c::사과}}'],
      ['동사', ''],
    ]);
    // Without a --- row, no row heads it.
    expect(tableOf('| a | b |\n| c | d |')!.headerRows, 0);
    // A line that is not a pipe row, or a single row, is no table.
    expect(tableOf('| a | b |\nc d'), isNull);
    expect(tableOf('| a | b |'), isNull);
  });

  test('a whole card is read with its blanks as the word for one until revealed, a table row by row', () {
    expect(
      spoken('{{c::Paris}} is in France', revealed: false, blank: 'blank'),
      'blank is in France',
    );
    expect(
      spoken('{{c::Paris}} is in France', revealed: true, blank: 'blank'),
      'Paris is in France',
    );
    expect(
      spoken(
        '| 품사 | 예 |\n| --- | --- |\n| 명사 | {{c::사과}} |',
        revealed: false,
        blank: '빈칸',
      ),
      '품사, 예. 명사, 빈칸',
    );
  });
}
