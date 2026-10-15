import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';

/// "공개됨", on a deck others can find.
class PublicChip extends StatelessWidget {
  const PublicChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.muted),
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Text(
        AppLocalizations.of(context).publicChip,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colors.muted, fontWeight: FontWeight.w600),
      ),
    );
  }
}
