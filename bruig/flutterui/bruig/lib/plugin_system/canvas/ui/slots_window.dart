import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_columns.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// slots_window.dart is the slots beside the timeline's rows, one row of them
// at a time: every cell one size however tall the row, the row clipped to
// the slots' column and scrolled along with every other row (see
// CanvasController.slotsScroll).

/// SlotsWindow is one row's slots beside it, [cell] for each slot shown.
class SlotsWindow extends StatelessWidget {
  final CanvasController controller;
  final Widget Function(int i) cell;
  const SlotsWindow({required this.controller, required this.cell, super.key});

  @override
  Widget build(BuildContext context) => slotsScroller(
        controller,
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 3, 2, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < controller.slotsShown; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                SizedBox(
                    width: CanvasController.slotCellWidth,
                    height: CanvasController.slotCellHeight,
                    child: cell(i)),
              ],
            ],
          ),
        ),
      );
}

/// slotsScroller is [child] in the slots' column, laid out as wide as it
/// wants: clipped to the column, moved along by the slots' scroll, and
/// scrolling it with the wheel or the trackpad, sideways.
Widget slotsScroller(CanvasController c, Widget child) => Builder(
    builder: (context) => Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            var d = event.scrollDelta;
            var sideways = HardwareKeyboard.instance.isShiftPressed ||
                d.dx.abs() > d.dy.abs();
            if (!sideways) return;
            // Taken here, before the timeline's own: see CanvasTimeline.
            GestureBinding.instance.pointerSignalResolver.register(event, (e) {
              var d = (e as PointerScrollEvent).scrollDelta;
              c.scrollSlots(d.dx != 0 ? d.dx : d.dy,
                  shown: slotsWidthNow(context, c));
            });
          },
          onPointerPanZoomUpdate: (event) {
            var pan = event.panDelta;
            if (pan.dx.abs() > pan.dy.abs()) {
              c.scrollSlots(-pan.dx, shown: slotsWidthNow(context, c));
            }
          },
          child: ClipRect(
            // The row moved inside the box rather than the box moved: a slot
            // scrolled into view is still in the box's bounds to be pressed.
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: ValueListenableBuilder<double>(
                valueListenable: c.slotsScroll,
                builder: (context, offset, child) {
                  var most =
                      math.max(0.0, c.slotsContent - slotsWidthIn(context, c));
                  return Transform.translate(
                      offset: Offset(-math.min(offset, most), 0), child: child);
                },
                child: child,
              ),
            ),
          ),
        ));

/// SlotKeys is a slot taking the keyboard once clicked: Delete or
/// Backspace empties it (Ken: "with a slot selected a user should be able
/// to delete it"). [focus] is asked for by the slot's click.
class SlotKeys extends StatelessWidget {
  final FocusNode focus;
  final VoidCallback onDelete;
  final Widget child;
  const SlotKeys(
      {required this.focus,
      required this.onDelete,
      required this.child,
      super.key});

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: focus,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace)) {
            onDelete();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );
}

/// SlotFocus is a slot that takes the keyboard once clicked, holding its own
/// focus for a slot drawn by a stateless list: [builder] is given the focus
/// to ask for on a click.
class SlotFocus extends StatefulWidget {
  final VoidCallback onDelete;
  final Widget Function(FocusNode focus) builder;
  const SlotFocus({required this.onDelete, required this.builder, super.key});

  @override
  State<SlotFocus> createState() => _SlotFocusState();
}

class _SlotFocusState extends State<SlotFocus> {
  final _focus = FocusNode(debugLabel: "slot");

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlotKeys(
      focus: _focus, onDelete: widget.onDelete, child: widget.builder(_focus));
}
