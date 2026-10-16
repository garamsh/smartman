import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';

/// The 기록 tab: its title, and that the record arrives here soon.
class RecordTab extends StatelessWidget {
  const RecordTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: AppSize.cta + AppSpace.s8,
        titleSpacing: AppSpace.gutter,
        title: Semantics(
          header: true,
          child: Text(l10n.tabRecord, style: AppType.deckTitle),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.gutter),
          child: Text(
            l10n.recordComingSoon,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: AppColors.of(context).muted),
          ),
        ),
      ),
    );
  }
}
