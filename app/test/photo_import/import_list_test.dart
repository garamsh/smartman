import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/photo_import/src/import_list.dart';

/// A word of [senses], each a part of speech and a meaning, in [topic].
CandidateCard _word(
  String front,
  List<(String?, String)> senses, {
  String topic = '단어',
}) => CandidateCard(
  front: front,
  kind: CardKind.vocabulary,
  senses: [
    for (final (pos, meaning) in senses) Sense(pos: pos, meaning: meaning),
  ],
  topic: topic,
);

Set<CardKey> _keys(List<String> fronts) => {
  for (final front in fronts) CardKey.fromFront(front),
};

List<(String, String)> _sides(ImportList list) => [
  for (final card in list.toImport()) (card.front, card.back),
];

void main() {
  group('duplicates', () {
    test("under 양쪽 다 the word's card alone decides a duplicate, and a reversed card the deck holds merges back", () {
      final list = ImportList([
        _word('big', [(null, '크다')]),
      ], _keys(['크다']));
      list.sections.single.form = const VocabularyForm(
        direction: Direction.both,
      );
      final row = list.rows.single;

      expect(list.isDuplicate(row), isFalse);
      expect(list.isIncluded(row), isTrue);
      expect(_sides(list), [('big', '크다'), ('크다', 'big')]);
      expect(
        list.toImport().map((card) => card.onDuplicate),
        everyElement(DuplicateChoice.mergeBack),
      );
      // Control: the deck holding the word leaves the row out.
      list.existingKeys = _keys(['big']);
      expect(list.isDuplicate(row), isTrue);
      expect(list.isIncluded(row), isFalse);
    });

    test("with meaning → word alone, the meaning's card decides", () {
      final list = ImportList([
        _word('big', [(null, '크다')]),
      ], _keys(['크다']));
      list.sections.single.form = const VocabularyForm(
        direction: Direction.backward,
      );
      expect(list.isDuplicate(list.rows.single), isTrue);
    });
  });

  test('the count is one per card key, as cards of one key merge into one', () {
    final list = ImportList([
      _word('big', [(null, '크다')]),
      _word('large', [(null, '크다')]),
    ], const {});
    list.sections.single.form = const VocabularyForm(direction: Direction.both);

    expect(list.toImport(), hasLength(4));
    expect(list.cardCount, 3, reason: "both reversed cards front '크다'");
    // Control: distinct meanings count every card.
    final distinct = ImportList([
      _word('big', [(null, '크다')]),
      _word('large', [(null, '넓다')]),
    ], const {});
    distinct.sections.single.form = const VocabularyForm(
      direction: Direction.both,
    );
    expect(distinct.cardCount, 4);
  });

  test("an edit is kept when the section's form changes after it", () {
    final list = ImportList([
      _word('face', [('[동]', '직면하다'), ('[명]', '표면'), ('[명]', '얼굴')]),
    ], const {});
    final row = list.rows.single;
    row.front = 'faces';
    row.senses[1].kept = false;
    row.senses[2].meaning = '생김새';

    list.sections.single.form = const VocabularyForm(
      direction: Direction.backward,
      showPos: false,
    );

    expect(_sides(list), [('직면하다\n생김새', 'faces')]);
    list.sections.single.form = const VocabularyForm(firstSenseOnly: true);
    expect(_sides(list), [('faces', '[동] 직면하다')]);
  });

  test(
    'a swapped note keeps a handwritten card\'s star on the side it moves to',
    () {
      final list = ImportList(const [
        CandidateCard(
          front: '★ 스물 → 스무',
          answer: '관형사가 되면 스무로 바뀐다',
          topic: '꼴이 바뀌는 수',
        ),
      ], const {});

      list.sections.single.form = const NoteForm(swapped: true);

      expect(_sides(list), [('관형사가 되면 스무로 바뀐다', '★ 스물 → 스무')]);
      // Control: unswapped, the star leads the front.
      list.sections.single.form = const NoteForm();
      expect(_sides(list), [('★ 스물 → 스무', '관형사가 되면 스무로 바뀐다')]);
    },
  );

  test('a row whose front holds a blank saves its front with the blanks filled as its back, swapped or not, where a plain note swaps', () {
    final list = ImportList(const [
      CandidateCard(
        front: '3인칭 재귀칭: 높임 당신 · 예사 {{c::자기}} · 낮춤 저',
        answer: '자기',
        type: CardType.cloze,
        topic: '재귀칭',
      ),
      CandidateCard(front: '재귀칭', answer: '앞의 명사를 다시 가리킴', topic: '재귀칭'),
    ], const {});
    const whole = (
      '3인칭 재귀칭: 높임 당신 · 예사 {{c::자기}} · 낮춤 저',
      '3인칭 재귀칭: 높임 당신 · 예사 자기 · 낮춤 저',
    );

    expect(_sides(list), [whole, ('재귀칭', '앞의 명사를 다시 가리킴')]);
    list.sections.single.form = const NoteForm(swapped: true);
    // Control: the plain note in the same section swaps.
    expect(_sides(list), [whole, ('앞의 명사를 다시 가리킴', '재귀칭')]);
  });

  group('stored forms', () {
    const deck = DeckId('id0');
    ImportList words() => ImportList([
      _word('big', [(null, '크다')]),
    ], const {});

    test('a form stored for the deck applies to its section', () {
      final stored = SectionForms({}).remember(
        words()
          ..sections.single.form = const VocabularyForm(
            direction: Direction.backward,
          ),
        deck,
      );
      final list = words();
      SectionForms.parse(stored).applyTo(list, deck);
      expect(
        (list.sections.single.form as VocabularyForm).direction,
        Direction.backward,
      );
    });

    test('corrupt stored JSON, or a form of the wrong shape, leaves every section its default', () {
      for (final stored in [
        'not json',
        '[1, 2]',
        '{"id0": 5}',
        '{"id0": {"vocabulary:단어": {"direction": "sideways", "firstSenseOnly": false, "showPos": true, "showPronunciation": false, "showExtras": false}}}',
        '{"id0": {"vocabulary:단어": {"swapped": true}}}',
        null,
      ]) {
        final list = words();
        SectionForms.parse(stored).applyTo(list, deck);
        expect(
          (list.sections.single.form as VocabularyForm).direction,
          Direction.forward,
          reason: '$stored',
        );
      }
    });
  });

  test(
    'identify rows start left out, and a section toggles every row together',
    () {
      final list = ImportList(const [
        CandidateCard(front: '양성모음', answer: 'ㅏ ㅗ', topic: '모음조화'),
        CandidateCard(
          front: "'잡아라'의 '아'",
          answer: '양성모음',
          type: CardType.identify,
          topic: '모음조화',
        ),
      ], const {});
      final [rules, identify] = list.sections;
      expect(identify.identify, isTrue);
      expect(list.isIncluded(identify.rows.single), isFalse);
      expect(list.isIncluded(rules.rows.single), isTrue, reason: 'control');

      list.toggleSection(identify);
      expect(list.isIncluded(identify.rows.single), isTrue);
      list.toggleSection(identify);
      expect(list.isIncluded(identify.rows.single), isFalse);
    },
  );
}
