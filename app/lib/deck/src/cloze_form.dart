import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// A run of a line's characters: where it starts and where it ends.
typedef Span = ({int start, int end});

/// The words of [line], in order: each a run of characters other than
/// whitespace.
List<Span> wordsOf(String line) => [
  for (final match in RegExp(r'\S+').allMatches(line))
    (start: match.start, end: match.end),
];

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// [word] of [line] without the punctuation it starts or ends with, which a
/// blank leaves outside (`자기,` blanks `자기`); the whole word when it holds no
/// letter or digit.
Span coreOf(String line, Span word) {
  final letters = _letterOrDigit.allMatches(
    line.substring(word.start, word.end),
  );
  if (letters.isEmpty) return word;
  return (
    start: word.start + letters.first.start,
    end: word.start + letters.last.end,
  );
}

/// A cloze as the cloze form edits it: the line, typed once, and its blanks,
/// each a span of the line (ADR 0092).
class ClozeDraft {
  ClozeDraft._(this._line, this._blanks);

  /// An empty line with no blank.
  ClozeDraft() : this._('', []);

  /// The line of [cloze] filled, each blank where the card has it.
  factory ClozeDraft.of(ClozeContent cloze) {
    final parts = cloze.text.split(clozeBlank);
    final blanks = <Span>[];
    final line = StringBuffer();
    for (final (index, part) in parts.indexed) {
      line.write(part);
      if (index < cloze.answers.length) {
        final start = line.length;
        line.write(cloze.answers[index]);
        blanks.add((start: start, end: line.length));
      }
    }
    return ClozeDraft._(line.toString(), blanks);
  }

  String _line;

  /// The blanks in the order of the line, none overlapping another.
  final List<Span> _blanks;

  /// The blanks in the order of the line.
  List<Span> get blanks => List.unmodifiable(_blanks);

  /// The text of [span] in the line.
  String textOf(Span span) => _line.substring(span.start, span.end);

  /// Whether a blank falls in the word at [index].
  bool isChosen(int index) => _overlapping(wordsOf(_line)[index]).isNotEmpty;

  List<Span> _overlapping(Span word) => [
    for (final blank in _blanks)
      if (blank.start < word.end && word.start < blank.end) blank,
  ];

  /// Takes [line] as the line. A blank stays where the edit leaves it whole:
  /// the text before and after the changed part is unchanged, so a blank
  /// there is the same text, moved.
  void update(String line) {
    final shorter = line.length < _line.length ? line.length : _line.length;
    var before = 0;
    while (before < shorter && line[before] == _line[before]) {
      before++;
    }
    var after = 0;
    while (after < shorter - before &&
        line[line.length - 1 - after] == _line[_line.length - 1 - after]) {
      after++;
    }
    final shift = line.length - _line.length;
    final kept = [
      for (final blank in _blanks)
        if (blank.end <= before)
          blank
        else if (blank.start >= _line.length - after)
          (start: blank.start + shift, end: blank.end + shift),
    ];
    _blanks
      ..clear()
      ..addAll(kept);
    _line = line;
  }

  /// Chooses the word at [index] as a blank of its own, without the
  /// punctuation around it, or leaves out every blank in it.
  void toggle(int index) {
    final word = wordsOf(_line)[index];
    final inWord = _overlapping(word);
    if (inWord.isEmpty) {
      _place(coreOf(_line, word));
    } else {
      _blanks.removeWhere(inWord.contains);
    }
  }

  /// Makes [letters], a span inside the word at [index], that word's one
  /// blank.
  void narrow(int index, Span letters) {
    _blanks.removeWhere(_overlapping(wordsOf(_line)[index]).contains);
    _place(letters);
  }

  void _place(Span blank) {
    _blanks
      ..add(blank)
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The line with each blank as `___`, and the answers in order.
  (String, List<String>) get _built {
    final text = StringBuffer();
    var at = 0;
    for (final blank in _blanks) {
      text
        ..write(_line.substring(at, blank.start))
        ..write(clozeBlank);
      at = blank.end;
    }
    text.write(_line.substring(at));
    return (text.toString(), [for (final blank in _blanks) textOf(blank)]);
  }

  /// Why the line cannot be saved yet: no blank chosen, or underscores in
  /// the line that would read as more blanks than it has answers; null once
  /// it can.
  ClozeProblem? get problem {
    final (text, answers) = _built;
    if (answers.isEmpty) return ClozeProblem.noBlank;
    if (text.split(clozeBlank).length - 1 != answers.length) {
      return ClozeProblem.blankMarker;
    }
    return null;
  }

  /// The cloze the line and its blanks make, each blank `___` with its
  /// answer, or null while it has a [problem].
  ClozeContent? get content {
    if (problem != null) return null;
    final (text, answers) = _built;
    return ClozeContent(text, answers);
  }
}

/// Why a cloze cannot be saved yet.
enum ClozeProblem { noBlank, blankMarker }

/// The line's words as toggle buttons under the line, each read as a word and
/// whether it is a blank; a tap makes one a blank of its own or leaves it
/// out. Under them, each blank in order with "글자 고르기", which narrows it to
/// letters of its word. With [showError], a line under them says what keeps
/// the cloze from being saved.
class ClozeWords extends StatelessWidget {
  const ClozeWords({
    super.key,
    required this.line,
    required this.draft,
    required this.showError,
    required this.onChanged,
  });

  final String line;
  final ClozeDraft draft;
  final bool showError;

  /// Called after every change, which this widget makes on [draft].
  final VoidCallback onChanged;

  Future<void> _pickLetters(BuildContext context, int index) async {
    final word = wordsOf(line)[index];
    final inWord = [
      for (final blank in draft.blanks)
        if (blank.start < word.end && word.start < blank.end) blank,
    ];
    final letters = await showAppSheet<Span>(
      context,
      builder: (_) => _LettersSheet(
        word: line.substring(word.start, word.end),
        initial: inWord.length == 1
            ? (
                start: inWord.single.start - word.start,
                end: inWord.single.end - word.start,
              )
            : null,
      ),
    );
    if (letters == null) return;
    draft.narrow(index, (
      start: word.start + letters.start,
      end: word.start + letters.end,
    ));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final words = wordsOf(line);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        Text(
          l10n.clozeWordsHint,
          style: AppType.secondary.copyWith(color: colors.muted),
        ),
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s8,
          children: [
            for (final (index, word) in words.indexed)
              Semantics(
                label: draft.isChosen(index)
                    ? l10n.clozeWordBlank(line.substring(word.start, word.end))
                    : l10n.clozeWord(line.substring(word.start, word.end)),
                excludeSemantics: true,
                button: true,
                selected: draft.isChosen(index),
                onTap: () {
                  draft.toggle(index);
                  onChanged();
                },
                child: FilterChip(
                  label: Text(line.substring(word.start, word.end)),
                  showCheckmark: false,
                  selected: draft.isChosen(index),
                  onSelected: (_) {
                    draft.toggle(index);
                    onChanged();
                  },
                ),
              ),
          ],
        ),
        for (final (number, blank) in draft.blanks.indexed)
          Row(
            spacing: AppSpace.s8,
            children: [
              Expanded(
                child: Text(
                  l10n.clozeBlankLine(number + 1, draft.textOf(blank)),
                  style: AppType.secondary.copyWith(color: colors.ink2),
                ),
              ),
              // A blank inside one word narrows to letters of it.
              if (words.indexed
                      .where(
                        (entry) =>
                            entry.$2.start <= blank.start &&
                            blank.end <= entry.$2.end,
                      )
                      .firstOrNull
                  case (final index, _))
                AppButton(
                  label: l10n.clozePickLetters,
                  icon: LucideIcons.textCursorInput,
                  variant: AppButtonVariant.text,
                  onPressed: () => _pickLetters(context, index),
                ),
            ],
          ),
        if (showError ? draft.problem : null case final problem?)
          Text(switch (problem) {
            ClozeProblem.noBlank => l10n.clozeBlankRequired,
            ClozeProblem.blankMarker => l10n.clozeBlankMarker,
          }, style: AppType.caption.copyWith(color: colors.dontKnowText)),
      ],
    );
  }
}

/// The letters of [word] as tiles; a tap on the first letter and then on the
/// last chooses the run between them, and "이 글자로" returns it as a span of
/// [word]. It opens on [initial] when the word's blank is one run of it.
class _LettersSheet extends StatefulWidget {
  const _LettersSheet({required this.word, required this.initial});

  final String word;
  final Span? initial;

  @override
  State<_LettersSheet> createState() => _LettersSheetState();
}

class _LettersSheetState extends State<_LettersSheet> {
  /// Each letter of the word as a span of it, a surrogate pair kept whole.
  late final List<Span> _letters = () {
    final letters = <Span>[];
    var at = 0;
    for (final letter in widget.word.characters) {
      letters.add((start: at, end: at + letter.length));
      at += letter.length;
    }
    return letters;
  }();

  /// The chosen run, as the places of its first and last letters.
  late (int, int)? _run = switch (widget.initial) {
    final span? => (
      _letters.indexWhere((letter) => letter.start == span.start),
      _letters.lastIndexWhere((letter) => letter.end == span.end),
    ),
    null => null,
  };

  /// The first letter tapped, while the last is still to come.
  int? _first;

  void _tap(int index) => setState(() {
    final first = _first;
    if (first == null) {
      _first = index;
      _run = (index, index);
    } else {
      _first = null;
      _run = first <= index ? (first, index) : (index, first);
    }
  });

  bool _inRun(int index) => switch (_run) {
    (final from, final to) => from <= index && index <= to,
    null => false,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final run = _run;
    return AppSheet(
      title: l10n.clozeLettersTitle,
      body: l10n.clozeLettersBody,
      content: Wrap(
        spacing: AppSpace.s4,
        runSpacing: AppSpace.s4,
        children: [
          for (final (index, letter) in _letters.indexed)
            Semantics(
              label: widget.word.substring(letter.start, letter.end),
              button: true,
              selected: _inRun(index),
              excludeSemantics: true,
              onTap: () => _tap(index),
              child: Material(
                color: _inRun(index) ? colors.brandTint : colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  side: BorderSide(
                    color: _inRun(index) ? colors.ink : colors.outline,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _tap(index),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: AppSize.field,
                      minHeight: AppSize.field,
                    ),
                    // As wide as the letter, at least the tile's size.
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        widget.word.substring(letter.start, letter.end),
                        style: AppType.body.copyWith(color: colors.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.clozeLettersDone,
          size: AppButtonSize.cta,
          onPressed: run == null
              ? null
              : () => Navigator.of(context).pop<Span>((
                  start: _letters[run.$1].start,
                  end: _letters[run.$2].end,
                )),
        ),
      ],
    );
  }
}
