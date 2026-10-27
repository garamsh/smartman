import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_section_label.dart';
import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';
import 'content_view.dart';
import 'whole_card_view.dart';

/// How long the card takes to turn over (#454).
const previewFlipDuration = Duration(milliseconds: 220);

/// The card as study draws it, full screen, from the card editor's
/// "미리보기" (ADR 0117): one study card on the surface, its front alone and,
/// after a tap, its back, or, for a card studied on one face, that face
/// with its blanks empty and, after a tap, filled. Each tap turns the card
/// over in 3D, or switches it at once when the system asks to reduce
/// motion. "앞면" or "뒷면" names the side over a card of two sides, and a
/// line under the card says what a tap does.
class CardPreviewScreen extends StatefulWidget {
  const CardPreviewScreen({super.key, required this.front, required this.back});

  final List<Content> front;
  final List<Content> back;

  @override
  State<CardPreviewScreen> createState() => _CardPreviewScreenState();
}

class _CardPreviewScreenState extends State<CardPreviewScreen>
    with SingleTickerProviderStateMixin {
  /// 0 with the front or the empty blanks up, 1 with the back or the filled
  /// blanks up.
  late final _turn = AnimationController(
    vsync: this,
    duration: previewFlipDuration,
  );

  /// Whether the card shows, or is turning to, its back or its answers.
  bool _turned = false;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _flip() {
    setState(() => _turned = !_turned);
    if (MediaQuery.disableAnimationsOf(context)) {
      _turn.value = _turned ? 1 : 0;
    } else if (_turned) {
      _turn.forward();
    } else {
      _turn.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final face = oneFaceOf(widget.front, widget.back);
    final hint = switch ((face != null, _turned)) {
      (false, false) => l10n.previewTapToBack,
      (false, true) => l10n.previewTapToFront,
      (true, false) => l10n.previewTapToReveal,
      (true, true) => l10n.previewTapToHide,
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.previewCard),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s8,
            AppSpace.gutter,
            AppSpace.gutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (face == null)
                AppSectionLabel(_turned ? l10n.cardBack : l10n.cardFront),
              Expanded(
                child: Semantics(
                  button: true,
                  onTapHint: hint,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _flip,
                    child: AnimatedBuilder(
                      animation: _turn,
                      builder: (context, _) {
                        final angle = _turn.value * pi;
                        final back = _turn.value >= 0.5;
                        return Transform(
                          alignment: Alignment.center,
                          // Perspective, then the turn; the far side is turned
                          // once more so it does not read mirrored.
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(back ? angle - pi : angle),
                          child: _Face(
                            face: face,
                            front: widget.front,
                            back: widget.back,
                            turned: back,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              ExcludeSemantics(
                child: Text(
                  keepWords(hint),
                  textAlign: TextAlign.center,
                  style: AppType.caption.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One side of the card as study's current card draws it: on the surface
/// with the study card's radius and shadow, its blocks centred, fitted to
/// its width in the front's type, a back in the back's, scrolling inside
/// where they are taller than the card.
class _Face extends StatelessWidget {
  const _Face({
    required this.face,
    required this.front,
    required this.back,
    required this.turned,
  });

  /// The one face of a card with a blank, or null for one of two sides.
  final List<Content>? face;
  final List<Content> front;
  final List<Content> back;
  final bool turned;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final face = this.face;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.raised(colors),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth - 2 * AppSpace.s16;
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: SizedBox(
                    width: double.infinity,
                    child: switch ((face, turned)) {
                      (final face?, _) => WholeCardView(
                        face,
                        revealed: turned,
                        style: AppType.front,
                        minFontSize: AppType.frontFloor,
                        width: width,
                      ),
                      (null, false) => ContentView(
                        front,
                        style: AppType.front,
                        fit: (
                          minFontSize: AppType.frontFloor,
                          width: width,
                          height: null,
                        ),
                      ),
                      (null, true) => ContentView(
                        back,
                        style: AppType.back.copyWith(color: colors.ink),
                        fit: (
                          minFontSize: AppType.backFloor,
                          width: width,
                          height: null,
                        ),
                      ),
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
