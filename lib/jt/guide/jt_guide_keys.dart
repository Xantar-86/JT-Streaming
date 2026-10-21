import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/jt/guide/jt_guide_controller.dart';

/// Previous (-1) or next (+1) day, same clock time and channel.
class JtGuideDayIntent extends Intent {
  final int delta;
  const JtGuideDayIntent(this.delta);
}

/// PageUp/PageDown plus aliases; the Mi Box remote has neither, there the
/// arrows at the row edge and the day picker change the day (§4).
const Map<ShortcutActivator, Intent> jtGuideDayShortcuts = {
  SingleActivator(LogicalKeyboardKey.pageUp): JtGuideDayIntent(-1),
  SingleActivator(LogicalKeyboardKey.pageDown): JtGuideDayIntent(1),
  SingleActivator(LogicalKeyboardKey.channelUp): JtGuideDayIntent(-1),
  SingleActivator(LogicalKeyboardKey.channelDown): JtGuideDayIntent(1),
  SingleActivator(LogicalKeyboardKey.mediaRewind): JtGuideDayIntent(-1),
  SingleActivator(LogicalKeyboardKey.mediaFastForward): JtGuideDayIntent(1),
};

/// Keys of the guide and its toolbar. The standard directional focus stays
/// the basis; only left/right inside a guide row is handled here so that the
/// arrow past the last/first program changes the day. OK/Enter stays
/// FocusButton.onTap, Escape/Back is not caught.
class JtGuideKeys extends StatelessWidget {
  final JtGuideController controller;
  final bool rowArrows;
  final Widget child;

  const JtGuideKeys({
    required this.controller,
    this.rowArrows = true,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: jtGuideDayShortcuts,
      child: Actions(
        actions: {
          JtGuideDayIntent: CallbackAction<JtGuideDayIntent>(onInvoke: (intent) {
            controller.changeDay(intent.delta);
            return null;
          }),
          if (rowArrows) DirectionalFocusIntent: _JtGuideDirectionalAction(controller),
        },
        child: child,
      ),
    );
  }
}

class _JtGuideDirectionalAction extends Action<DirectionalFocusIntent> {
  final JtGuideController controller;
  _JtGuideDirectionalAction(this.controller);

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = primaryFocus;
    if (node == null) return;
    final horizontal = intent.direction == TraversalDirection.left || intent.direction == TraversalDirection.right;
    final row = horizontal ? controller.rowOf(node) : null;
    if (row == null) {
      // Same as the default DirectionalFocusAction.
      if (!intent.ignoreTextFields || node.context?.widget is! EditableText) node.focusInDirection(intent.direction);
      return;
    }
    final cells = row.cells;
    final index = cells.indexOf(node);
    final next = intent.direction == TraversalDirection.right ? index + 1 : index - 1;
    if (index >= 0 && next >= 0 && next < cells.length) {
      cells[next].requestFocus();
      return;
    }
    controller.edgeJump(intent.direction == TraversalDirection.right ? 1 : -1, row.channelId);
  }
}
