import 'package:flutter/material.dart';

import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';

/// A table as the table form edits it: its column headers, its rows of
/// cells, each as many as there are columns and starting with the row's
/// header, and its blanks, in the order they were chosen.
class TableDraft {
  TableDraft._(this.columns, this.rows, this.blanks);

  /// Two columns and two rows, every cell empty, with no blank.
  TableDraft() : this._(_cells(2), [_cells(2), _cells(2)], {});

  /// The columns, rows and blanks of [table].
  factory TableDraft.of(TableContent table) => TableDraft._(
    [for (final text in table.columns) TextEditingController(text: text)],
    [
      for (final row in table.rows)
        [for (final text in row) TextEditingController(text: text)],
    ],
    {...table.blanks},
  );

  final List<TextEditingController> columns;
  final List<List<TextEditingController>> rows;

  /// The cells chosen as blanks; a set keeps the order they were added in.
  final Set<TableBlank> blanks;

  void addRow() => rows.add(_cells(columns.length));

  void addColumn() {
    columns.add(TextEditingController());
    for (final row in rows) {
      row.add(TextEditingController());
    }
  }

  /// Removes the row at [index], its blanks with it.
  void removeRow(int index) {
    for (final cell in rows.removeAt(index)) {
      cell.dispose();
    }
    _moveBlanks(
      (blank) => switch (blank.row) {
        final row when row == index => null,
        final row when row > index => (row: row - 1, column: blank.column),
        _ => blank,
      },
    );
  }

  /// Removes the column at [index], its blanks with it.
  void removeColumn(int index) {
    columns.removeAt(index).dispose();
    for (final row in rows) {
      row.removeAt(index).dispose();
    }
    _moveBlanks(
      (blank) => switch (blank.column) {
        final column when column == index => null,
        final column when column > index => (
          row: blank.row,
          column: column - 1,
        ),
        _ => blank,
      },
    );
  }

  void _moveBlanks(TableBlank? Function(TableBlank blank) move) {
    final moved = [for (final blank in blanks) move(blank)].nonNulls.toList();
    blanks
      ..clear()
      ..addAll(moved);
  }

  /// Chooses [cell] as a blank, or leaves it out.
  void toggle(TableBlank cell) {
    if (!blanks.remove(cell)) blanks.add(cell);
  }

  /// The text of [cell], trimmed.
  String textAt(TableBlank cell) => rows[cell.row][cell.column].text.trim();

  /// The table as typed, every cell trimmed, with its blanks.
  TableContent get table => TableContent(
    columns: [for (final header in columns) header.text.trim()],
    rows: [
      for (final row in rows) [for (final cell in row) cell.text.trim()],
    ],
    blanks: blanks.toList(),
  );

  /// Why the table cannot be saved yet: no blank, or a blank on an empty
  /// cell; null once it can.
  TableProblem? get problem => blanks.isEmpty
      ? TableProblem.noBlank
      : blanks.any((blank) => textAt(blank).isEmpty)
      ? TableProblem.emptyBlank
      : null;

  void dispose() {
    for (final cell in [...columns, ...rows.expand((row) => row)]) {
      cell.dispose();
    }
  }
}

/// Why a table cannot be saved yet.
enum TableProblem { noBlank, emptyBlank }

List<TextEditingController> _cells(int count) => [
  for (var i = 0; i < count; i++) TextEditingController(),
];

/// A cell of the grid: a row of the table, or -1 for the header row, and a
/// column.
typedef _Cell = ({int row, int column});

/// What "지우기" removes: the selected cell's row or its column.
enum _Remove { row, column }

/// The table form: a toolbar over the table, "행 추가", "열 추가", "빈칸" and
/// "지우기", which act on the selected cell, and the table in a grid that
/// scrolls sideways, each header and cell edited in place, a blank tinted
/// `brandTint`. A tap on a cell selects it and edits it; the keyboard's next
/// moves to the next cell. With [showErrors], what keeps it from being saved
/// shows under it (ADR 0102).
class TableFields extends StatefulWidget {
  const TableFields({
    super.key,
    required this.draft,
    required this.showErrors,
    required this.onChanged,
  });

  final TableDraft draft;
  final bool showErrors;

  /// Called after every change, which this widget makes on [draft].
  final VoidCallback onChanged;

  @override
  State<TableFields> createState() => _TableFieldsState();
}

class _TableFieldsState extends State<TableFields> {
  /// The cell the toolbar acts on: the last one tapped or moved to, kept
  /// while a toolbar button is pressed.
  _Cell? _selected;

  /// A cell's width, so that a column lines up from row to row.
  static const _cellWidth = 136.0;

  TableDraft get _draft => widget.draft;

  void _change(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  /// Whether the selected cell is a body cell, the only kind a blank can be.
  TableBlank? get _selectedBody => switch (_selected) {
    (:final row, :final column) when row >= 0 => (row: row, column: column),
    _ => null,
  };

  /// Removes the selected cell's row or column, asking first when it holds
  /// text the card would lose.
  Future<void> _remove(_Remove what) async {
    final cell = _selected;
    if (cell == null) return;
    final l10n = AppLocalizations.of(context);
    final texts = switch (what) {
      _Remove.row => [for (final c in _draft.rows[cell.row]) c.text],
      _Remove.column => [
        _draft.columns[cell.column].text,
        for (final row in _draft.rows) row[cell.column].text,
      ],
    };
    if (texts.any((text) => text.trim().isNotEmpty) &&
        !await showAppConfirm(
          context,
          title: switch (what) {
            _Remove.row => l10n.tableRemoveRowTitle(cell.row + 1),
            _Remove.column => l10n.tableRemoveColumnTitle(cell.column + 1),
          },
          consequence: l10n.tableRemoveBody,
          confirmLabel: l10n.tableRemove,
        )) {
      return;
    }
    if (!mounted) return;
    _change(() {
      switch (what) {
        case _Remove.row:
          _draft.removeRow(cell.row);
        case _Remove.column:
          _draft.removeColumn(cell.column);
      }
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final problem = widget.showErrors ? _draft.problem : null;
    final selected = _selected;
    final body = _selectedBody;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s12,
      children: [
        Semantics(
          label: l10n.tableToolbar,
          container: true,
          child: Wrap(
            spacing: AppSpace.s4,
            runSpacing: AppSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                label: Text(l10n.addRow),
                labelStyle: AppType.bodyStrong.copyWith(color: colors.ink),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => _change(_draft.addRow),
              ),
              ActionChip(
                label: Text(l10n.addColumn),
                labelStyle: AppType.bodyStrong.copyWith(color: colors.ink),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => _change(_draft.addColumn),
              ),
              FilterChip(
                label: Text(l10n.tableBlankToggle),
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                selected: body != null && _draft.blanks.contains(body),
                selectedColor: colors.brandTint,
                labelStyle: AppType.bodyStrong.copyWith(color: colors.ink),
                onSelected: body == null
                    ? null
                    : (_) => _change(() => _draft.toggle(body)),
              ),
              PopupMenuButton<_Remove>(
                tooltip: l10n.tableRemove,
                enabled: selected != null,
                onSelected: _remove,
                itemBuilder: (_) => [
                  if (selected != null && selected.row >= 0)
                    PopupMenuItem(
                      value: _Remove.row,
                      enabled: _draft.rows.length > 1,
                      child: Text(l10n.deleteRow(selected.row + 1)),
                    ),
                  if (selected != null)
                    PopupMenuItem(
                      value: _Remove.column,
                      enabled: _draft.columns.length > 1,
                      child: Text(l10n.deleteColumn(selected.column + 1)),
                    ),
                ],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSize.tapTarget,
                    minWidth: AppSize.tapTarget,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s12,
                      ),
                      child: Text(
                        l10n.tableRemove,
                        style: AppType.bodyStrong.copyWith(
                          color: selected == null ? colors.muted : colors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(_cellWidth),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                children: [
                  for (final (column, header) in _draft.columns.indexed)
                    _field(header, (row: -1, column: column), l10n),
                ],
              ),
              for (final (row, cells) in _draft.rows.indexed)
                TableRow(
                  children: [
                    for (final (column, cell) in cells.indexed)
                      _field(
                        cell,
                        (row: row, column: column),
                        l10n,
                        problem: problem,
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (problem != null)
          Text(switch (problem) {
            TableProblem.noBlank => l10n.tableBlankRequired,
            TableProblem.emptyBlank => l10n.tableBlankEmpty,
          }, style: AppType.caption.copyWith(color: colors.dontKnowText)),
      ],
    );
  }

  /// A header or a cell, edited in place: a header and each row's first cell
  /// bold, a blank tinted, the selected cell outlined in ink, and a blank
  /// with no text outlined in red once the save is refused.
  Widget _field(
    TextEditingController controller,
    _Cell cell,
    AppLocalizations l10n, {
    TableProblem? problem,
  }) {
    final colors = AppColors.of(context);
    final body = cell.row >= 0 ? (row: cell.row, column: cell.column) : null;
    final blank = body != null && _draft.blanks.contains(body);
    final error =
        problem == TableProblem.emptyBlank &&
        blank &&
        _draft.textAt(body).isEmpty;
    final selected = _selected == cell;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color, width: width),
    );
    return Semantics(
      label: [
        if (cell.row < 0)
          l10n.tableHeaderCell(cell.column + 1)
        else
          l10n.tableCell(cell.row + 1, cell.column + 1),
        if (blank) l10n.blank,
      ].join(', '),
      child: Focus(
        // Not a stop of its own: it hears the field inside gain focus.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) setState(() => _selected = cell);
        },
        child: TextField(
          controller: controller,
          maxLines: null,
          textInputAction: TextInputAction.next,
          style: AppType.body.copyWith(
            color: colors.ink,
            fontWeight: cell.row < 0 || cell.column == 0
                ? FontWeight.w700
                : null,
          ),
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: blank
                ? colors.brandTint
                : cell.row < 0
                ? colors.ground
                : colors.surface,
            contentPadding: const EdgeInsets.all(AppSpace.s12),
            enabledBorder: error
                ? border(colors.dontKnowText, 2)
                : selected
                ? border(colors.ink, 2)
                : border(colors.outline, 1),
            focusedBorder: border(error ? colors.dontKnowText : colors.ink, 2),
          ),
        ),
      ),
    );
  }
}
