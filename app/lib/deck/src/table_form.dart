import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_text_field.dart';
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

/// The table form's two ways of working, so that a tap does one thing in
/// each: typing the cells, or choosing the blanks.
enum _Mode { cells, blanks }

/// The table form: a switch between typing the cells and choosing the
/// blanks, the table in a grid that scrolls sideways, buttons that add and
/// remove its rows and columns, and, with [showErrors], what keeps it from
/// being saved.
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
  _Mode _mode = _Mode.cells;

  /// A cell's width, so that a column lines up from row to row.
  static const _cellWidth = 136.0;

  TableDraft get _draft => widget.draft;

  void _change(VoidCallback change) {
    change();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final problem = widget.showErrors ? _draft.problem : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s12,
      children: [
        Semantics(
          label: l10n.tableModeLabel,
          child: SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Mode.cells,
                label: Text(l10n.tableModeCells),
              ),
              ButtonSegment(
                value: _Mode.blanks,
                label: Text(l10n.tableModeBlanks),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (modes) => setState(() => _mode = modes.single),
          ),
        ),
        Text(switch (_mode) {
          _Mode.cells => l10n.tableCellsHint,
          _Mode.blanks => l10n.tableBlanksHint,
        }, style: AppType.secondary.copyWith(color: colors.muted)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: switch (_mode) {
            _Mode.cells => _cellsGrid(l10n),
            _Mode.blanks => _blanksGrid(l10n, problem),
          },
        ),
        if (_mode == _Mode.cells)
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              AppButton(
                label: l10n.addRow,
                icon: LucideIcons.plus,
                variant: AppButtonVariant.secondary,
                onPressed: () => _change(_draft.addRow),
              ),
              AppButton(
                label: l10n.addColumn,
                icon: LucideIcons.plus,
                variant: AppButtonVariant.secondary,
                onPressed: () => _change(_draft.addColumn),
              ),
            ],
          ),
        if (problem != null)
          Text(switch (problem) {
            TableProblem.noBlank => l10n.tableBlankRequired,
            TableProblem.emptyBlank => l10n.tableBlankEmpty,
          }, style: AppType.caption.copyWith(color: colors.dontKnowText)),
      ],
    );
  }

  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.all(AppSpace.s4), child: child);

  /// The headers and cells as fields, each column with a delete button over
  /// it and each row with one after it.
  Widget _cellsGrid(AppLocalizations l10n) {
    final columns = _draft.columns.length;
    final rows = _draft.rows.length;
    Widget field(
      TextEditingController cell,
      String label, {
      bool bold = false,
    }) => _padded(
      Semantics(
        label: label,
        child: AppTextField(
          controller: cell,
          maxLines: null,
          style: bold
              ? AppType.body.copyWith(fontWeight: FontWeight.w700)
              : null,
          onChanged: (_) => widget.onChanged(),
        ),
      ),
    );
    return Table(
      defaultColumnWidth: const FixedColumnWidth(_cellWidth),
      columnWidths: {columns: const IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (var column = 0; column < columns; column++)
              Center(
                child: IconButton(
                  tooltip: l10n.deleteColumn(column + 1),
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: columns > 1
                      ? () => _change(() => _draft.removeColumn(column))
                      : null,
                ),
              ),
            const SizedBox.shrink(),
          ],
        ),
        TableRow(
          children: [
            for (final (column, header) in _draft.columns.indexed)
              field(header, l10n.tableHeaderCell(column + 1), bold: true),
            const SizedBox.shrink(),
          ],
        ),
        for (final (row, cells) in _draft.rows.indexed)
          TableRow(
            children: [
              for (final (column, cell) in cells.indexed)
                field(
                  cell,
                  l10n.tableCell(row + 1, column + 1),
                  bold: column == 0,
                ),
              IconButton(
                tooltip: l10n.deleteRow(row + 1),
                icon: const Icon(LucideIcons.trash2),
                onPressed: rows > 1
                    ? () => _change(() => _draft.removeRow(row))
                    : null,
              ),
            ],
          ),
      ],
    );
  }

  /// The headers as text and each cell as a toggle, chosen as a blank or
  /// not, read with its place and its state and given the screen-reader
  /// action that changes it.
  Widget _blanksGrid(AppLocalizations l10n, TableProblem? problem) {
    final colors = AppColors.of(context);
    return Table(
      defaultColumnWidth: const FixedColumnWidth(_cellWidth),
      defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
      children: [
        TableRow(
          children: [
            for (final header in _draft.columns)
              _padded(
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSize.field),
                  child: Center(
                    child: Text(
                      header.text.trim(),
                      textAlign: TextAlign.center,
                      style: AppType.body.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (final (row, cells) in _draft.rows.indexed)
          TableRow(
            children: [
              for (final column in cells.indexed.map((entry) => entry.$1))
                _padded(
                  _BlankCell(
                    text: _draft.textAt((row: row, column: column)),
                    place: l10n.tableCell(row + 1, column + 1),
                    chosen: _draft.blanks.contains((row: row, column: column)),
                    bold: column == 0,
                    error:
                        problem == TableProblem.emptyBlank &&
                        _draft.blanks.contains((row: row, column: column)) &&
                        _draft.textAt((row: row, column: column)).isEmpty,
                    onToggle: () => _change(
                      () => _draft.toggle((row: row, column: column)),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A cell of the blanks grid: its text on a tile, filled when [chosen], a
/// tap choosing it or leaving it out. A screen reader reads its text, its
/// place and whether it is a blank, and offers "빈칸으로" or "빈칸 해제".
class _BlankCell extends StatelessWidget {
  const _BlankCell({
    required this.text,
    required this.place,
    required this.chosen,
    required this.bold,
    required this.error,
    required this.onToggle,
  });

  final String text;
  final String place;
  final bool chosen;
  final bool bold;

  /// Whether the cell is a blank with no text, which keeps the table from
  /// being saved.
  final bool error;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: [
        if (text.isEmpty) l10n.tableEmptyCell else text,
        place,
        if (chosen) l10n.blank,
      ].join(', '),
      button: true,
      selected: chosen,
      excludeSemantics: true,
      onTap: onToggle,
      customSemanticsActions: {
        CustomSemanticsAction(
          label: chosen ? l10n.tableClearBlank : l10n.tableMakeBlank,
        ): onToggle,
      },
      child: Material(
        color: chosen ? colors.brandTint : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side: BorderSide(
            color: error
                ? colors.dontKnowText
                : chosen
                ? colors.ink
                : colors.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.field),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s12),
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(
                    color: colors.ink,
                    fontWeight: bold ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
