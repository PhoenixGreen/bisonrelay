import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
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

  var ends = [
    if (e.startEnd != LineEnd.none) e.startEnd.label,
    if (e.endEnd != LineEnd.none) e.endEnd.label,
  ];
  return [
    section(e, "line",
        icon: Icons.timeline,
        title: "Line",
        summary: "${shortNumber(e.strokeWidth)} wide · ${e.length.round()} long"
            "${e.angle.round() != 0 ? " · ${e.angle.round()}°" : ""}",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "Stroke",
            help: "Its colour -- or a fade along it -- how thick it is, and "
                "how far it bows. The curve can be keyframed: the diamond "
                "beside it says whether this frame holds one.",
            rule: false,
            children: [
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
                  write(
                      g == null ? e.copyWith(flat: true) : e.copyWith(fade: g));
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
              const CanvasLineBreak(),
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
          ),
          // A line is its two ends, so it is sized and turned by its length
          // and angle rather than by a box -- see LineElement.withEnds.
          CanvasControlGroup(
            label: "Length and angle",
            help: "A line is sized and turned by its two ends: how long it "
                "is from its start, and which way it points. The buttons "
                "lay it level or stand it upright.",
            rule: false,
            children: [
              CanvasNumberField(
                key: const ValueKey("lineLength"),
                label: "Length",
                value: e.length,
                min: 1,
                max: 20000,
                decimals: 0,
                width: 58,
                onChanged: (v) {
                  begin();
                  var r = e.angle * math.pi / 180;
                  write(e.withEnds(
                      e.start, e.start + Offset(math.cos(r), math.sin(r)) * v));
                },
                onCommit: commit,
              ),
              CanvasNumberField(
                key: const ValueKey("lineAngle"),
                label: "Angle",
                value: e.angle,
                min: -180,
                max: 180,
                decimals: 1,
                width: 54,
                onChanged: (v) {
                  begin();
                  var r = v * math.pi / 180;
                  write(e.withEnds(e.start,
                      e.start + Offset(math.cos(r), math.sin(r)) * e.length));
                },
                onCommit: commit,
              ),
              const CanvasLineBreak(),
              CanvasTextButton(
                key: const ValueKey("lineLevel"),
                icon: Icons.horizontal_rule,
                label: "Level",
                onPressed: () => now(e.level),
              ),
              CanvasTextButton(
                key: const ValueKey("linePlumb"),
                icon: Icons.height,
                label: "Upright",
                onPressed: () => now(e.plumb),
              ),
            ],
          ),
        ]),
    section(e, "ends",
        icon: Icons.arrow_right_alt,
        title: "Ends and dashes",
        summary: [
          ...ends,
          if (e.dash > 0) "dashed" else "solid",
        ].join(" · "),
        children: [
          CanvasControlGroup(
            label: "Ends",
            help: "How the stroke is finished at each end -- square, round, "
                "an arrowhead -- and how big the ends are against the "
                "line's width. Flipping swaps which end is the start.",
            rule: false,
            children: [
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
              CanvasToggle(
                key: const ValueKey("lineFlipped"),
                label: "Run the other way",
                value: e.flipped,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(flipped: v));
                  commit();
                },
              ),
            ],
          ),
          CanvasControlGroup(
            label: "Dashes",
            help: "How long each dash is. 0 is a solid line.",
            rule: false,
            children: [
              CanvasNumberField(
                key: const ValueKey("lineDash"),
                label: "Dash",
                value: e.dash,
                min: 0,
                max: 400,
                width: 50,
                onChanged: (v) => write(e.copyWith(dash: v)),
                onCommit: commit,
              ),
            ],
          ),
        ]),
    animationPanelSection(controller, e, e.animation,
        (a) => write(e.copyWith(animation: a)), begin, commit),
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
