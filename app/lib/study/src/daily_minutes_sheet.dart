import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart' show DeckFailure, describeFailure;
import '../../design/app_button.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'daily_minutes.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'queue.dart';

/// Opens the sheet that sets the daily study minutes. With [first] it is the
/// first-run step, titled as a question, whose "건너뛰기" keeps the minutes as
/// they are. Resolves to the minutes saved, or null when none were.
Future<int?> showDailyMinutesSheet(
  BuildContext context, {
  bool first = false,
}) =>
    showAppSheet<int>(context, builder: (_) => DailyMinutesSheet(first: first));

/// Shows the first-run step once on this device, while no daily study
/// minutes are stored from any device, and stores that it has shown; null,
/// with nothing to wait on, where it has shown before.
Future<void>? askDailyMinutesOnce(BuildContext context) {
  final providers = ProviderScope.containerOf(context, listen: false);
  final storage = providers.read(studyStorageProvider);
  if (storage.getBool(dailyMinutesAskedKey) == true) return null;
  // Stored before the read, so a second caller meanwhile does not ask again.
  unawaited(storage.setBool(dailyMinutesAskedKey, true));
  return () async {
    final int? stored;
    try {
      stored = await providers.read(studyRepositoryProvider).dailyMinutes();
    } on StudyFailure {
      return;
    }
    if (stored != null || !context.mounted) return;
    await showDailyMinutesSheet(context, first: true);
  }();
}

/// Asks for the daily study minutes once ([askDailyMinutesOnce]) the first
/// time it is visible with its route on top: the 오늘 tab's first-run step
/// once a deck has cards, which waits while another tab is selected or a
/// screen is open over the tab.
class FirstDailyMinutes extends StatefulWidget {
  const FirstDailyMinutes({super.key});

  @override
  State<FirstDailyMinutes> createState() => _FirstDailyMinutesState();
}

class _FirstDailyMinutesState extends State<FirstDailyMinutes> {
  var _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A tab kept behind the selected one is not visible.
    if (_asked ||
        !Visibility.of(context) ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return;
    }
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(askDailyMinutesOnce(context));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The daily study minutes, "하루 n분" after a pencil, read as "하루 공부 시간
/// n분, 바꾸기", which opens the sheet that changes them; [onHero] draws it
/// on the navy cards.
class DailyMinutesButton extends StatelessWidget {
  const DailyMinutesButton({
    super.key,
    required this.minutes,
    this.onHero = false,
  });

  final int minutes;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final ink = onHero ? colors.onHero : colors.ink;
    return Semantics(
      container: true,
      button: true,
      label: l10n.dailyMinutesControlSemantics(minutes),
      excludeSemantics: true,
      child: Material(
        // Off the navy it is the surface, as the done card's pills are.
        color: onHero ? colors.hero : colors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: onHero ? colors.onHero : colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(showDailyMinutesSheet(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.tapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpace.s8,
                children: [
                  Flexible(
                    child: Text(
                      l10n.dailyMinutesControl(minutes),
                      style: AppType.label.copyWith(color: ink),
                    ),
                  ),
                  Icon(LucideIcons.pencil, size: AppSize.smallIcon, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The daily study minutes as a row, "하루 공부 시간" with the minutes, which
/// opens the sheet that changes them and shows those saved: the account
/// screen's setting.
class DailyMinutesRow extends ConsumerStatefulWidget {
  const DailyMinutesRow({super.key});

  @override
  ConsumerState<DailyMinutesRow> createState() => _DailyMinutesRowState();
}

class _DailyMinutesRowState extends ConsumerState<DailyMinutesRow> {
  late Future<int?> _minutes = ref.read(studyRepositoryProvider).dailyMinutes();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _minutes,
      builder: (context, read) => AppListRow(
        title: l10n.dailyMinutesTitle,
        leading: const Icon(LucideIcons.timer),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpace.s4,
          children: [
            if (read.connectionState == ConnectionState.done && !read.hasError)
              Text(
                l10n.dailyMinutesChoice(read.data ?? defaultDailyMinutes),
                style: AppType.secondary.copyWith(
                  color: AppColors.of(context).ink2,
                ),
              ),
            const Icon(LucideIcons.chevronRight),
          ],
        ),
        onTap: () async {
          final saved = await showDailyMinutesSheet(context);
          if (saved != null && mounted) {
            setState(() {
              _minutes = Future.value(saved);
            });
          }
        },
      ),
    );
  }
}

/// The sheet that sets the daily study minutes: the choices, a custom value
/// in steps of five, a preview of today's new cards and reviews and of when
/// the last new card starts, and "저장".
class DailyMinutesSheet extends ConsumerStatefulWidget {
  const DailyMinutesSheet({super.key, this.first = false});

  /// Whether the sheet is the first-run step.
  final bool first;

  @override
  ConsumerState<DailyMinutesSheet> createState() => _DailyMinutesSheetState();
}

class _DailyMinutesSheetState extends ConsumerState<DailyMinutesSheet> {
  late final Future<MinutesPlan> _plan = readMinutesPlan(ref);

  /// The minutes chosen; null until a choice differs from the stored ones.
  int? _chosen;

  /// Whether the custom choice is selected; null until a choice is made.
  bool? _custom;
  var _saving = false;
  String? _error;

  Future<void> _save(int minutes) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(studyRepositoryProvider)
          .setDailyMinutes(minutes, at: ref.read(studyClockProvider)());
      if (mounted) Navigator.of(context).pop(minutes);
    } on StudyFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeStudyFailure(AppLocalizations.of(context), failure);
      });
    }
  }

  /// The sheet's content: why the plan could not be read, its place while it
  /// is read, or the choices.
  Widget _content(
    BuildContext context,
    AsyncSnapshot<MinutesPlan> read,
    MinutesPlan? plan,
    int? minutes,
    bool custom,
  ) {
    final l10n = AppLocalizations.of(context);
    if (read case AsyncSnapshot(hasError: true, :final error?)) {
      return Text(
        switch (error) {
          DeckFailure() => describeFailure(l10n, error),
          StudyFailure() => describeStudyFailure(l10n, error),
          _ => Error.throwWithStackTrace(
            error,
            read.stackTrace ?? StackTrace.empty,
          ),
        },
        style: AppType.secondary.copyWith(
          color: AppColors.of(context).dontKnowText,
        ),
      );
    }
    if (plan == null || minutes == null) {
      // The choices' height, so the sheet does not jump.
      return const SizedBox(
        height: AppSize.cta + AppSize.cta + AppSize.cta + AppSpace.s16,
      );
    }
    return _Choices(
      plan: plan,
      minutes: minutes,
      custom: custom,
      error: _error,
      onChoose: (value, {required custom}) => setState(() {
        _chosen = value;
        _custom = custom;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _plan,
      builder: (context, read) {
        final plan = read.data;
        final minutes = _chosen ?? plan?.current;
        final custom =
            _custom ??
            !dailyMinutePresets.contains(minutes ?? defaultDailyMinutes);
        return AppSheet(
          title: widget.first
              ? l10n.dailyMinutesFirstTitle
              : l10n.dailyMinutesTitle,
          body: l10n.dailyMinutesBody,
          content: _content(context, read, plan, minutes, custom),
          actions: [
            if (widget.first)
              AppButton(
                label: l10n.dailyMinutesSkip,
                variant: AppButtonVariant.text,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            AppButton(
              label: l10n.save,
              size: AppButtonSize.cta,
              loading: _saving,
              onPressed: minutes == null ? null : () => _save(minutes),
            ),
          ],
        );
      },
    );
  }
}

/// The choices, the custom steps of [dailyMinuteStep] while custom is chosen, and the preview of
/// [minutes] by [plan].
class _Choices extends StatelessWidget {
  const _Choices({
    required this.plan,
    required this.minutes,
    required this.custom,
    required this.error,
    required this.onChoose,
  });

  final MinutesPlan plan;
  final int minutes;
  final bool custom;
  final String? error;
  final void Function(int minutes, {required bool custom}) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    const perRow = 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        for (var row = 0; row < dailyMinutePresets.length; row += perRow)
          Row(
            spacing: AppSpace.s8,
            children: [
              for (final preset in dailyMinutePresets.skip(row).take(perRow))
                Expanded(
                  child: _Choice(
                    label: l10n.dailyMinutesChoice(preset),
                    selected: !custom && minutes == preset,
                    onTap: () => onChoose(preset, custom: false),
                  ),
                ),
            ],
          ),
        _Choice(
          label: custom
              ? l10n.dailyMinutesCustomValue(minutes)
              : l10n.dailyMinutesCustom,
          selected: custom,
          onTap: () => onChoose(minutes, custom: true),
        ),
        if (custom)
          Row(
            children: [
              _Step(
                icon: LucideIcons.minus,
                tooltip: l10n.dailyMinutesLess,
                onPressed: minutes > minDailyMinutes
                    ? () => onChoose(
                        max(minDailyMinutes, minutes - dailyMinuteStep),
                        custom: true,
                      )
                    : null,
              ),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    l10n.dailyMinutesChoice(minutes),
                    textAlign: TextAlign.center,
                    style: AppType.headline,
                  ),
                ),
              ),
              _Step(
                icon: LucideIcons.plus,
                tooltip: l10n.dailyMinutesMore,
                onPressed: minutes < maxDailyMinutes
                    ? () => onChoose(
                        min(maxDailyMinutes, minutes + dailyMinuteStep),
                        custom: true,
                      )
                    : null,
              ),
            ],
          ),
        const SizedBox(height: AppSpace.s4),
        _Preview(plan: plan, minutes: minutes),
        if (error case final error?)
          Text(
            error,
            style: AppType.caption.copyWith(color: colors.dontKnowText),
          ),
      ],
    );
  }
}

/// A large choice, the primary fill while [selected], read as a button in a
/// group of which one is selected.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.ink : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(color: selected ? colors.ink : colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AppSize.cta,
            child: Center(
              child: Text(
                label,
                style: AppType.label.copyWith(
                  color: selected ? colors.onPrimary : colors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A step of the custom minutes, an outlined icon button.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      minimumSize: const Size.square(AppSize.button),
      side: BorderSide(color: AppColors.of(context).outline),
    ),
  );
}

/// What [minutes] a day means, on the brand tint: today's new cards and
/// reviews, and when the last new card starts; in a backlog, that new cards
/// wait. A screen reader hears it again whenever it changes.
class _Preview extends StatelessWidget {
  const _Preview({required this.plan, required this.minutes});

  final MinutesPlan plan;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final (:fresh, :lastDay) = plan.at(minutes);
    final lines = plan.backlog
        ? [l10n.backlogPaused]
        : [
            l10n.dailyMinutesToday(fresh, plan.reviews),
            switch (lastDay) {
              _ when plan.unstarted == 0 => l10n.dailyMinutesAllStarted,
              null => l10n.dailyMinutesNoTime,
              final day when day == plan.todayStart =>
                l10n.dailyMinutesForecastToday(plan.unstarted),
              final day => l10n.dailyMinutesForecast(
                plan.unstarted,
                _date(context, day, plan.offsetAt),
              ),
            },
          ];
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.brandTint,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpace.s4,
            children: [
              Text(lines.first, style: AppType.bodyStrong),
              for (final line in lines.skip(1))
                Text(
                  line,
                  style: AppType.secondary.copyWith(color: colors.ink2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The calendar date of the study day starting at [start], month and day, in
/// the app's language.
String _date(BuildContext context, DateTime start, UtcOffsetAt offsetAt) {
  final wall = start.toUtc().add(offsetAt(start));
  return DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag())
      .format(DateTime.utc(wall.year, wall.month, wall.day));
}
