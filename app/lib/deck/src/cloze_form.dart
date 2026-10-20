import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// A word of a line: a run of characters other than whitespace, with where it
/// starts and ends.
typedef Word = ({int start, int end});

/// The words of [line], in order.
List<Word> wordsOf(String line) => [
  for (final match in RegExp(r'\S+').allMatches(line))
    (start: match.start, end: match.end),
];

/// A cloze as the cloze form edits it: the line, typed once, and which of its
/// words are blanks, by their place among the line's words. Adjacent chosen
/// words make one blank.
class ClozeDraft {
  ClozeDraft._(this._line, this.chosen);

  /// An empty line with no blank.
  ClozeDraft() : this._('', {});

  /// The line of [cloze] filled, with each word a blank overlaps chosen.
  factory ClozeDraft.of(ClozeContent cloze) {
    final parts = cloze.text.split(clozeBlank);
    final spans = <Word>[];
    final line = StringBuffer();
    for (final (index, part) in parts.indexed) {
      line.write(part);
      if (index < cloze.answers.length) {
        final start = line.length;
        line.write(cloze.answers[index]);
        spans.add((start: start, end: line.length));
      }
    }
    final text = line.toString();
    return ClozeDraft._(text, {
      for (final (index, word) in wordsOf(text).indexed)
        if (spans.any((span) => span.start < word.end && word.start < span.end))
          index,
    });
  }

  String _line;

  /// The places of the chosen words among the line's words.
  final Set<int> chosen;

  /// Takes [line] as the line. A chosen word stays chosen while the edit
  /// leaves it whole: the text before and after the changed part is
  /// unchanged, so a chosen word there is the same word, moved.
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
    final words = wordsOf(_line);
    final moved = {
      for (final index in chosen)
        if (words[index].end <= before)
          words[index]
        else if (words[index].start >= _line.length - after)
          (start: words[index].start + shift, end: words[index].end + shift),
    };
    chosen
      ..clear()
      ..addAll([
        for (final (index, word) in wordsOf(line).indexed)
          if (moved.contains(word)) index,
      ]);
    _line = line;
  }

  /// Chooses the word at [index] as a blank, or leaves it out.
  void toggle(int index) {
    if (!chosen.remove(index)) chosen.add(index);
  }

  /// The line with each run of adjacent chosen words as one `___` blank,
  /// and the answers in order.
  (String, List<String>) get _built {
    final words = wordsOf(_line);
    final text = StringBuffer();
    final answers = <String>[];
    var at = 0;
    var index = 0;
    while (index < words.length) {
      if (!chosen.contains(index)) {
        index++;
        continue;
      }
      final start = words[index].start;
      while (chosen.contains(index + 1) && index + 1 < words.length) {
        index++;
      }
      final end = words[index].end;
      text
        ..write(_line.substring(at, start))
        ..write(clozeBlank);
      answers.add(_line.substring(start, end));
      at = end;
      index++;
    }
    text.write(_line.substring(at));
    return (text.toString(), answers);
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

  /// The cloze the line and its chosen words make, each run of adjacent
  /// chosen words one blank and its answer, or null while it has a
  /// [problem].
  ClozeContent? get content {
    if (problem != null) return null;
    final (text, answers) = _built;
    return ClozeContent(text, answers);
  }
}

/// Why a cloze cannot be saved yet.
enum ClozeProblem { noBlank, blankMarker }

/// The line's words as toggle buttons under the line, each read as a word and
/// whether it is a blank; a tap chooses or leaves out one. With [showError],
/// a line under them says what keeps the cloze from being saved.
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

  /// Called after every toggle, which this widget makes on [draft].
  final VoidCallback onChanged;

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
                label: draft.chosen.contains(index)
                    ? l10n.clozeWordBlank(line.substring(word.start, word.end))
                    : l10n.clozeWord(line.substring(word.start, word.end)),
                excludeSemantics: true,
                button: true,
                selected: draft.chosen.contains(index),
                onTap: () {
                  draft.toggle(index);
                  onChanged();
                },
                child: FilterChip(
                  label: Text(line.substring(word.start, word.end)),
                  showCheckmark: false,
                  selected: draft.chosen.contains(index),
                  onSelected: (_) {
                    draft.toggle(index);
                    onChanged();
                  },
                ),
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
