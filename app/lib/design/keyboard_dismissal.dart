import 'package:flutter/widgets.dart';

/// Closes the keyboard, by taking the focus from the focused field, when a tap
/// lands on nothing that handles it or a drag scrolls a scrollable that holds
/// that field. A tap that a button or another field handles does what it did.
///
/// The app root wraps every route in it, so the rule holds on every screen.
class KeyboardDismissal extends StatelessWidget {
  const KeyboardDismissal({super.key, required this.child});

  /// The app's navigator, which `MaterialApp.builder` passes.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        final focused = _focused();
        if (notification.dragDetails != null &&
            focused != null &&
            _holds(notification.context, focused.context)) {
          focused.unfocus();
        }
        return false;
      },
      // A tap any widget under the pointer handles wins the gesture arena
      // over this one, which sits above them all.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: () => _focused()?.unfocus(),
        child: child,
      ),
    );
  }

  /// The focused field, or null while only a scope, a route's, holds the
  /// focus.
  static FocusNode? _focused() => switch (FocusManager.instance.primaryFocus) {
    final FocusScopeNode _ => null,
    final node => node,
  };

  /// Whether [scrollable] is an ancestor of [field], so a drag on a strip
  /// beside the field, or inside the field's own text, keeps the keyboard.
  static bool _holds(BuildContext? scrollable, BuildContext? field) {
    if (scrollable == null || field == null) return false;
    var found = false;
    field.visitAncestorElements((element) {
      found = identical(element, scrollable);
      return !found;
    });
    return found;
  }
}
