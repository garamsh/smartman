import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import 'previous_cards.dart';
import 'rust/api/engine.dart';
import 'session.dart';
import 'study_style.dart';

/// Every card answered in the session and, last, [current], in one scroll
/// view. At rest the view sits at its end, with [current]'s centre at
/// [currentCenter] while it fits; dragging down reveals earlier cards, and
/// [current] moves down with them.
///
/// The view stays at its end as cards are added while it is there. An answer
/// given while scrolled back returns it to the end; a change of a previous
/// answer leaves it where it is. Scrolled back, it comes to rest with a
/// previous card at its centre, and "지금 카드로" returns it to the end.
class SessionScroll extends StatefulWidget {
  const SessionScroll({
    super.key,
    required this.cards,
    required this.onRedecide,
    required this.current,
    required this.currentCenter,
    required this.currentMaxHeight,
    this.footer = 0,
  });

  /// Oldest first.
  final List<PreviousCard> cards;
  final void Function(int position, Answer answer) onRedecide;

  /// The current card, or the completion card in its place.
  final Widget current;

  /// The height of what [current] holds below the card itself, which is not
  /// counted in placing the card.
  final double footer;

  /// Where [current]'s centre sits at rest, from the top of this view.
  final double currentCenter;

  /// The tallest [current] may grow.
  final double currentMaxHeight;

  @override
  State<SessionScroll> createState() => _SessionScrollState();
}

class _SessionScrollState extends State<SessionScroll> {
  final _controller = _EndPinnedController();

  /// Whether the view is scrolled back from its end by more than half a card.
  final _back = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_trackBack);
  }

  void _trackBack() {
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    _back.value =
        position.maxScrollExtent - position.pixels >
        StudyStyle.currentMinHeight / 2;
  }

  @override
  void didUpdateWidget(SessionScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only an answer adds a card to the stack.
    if (widget.cards.length > oldWidget.cards.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _returnToEnd());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _back.dispose();
    super.dispose();
  }

  void _returnToEnd() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final end = position.maxScrollExtent;
    if (position.pixels >= end) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(end);
    } else {
      position.animateTo(
        end,
        duration: StudyStyle.settleDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ground = AppColors.of(context).ground;
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxHeight * StudyStyle.previousSlotFraction;
        return Stack(
          children: [
            Align(
              // Fewer cards than fill the view sit at its bottom.
              alignment: Alignment.bottomCenter,
              child: CustomScrollView(
                controller: _controller,
                shrinkWrap: true,
                physics: const _CardSnapPhysics(),
                // The current card paints over the stack, as each card does
                // over the one above it.
                paintOrder: SliverPaintOrder.lastIsTop,
                slivers: [
                  PreviousCards(
                    cards: widget.cards,
                    slot: slot,
                    onRedecide: widget.onRedecide,
                  ),
                  SliverToBoxAdapter(
                    child: _CurrentPlace(
                      viewport: constraints.maxHeight,
                      center: widget.currentCenter,
                      maxHeight: widget.currentMaxHeight,
                      footer: widget.footer,
                      child: _Receding(slot: slot, child: widget.current),
                    ),
                  ),
                ],
              ),
            ),
            // Cards scrolled under the top bar fade into the ground.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: StudyStyle.topFade,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ground, ground.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            // Scrolled back, "지금 카드로" over a fade into the ground.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder(
                valueListenable: _back,
                builder: (context, back, _) => back
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [ground.withValues(alpha: 0), ground],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: StudyStyle.bottomFade,
                            bottom: StudyStyle.currentBottomGap,
                          ),
                          child: Center(
                            child: AppButton(
                              label: l10n.backToCurrent,
                              icon: LucideIcons.chevronDown,
                              onPressed: _returnToEnd,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shrinks and dims the current card as the column scrolls back, as it does
/// the previous cards away from its centre; at the end it is at full size
/// and opacity.
class _Receding extends StatelessWidget {
  const _Receding({required this.slot, required this.child});

  final double slot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.of(context).position;
    return ListenableBuilder(
      listenable: position,
      builder: (context, child) {
        final back = scrolledBack(position, slot);
        return Opacity(
          opacity: 1 - (1 - StudyStyle.previousSideOpacity) * back,
          child: Transform.scale(
            scale: 1 - (1 - StudyStyle.previousSideScale) * back,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Brings a fling or a drag released while scrolled back to rest with a
/// previous card at the centre of the view, or at the view's end.
///
/// A previous card's slot is read from the view's height, as the column sizes
/// it, so the physics holds no size of its own that a new layout could leave
/// stale.
class _CardSnapPhysics extends ScrollPhysics {
  const _CardSnapPhysics({super.parent});

  @override
  _CardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _CardSnapPhysics(parent: buildParent(ancestor));

  /// The resting place nearest [pixels]: a previous card's centre at the
  /// view's centre, or the end.
  double _target(ScrollMetrics metrics, double pixels) {
    final slot = metrics.viewportDimension * StudyStyle.previousSlotFraction;
    final end = metrics.maxScrollExtent;
    // The previous card's slot whose centre lies nearest the view's centre.
    final index = ((pixels + metrics.viewportDimension / 2) / slot - 0.5)
        .roundToDouble();
    final centred = (index * slot + slot / 2 - metrics.viewportDimension / 2)
        .clamp(metrics.minScrollExtent, end);
    return (end - pixels).abs() < (centred - pixels).abs() ? end : centred;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final projected =
        super
            .createBallisticSimulation(position, velocity)
            ?.x(double.infinity) ??
        position.pixels;
    final target = _target(position, projected);
    if ((target - position.pixels).abs() < tolerance.distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Makes positions that stay at the end of the scroll view while it grows or
/// shrinks, for as long as they are at it.
class _EndPinnedController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _EndPinnedPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _EndPinnedPosition extends ScrollPositionWithSingleContext {
  _EndPinnedPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  }) {
    addListener(_track);
  }

  /// Whether the view is at its end. A new position starts there.
  var _pinned = true;

  void _track() {
    if (hasContentDimensions) {
      _pinned = pixels >= maxScrollExtent - Tolerance.defaultTolerance.distance;
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // Moved only when the end moved, so an overscroll at the end still
    // springs back as the platform's physics has it.
    final endMoved =
        !hasContentDimensions || this.maxScrollExtent != maxScrollExtent;
    if (_pinned && endMoved && pixels != maxScrollExtent) {
      correctPixels(maxScrollExtent);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// The current card's place at the end of the scroll view: the card full
/// width less [StudyStyle.cardMargin] on each side, below
/// [StudyStyle.previousGap], with the space below it that puts the card's
/// centre at [center] of the [viewport] when the view is at its end, while the
/// card and its [footer] fit above [StudyStyle.currentBottomGap].
class _CurrentPlace extends SingleChildRenderObjectWidget {
  const _CurrentPlace({
    required this.viewport,
    required this.center,
    required this.maxHeight,
    required this.footer,
    required Widget super.child,
  });

  final double viewport;
  final double center;
  final double maxHeight;
  final double footer;

  @override
  _RenderCurrentPlace createRenderObject(BuildContext context) =>
      _RenderCurrentPlace(
        viewport: viewport,
        center: center,
        maxHeight: maxHeight,
        footer: footer,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCurrentPlace renderObject,
  ) {
    renderObject
      ..viewport = viewport
      ..center = center
      ..maxHeight = maxHeight
      ..footer = footer;
  }
}

class _RenderCurrentPlace extends RenderShiftedBox {
  _RenderCurrentPlace({
    required this._viewport,
    required this._center,
    required this._maxHeight,
    required this._footer,
  }) : super(null);

  double _viewport;
  set viewport(double value) {
    if (value == _viewport) return;
    _viewport = value;
    markNeedsLayout();
  }

  double _center;
  set center(double value) {
    if (value == _center) return;
    _center = value;
    markNeedsLayout();
  }

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double _footer;
  set footer(double value) {
    if (value == _footer) return;
    _footer = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    final width = constraints.maxWidth;
    if (child == null) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final cardWidth = max(0.0, width - StudyStyle.cardMargin * 2);
    // The lowest the card's bottom may sit, with its footer below it.
    final bottom = _viewport - StudyStyle.currentBottomGap - _footer;
    child.layout(
      BoxConstraints(
        minWidth: cardWidth,
        maxWidth: cardWidth,
        maxHeight: max(0.0, min(_maxHeight, bottom)) + _footer,
      ),
      parentUsesSize: true,
    );
    final height = child.size.height - _footer;
    final top = max(0.0, min(_center - height / 2, bottom - height));
    if (child.parentData case final BoxParentData data) {
      data.offset = const Offset(StudyStyle.cardMargin, StudyStyle.previousGap);
    }
    size = constraints.constrain(
      Size(width, StudyStyle.previousGap + _viewport - top),
    );
  }
}
