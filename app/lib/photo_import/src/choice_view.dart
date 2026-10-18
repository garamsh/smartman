import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_chip.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'choice.dart';

/// Which side of a topic's sample card has its options open.
enum _Side { front, back }

/// "무엇을 외울까요": the one call's topics as pills, each on at first, and
/// for each topic that is on its first card as a sample, whose front and
/// back open the shape every card of the topic takes. "다음" goes on with
/// the cards of the topics that are on.
class ChoiceView extends StatefulWidget {
  const ChoiceView({super.key, required this.choice, required this.onNext});

  final Choice choice;

  /// Goes on to Review with [Choice.chosen].
  final VoidCallback onNext;

  @override
  State<ChoiceView> createState() => _ChoiceViewState();
}

class _ChoiceViewState extends State<ChoiceView> {
  /// The topic whose sample has a side's options open, and that side.
  (ChoiceTopic, _Side)? _open;

  Choice get _choice => widget.choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String nameOf(ChoiceTopic topic) => topic.name ?? l10n.choiceTopicNone;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s24,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.choiceTitle(_choice.cardCount),
              textAlign: TextAlign.center,
              style: AppType.title,
            ),
          ),
          const SizedBox(height: AppSpace.s24),
          Semantics(
            container: true,
            label: l10n.choiceTopics,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpace.s8,
              runSpacing: AppSpace.s8,
              children: [
                for (final topic in _choice.topics)
                  AppChip(
                    label: nameOf(topic),
                    kind: AppChipChoice(
                      selected: topic.on,
                      onPressed: () => setState(() {
                        topic.on = !topic.on;
                        if (_open?.$1 == topic) _open = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          for (final topic in _choice.topics.where((topic) => topic.on)) ...[
            const SizedBox(height: AppSpace.s24),
            _TopicSample(
              key: ObjectKey(topic),
              name: nameOf(topic),
              topic: topic,
              open: _open?.$1 == topic ? _open!.$2 : null,
              onOpen: (side) => setState(
                () => _open = _open == (topic, side) ? null : (topic, side),
              ),
              onShaped: () => setState(() => _open = null),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s8,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          child: AppButton(
            label: l10n.choiceNext,
            size: AppButtonSize.cta,
            onPressed: _choice.anyOn ? widget.onNext : null,
          ),
        ),
      ),
    );
  }
}

/// A topic's name over its sample card in the chosen shape, whose front and
/// back each open their options.
class _TopicSample extends StatelessWidget {
  const _TopicSample({
    super.key,
    required this.name,
    required this.topic,
    required this.open,
    required this.onOpen,
    required this.onShaped,
  });

  final String name;
  final ChoiceTopic topic;

  /// The side whose options are open; null for none.
  final _Side? open;

  final ValueChanged<_Side> onOpen;

  /// Called after a shape was chosen.
  final VoidCallback onShaped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final sample = topic.sample;
    Widget side(_Side which, String text, TextStyle style) => Expanded(
      child: Semantics(
        button: true,
        expanded: open == which,
        label: switch (which) {
          _Side.front => l10n.choiceFrontLabel(name, text),
          _Side.back => l10n.choiceBackLabel(name, text),
        },
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onOpen(which),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSize.cta * 1.5),
            color: open == which ? colors.brandTint : null,
            padding: const EdgeInsets.all(AppSpace.s16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpace.s8,
              children: [
                Expanded(child: Text(keepWords(text), style: style)),
                Icon(
                  LucideIcons.pencil,
                  size: AppSize.smallIcon,
                  color: colors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final options = switch (open) {
      _Side.front => [
        for (final shape in FrontShape.values)
          (
            switch (shape) {
              FrontShape.name => l10n.choiceFrontName,
              FrontShape.content => l10n.choiceFrontContent,
            },
            topic.front == shape,
            () => topic.front = shape,
          ),
      ],
      _Side.back => [
        for (final shape in BackShape.values)
          if (shape != BackShape.examples || topic.hasExamples)
            (
              switch (shape) {
                BackShape.core => l10n.choiceBackCore,
                BackShape.examples => l10n.choiceBackExamples,
              },
              topic.back == shape,
              () => topic.back = shape,
            ),
      ],
      null => const <(String, bool, VoidCallback)>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            name,
            style: AppType.section.copyWith(color: colors.muted),
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        AppRowSurface(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.row),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  side(
                    _Side.front,
                    sample.front,
                    AppType.bodyStrong.copyWith(color: colors.ink),
                  ),
                  VerticalDivider(width: 1, color: colors.hairline),
                  side(
                    _Side.back,
                    sample.back,
                    AppType.body.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (options.isNotEmpty)
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s8,
            children: [
              for (final (label, chosen, choose) in options)
                AppChip(
                  label: label,
                  kind: AppChipChoice(
                    selected: chosen,
                    onPressed: () {
                      choose();
                      onShaped();
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
