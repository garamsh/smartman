import 'dart:convert';

import '../../deck/deck.dart';
import 'extraction_client.dart';

/// Which cards a vocabulary row makes: word to meaning, meaning to word, or
/// both.
enum Direction { forward, backward, both }

/// How the cards of one section read. A vocabulary section's form decides
/// the direction and what its meanings show; a note section's whether front
/// and back are swapped. The user picks it from the section's menu, and the
/// device remembers it per deck and topic.
sealed class SectionForm {
  const SectionForm();

  /// The form [json] stores, or null when it is not one.
  static SectionForm? fromJson(Object? json) => switch (json) {
    {
      'direction': final String direction,
      'firstSenseOnly': final bool firstSenseOnly,
      'showPos': final bool showPos,
      'showPronunciation': final bool showPronunciation,
      'showExtras': final bool showExtras,
    } =>
      switch (Direction.values.where((d) => d.name == direction).firstOrNull) {
        final direction? => VocabularyForm(
          direction: direction,
          firstSenseOnly: firstSenseOnly,
          showPos: showPos,
          showPronunciation: showPronunciation,
          showExtras: showExtras,
        ),
        null => null,
      },
    {'swapped': final bool swapped} => NoteForm(swapped: swapped),
    _ => null,
  };

  Map<String, Object> toJson();
}

/// How a vocabulary section's cards read: by default word to meaning, every
/// sense with its part of speech, and no pronunciation or extras.
final class VocabularyForm extends SectionForm {
  const VocabularyForm({
    this.direction = Direction.forward,
    this.firstSenseOnly = false,
    this.showPos = true,
    this.showPronunciation = false,
    this.showExtras = false,
  });

  final Direction direction;
  final bool firstSenseOnly;
  final bool showPos;
  final bool showPronunciation;
  final bool showExtras;

  VocabularyForm copyWith({
    Direction? direction,
    bool? firstSenseOnly,
    bool? showPos,
    bool? showPronunciation,
    bool? showExtras,
  }) => VocabularyForm(
    direction: direction ?? this.direction,
    firstSenseOnly: firstSenseOnly ?? this.firstSenseOnly,
    showPos: showPos ?? this.showPos,
    showPronunciation: showPronunciation ?? this.showPronunciation,
    showExtras: showExtras ?? this.showExtras,
  );

  @override
  Map<String, Object> toJson() => {
    'direction': direction.name,
    'firstSenseOnly': firstSenseOnly,
    'showPos': showPos,
    'showPronunciation': showPronunciation,
    'showExtras': showExtras,
  };
}

/// How a note section's cards read: front and back as the page gave them, or
/// swapped.
final class NoteForm extends SectionForm {
  const NoteForm({this.swapped = false});

  final bool swapped;

  @override
  Map<String, Object> toJson() => {'swapped': swapped};
}

/// One sense of a row, which the user keeps or drops, edits and reorders.
final class RowSense {
  RowSense(this.pos, this.meaning);

  final String? pos;
  String meaning;
  bool kept = true;
}

/// A card a row saves: its two sides as plain text.
typedef CardSides = ({String front, String back});

/// The candidates of one card key on the photo, combined into one row the
/// user includes or leaves out, and edits.
final class ImportRow {
  ImportRow(this.sources)
    : front = sources.first.front,
      senses = [
        for (final sense in {for (final card in sources) ...card.senses})
          RowSense(sense.pos, sense.meaning),
      ],
      answer = _mergedAnswer(sources);

  /// Every candidate with this row's key, in the order the photo gave them.
  final List<CandidateCard> sources;

  String front;

  /// A vocabulary row's senses in their order, each kept or dropped.
  final List<RowSense> senses;

  /// A note row's answer: the first candidate's, with each later one's joined
  /// by the merge-back rule.
  String answer;

  /// Whether the user included the row (true) or left it out (false); null
  /// until they do either, when [ImportList.isIncluded] decides.
  bool? included;

  CardKind get kind => sources.first.kind;
  CardType get type => sources.first.type;
  String? get topic => sources.first.topic;
  String? get pronunciation => sources.first.pronunciation;
  List<Extra> get extras => sources.first.extras;

  /// Whether the row has anything to save: a note always, a vocabulary row
  /// while it keeps a sense.
  bool get savable =>
      kind == CardKind.note || senses.any((sense) => sense.kept);

  static String _mergedAnswer(List<CandidateCard> sources) {
    var blocks = <Content>[TextContent(sources.first.answer)];
    for (final card in sources.skip(1)) {
      blocks = mergeBack(blocks, card.answer) ?? blocks;
    }
    return plainText(blocks);
  }

  /// The word side in [form]: the front, and the pronunciation on a line
  /// below it when shown.
  String word(VocabularyForm form) => switch (pronunciation) {
    final pronunciation? when form.showPronunciation =>
      '$front\n$pronunciation',
    _ => front,
  };

  /// The meaning side in [form]: one line per kept sense, or the first alone,
  /// each with its part of speech when shown, then each extra when shown.
  String meaning(VocabularyForm form) {
    final kept = senses.where((sense) => sense.kept);
    return [
      for (final sense in form.firstSenseOnly ? kept.take(1) : kept)
        switch (sense.pos) {
          final pos? when form.showPos => '$pos ${sense.meaning}',
          _ => sense.meaning,
        },
      if (form.showExtras)
        for (final extra in extras) '${extra.label} ${extra.text}',
    ].join('\n');
  }

  /// Whether the row's front holds a blank: a whole card, whose back is its
  /// front with the blanks filled, in any form.
  bool get whole => hasBlanks(front);

  /// The cards the row saves in [form].
  List<CardSides> cards(SectionForm form) => switch (form) {
    _ when whole => [(front: front, back: filled(front))],
    VocabularyForm(:final direction) when kind == CardKind.vocabulary => [
      if (direction != Direction.backward)
        (front: word(form), back: meaning(form)),
      if (direction != Direction.forward)
        (front: meaning(form), back: word(form)),
    ],
    NoteForm(swapped: true) => [(front: answer, back: front)],
    _ => [(front: front, back: answer)],
  };
}

/// The rows of one topic, of one kind, identify cards apart, with the form
/// their cards take.
final class ImportSection {
  ImportSection({
    required this.topic,
    required this.kind,
    required this.identify,
  }) : form = kind == CardKind.vocabulary && !identify
           ? const VocabularyForm()
           : const NoteForm();

  /// The topic's name; null for the cards of a function that names none.
  final String? topic;

  final CardKind kind;

  /// Whether the section holds the topic's identify cards.
  final bool identify;

  final rows = <ImportRow>[];

  SectionForm form;

  /// The key the device remembers the section's form under, within a deck.
  String get formKey =>
      '${identify ? 'identify:' : ''}${kind.name}:${topic ?? ''}';
}

/// The rows of a photo, in sections by topic, against the keys the deck they
/// go into already holds.
final class ImportList {
  ImportList(List<CandidateCard> cards, this.existingKeys) {
    final groups = <CardKey, List<CandidateCard>>{};
    for (final card in cards) {
      (groups[CardKey.fromFront(card.front)] ??= []).add(card);
    }
    for (final group in groups.values) {
      final row = ImportRow(group);
      final identify = row.type == CardType.identify;
      var section = sections
          .where(
            (section) =>
                section.topic == row.topic &&
                section.kind == row.kind &&
                section.identify == identify,
          )
          .firstOrNull;
      if (section == null) {
        section = ImportSection(
          topic: row.topic,
          kind: row.kind,
          identify: identify,
        );
        sections.add(section);
      }
      section.rows.add(row);
    }
  }

  /// The sections, in the order each first appears, identify cards after the
  /// page's own.
  final sections = <ImportSection>[];

  /// The keys the deck the rows go into holds; replaced when the user
  /// chooses another deck.
  Set<CardKey> existingKeys;

  Iterable<ImportRow> get rows => sections.expand((section) => section.rows);

  /// Whether every row is a vocabulary entry.
  bool get allVocabulary =>
      rows.every((row) => row.kind == CardKind.vocabulary);

  ImportSection sectionOf(ImportRow row) =>
      sections.firstWhere((section) => section.rows.contains(row));

  /// Whether the deck already holds [row]'s first card in its form, the
  /// word to its meaning unless the form turns it. A further card, such as
  /// "양쪽 다"'s reversed one, whose key the deck holds merges back when
  /// saved, as any duplicate does, and leaves the row included.
  bool isDuplicate(ImportRow row) => existingKeys.contains(
    CardKey.fromFront(row.cards(sectionOf(row).form).first.front),
  );

  /// Whether [row] is saved: as the user set it, else unless it is an
  /// identify card or the deck holds it. A row with nothing to save is not.
  bool isIncluded(ImportRow row) =>
      row.savable &&
      (row.included ?? (row.type != CardType.identify && !isDuplicate(row)));

  /// The cards to import, each as its section's form shows it. Each merges
  /// back into a card with its key, the deck's or one written before it.
  List<ImportedCard> toImport() => [
    for (final section in sections)
      for (final row in section.rows)
        if (isIncluded(row))
          for (final card in row.cards(section.form))
            ImportedCard(
              front: card.front,
              back: card.back,
              onDuplicate: DuplicateChoice.mergeBack,
            ),
  ];

  /// How many cards saving writes or merges into: one per card key among
  /// [toImport], since cards of one key merge into one.
  int get cardCount =>
      {for (final card in toImport()) CardKey.fromFront(card.front)}.length;

  /// Includes every row of [section], or leaves every one out when any is
  /// included.
  void toggleSection(ImportSection section) {
    final include = !section.rows.any(isIncluded);
    for (final row in section.rows) {
      row.included = include;
    }
  }
}

/// The section forms the device remembers, per deck and section, in one
/// stored JSON value.
final class SectionForms {
  SectionForms(this._stored);

  /// Every form the device holds: deck id → section key → form.
  final Map<String, Map<String, Object?>> _stored;

  /// The forms [json] stores; none when it is absent or not a map of maps.
  factory SectionForms.parse(String? json) {
    final Object? decoded;
    try {
      decoded = json == null ? null : jsonDecode(json);
    } on FormatException {
      return SectionForms({});
    }
    return SectionForms({
      if (decoded case final Map<String, Object?> decks)
        for (final MapEntry(:key, :value) in decks.entries)
          if (value case final Map<String, Object?> sections) key: sections,
    });
  }

  /// Applies the forms remembered for [deck] to [list]'s sections of the same
  /// kind; a section with none keeps its own.
  void applyTo(ImportList list, DeckId deck) {
    final remembered = _stored[deck.value] ?? const {};
    for (final section in list.sections) {
      final form = SectionForm.fromJson(remembered[section.formKey]);
      if (form != null && form.runtimeType == section.form.runtimeType) {
        section.form = form;
      }
    }
  }

  /// Remembers [list]'s section forms for [deck], and returns the JSON to
  /// store.
  String remember(ImportList list, DeckId deck) {
    _stored[deck.value] = {
      ...?_stored[deck.value],
      for (final section in list.sections)
        section.formKey: section.form.toJson(),
    };
    return jsonEncode(_stored);
  }
}
