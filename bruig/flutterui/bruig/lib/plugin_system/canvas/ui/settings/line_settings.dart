import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// line settings.dart is a line's settings.

List<Widget> lineSettings(
    BuildContext context,
    CanvasController controller,
    LineElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(LineElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    // No caption: the panel header says "Line settings" already, and a
    // group called Line directly under it was the word twice.
    //
    // What the line is -- its colour, its weight, its curve -- on the line,
    // and how it is finished off behind the button. The curve is out here
    // because it can be keyframed, and the diamond beside it is the only
    // thing that says so.
    CanvasMoreGroup(
        label: "Line",
        hideCaption: true,
        remember: "lineMore",
        // Nothing between the line's own settings and the section that says
        // how it arrives: the section has a border of its own to say where it
        // starts.
        rule: false,
        tooltip: "How the line ends, and whether it is dashed",
        row: [
          CanvasColorButton(
            label: "Colour",
            color: e.color,
            gradient: e.fade,
            onChanged: (c) {
              begin();
              write(e.copyWith(color: c));
              commit();
            },
            onGradientChanged: (g) {
              begin();
              write(g == null ? e.copyWith(flat: true) : e.copyWith(fade: g));
              commit();
            },
          ),
          CanvasNumberField(
            label: "Width",
            value: e.strokeWidth,
            min: 0.2,
            max: 200,
            decimals: 1,
            width: 54,
            onChanged: (v) => write(e.copyWith(strokeWidth: v)),
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Curve",
            decimals: 2,
            width: 62,
            value: controller.valueAt(e, KeyframeChannel.bow, e.curvature),
            min: -1,
            max: 1,
            onChanged: (v) {
              begin();
              if (controller.hasValueKey(e, KeyframeChannel.bow)) {
                controller.setValueKey(e, KeyframeChannel.bow, v);
                return;
              }
              write(e.copyWith(curvature: v));
            },
            onCommit: commit,
          ),
          valueDot(controller, e, KeyframeChannel.bow, "the line's curve",
              e.curvature),
        ],
        more: [
          ...strokeEndControls(
            cap: e.cap,
            startEnd: e.startEnd,
            endEnd: e.endEnd,
            endSize: e.endSize,
            onCap: (v) => now(e.copyWith(cap: v)),
            onStart: (v) => now(e.copyWith(startEnd: v)),
            onEnd: (v) => now(e.copyWith(endEnd: v)),
            onEndSize: (v) {
              begin();
              write(e.copyWith(endSize: v));
            },
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Dash",
            value: e.dash,
            min: 0,
            max: 400,
            width: 50,
            onChanged: (v) => write(e.copyWith(dash: v)),
            onCommit: commit,
          ),
          CanvasIconButton(
            icon: Icons.swap_vert,
            tooltip: "Flip which way the line runs",
            active: e.flipped,
            onPressed: () {
              begin();
              write(e.copyWith(flipped: !e.flipped));
              commit();
            },
          ),
        ]),
    // How it arrives, in a section of its own like a headline's.
    boxed(
        context,
        elementAnimationSection(controller, e, e.animation,
            (a) => write(e.copyWith(animation: a)), begin, commit)),
  ];
}

/// strokeEndControls is how a stroke starts, how it ends, and how big the
/// ends are.
///
/// Shared by the line and the path, which are the same four controls with a
/// different element behind them: an arrowhead that means one thing on a line
/// and another on a route is the sort of difference nobody asks for and
/// everybody notices.
List<Widget> strokeEndControls({
  required LineStrokeCap cap,
  required LineEnd startEnd,
  required LineEnd endEnd,
  required double endSize,
  required ValueChanged<LineStrokeCap> onCap,
  required ValueChanged<LineEnd> onStart,
  required ValueChanged<LineEnd> onEnd,
  required ValueChanged<double> onEndSize,
  required VoidCallback onCommit,
}) =>
    [
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: onCap,
      ),
      CanvasDropdown<LineEnd>(
        label: "Start",
        value: startEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: onStart,
      ),
      CanvasDropdown<LineEnd>(
        label: "End",
        value: endEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: onEnd,
      ),
      CanvasNumberField(
        label: "End size",
        value: endSize,
        min: 0.2,
        max: 8,
        decimals: 1,
        width: 58,
        onChanged: onEndSize,
        onCommit: onCommit,
      ),
    ];
