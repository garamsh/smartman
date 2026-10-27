import 'package:flutter/material.dart';

import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';

/// One way to do what an option sheet offers: a [title] and, where the title
/// alone does not say what happens, the one line under it, [body]. The sheet
/// draws no [icon]; the field goes once the add-card sheet stops passing one
/// (#445).
typedef SheetOption<T> = ({IconData icon, String title, String? body, T value});

/// Opens a sheet titled [title] with a row for each of [options]. Resolves to
/// the value of the option tapped, or null when the sheet is dismissed.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetOption<T>> options,
}) => showAppSheet<T>(
  context,
  builder: (context) => AppSheet(
    title: title,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          AppListRow(
            title: option.title,
            subtitle: option.body,
            onSheet: true,
            onTap: () => Navigator.of(context).pop(option.value),
          ),
      ],
    ),
  ),
);
