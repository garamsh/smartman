import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';

/// How much of a page becomes cards, from its core ideas to every detail: a
/// card is offered from its step upward, and each answer says more at higher
/// steps.
enum DetailStep {
  /// The core ideas, each answer in its short form (핵심).
  core(1),

  /// The key points, each answer in full (요점).
  keyPoints(2),

  /// A vocabulary entry's part of speech before its answer (기본), the default.
  basic(3),

  /// [basic], then each example on its own line (자세히).
  detailed(4),

  /// [detailed], with every detail of the page offered (세부).
  full(5);

  const DetailStep(this.value);

  /// From 1 to 5, as `extract-cards` numbers a card's step.
  final int value;
}

/// The keys the storage given to the photo import screen must be opened to
/// cache: the step, and the level stored before it, which is read once.
const detailStepStorageKeys = {_stepKey, _levelKey};

const _stepKey = 'photoDetailStep';

/// Where the 간단, 기본 and 자세히 level was kept before the steps.
const _levelKey = 'photoDetailLevel';

/// The step a level stored before the steps maps to: the nearest one.
const _stepOfLevel = {
  'simple': DetailStep.core,
  'basic': DetailStep.basic,
  'detailed': DetailStep.detailed,
};

/// The step stored on this device; else the step of a level stored before
/// the steps, which is stored as the step and no longer read; else
/// [DetailStep.basic].
DetailStep readDetailStep(SharedPreferencesWithCache storage) {
  final stored = DetailStep.values.asNameMap()[storage.getString(_stepKey)];
  if (stored != null) return stored;
  final level = _stepOfLevel[storage.getString(_levelKey)];
  if (level == null) return DetailStep.basic;
  unawaited(storeDetailStep(storage, level));
  unawaited(storage.remove(_levelKey));
  return level;
}

/// Stores [step] as this device's choice.
Future<void> storeDetailStep(
  SharedPreferencesWithCache storage,
  DetailStep step,
) => storage.setString(_stepKey, step.name);

/// The name of [step], as the slider shows it.
String detailStepName(AppLocalizations l10n, DetailStep step) => switch (step) {
  DetailStep.core => l10n.detailStepCore,
  DetailStep.keyPoints => l10n.detailStepKeyPoints,
  DetailStep.basic => l10n.detailStepBasic,
  DetailStep.detailed => l10n.detailStepDetailed,
  DetailStep.full => l10n.detailStepFull,
};

/// "카드에 담을 내용" with the chosen step's name, over a slider of the five
/// steps from 핵심 to 세부.
class DetailStepSlider extends StatelessWidget {
  const DetailStepSlider({
    super.key,
    required this.step,
    required this.onChanged,
  });

  final DetailStep step;
  final ValueChanged<DetailStep> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final ends = AppType.caption.copyWith(color: colors.muted);
    DetailStep at(double value) => DetailStep.values[value.round() - 1];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.detailStepLabel,
                  style: AppType.section.copyWith(color: colors.muted),
                ),
              ),
              Text(
                detailStepName(l10n, step),
                style: AppType.label.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: l10n.detailStepLabel,
            child: Slider(
              value: step.value.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              semanticFormatterCallback: (value) => l10n.detailStepValue(
                detailStepName(l10n, at(value)),
                value.round(),
              ),
              onChanged: (value) {
                final chosen = at(value);
                if (chosen != step) onChanged(chosen);
              },
            ),
          ),
        ),
        ExcludeSemantics(
          child: Row(
            children: [
              Expanded(child: Text(l10n.detailStepCore, style: ends)),
              Text(l10n.detailStepFull, style: ends),
            ],
          ),
        ),
      ],
    );
  }
}
