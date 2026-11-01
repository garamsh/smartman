import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/spreadsheet.dart';
import 'package:smartman/deck/src/spreadsheet_cards.dart';
import 'package:smartman/deck/src/spreadsheet_format.dart';

import 'xlsx.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Spreadsheet _opened(OpenedFile file) => switch (file) {
  final Spreadsheet book => book,
  RefusedFile(:final refusal) => throw StateError('refused: $refusal'),
};

List<SheetRow> _rows(SheetRead read) => switch (read) {
  SheetRows(:final rows) => rows,
  RefusedSheet(:final refusal) => throw StateError('refused: $refusal'),
};

List<List<String>> _texts(List<SheetRow> rows) => [
  for (final row in rows) [for (final cell in row.cells) cell.text],
];

List<SheetRow> _sheet(List<List<TestCell>> rows) => _rows(
  _opened(parseSpreadsheet('words.xlsx', xlsxOf([TestSheet('단어', rows)])))
      .sheets[0]
      .read,
);

List<SheetRow> _csv(String text) =>
    _rows(_opened(parseSpreadsheet('words.csv', _bytes(text))).sheets[0].read);

TestCell _t(String text) => StringCell(text);

const _frontBack = SheetColumns(front: 0, back: 1);

void main() {
  group('the limits, refused before the file is read', () {
    test('refuses a file over 5 MB without reading a byte, beside one at the limit that is read', () async {
      var reads = 0;
      Future<Uint8List> read() async {
        reads++;
        return _bytes('단어,뜻\napple,사과\n');
      }

      final over = await openSpreadsheet(
        'words.csv',
        spreadsheetFileLimit + 1,
        read,
      );
      expect(over, isA<RefusedFile>());
      expect((over as RefusedFile).refusal, SpreadsheetRefusal.tooLarge);
      expect(reads, 0);

      final at = await openSpreadsheet('words.csv', spreadsheetFileLimit, read);
      expect(_texts(_rows(_opened(at).sheets[0].read)), [
        ['단어', '뜻'],
        ['apple', '사과'],
      ]);
      expect(reads, 1);
    });

    test('refuses a sheet of more than 1,000 rows holding text, beside one of 1,000 with empty rows among them', () {
      List<String> lines(int count) => [
        for (var at = 0; at < count; at++) 'word $at,뜻 $at',
      ];
      SheetRead csv(String text) =>
          _opened(parseSpreadsheet('w.csv', _bytes(text))).sheets[0].read;
      expect(
        csv(lines(spreadsheetRowLimit + 1).join('\n')),
        isA<RefusedSheet>().having(
          (read) => read.refusal,
          'refusal',
          SpreadsheetRefusal.tooManyRows,
        ),
      );
      expect(
        _rows(csv([...lines(spreadsheetRowLimit), '', ',', ''].join('\n'))),
        hasLength(spreadsheetRowLimit),
      );

      SheetRead book(int count) => _opened(
        parseSpreadsheet(
          'w.xlsx',
          xlsxOf([
            TestSheet('단어', [
              for (var at = 0; at < count; at++)
                [_t('word $at'), NumberCell(at)],
            ]),
          ]),
        ),
      ).sheets[0].read;
      expect(book(spreadsheetRowLimit + 1), isA<RefusedSheet>());
      expect(_rows(book(spreadsheetRowLimit)), hasLength(spreadsheetRowLimit));
    });

    test('refuses a file that is neither .xlsx nor .csv, and a CSV not in UTF-8, beside the same text in UTF-8', () {
      expect(
        parseSpreadsheet('words.xls', _bytes('a,b')),
        isA<RefusedFile>().having(
          (file) => file.refusal,
          'refusal',
          SpreadsheetRefusal.wrongType,
        ),
      );
      // 사과,apple in EUC-KR, as Excel's plain CSV writes it on a Korean system.
      final eucKr = Uint8List.fromList(const [
        0xbb,
        0xe7,
        0xb0,
        0xfa,
        0x2c,
        0x61,
        0x70,
        0x70,
        0x6c,
        0x65,
      ]);
      expect(
        parseSpreadsheet('words.csv', eucKr),
        isA<RefusedFile>().having(
          (file) => file.refusal,
          'refusal',
          SpreadsheetRefusal.notUtf8,
        ),
      );
      expect(_texts(_csv('사과,apple')), [
        ['사과', 'apple'],
      ]);
    });

    test('refuses as unreadable a part that unpacks past 50 MB, beside a workbook under it, and a file that is no zip', () {
      Uint8List padded(int size) {
        final zip = ZipDecoder().decodeBytes(
          xlsxOf([
            TestSheet('단어', [
              [_t('apple'), _t('사과')],
            ]),
          ]),
        );
        zip.add(ArchiveFile.bytes('xl/styles.xml', _spaces(size)));
        return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
      }

      const limit = 50 * 1024 * 1024;
      expect(
        parseSpreadsheet('w.xlsx', padded(limit + 1)),
        isA<RefusedFile>().having(
          (file) => file.refusal,
          'refusal',
          SpreadsheetRefusal.unreadable,
        ),
      );
      expect(
        _texts(
          _rows(
            _opened(parseSpreadsheet('w.xlsx', padded(limit))).sheets[0].read,
          ),
        ),
        [
          ['apple', '사과'],
        ],
      );
      expect(
        parseSpreadsheet('w.xlsx', _bytes('not a zip')),
        isA<RefusedFile>(),
      );
    });
  });

  group('a malformed sheet', () {
    Uint8List withSheet(String xml) {
      final zip = ZipDecoder().decodeBytes(
        xlsxOf([
          TestSheet('단어', [
            [_t('apple'), _t('사과')],
          ]),
        ]),
      );
      zip.add(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(xml)));
      return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
    }

    SheetRead read(String xml) =>
        _opened(parseSpreadsheet('w.xlsx', withSheet(xml))).sheets[0].read;

    test('is refused cut off inside a row, beside the same row closed', () {
      const row = '<row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>2</v>';
      expect(
        read('<worksheet><sheetData>$row'),
        isA<RefusedSheet>().having(
          (read) => read.refusal,
          'refusal',
          SpreadsheetRefusal.unreadable,
        ),
      );
      expect(
        _texts(
          _rows(
            read(
              '<worksheet><sheetData>$row</c></row></sheetData></worksheet>',
            ),
          ),
        ),
        [
          ['1', '2'],
        ],
      );
    });

    test('stops at the row limit, reading no further into the sheet', () {
      final rows = [
        for (var at = 1; at <= spreadsheetRowLimit + 1; at++)
          '<row r="$at"><c r="A$at"><v>$at</v></c></row>',
      ].join();
      expect(
        read('<worksheet><sheetData>$rows<row'),
        isA<RefusedSheet>().having(
          (read) => read.refusal,
          'refusal',
          SpreadsheetRefusal.tooManyRows,
        ),
      );
    });
  });

  group("a cell's shown text", () {
    test('draws a number and a date through their formats, a formula as its cached value, and General as Excel does', () {
      final rows = _sheet([
        [_t('천 단위'), const NumberCell(1234.5, '#,##0.00')],
        [_t('퍼센트'), const NumberCell(0.256, '0.0%')],
        [_t('날짜'), const NumberCell(46324, 14)],
        [_t('한국어 날짜'), const NumberCell(46324, 'yyyy"년" m"월" d"일"')],
        [_t('시각'), const NumberCell(0.75, 'h:mm')],
        [_t('수식'), const FormulaCell('B1*2', 2469)],
        [_t('글 수식'), const FormulaCell('"사"&"과"', '사과')],
        [_t('캐시 없는 수식'), const FormulaCell('B1', null), _t('남은 칸')],
        [_t('일반'), const NumberCell(0.1 + 0.2)],
      ]);
      expect(
        [for (final row in rows) row.cells[1].text],
        [
          '1,234.50',
          '25.6%',
          '2026-10-29',
          '2026년 10월 29일',
          '18:00',
          '2469',
          '사과',
          '',
          '0.3',
        ],
      );
      expect(
        [for (final row in rows) row.cells[1].isText],
        [false, false, false, false, false, false, true, false, false],
      );
    });

    test('counts a date from 1904 where the workbook says so', () {
      final book = _opened(
        parseSpreadsheet(
          'w.xlsx',
          xlsxOf([
            const TestSheet('단어', [
              [NumberCell(46324, 14)],
            ]),
          ], date1904: true),
        ),
      );
      expect(_texts(_rows(book.sheets[0].read)), [
        ['2030-10-30'],
      ]);
    });

    test("trims a cell, keeps its line breaks, and decodes Excel's escaped carriage return", () {
      expect(
        _texts(
          _sheet([
            [_t('  첫 줄_x000D_\n둘째 줄  '), _t('\n뜻\n')],
          ]),
        ),
        [
          ['첫 줄\n둘째 줄', '뜻'],
        ],
      );
    });

    test('reads a CSV with a byte order mark, Korean text, quoted commas, quotes and line breaks', () {
      final bom = [0xef, 0xbb, 0xbf];
      final rows = _rows(
        _opened(
          parseSpreadsheet(
            '단어.csv',
            Uint8List.fromList([
              ...bom,
              ...utf8.encode('앞면,뒷면\r\n사과,"과일, 빨간"\r\n"줄\n바꿈","따옴표 ""안"""\r\n'),
            ]),
          ),
        ).sheets[0].read,
      );
      expect(_texts(rows), [
        ['앞면', '뒷면'],
        ['사과', '과일, 빨간'],
        ['줄\n바꿈', '따옴표 "안"'],
      ]);
      final quotedFirst = _rows(
        _opened(
          parseSpreadsheet(
            'q.csv',
            Uint8List.fromList([...bom, ...utf8.encode('"앞,면",뒷면')]),
          ),
        ).sheets[0].read,
      );
      expect(_texts(quotedFirst), [
        ['앞,면', '뒷면'],
      ]);
    });

    test('lists the visible sheets and reads the one chosen', () {
      final book = _opened(
        parseSpreadsheet(
          'w.xlsx',
          xlsxOf([
            TestSheet('명사', [
              [_t('apple'), _t('사과')],
            ]),
            TestSheet('숨김', [
              [_t('secret'), _t('비밀')],
            ], hidden: true),
            TestSheet('동사', [
              [_t('run'), _t('달리다')],
            ]),
          ]),
        ),
      );
      expect([for (final sheet in book.sheets) sheet.name], ['명사', '동사']);
      expect(_texts(_rows(book.sheets[1].read)), [
        ['run', '달리다'],
      ]);
    });

    // Each expected text is what ssf 0.11.2's format() returned for the case,
    // or format("General") where it threw, as the web falls back.
    test('draws what SSF 0.11.2 draws for the formats sheets hold', () {
      const cases = <(String, num, String)>[
        ('General', 12345678901, '12345678901'),
        ('General', 123456789012, '1.23457E+11'),
        ('General', 1e-11, '1E-11'),
        ('0', 2.5, '3'),
        ('0.00', 1.005, '1.00'),
        ('0.0', 1.45, '1.5'),
        ('#,##0', 1234567, '1,234,567'),
        ('#,##0.00', -1234.5, '-1,234.50'),
        ('0%', 0.25, '25%'),
        ('0.00E+00', 1234.5, '1.23E+03'),
        ('##0.0E+0', 12345, '12.3E+3'),
        ('# ?/?', 1.5, '1 1/2'),
        ('# ??/16', 2.5, '2  8/16'),
        ('#,##0 ;(#,##0)', -1234, '(1,234)'),
        ('0"개"', 12, '12개'),
        ('#,##0"원"', 12345, '12,345원'),
        ('[\$₩-412]#,##0', 12345, '₩12,345'),
        ('\$#,##0.00', 1234.5, '\$1,234.50'),
        ('0;-0;"zero"', 0, 'zero'),
        ('[>=100]0;[<0]"neg"0;0.0', 5, '5.0'),
        ('[=1]"one";[=2]"two";"many"', 2, 'two'),
        ('[Red]0.00', 1.5, '1.50'),
        ('000-0000', 1234567, '123-4567'),
        ('#', 0, ''),
        ('#.##', 1.5, '1.5'),
        ('.00', 1.5, '1.50'),
        ('@', 12, '12'),
        ('yyyy-mm-dd h:mm', 46324.75, '2026-10-29 18:00'),
        ('mmm-yy', 46324, 'Oct-26'),
        ('mmmm d, yyyy', 46324, 'October 29, 2026'),
        ('mmmmm', 46324, 'O'),
        ('ddd', 46324, 'Thu'),
        ('dddd', 46324, 'Thursday'),
        ('h:mm AM/PM', 0.75, '6:00 PM'),
        ('AM/PM h"시" mm"분"', 0.25, 'AM 6시 00분'),
        ('A/P h:mm', 0.75, 'P 6:00'),
        ('[h]:mm:ss', 1.5, '36:00:00'),
        ('[m]:ss', 0.5, '720:00'),
        ('mm:ss', 0.0416666, '59:00'),
        ('h:mm:ss.0', 0.5, '12:00:00.0'),
        ('e-m-d', 46324, '2026-10-29'),
        ('bbbb', 46324, '2569'),
        ('[\$-412]yyyy"년" m"월" d"일"', 46324, '2026년 10월 29일'),
        ('m/d/yy', 60, '2/29/00'),
        // SSF refuses these, so they draw as General.
        ('yyyy.mm.dd', 46324, '46324'),
        ('yyyy년', 46324, '46324'),
        ('"open', 46324, '46324'),
        ('0;0;0;0;0', 46324, '46324'),
        // Out of Excel's range, a date draws nothing.
        ('yyyy-mm-dd', 2958466, ''),
        ('yyyy-mm-dd', -1, ''),
      ];
      expect(
        [
          for (final (code, value, _) in cases)
            shownNumber(code, value.toDouble(), date1904: false).trim(),
        ],
        [for (final (_, _, text) in cases) text],
      );
    });
  });

  group("the header toggle's default", () {
    test('is on for a first row holding a common column name, trimmed and case-folded', () {
      expect(headerByDefault(_csv('단어,뜻\napple,사과\nbanana,바나나')), isTrue);
      expect(headerByDefault(_csv(' Word ,설명\napple,사과')), isTrue);
      expect(headerByDefault(_csv('메모,DEFINITION\napple,사과')), isTrue);
    });

    test('is on for text over a column of numbers or dates, against the same row over text', () {
      List<SheetRow> over(TestCell below) => _sheet([
        [_t('이름'), _t('날짜')],
        [_t('kim'), below],
        [_t('lee'), const StringCell(null)],
      ]);
      expect(headerByDefault(over(const NumberCell(46324, 14))), isTrue);
      expect(headerByDefault(over(const NumberCell(90))), isTrue);
      expect(headerByDefault(over(_t('어제'))), isFalse);
      expect(headerByDefault(_csv('이름,점수\nkim,90\nlee,85')), isTrue);
    });

    test(
      'is off for a headerless word list, whose first word becomes a card',
      () {
        final rows = _csv('apple,사과\nbanana,바나나');
        final header = headerByDefault(rows);
        expect(header, isFalse);
        final result = cardsOfRows(rows, _frontBack, header: header);
        expect(
          [
            for (final card in result.cards)
              (card.row, plainText(sidesOf(card.cells).front)),
          ],
          [(1, 'apple'), (2, 'banana')],
        );
      },
    );

    test('is off for a number over numbers and for a sheet of one row, against a named header', () {
      expect(
        headerByDefault(
          _sheet([
            [_t('apple'), const NumberCell(1)],
            [_t('banana'), const NumberCell(2)],
          ]),
        ),
        isFalse,
      );
      expect(headerByDefault(_csv('2026,연도\n2027,연도')), isFalse);
      expect(headerByDefault(_csv('단어,뜻')), isFalse);
      expect(headerByDefault(_csv('단어,뜻\napple,사과')), isTrue);
    });
  });

  group('rows into cards', () {
    test('maps the chosen front and back columns to a 글, ignoring the others, below a header', () {
      final rows = _csv('메모,뜻,단어\n외우기,사과,apple\n,바나나,banana');
      const columns = SheetColumns(front: 2, back: 1);
      final result = cardsOfRows(rows, columns, header: true);
      expect(
        [
          for (final card in result.cards)
            (
              card.row,
              plainText(sidesOf(card.cells).front),
              plainText(sidesOf(card.cells).back),
            ),
        ],
        [(2, 'apple', '사과'), (3, 'banana', '바나나')],
      );
      expect(cardsOfRows(rows, columns, header: false).cards[0].row, 1);
    });

    test('fills a 단어\'s meaning from optional label and example columns, as direct entry writes it', () {
      final rows = _csv('apple,사과,명,"an apple\nan apple a day"\nrun,달리다,,');
      final result = cardsOfRows(
        rows,
        const SheetColumns(front: 0, back: 1, label: 2, example: 3),
        header: false,
      );
      expect(result.cards.map((card) => sidesOf(card.cells).back), [
        [
          const SensesContent([
            CardSense(
              labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
              meaning: '사과',
              examples: ['an apple', 'an apple a day'],
            ),
          ]),
        ],
        [
          const SensesContent([CardSense(meaning: '달리다')]),
        ],
      ]);
      final labelOnly = cardsOfRows(
        rows,
        const SheetColumns(front: 0, back: 1, label: 2),
        header: false,
      );
      expect(sidesOf(labelOnly.cards[0].cells).back, [
        const SensesContent([
          CardSense(
            labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
            meaning: '사과',
          ),
        ]),
      ]);
    });

    test('makes the back a meaning for an example column alone', () {
      final result = cardsOfRows(
        _csv('run,달리다,"run fast"'),
        const SheetColumns(front: 0, back: 1, example: 2),
        header: false,
      );
      expect(sidesOf(result.cards.single.cells).back, [
        const SensesContent([
          CardSense(meaning: '달리다', examples: ['run fast']),
        ]),
      ]);
    });

    test('skips a row with an empty front or back and counts it, and an empty row not at all', () {
      final rows = _csv('apple,사과\n,바나나\ncherry,\n,,\n\ndate,대추');
      final result = cardsOfRows(rows, _frontBack, header: false);
      expect([for (final card in result.cards) card.row], [1, 6]);
      expect(result.skipped, [2, 3]);
      expect(result.tooLong, isEmpty);
    });

    test(
      'refuses a row whose used cell is over $spreadsheetCellLimit characters and names it, beside one at the limit',
      () {
        final at = '가' * spreadsheetCellLimit;
        final over = '😀' * (spreadsheetCellLimit + 1);
        final rows = _csv(
          'ok,$at\nlong,$over\nexample,뜻,,$over\nignored,뜻,$over',
        );
        final result = cardsOfRows(
          rows,
          const SheetColumns(front: 0, back: 1, example: 3),
          header: false,
        );
        expect([for (final card in result.cards) card.row], [1, 4]);
        expect(result.tooLong, [2, 3]);
      },
    );

    test(
      'reads two fields of one column as not distinct, against two columns',
      () {
        expect(const SheetColumns(front: 0, back: 0).distinct, isFalse);
        expect(
          const SheetColumns(front: 0, back: 1, label: 1).distinct,
          isFalse,
        );
        expect(
          const SheetColumns(front: 0, back: 1, label: 2).distinct,
          isTrue,
        );
      },
    );

    test('finds the first row repeating a stored card or an earlier row, normalized as the card key is, and none in a list of distinct fronts', () {
      List<RowCard> cards(String text) =>
          cardsOfRows(_csv(text), _frontBack, header: false).cards;
      final stored = {CardKey.fromFront('apple')};
      expect(
        firstDuplicate(cards('pear,배\nApple,사과'), stored),
        isA<DuplicateOfStored>().having((found) => found.row, 'row', 2),
      );
      expect(
        firstDuplicate(cards('kiwi,키위\nKIWI,참다래'), stored),
        isA<DuplicateOfRow>()
            .having((found) => found.row, 'row', 2)
            .having((found) => found.earlier, 'earlier', 1),
      );
      expect(firstDuplicate(cards('pear,배\nkiwi,키위'), stored), isNull);
    });
  });
}

/// [size] spaces, which compress to nothing, as a valid XML part's tail.
Uint8List _spaces(int size) {
  const head = '<?xml version="1.0"?><styleSheet/>';
  final bytes = Uint8List(size)..fillRange(0, size, 0x20);
  bytes.setRange(0, head.length, head.codeUnits);
  return bytes;
}
