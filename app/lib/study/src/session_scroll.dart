import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'previous_cards.dart';
import 'session.dart';
import 'study_style.dart';

/// Every card answered in the session and, last, [current], in one scroll
/// view. At rest the view sits at its end, with [current]'s centre at
/// [currentCenter] while it fits; dragging down reveals earlier cards, and
/// [current] moves down with them.
///
/// The view stays at its end as cards are added while it is there. An answer
/// given while scrolled back returns it to the end; a toggle leaves it where
/// it is.
class SessionScroll extends StatefulWidget {
  const SessionScroll({
    super.key,
    required this.cards,
    required this.onToggle,
    required this.current,
    required this.currentCenter,
    required this.currentMaxHeight,
  });

  /// Oldest first.
  final List<PreviousCard> cards;
  final void Function(int position) onToggle;

  /// The current card, or the summary in its place.
  final Widget current;

  /// Where [current]'s centre sits at rest, from the top of this view.
  final double currentCenter;

  /// The tallest [current] may grow.
  final double currentMaxHeight;

  @override
  State<SessionScroll> createState() => _SessionScrollState();
}

class _SessionScrollState extends State<SessionScroll> {
  final _controller = _EndPinnedController();

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      // Fewer cards than fill the view sit at its bottom.
      alignment: Alignment.bottomCenter,
      child: CustomScrollView(
        controller: _controller,
        shrinkWrap: true,
        // The current card paints over the stack, as each card does over the
        // one above it.
        paintOrder: SliverPaintOrder.lastIsTop,
        slivers: [
          PreviousCards(cards: widget.cards, onToggle: widget.onToggle),
          SliverToBoxAdapter(
            child: _CurrentPlace(
              viewport: constraints.maxHeight,
              center: widget.currentCenter,
              maxHeight: widget.currentMaxHeight,
              child: widget.current,
            ),
          ),
        ],
      ),
    ),
  );
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
/// [StudyStyle.previousGap], with the space below it that puts its centre at
/// [center] of the [viewport] when the view is at its end, while the card fits
/// above [StudyStyle.currentBottomGap].
class _CurrentPlace extends SingleChildRenderObjectWidget {
  const _CurrentPlace({
    required this.viewport,
    required this.center,
    required this.maxHeight,
    required Widget super.child,
  });

  final double viewport;
  final double center;
  final double maxHeight;

  @override
  _RenderCurrentPlace createRenderObject(BuildContext context) =>
      _RenderCurrentPlace(
        viewport: viewport,
        center: center,
        maxHeight: maxHeight,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCurrentPlace renderObject,
  ) {
    renderObject
      ..viewport = viewport
      ..center = center
      ..maxHeight = maxHeight;
  }
}

class _RenderCurrentPlace extends RenderShiftedBox {
  _RenderCurrentPlace({
    required this._viewport,
    required this._center,
    required this._maxHeight,
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

  @override
  void performLayout() {
    final child = this.child;
    final width = constraints.maxWidth;
    if (child == null) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final cardWidth = max(0.0, width - StudyStyle.cardMargin * 2);
    final bottom = _viewport - StudyStyle.currentBottomGap;
    child.layout(
      BoxConstraints(
        minWidth: cardWidth,
        maxWidth: cardWidth,
        maxHeight: max(0.0, min(_maxHeight, bottom)),
      ),
      parentUsesSize: true,
    );
    final height = child.size.height;
    final top = max(0.0, min(_center - height / 2, bottom - height));
    if (child.parentData case final BoxParentData data) {
      data.offset = const Offset(StudyStyle.cardMargin, StudyStyle.previousGap);
    }
    size = constraints.constrain(
      Size(width, StudyStyle.previousGap + _viewport - top),
    );
  }
}
