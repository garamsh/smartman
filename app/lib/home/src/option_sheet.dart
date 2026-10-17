import 'package:flutter/material.dart';

import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';

/// One way to do what an option sheet offers: an [icon] on a tile, a [title]
/// and the one line under it, [body].
typedef SheetOption<T> = ({IconData icon, String title, String body, T value});

/// Opens a sheet titled [title] with a row for each of [options]. Resolves to
/// the value of the option tapped, or null when the sheet is dismissed.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetOption<T>> options,
}) => showAppSheet<T>(
  context,
  builder: (context) {
    final colors = AppColors.of(context);
    return AppSheet(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            AppListRow(
              title: option.title,
              subtitle: option.body,
              onSheet: true,
              leading: Container(
                width: AppSize.deckTile,
                height: AppSize.deckTile,
                decoration: BoxDecoration(
                  color: colors.brandTint,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Icon(option.icon, color: colors.ink),
              ),
              onTap: () => Navigator.of(context).pop(option.value),
            ),
        ],
      ),
    );
  },
);
