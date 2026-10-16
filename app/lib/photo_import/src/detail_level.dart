import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';

/// How much of a page's entry each card's answer says.
enum DetailLevel {
  /// The meaning alone.
  simple,

  /// The part of speech, when the page prints one, then the meaning.
  basic,

  /// [basic], then each example on its own line.
  detailed,
}

/// The keys the storage given to the photo import screen must be opened to
/// cache.
const detailLevelStorageKeys = {_detailLevelKey};

const _detailLevelKey = 'photoDetailLevel';

/// The level stored on this device, [DetailLevel.basic] when none or an
/// unknown one is stored.
DetailLevel readDetailLevel(SharedPreferencesWithCache storage) =>
    DetailLevel.values.asNameMap()[storage.getString(_detailLevelKey)] ??
    DetailLevel.basic;

/// Stores [level] as this device's choice.
Future<void> storeDetailLevel(
  SharedPreferencesWithCache storage,
  DetailLevel level,
) => storage.setString(_detailLevelKey, level.name);

/// "카드에 담을 내용" over the three levels, the chosen one selected.
class DetailLevelSelector extends StatelessWidget {
  const DetailLevelSelector({
    super.key,
    required this.level,
    required this.onChanged,
  });

  final DetailLevel level;
  final ValueChanged<DetailLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: l10n.detailLevelLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              l10n.detailLevelLabel,
              style: AppType.section.copyWith(color: colors.muted),
            ),
          ),
          const SizedBox(height: AppSpace.s8),
          SegmentedButton<DetailLevel>(
            segments: [
              ButtonSegment(
                value: DetailLevel.simple,
                label: Text(l10n.detailLevelSimple),
              ),
              ButtonSegment(
                value: DetailLevel.basic,
                label: Text(l10n.detailLevelBasic),
              ),
              ButtonSegment(
                value: DetailLevel.detailed,
                label: Text(l10n.detailLevelDetailed),
              ),
            ],
            selected: {level},
            showSelectedIcon: false,
            onSelectionChanged: (choice) => onChanged(choice.single),
          ),
        ],
      ),
    );
  }
}
