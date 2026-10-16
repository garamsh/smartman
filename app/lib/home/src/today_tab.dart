import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../account/account.dart';
import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../study/study.dart';
import '../../sync/sync.dart';
import 'hero.dart';

/// The 오늘 tab over [decks]: the today card, the next seven days, and the
/// decks that hold cards for today; once today's cards are done, the done
/// card, the seven days and 계속 학습.
class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.decks});

  final List<Deck> decks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = DeckSelection.of([for (final deck in decks) deck.id]);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpace.gutter,
        title: const BrandTitle(),
        actions: const [AccountButton()],
      ),
      body: all == null
          ? const SizedBox.shrink()
          : TodayOverviewReader(
              decks: all,
              builder: (context, overview) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.s8,
                  AppSpace.gutter,
                  AppSpace.s24,
                ),
                children: switch (overview) {
                  TodayOverview(count: TodayCounted(total: 0)) => [
                    _DoneCard(overview: overview),
                    const SizedBox(height: AppSpace.s12),
                    _Forecast(overview: overview),
                    const SizedBox(height: AppSpace.s12),
                    AppButton(
                      label: l10n.todayKeepStudying,
                      icon: LucideIcons.play,
                      size: AppButtonSize.cta,
                      onPressed: () => _study(context, all),
                    ),
                  ],
                  TodayOverview() => [
                    _TodayCard(
                      overview: overview,
                      onStudy: () => _study(context, all),
                    ),
                    const SizedBox(height: AppSpace.s12),
                    _Forecast(overview: overview),
                    _TodayDecks(decks: decks),
                  ],
                  OverviewUnavailable(:final message) => [
                    _HeroCard(
                      children: [
                        Text(
                          message,
                          style: AppType.secondary.copyWith(
                            color: AppColors.of(context).onHero,
                          ),
                        ),
                        AppButton(
                          label: l10n.studyAll,
                          icon: LucideIcons.play,
                          variant: AppButtonVariant.onHero,
                          onPressed: () => _study(context, all),
                        ),
                      ],
                    ),
                  ],
                  // The card's height, so it does not jump.
                  OverviewPending() => [
                    const _HeroCard(
                      children: [SizedBox(height: AppSize.heroSymbol + AppSpace.s40)],
                    ),
                  ],
                },
              ),
            ),
    );
  }
}

void _study(BuildContext context, DeckSelection decks) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => StudyScreen(decks: decks)));

/// The horizontal lockup as the top bar's title, read as the app's name.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    image: true,
    label: AppLocalizations.of(context).appTitle,
    child: Image.asset(
      AppBrand.lockup(Theme.of(context).brightness),
      height: AppSize.lockupHeight,
      excludeFromSemantics: true,
    ),
  );
}

/// The account's avatar at the end of a top bar, which opens the account
/// screen.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpace.s12),
    child: IconButton(
      tooltip: AppLocalizations.of(context).account,
      icon: const AccountAvatar(size: AppSize.smallAvatar),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AccountScreen(syncStatus: SyncStatusView()),
        ),
      ),
    ),
  );
}

/// A navy card holding [children], one under another.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hero,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.s16,
          children: children,
        ),
      ),
    );
  }
}

/// Today's cards over every deck on the navy card: the count and its minutes
/// beside the goal ring, the streak and the goal's line, and 모두 학습.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.overview, required this.onStudy});

  final TodayOverview overview;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final quiet = AppType.secondary.copyWith(color: heroQuiet(colors));
    final TodayOverview(:count, :goal, :streak) = overview;
    return _HeroCard(
      children: [
        Row(
          spacing: AppSpace.s16,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.s4,
                children: [
                  Text(l10n.todayTitle, style: quiet),
                  HeroCount(
                    count: count.total,
                    unit: l10n.todayCountMinutes(count.minutes),
                    semantics: l10n.todayCards(count.total),
                  ),
                ],
              ),
            ),
            _GoalRing(goal: goal),
          ],
        ),
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (streak > 0) _StreakChip(days: streak, onHero: true),
            Text(l10n.goalLine(goal.done, goal.goal), style: quiet),
          ],
        ),
        if (count.backlog) Text(l10n.backlogPaused, style: quiet),
        AppButton(
          label: l10n.studyAll,
          icon: LucideIcons.play,
          variant: AppButtonVariant.onHero,
          onPressed: onStudy,
        ),
      ],
    );
  }
}

/// The daily goal as a ring on the navy card, done over goal in its middle.
class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.goal});

  final DailyGoal goal;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const size = AppSize.mascotMedium - AppSpace.s8;
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).goalRingSemantics(
        goal.done,
        goal.goal,
      ),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: goal.goal == 0 ? 0 : goal.done / goal.goal,
            track: heroTrack(colors),
            ink: colors.onHero,
            stroke: AppSpace.s8,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${goal.done}',
                  style: AppType.bodyStrong.copyWith(color: colors.onHero),
                ),
                Text(
                  '/ ${goal.goal}',
                  style: AppType.micro.copyWith(color: heroQuiet(colors)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.ink,
    required this.stroke,
  });

  final double fraction;
  final Color track;
  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, -pi / 2, 2 * pi * fraction, false, paint..color = ink);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.ink != ink;
}

/// "n일 연속" after a flame, on the navy card or on the surface.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days, required this.onHero});

  final int days;
  final bool onHero;

  @override
  Widget build(BuildContext context) => _Pill(
    onHero: onHero,
    icon: Icon(
      LucideIcons.flame,
      size: AppSpace.s16,
      color: AppColors.of(context).streak,
    ),
    label: AppLocalizations.of(context).streakDays(days),
  );
}

/// A small rounded label after an icon: on the navy card its faint white, on
/// the done card the surface.
class _Pill extends StatelessWidget {
  const _Pill({required this.onHero, required this.icon, required this.label});

  final bool onHero;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: onHero ? heroTrack(colors) : colors.surface,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12,
          vertical: AppSpace.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpace.s4,
          children: [
            icon,
            Text(
              label,
              style: AppType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: onHero ? colors.onHero : colors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Once today's cards are done: the mascot resting, that the day is done, the
/// next review, the streak and the goal reached.
class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.overview});

  final TodayOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final next = overview.nextReview;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.brandTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s24),
        child: Column(
          spacing: AppSpace.s8,
          children: [
            const _RestingMascot(),
            const SizedBox(height: AppSpace.s4),
            Semantics(
              header: true,
              child: Text(
                l10n.todayDone,
                textAlign: TextAlign.center,
                style: AppType.title,
              ),
            ),
            Text(
              next == null
                  ? l10n.noNextReview
                  : l10n.nextReview(
                      next.after == 1
                          ? l10n.forecastTomorrow
                          : DateFormat.EEEE(
                              locale,
                            ).format(overview.days[next.after]),
                      next.cards,
                      overview.minutesFor(next.cards),
                    ),
              textAlign: TextAlign.center,
              style: AppType.secondary.copyWith(color: colors.ink2),
            ),
            Wrap(
              spacing: AppSpace.s8,
              runSpacing: AppSpace.s8,
              alignment: WrapAlignment.center,
              children: [
                if (overview.streak > 0)
                  _StreakChip(days: overview.streak, onHero: false),
                if (overview.goal.reached)
                  _Pill(
                    onHero: false,
                    icon: Icon(
                      LucideIcons.check,
                      size: AppSpace.s16,
                      color: colors.know,
                    ),
                    label: l10n.goalReached(overview.goal.goal),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The mascot in a white circle, resting, with three z's over its shoulder.
class _RestingMascot extends StatelessWidget {
  const _RestingMascot();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const size = AppSize.mascotMedium + AppSpace.s12;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Mascot(size: size, fill: colors.surface),
            Positioned(
              right: -AppSpace.s12,
              top: -AppSpace.s4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (index, style) in [
                    AppType.headline,
                    AppType.label,
                    AppType.micro,
                  ].indexed)
                    Padding(
                      padding: EdgeInsets.only(bottom: AppSpace.s8 * index),
                      child: Text(
                        'z',
                        style: style.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink.withValues(
                            alpha: 0.5 - 0.12 * index,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The next seven study days on a card: the cards due on each as a bar,
/// today's in ink, with tomorrow's count and the week's beside the heading.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.overview});

  final TodayOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final counts = overview.forecast;
    final week = counts.fold(0, (sum, count) => sum + count);
    final most = counts.fold(1, max);
    final done = overview.count.total == 0;
    final labels = [
      for (final (index, day) in overview.days.indexed)
        switch (index) {
          0 => l10n.forecastToday,
          1 => l10n.forecastTomorrow,
          _ => DateFormat.E(locale).format(day),
        },
    ];
    // On the done card the next day with cards stands out; otherwise today.
    final emphasised = done ? (overview.nextReview?.after ?? -1) : 0;
    const barHeight = AppSpace.s40;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.previous),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.s12,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.forecastTitle, style: AppType.label),
                  ),
                ),
                Text(
                  done
                      ? l10n.forecastWeek(week)
                      : l10n.forecastSummary(counts[1], week),
                  style: AppType.caption.copyWith(color: colors.muted),
                ),
              ],
            ),
            Semantics(
              container: true,
              label: [
                for (final (index, count) in counts.indexed)
                  l10n.forecastDay(labels[index], count),
              ].join(', '),
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: AppSpace.s8,
                children: [
                  for (final (index, count) in counts.indexed)
                    Expanded(
                      child: Column(
                        spacing: AppSpace.s4,
                        children: [
                          Text(
                            '$count',
                            style: AppType.micro.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.ink2,
                            ),
                          ),
                          Container(
                            height: max(
                              AppSpace.s4,
                              (count / most * barHeight).roundToDouble(),
                            ),
                            constraints: const BoxConstraints(
                              maxWidth: AppSpace.s24 - 2,
                            ),
                            decoration: BoxDecoration(
                              color: index == emphasised
                                  ? colors.ink
                                  : colors.ink.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(
                                AppSpace.s8 - 2,
                              ),
                            ),
                          ),
                          Text(
                            labels[index],
                            style: AppType.micro.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "오늘 할 덱" and a row for each deck with cards left today, which studies
/// that deck.
class _TodayDecks extends StatelessWidget {
  const _TodayDecks({required this.decks});

  final List<Deck> decks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s4,
            AppSpace.s20,
            AppSpace.s4,
            AppSpace.s8,
          ),
          child: Semantics(
            header: true,
            child: Text(l10n.todayDecks, style: AppType.label),
          ),
        ),
        for (final deck in decks)
          TodayCounter(
            decks: DeckSelection(deck.id),
            builder: (context, count) => switch (count) {
              TodayCounted(:final total) when total > 0 => Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.rowGap),
                child: Semantics(
                  container: true,
                  button: true,
                  label: l10n.studyDeckToday(deck.name, total),
                  onTap: () => _study(context, DeckSelection(deck.id)),
                  excludeSemantics: true,
                  child: Material(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      excludeFromSemantics: true,
                      onTap: () => _study(context, DeckSelection(deck.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.s12,
                          vertical: AppSpace.s8,
                        ),
                        child: Row(
                          spacing: AppSpace.s12,
                          children: [
                            DeckTile(deck: deck),
                            Expanded(
                              child: Text(deck.name, style: AppType.label),
                            ),
                            Text(
                              l10n.deckDueCount(total),
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.ink2,
                              ),
                            ),
                            Icon(LucideIcons.play, color: colors.ink),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}
