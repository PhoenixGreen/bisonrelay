import 'package:flutter/material.dart';

// caret_keys.dart works round a fault in Flutter's text fields: Up and Down
// in a field whose text is centred or right-aligned fail an assertion
// ("isValid", in VerticalCaretMovementRun) and leave the caret where it was.
//
// Flutter moves the caret a line at a time with a "run" that remembers the
// field's line metrics, and treats a different list of them as the layout
// having changed. Text shifted to its alignment -- a single line always, and
// several lines wherever the width is not exact in the text engine's own
// precision (561.6 px, say) -- has its metrics made afresh on every call, so
// every run is out of date before its first step.
//
// caretKeyActions overrides the two Up and Down intents (EditableText lets
// an ancestor's Actions override them) with an action that hands them back
// to Flutter wherever its run is sound, which is every left-aligned field,
// and otherwise moves the caret itself: in a single line to its start or end,
// as the platform does, and in several lines to the point a line above or
// below the caret.

/// caretKeyActions is put over the app (MaterialApp.actions, with
/// WidgetsApp.defaultActions), so every text field in it, dialogs and menus
/// included, has an Up and Down that work.
/// One action for both, typed for their common intent as Flutter's own is:
/// the action it overrides becomes its callingAction.
final Map<Type, Action<Intent>> caretKeyActions = {
  ExtendSelectionVerticallyToAdjacentLineIntent: SafeVerticalCaretAction(),
  ExtendSelectionVerticallyToAdjacentPageIntent: SafeVerticalCaretAction(),
};

/// SafeVerticalCaretAction is Up or Down in a text field: Flutter's own,
/// where Flutter can do it, else the caret moved here.
class SafeVerticalCaretAction
    extends ContextAction<DirectionalCaretMovementIntent> {
  @override
  bool isEnabled(DirectionalCaretMovementIntent intent,
      [BuildContext? context]) {
    var calling = callingAction;
    if (calling == null) return true;
    return calling is ContextAction<DirectionalCaretMovementIntent>
        ? calling.isEnabled(intent, context)
        : calling.isEnabled(intent);
  }

  /// _flutters is Flutter's own action for [intent], as overridden.
  Object? _flutters(
      DirectionalCaretMovementIntent intent, BuildContext? context) {
    var calling = callingAction;
    if (calling == null) return null;
    return calling is ContextAction<DirectionalCaretMovementIntent>
        ? calling.invoke(intent, context)
        : calling.invoke(intent);
  }

  @override
  Object? invoke(DirectionalCaretMovementIntent intent,
      [BuildContext? context]) {
    var state = _editing(context) ?? _editing(primaryFocus?.context);
    if (state == null) return _flutters(intent, context);
    var value = state.textEditingValue;
    var selection = value.selection;
    if (!selection.isValid) return _flutters(intent, context);
    var editable = state.renderEditable;
    // Flutter's run, where it is sound: every left-aligned field.
    if (editable.startVerticalCaretMovement(selection.extent).isValid) {
      return _flutters(intent, context);
    }
    var forward = intent.forward;
    var start = const TextPosition(offset: 0);
    var end = TextPosition(offset: value.text.length);
    TextPosition to;
    if (editable.maxLines == 1) {
      to = forward ? end : start;
    } else {
      var caret = editable.getLocalRectForCaret(selection.extent);
      var step = intent is ExtendSelectionVerticallyToAdjacentPageIntent
          ? editable.size.height
          : editable.preferredLineHeight;
      var at = caret.center + Offset(0, forward ? step : -step);
      to = editable.getPositionForPoint(editable.localToGlobal(at));
      // Already on the first or last line: on to the start or the end, as
      // Flutter's own does.
      if (to.offset == selection.extent.offset) to = forward ? end : start;
    }
    var next = intent.collapseSelection
        ? TextSelection.fromPosition(to)
        : selection.extendTo(to);
    state.userUpdateTextEditingValue(
        value.copyWith(selection: next), SelectionChangedCause.keyboard);
    state.bringIntoView(next.extent);
    return null;
  }

  /// _editing is the field [context] is in: its own state, or its nearest.
  static EditableTextState? _editing(BuildContext? context) {
    if (context == null) return null;
    if (context is StatefulElement && context.state is EditableTextState) {
      return context.state as EditableTextState;
    }
    return context.findAncestorStateOfType<EditableTextState>();
  }
}
