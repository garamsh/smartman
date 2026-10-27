import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_list_row.dart';
import '../../l10n/app_localizations.dart';
import 'providers.dart';

/// Whether a study card's front sound plays once as the card appears, as
/// [storage] keeps it: on until the user turns it off (ADR 0112).
bool autoplaysAudio(SharedPreferencesWithCache storage) =>
    storage.getBool(autoplayAudioKey) ?? true;

/// The settings row "앞면 소리 자동 재생": a switch, stored on the device at
/// once, over whether a study card's front sound plays once as the card
/// appears (ADR 0112).
class AutoplayAudioRow extends ConsumerStatefulWidget {
  const AutoplayAudioRow({super.key});

  @override
  ConsumerState<AutoplayAudioRow> createState() => _AutoplayAudioRowState();
}

class _AutoplayAudioRowState extends ConsumerState<AutoplayAudioRow> {
  late final _storage = ref.read(studyStorageProvider);
  late var _on = autoplaysAudio(_storage);

  void _set(bool on) {
    setState(() => _on = on);
    unawaited(_storage.setBool(autoplayAudioKey, on));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListRow(
      title: l10n.autoplayAudio,
      trailing: Switch(value: _on, onChanged: _set),
      onTap: () => _set(!_on),
    );
  }
}
