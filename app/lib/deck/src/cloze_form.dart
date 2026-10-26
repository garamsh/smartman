import 'package:flutter/material.dart';

import '../../design/app_button.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// A run of a line's characters: where it starts and where it ends.
typedef Span = ({int start, int end});

/// What the preview draws for an empty blank, so it shows as a block before
/// anything is typed into it.
const _emptyAnswer = '  ';

/// A cloze as the cloze form edits it: the line, and its blanks, each a span
/// of the line's characters (ADR 0092, ADR 0101).
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

  /// The blank "빈칸 넣기" opened at the cursor, which grows with what is
  /// typed at its end until the cursor leaves it.
  Span? _open;

  /// The blanks in the order of the line.
  List<Span> get blanks => List.unmodifiable(_blanks);

  /// The line the blanks are spans of.
  String get line => _line;

  /// The text of [span] in the line.
  String textOf(Span span) => _line.substring(span.start, span.end);

  /// Takes [line] as the line. A blank stays where the edit leaves it whole:
  /// the text before and after the changed part is unchanged, so a blank
  /// there is the same text, moved. Text typed at the end of the open blank
  /// becomes part of it.
  void update(String line) {
    if (line == _line) return;
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
    final open = _open;
    // Typed into the open blank: an insertion at its end, nothing removed.
    final grows =
        open != null &&
        shift > 0 &&
        before + after == _line.length &&
        before == open.end;
    final kept = [
      for (final blank in _blanks)
        if (grows && blank == open)
          (start: blank.start, end: blank.end + shift)
        else if (blank.end <= before && !(blank.end == before && grows))
          blank
        else if (blank.start >= _line.length - after)
          (start: blank.start + shift, end: blank.end + shift),
    ];
    _open = grows ? (start: open.start, end: open.end + shift) : null;
    _blanks
      ..clear()
      ..addAll(kept);
    _line = line;
  }

  /// Makes [selection] a blank: exactly its characters when it holds any,
  /// replacing the blanks it overlaps; otherwise an empty blank at the
  /// cursor, open to what is typed next. A cursor inside a blank adds none.
  void insert(TextSelection selection) {
    final start = selection.isValid ? selection.start : _line.length;
    final end = selection.isValid ? selection.end : _line.length;
    if (start < end) {
      _blanks.removeWhere((blank) => blank.start < end && start < blank.end);
      _place((start: start, end: end));
      _open = null;
      return;
    }
    if (_blanks.any((blank) => blank.start < start && start < blank.end)) {
      return;
    }
    _closeOpen();
    final blank = (start: start, end: start);
    _place(blank);
    _open = blank;
  }

  /// Ends the open blank once [selection] leaves it, dropping it when nothing
  /// was typed into it.
  void track(TextSelection selection) {
    final open = _open;
    if (open == null) return;
    if (selection.isCollapsed &&
        open.start <= selection.start &&
        selection.start <= open.end) {
      return;
    }
    _closeOpen();
  }

  void _closeOpen() {
    final open = _open;
    if (open == null) return;
    if (open.start == open.end) _blanks.remove(open);
    _open = null;
  }

  /// Turns [blank] back into text.
  void remove(Span blank) {
    _blanks.remove(blank);
    if (blank == _open) _open = null;
  }

  void _place(Span blank) {
    _blanks
      ..add(blank)
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The line with each of [blanks] as `___`, and their answers in order.
  (String, List<String>) _built(Iterable<Span> blanks, {String empty = ''}) {
    final text = StringBuffer();
    final answers = <String>[];
    var at = 0;
    for (final blank in blanks) {
      text
        ..write(_line.substring(at, blank.start))
        ..write(clozeBlank);
      answers.add(blank.start == blank.end ? empty : textOf(blank));
      at = blank.end;
    }
    text.write(_line.substring(at));
    return (text.toString(), answers);
  }

  /// The blanks that hold text, the ones a save keeps.
  Iterable<Span> get _filled =>
      _blanks.where((blank) => blank.start < blank.end);

  /// Why the line cannot be saved yet: no blank holding text, or underscores
  /// in the line that would read as more blanks than it has answers; null
  /// once it can.
  ClozeProblem? get problem {
    final (text, answers) = _built(_filled);
    if (answers.isEmpty) return ClozeProblem.noBlank;
    if (text.split(clozeBlank).length - 1 != answers.length) {
      return ClozeProblem.blankMarker;
    }
    return null;
  }

  /// The cloze the line and its blanks that hold text make, each blank `___`
  /// with its answer, or null while it has a [problem].
  ClozeContent? get content {
    if (problem != null) return null;
    final (text, answers) = _built(_filled);
    return ClozeContent(text, answers);
  }

  /// The cloze as the preview draws it: every blank in place, an empty one
  /// as a block of its own.
  ClozeContent get preview {
    final (text, answers) = _built(_blanks, empty: _emptyAnswer);
    return ClozeContent(text, answers);
  }
}

/// Why a cloze cannot be saved yet.
enum ClozeProblem { noBlank, blankMarker }

/// The line's controller, which draws each blank of [blanks] as a block in
/// the line: its text on `brandTint`, in ink.
class ClozeLineController extends TextEditingController {
  ClozeLineController({super.text, required this.blanks});

  /// The blanks to draw, each within the text, or none while the line is
  /// not a cloze's.
  final List<Span> Function() blanks;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final blanks = this.blanks();
    if (blanks.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final colors = AppColors.of(context);
    final block = TextStyle(
      backgroundColor: colors.brandTint,
      color: colors.ink,
      fontWeight: FontWeight.w600,
    );
    final children = <TextSpan>[];
    var at = 0;
    for (final blank in blanks) {
      children
        ..add(TextSpan(text: text.substring(at, blank.start)))
        ..add(
          TextSpan(text: text.substring(blank.start, blank.end), style: block),
        );
      at = blank.end;
    }
    children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }
}

/// The blanks of the line, each a chip of its answer with a button that turns
/// it back into text, read as "빈칸 풀기, {answer}". With [showError], a line
/// under them says what keeps the cloze from being saved.
class ClozeBlanks extends StatelessWidget {
  const ClozeBlanks({
    super.key,
    required this.draft,
    required this.showError,
    required this.onChanged,
  });

  final ClozeDraft draft;
  final bool showError;

  /// Called after every change, which this widget makes on [draft].
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final problem = showError ? draft.problem : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        if (draft.blanks.isNotEmpty)
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              for (final blank in draft.blanks)
                InputChip(
                  label: Text(
                    blank.start == blank.end
                        ? l10n.clozeEmptyBlank
                        : draft.textOf(blank),
                  ),
                  labelStyle: AppType.bodyStrong.copyWith(color: colors.ink),
                  backgroundColor: colors.brandTint,
                  side: BorderSide(color: colors.brandTint),
                  deleteButtonTooltipMessage: l10n.clozeRemoveBlank(
                    blank.start == blank.end
                        ? l10n.clozeEmptyBlank
                        : draft.textOf(blank),
                  ),
                  onDeleted: () {
                    draft.remove(blank);
                    onChanged();
                  },
                ),
            ],
          ),
        if (problem != null)
          Text(switch (problem) {
            ClozeProblem.noBlank => l10n.clozeBlankRequired,
            ClozeProblem.blankMarker => l10n.clozeBlankMarker,
          }, style: AppType.caption.copyWith(color: colors.dontKnowText)),
      ],
    );
  }
}

/// The cloze form's one action, "빈칸 넣기", in a bar right above the
/// keyboard.
class ClozeToolbar extends StatelessWidget {
  const ClozeToolbar({super.key, required this.onInsert});

  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12,
          vertical: AppSpace.s8,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: AppLocalizations.of(context).clozeInsertBlank,
            onPressed: onInsert,
          ),
        ),
      ),
    );
  }
}
