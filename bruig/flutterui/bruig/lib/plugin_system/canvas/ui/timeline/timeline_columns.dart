import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/widgets.dart';

// timeline_columns.dart is how wide the columns left of a timeline's frames
// are, for the rows drawn inside it: the channels' strips, then the slots.
// Each timeline on screen says for itself (see CanvasTimeline) -- the one
// with its slots beside its rows, and one showing the slots on their own --
// so the two can be on screen together, each with its own widths.

/// TimelineColumns is the widths a timeline gives the rows under it.
class TimelineColumns extends InheritedWidget {
  /// slotsWidth is the slots' column, nought with none.
  final double slotsWidth;

  /// headerWidth is the channels' strips' column.
  final double headerWidth;

  /// lanes is whether the rows draw their frames: not for the slots shown
  /// alone.
  final bool lanes;

  const TimelineColumns({
    required this.slotsWidth,
    required this.headerWidth,
    this.lanes = true,
    required super.child,
    super.key,
  });

  /// leftWidth is everything left of the frames, where the time starts.
  double get leftWidth => headerWidth + slotsWidth;

  @override
  bool updateShouldNotify(TimelineColumns old) =>
      old.slotsWidth != slotsWidth ||
      old.headerWidth != headerWidth ||
      old.lanes != lanes;
}

/// slotsWidthIn is the slots' column for rows built under [context]: the
/// timeline's they are in, or, outside one, the controller's own.
double slotsWidthIn(BuildContext context, CanvasController controller) =>
    context.dependOnInheritedWidgetOfExactType<TimelineColumns>()?.slotsWidth ??
    controller.slotsWidth;

/// leftWidthIn is everything left of the frames for rows built under
/// [context]: see slotsWidthIn.
double leftWidthIn(BuildContext context, CanvasController controller) =>
    controller.headerWidth + slotsWidthIn(context, controller);

/// leftWidthNow is leftWidthIn for a gesture or a measurement, outside a
/// build: read without depending on it.
double leftWidthNow(BuildContext context, CanvasController controller) =>
    controller.headerWidth +
    (context.getInheritedWidgetOfExactType<TimelineColumns>()?.slotsWidth ??
        controller.slotsWidth);

/// slotsWidthNow is slotsWidthIn outside a build: see leftWidthNow.
double slotsWidthNow(BuildContext context, CanvasController controller) =>
    context.getInheritedWidgetOfExactType<TimelineColumns>()?.slotsWidth ??
    controller.slotsWidth;

/// lanesIn is whether rows built under [context] draw their frames.
bool lanesIn(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<TimelineColumns>()?.lanes ??
    true;
