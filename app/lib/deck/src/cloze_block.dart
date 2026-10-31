import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design/app_chip.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// A run of a line's characters: where it starts and where it ends.
typedef Span = ({int start, int end});

/// What the preview draws for an empty blank, so it shows as a block before
/// anything is typed into it.
const _emptyAnswer = '  ';

/// A cloze as a 빈칸 문장 block edits it: the line, and its blanks, each a span
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
  /// cursor, open to what is typed next. A cursor in a blank adds none.
  void insert(TextSelection selection) {
    final start = selection.isValid ? selection.start : _line.length;
    final end = selection.isValid ? selection.end : _line.length;
    if (start < end) {
      _blanks.removeWhere((blank) => blank.start < end && start < blank.end);
      _place((start: start, end: end));
      _open = null;
      return;
    }
    if (_blanks.any((blank) => _holdsCaret(blank, start))) return;
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
    if (selection.isCollapsed && _holdsCaret(open, selection.start)) return;
    _closeOpen();
  }

  void _closeOpen() {
    final open = _open;
    if (open == null) return;
    if (open.start == open.end) _blanks.remove(open);
    _open = null;
  }

  /// The blank [selection] is in, which "빈칸 풀기" acts on: the blank that
  /// holds the whole selection, the open blank while the caret is in it, or
  /// one the caret is in, at either end included; null elsewhere.
  Span? blankAt(TextSelection selection) {
    if (!selection.isValid) return null;
    final (start, end) = (selection.start, selection.end);
    final open = _open;
    if (selection.isCollapsed && open != null && _holdsCaret(open, start)) {
      return open;
    }
    for (final blank in _blanks) {
      final inside = selection.isCollapsed
          ? _holdsCaret(blank, start)
          : blank.start <= start && end <= blank.end;
      if (inside) return blank;
    }
    return null;
  }

  /// Whether a caret at [offset] is in [blank]: between its ends or at
  /// either, so a tap on a blank of one character, which leaves the caret
  /// on one side of it, reaches it.
  static bool _holdsCaret(Span blank, int offset) =>
      blank.start <= offset && offset <= blank.end;

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
      final before = text.substring(at, blank.start);
      if (blank.start == blank.end && before.isNotEmpty) {
        // The character before an empty blank is spaced out by the gap the
        // blank is drawn in, so no character is added to the line.
        final last = before.length > 1 && _trails(before) ? 2 : 1;
        final split = before.length - last;
        children
          ..add(TextSpan(text: before.substring(0, split)))
          ..add(
            TextSpan(
              text: before.substring(split),
              style: const TextStyle(letterSpacing: emptyBlankWidth),
            ),
          );
      } else {
        children.add(TextSpan(text: before));
      }
      children.add(
        TextSpan(text: text.substring(blank.start, blank.end), style: block),
      );
      at = blank.end;
    }
    children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }

  /// Whether [text] ends in the second half of a surrogate pair.
  static bool _trails(String text) =>
      text.codeUnitAt(text.length - 1) & 0xFC00 == 0xDC00;
}

/// How wide an empty blank is drawn in the line: its gap and the underline
/// under it. At the line's start, where no character makes room, the gap is
/// the field's own inset.
const emptyBlankWidth = AppSpace.s12;

/// The line's field, [child], with each empty blank of [controller] drawn
/// in it as a hidden blank is drawn (ADR 0119): a gap, which the controller
/// leaves before the blank, over a `muted` underline ending at the caret's
/// place. Nothing is added to the line's text.
class ClozeEmptyBlanks extends SingleChildRenderObjectWidget {
  const ClozeEmptyBlanks({
    super.key,
    required this.controller,
    required super.child,
  });

  final ClozeLineController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderClozeEmptyBlanks(controller, AppColors.of(context).muted);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderClozeEmptyBlanks renderObject,
  ) => renderObject
    ..controller = controller
    ..color = AppColors.of(context).muted;
}

/// What [ClozeEmptyBlanks] draws with.
class RenderClozeEmptyBlanks extends RenderProxyBox {
  RenderClozeEmptyBlanks(this._controller, this._color);

  ClozeLineController _controller;
  set controller(ClozeLineController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The field's text layout, the one render editable under it.
  RenderEditable? get _editable {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
      } else {
        child.visitChildren(visit);
      }
    }

    child?.visitChildren(visit);
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final editable = _editable;
    if (editable == null || !editable.hasSize) return;
    final empty = [
      for (final blank in _controller.blanks())
        if (blank.start == blank.end) blank.start,
    ];
    if (empty.isEmpty) return;
    final transform = editable.getTransformTo(this);
    final paint = Paint()
      ..color = _color
      ..strokeWidth = 1;
    for (final at in empty) {
      final caret = editable.getLocalRectForCaret(TextPosition(offset: at));
      final end = MatrixUtils.transformPoint(transform, caret.bottomLeft);
      context.canvas.drawLine(
        offset + end - const Offset(emptyBlankWidth, 0),
        offset + end,
        paint,
      );
    }
  }
}

/// What keeps the cloze from being saved, in a line under it while
/// [showError]; nothing otherwise.
class ClozeProblemText extends StatelessWidget {
  const ClozeProblemText({
    super.key,
    required this.draft,
    required this.showError,
  });

  final ClozeDraft draft;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = showError ? draft.problem : null;
    if (problem == null) return const SizedBox.shrink();
    final message = switch (problem) {
      ClozeProblem.noBlank => l10n.clozeBlankRequired,
      ClozeProblem.blankMarker => l10n.clozeBlankMarker,
    };
    return Text(
      keepWords(message),
      semanticsLabel: message,
      style: AppType.caption.copyWith(
        color: AppColors.of(context).dontKnowText,
      ),
    );
  }
}

/// A 빈칸 문장's one action, a small outlined chip right under its line. With
/// the caret or the selection inside [blank], it reads "빈칸 풀기", is named
/// for a screen reader with the blank's answer, and turns that blank back
/// into text; elsewhere it reads "빈칸 넣기" (ADR 0101). It is never a
/// primary fill, which the bottom bar holds (ADR 0117).
class ClozeAction extends StatelessWidget {
  const ClozeAction({
    super.key,
    required this.draft,
    required this.blank,
    required this.onInsert,
    required this.onUndo,
  });

  final ClozeDraft draft;

  /// The blank the caret or the selection is in, or null.
  final Span? blank;
  final VoidCallback onInsert;
  final ValueChanged<Span> onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blank = this.blank;
    Widget chip(String label, VoidCallback onPressed) =>
        AppChip.action(label: label, onPressed: onPressed);
    return Align(
      alignment: Alignment.centerLeft,
      child: blank == null
          ? chip(l10n.clozeInsertBlank, onInsert)
          : Semantics(
              label: l10n.clozeRemoveBlank(
                blank.start == blank.end
                    ? l10n.clozeEmptyBlank
                    : draft.textOf(blank),
              ),
              button: true,
              excludeSemantics: true,
              onTap: () => onUndo(blank),
              child: chip(l10n.clozeUndoBlank, () => onUndo(blank)),
            ),
    );
  }
}
