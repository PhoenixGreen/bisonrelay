import 'package:flutter/material.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';

// stroke_controls.dart is a stroke's controls, each built by one function
// that a line's and a path's panels both use, in the quick strip and in
// Look alike, so a control and its twin cannot part: the colour with its
// fade, the width, the cap, the mark on each end, the marks' size, and the
// dash. They write through StrokedElement.withStroke and so never ask which
// of the two they are on; every range is the model's (StrokeRange). A
// shape's outline is built from the same colour and width pieces
// (fadedColour, widthField).

/// StrokeEdit is a stroke being set in a panel: the element it is on and
/// the panel's write, begin and commit (see the README's "Changing the
/// element").
class StrokeEdit {
  final StrokedElement element;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  const StrokeEdit(this.element, this.write, this.begin, this.commit);

  StrokeSpec get stroke => element.stroke;

  /// live writes [next] as a drag or a typed number goes; [commit] ends it.
  void live(StrokeSpec next) {
    begin();
    write(element.withStroke(next));
  }

  /// now writes [next] as one step: a choice made in one press.
  void now(StrokeSpec next) {
    live(next);
    commit();
  }
}

/// fadedColour is a colour with the fade beside it in its picker, chosen in
/// one press: a stroke's, a shape's outline, a shape's fill.
Widget fadedColour({
  Key? key,
  required String label,
  required Color color,
  required GradientSpec? fade,
  required ValueChanged<Color> onColour,
  required ValueChanged<GradientSpec?> onFade,
}) =>
    CanvasColorButton(
      key: key,
      label: label,
      color: color,
      gradient: fade,
      onChanged: onColour,
      onGradientChanged: onFade,
    );

/// widthField is how thick a stroke or an outline is, from [min] to
/// StrokeRange.maxWidth: in the quick strip ([quick]) a stepper as wide as
/// its cell, elsewhere a number in its group.
Widget widthField({
  Key? key,
  required String label,
  required double value,
  required double min,
  required bool quick,
  required ValueChanged<double> onChanged,
  required VoidCallback onCommit,
}) =>
    _number(
        key: key,
        label: label,
        value: value,
        min: min,
        max: StrokeRange.maxWidth,
        decimals: 1,
        quick: quick,
        suffix: " px",
        width: 54,
        onChanged: onChanged,
        onCommit: onCommit);

/// _number is a number in the quick strip or in a group: the one place the
/// two forms differ, so that the range, the decimals and what is written
/// are said once for both.
Widget _number({
  Key? key,
  required String label,
  required double value,
  required double min,
  required double max,
  required int decimals,
  required bool quick,
  required double width,
  String suffix = "",
  required ValueChanged<double> onChanged,
  required VoidCallback onCommit,
}) =>
    quick
        ? CanvasStepper(
            key: key,
            label: label,
            value: value,
            min: min,
            max: max,
            decimals: decimals,
            step: 1,
            suffix: suffix,
            fill: true,
            onChanged: onChanged,
            onCommit: onCommit,
          )
        : CanvasNumberField(
            key: key,
            label: label,
            value: value,
            min: min,
            max: max,
            decimals: decimals,
            width: width,
            onChanged: onChanged,
            onCommit: onCommit,
          );

/// strokeColour is a stroke's colour, or the fade it runs through.
Widget strokeColour(StrokeEdit s, {Key? key}) => fadedColour(
      key: key,
      label: "Colour",
      color: s.stroke.color,
      fade: s.stroke.fade,
      onColour: (c) => s.now(s.stroke.copyWith(color: c)),
      onFade: (g) => s.now(g == null
          ? s.stroke.copyWith(flat: true)
          : s.stroke.copyWith(fade: g)),
    );

/// strokeWidth is how thick a stroke is.
Widget strokeWidth(StrokeEdit s, {Key? key, required bool quick}) => widthField(
      key: key,
      label: "Width",
      value: s.stroke.strokeWidth,
      min: StrokeRange.minWidth,
      quick: quick,
      onChanged: (v) => s.live(s.stroke.copyWith(strokeWidth: v)),
      onCommit: s.commit,
    );

/// strokeDash is how long each dash is; 0 is a solid stroke.
Widget strokeDash(StrokeEdit s, {Key? key, required bool quick}) => _number(
      key: key,
      label: "Dash",
      value: s.stroke.dash,
      min: 0,
      max: StrokeRange.maxDash,
      decimals: 1,
      quick: quick,
      width: 54,
      onChanged: (v) => s.live(s.stroke.copyWith(dash: v)),
      onCommit: s.commit,
    );

/// strokeEnd is what is drawn on the stroke's [start] or last end.
Widget strokeEnd(StrokeEdit s,
        {Key? key, required bool start, required bool quick}) =>
    CanvasDropdown<LineEnd>(
      key: key,
      label: start ? "Start" : "End",
      value: start ? s.stroke.startEnd : s.stroke.endEnd,
      width: quick ? 130 : 124,
      options: [for (var c in LineEnd.values) (c, c.label)],
      onChanged: (v) => s.now(start
          ? s.stroke.copyWith(startEnd: v)
          : s.stroke.copyWith(endEnd: v)),
    );

/// strokeEndControls are how a stroke finishes and what is drawn on its
/// ends: the cap, the mark at each end, how big they are against its width,
/// and a button that swaps the two marks. A stroke that draws no ends (a
/// closed path) is offered only its cap, which each dash still has.
List<Widget> strokeEndControls(StrokeEdit s) => [
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: s.stroke.cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: (v) => s.now(s.stroke.copyWith(cap: v)),
      ),
      if (s.element.drawsEnds) ...[
        strokeEnd(s, start: true, quick: false),
        strokeEnd(s, start: false, quick: false),
        CanvasNumberField(
          label: "End size",
          value: s.stroke.endSize,
          min: StrokeRange.minEndSize,
          max: StrokeRange.maxEndSize,
          decimals: 1,
          width: 58,
          onChanged: (v) => s.live(s.stroke.copyWith(endSize: v)),
          onCommit: s.commit,
        ),
        CanvasTextButton(
          key: const ValueKey("strokeSwapEnds"),
          icon: Icons.swap_horiz,
          label: "Swap ends",
          onPressed: s.stroke.startEnd == s.stroke.endEnd
              ? null
              : () => s.now(s.stroke.endsSwapped),
        ),
      ],
    ];
