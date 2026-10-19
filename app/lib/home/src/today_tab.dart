import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../account/account.dart';
import '../../deck/deck.dart';
import '../../design/app_button.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import '../../study/study.dart';
import '../../sync/sync.dart';
import 'deck_screen.dart';
import 'first_run.dart';
import 'hero.dart';

/// The 오늘 tab over [decks]: the today card, the next seven days, and the
/// decks that hold cards for today; in a backlog, the backlog card and the
/// catch-up at an average day's load; once today's cards are done, the done
/// card, the seven days and 학습하기. While no deck holds a card, by
/// [counts], how to start: with one deck, adding cards to it; with more,
/// [onShowDecks], which shows the 덱 tab. Showing a day with cards, it asks for
/// the daily study minutes once ([FirstDailyMinutes]).
class TodayTab extends StatelessWidget {
  const TodayTab({
    super.key,
    required this.decks,
    required this.counts,
    required this.onShowDecks,
  });

  final List<Deck> decks;
  final Map<DeckId, int> counts;
  final VoidCallback onShowDecks;

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
          : counts.values.every((count) => count == 0)
          ? _NoCards(decks: decks, onShowDecks: onShowDecks)
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
                  // The first-run step asks for the minutes once a deck has
                  // cards.
                  TodayOverview(count: TodayCounted(total: 0)) => [
                    const FirstDailyMinutes(),
                    _DoneCard(overview: overview),
                    const SizedBox(height: AppSpace.s12),
                    _Forecast(overview: overview),
                    const SizedBox(height: AppSpace.s12),
                    AppButton(
                      label: l10n.todayStudy,
                      icon: LucideIcons.play,
                      size: AppButtonSize.cta,
                      onPressed: () => _study(context, all),
                    ),
                  ],
                  TodayOverview(count: TodayCounted(backlog: true)) => [
                    const FirstDailyMinutes(),
                    _BacklogCard(
                      overview: overview,
                      onStudy: () => _study(context, all),
                    ),
                    const SizedBox(height: AppSpace.s12),
                    _CatchUp(overview: overview),
                  ],
                  TodayOverview() => [
                    const FirstDailyMinutes(),
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
                      children: [
                        SizedBox(height: AppSize.heroSymbol + AppSpace.s40),
                      ],
                    ),
                  ],
                },
              ),
            ),
    );
  }
}

/// How to start while no deck holds a card: add cards to the one deck, or
/// open it; with more decks, go to the 덱 tab to add cards in one of them.
class _NoCards extends StatelessWidget {
  const _NoCards({required this.decks, required this.onShowDecks});

  final List<Deck> decks;
  final VoidCallback onShowDecks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void open(Deck deck, {required bool adding}) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeckScreen(deck: deck, addingCard: adding),
      ),
    );
    return FirstRun(
      title: l10n.noCardsTitle,
      body: l10n.noCardsBody,
      actions: switch (decks) {
        [final deck] => [
          AppButton(
            label: l10n.newCard,
            icon: LucideIcons.plus,
            size: AppButtonSize.cta,
            onPressed: () => open(deck, adding: true),
          ),
          AppButton(
            label: l10n.openDeck,
            variant: AppButtonVariant.text,
            onPressed: () => open(deck, adding: false),
          ),
        ],
        _ => [
          AppButton(
            label: l10n.addCardsInDecks,
            icon: LucideIcons.layers,
            size: AppButtonSize.cta,
            onPressed: onShowDecks,
          ),
        ],
      },
    );
  }
}

void _study(BuildContext context, DeckSelection decks) =>
    unawaited(openStudy(context, decks));

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
          builder: (_) => const AccountScreen(
            syncStatus: SyncStatusView(),
            studySetting: DailyMinutesRow(),
          ),
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
/// beside the goal ring, the streak and where the user stands today
/// ([TodayStatus]), and 모두 학습.
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
        Align(
          alignment: Alignment.centerLeft,
          child: DailyMinutesButton(
            minutes: overview.dailyMinutes,
            onHero: true,
          ),
        ),
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (streak > 0) _StreakChip(days: streak, onHero: true),
            if (overview.extra > 0)
              _ExtraPill(count: overview.extra, onHero: true),
            Text(
              keepWords(switch (TodayStatus.of(goal, streak: streak)) {
                StatusStreak(:final days) => l10n.statusStreak(days),
                StatusWaiting() => l10n.statusWaiting,
                StatusAlmostDone() => l10n.statusAlmostDone,
                StatusPastHalf() => l10n.statusPastHalf,
                StatusStarted() => l10n.statusStarted,
              }),
              style: quiet,
            ),
          ],
        ),
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

/// In a backlog of reviews, on the navy card: the mascot cheering, that the
/// user can pick up again, how many reviews are overdue and that new cards
/// pause, and the button that studies them, with their minutes.
class _BacklogCard extends StatelessWidget {
  const _BacklogCard({required this.overview, required this.onStudy});

  final TodayOverview overview;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final count = overview.count;
    return _HeroCard(
      children: [
        Row(
          spacing: AppSpace.s16,
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: AppSize.mascotGuide,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Mascot(size: AppSize.mascotGuide, fill: colors.surface),
                    Positioned(
                      right: -AppSpace.s4,
                      bottom: -AppSpace.s4,
                      child: Container(
                        width: AppSpace.s24,
                        height: AppSpace.s24,
                        decoration: ShapeDecoration(
                          color: colors.tintAmber,
                          shape: const CircleBorder(),
                        ),
                        child: Icon(
                          LucideIcons.check,
                          size: AppSpace.s16,
                          color: colors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.s4,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.backlogTitle,
                      style: AppType.headline.copyWith(color: colors.onHero),
                    ),
                  ),
                  Text(
                    l10n.backlogBody(count.total),
                    style: AppType.secondary.copyWith(color: heroQuiet(colors)),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DailyMinutesButton(minutes: overview.dailyMinutes, onHero: true),
            if (overview.streak > 0)
              _StreakChip(days: overview.streak, onHero: true),
          ],
        ),
        AppButton(
          label: l10n.backlogStudy(count.total, count.minutes),
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
      label: AppLocalizations.of(context)
          .goalRingSemantics(goal.done, goal.goal),
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
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * fraction,
        false,
        paint..color = ink,
      );
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

/// "오늘 n장 더 했어요" after a plus: the cards studied past the day's plan,
/// which its goal never counts.
class _ExtraPill extends StatelessWidget {
  const _ExtraPill({required this.count, required this.onHero});

  final int count;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _Pill(
      onHero: onHero,
      icon: Icon(
        LucideIcons.plus,
        size: AppSpace.s16,
        color: onHero ? colors.onHero : colors.ink,
      ),
      label: AppLocalizations.of(context).todayExtra(count),
    );
  }
}

/// A small rounded label after an icon: on the navy card an outline in its
/// faint white, on the done card the surface.
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
        // On the navy the pill is an outline, so its flame sits on the navy.
        color: onHero ? null : colors.surface,
        shape: StadiumBorder(
          side: onHero ? BorderSide(color: heroTrack(colors)) : BorderSide.none,
        ),
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
                          : DateFormat.EEEE(locale)
                                .format(overview.days[next.after]),
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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DailyMinutesButton(minutes: overview.dailyMinutes),
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
                if (overview.extra > 0)
                  _ExtraPill(count: overview.extra, onHero: false),
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

/// The labels of the seven days of [overview]: 오늘, 내일, then the weekday.
List<String> _dayLabels(BuildContext context, TodayOverview overview) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return [
    for (final (index, day) in overview.days.indexed)
      switch (index) {
        0 => l10n.forecastToday,
        1 => l10n.forecastTomorrow,
        _ => DateFormat.E(locale).format(day),
      },
  ];
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
    final counts = overview.forecast;
    final week = counts.fold(0, (sum, count) => sum + count);
    final done = overview.count.total == 0;
    final labels = _dayLabels(context, overview);
    return _ChartCard(
      title: l10n.forecastTitle,
      trailing: done
          ? l10n.forecastWeek(week)
          : l10n.forecastSummary(counts[1], week),
      chart: _DayBars(
        counts: counts,
        labels: labels,
        // On the done card the next day with cards stands out; otherwise
        // today.
        emphasised: done ? (overview.nextReview?.after ?? -1) : 0,
        ink: colors.ink,
        semantics: [
          for (final (index, count) in counts.indexed)
            l10n.forecastDay(labels[index], count),
        ].join(', '),
      ),
    );
  }
}

/// In a backlog: the overdue reviews left at the start of each of the next
/// seven days at an average day's load, in the streak's amber, and how many
/// days that takes.
class _CatchUp extends StatelessWidget {
  const _CatchUp({required this.overview});

  final TodayOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final counts = overview.backlogLeft;
    final labels = _dayLabels(context, overview);
    final days = (overview.count.total / overview.load).ceil();
    return _ChartCard(
      title: l10n.catchUpTitle(overview.load, days),
      chart: _DayBars(
        counts: counts,
        labels: labels,
        emphasised: null,
        ink: colors.streak,
        semantics: l10n.catchUpSemantics(
          [
            for (final (index, count) in counts.indexed)
              l10n.forecastDay(labels[index], count),
          ].join(', '),
        ),
      ),
      note: l10n.catchUpNote(overview.load),
    );
  }
}

/// A chart on the surface: its [title], an optional [trailing] line beside
/// it, the [chart], and an optional [note] under it.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.chart,
    this.trailing,
    this.note,
  });

  final String title;
  final Widget chart;
  final String? trailing;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final quiet = AppType.caption.copyWith(color: colors.muted);
    final trailing = this.trailing;
    final note = this.note;
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
                    child: Text(title, style: AppType.label),
                  ),
                ),
                if (trailing != null) Text(trailing, style: quiet),
              ],
            ),
            chart,
            if (note != null) Text(note, style: quiet),
          ],
        ),
      ),
    );
  }
}

/// A bar for each of [counts], its count above it and its label under it,
/// the [emphasised] one in [ink] and the others a quieter shade of it, or all
/// in [ink] when none is; read as [semantics].
class _DayBars extends StatelessWidget {
  const _DayBars({
    required this.counts,
    required this.labels,
    required this.emphasised,
    required this.ink,
    required this.semantics,
  });

  final List<int> counts;
  final List<String> labels;
  final int? emphasised;
  final Color ink;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final most = counts.fold(1, max);
    const barHeight = AppSpace.s40;
    return Semantics(
      container: true,
      label: semantics,
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
                      color: emphasised == null || index == emphasised
                          ? ink
                          : AppColors.quiet(ink),
                      borderRadius: BorderRadius.circular(AppSpace.s8 - 2),
                    ),
                  ),
                  Text(
                    labels[index],
                    style: AppType.micro.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
        ],
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
