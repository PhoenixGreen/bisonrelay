import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// line settings.dart is a line's settings.

List<Widget> lineSettings(CanvasController controller, LineElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(LineElement next) {
    begin();
    write(next);
    commit();
  }

  return [
    CanvasControlGroup(label: "Line", children: [
      CanvasColorButton(
        label: "Colour",
        color: e.color,
        onChanged: (c) {
          begin();
          write(e.copyWith(color: c));
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
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: e.cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(cap: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "Start",
        value: e.startEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(startEnd: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "End",
        value: e.endEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(endEnd: v)),
      ),
      CanvasNumberField(
        label: "End size",
        value: e.endSize,
        min: 0.2,
        max: 8,
        decimals: 1,
        width: 58,
        onChanged: (v) {
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
      valueDot(
          controller, e, KeyframeChannel.bow, "the line's curve", e.curvature),
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
  ];
}
