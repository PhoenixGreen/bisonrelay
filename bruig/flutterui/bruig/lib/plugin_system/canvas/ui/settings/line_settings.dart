import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stroke_controls.dart';

// line_settings.dart is a line's panel (see element_panel.dart): quick
// strip, Look (stroke, ends, dashes) and Layout (length and direction). Its
// stroke's controls are stroke_controls.dart's, which a path's panel uses
// too.

Widget linePanel(
    BuildContext context,
    CanvasController controller,
    LineElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var s = StrokeEdit(e, write, begin, commit);
  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        panelRow([
          cell(strokeColour(s, key: const ValueKey("quickLineColour")),
              width: 104),
          cell(
              strokeWidth(s,
                  key: const ValueKey("quickLineWidth"), quick: true),
              width: 132),
        ]),
        const SizedBox(height: 8),
        panelRow([
          cell(
              strokeEnd(s,
                  key: const ValueKey("quickLineEnd"),
                  start: false,
                  quick: true),
              flex: 3,
              min: 110),
          cell(strokeDash(s, key: const ValueKey("quickLineDash"), quick: true),
              width: 132),
        ]),
      ]),
      bits: [
        _strokeBit(controller, e, s),
        _lengthBit(e, s),
        _endsBit(e, s),
        // How it comes in, loops and goes is the Chain's Motion view.
      ]);
}

/// _strokeBit is the line's colour, width and bow, in Look.
PanelBit _strokeBit(CanvasController controller, LineElement e, StrokeEdit s) =>
    PanelBit(PanelSection.look,
        summary: "${shortNumber(e.strokeWidth)} wide",
        children: [
          CanvasControlGroup(
            label: "Stroke",
            help: "Its colour -- or a fade along it -- how thick it is, and "
                "how far it bows. The curve can be keyframed: the diamond "
                "beside it says whether this frame holds one.",
            rule: false,
            children: [
              strokeColour(s),
              strokeWidth(s, quick: false),
              const CanvasLineBreak(),
              CanvasNumberField(
                label: "Curve",
                decimals: 2,
                width: 62,
                value: controller.valueAt(e, KeyframeChannel.bow, e.curvature),
                min: -1,
                max: 1,
                onChanged: (v) {
                  s.begin();
                  if (controller.hasValueKey(e, KeyframeChannel.bow)) {
                    controller.setValueKey(e, KeyframeChannel.bow, v);
                    return;
                  }
                  s.write(e.copyWith(curvature: v));
                },
                onCommit: s.commit,
              ),
              valueDot(controller, e, KeyframeChannel.bow, "the line's curve",
                  e.curvature),
            ],
          ),
        ]);

/// _lengthBit is how long the line is and which way it points, as it is
/// drawn, in Layout.
PanelBit _lengthBit(LineElement e, StrokeEdit s) {
  void now(LineElement next) {
    s.begin();
    s.write(next);
    s.commit();
  }

  return PanelBit(PanelSection.layout,
      summary: "${e.length.round()} long"
          "${e.angle.round() != 0 ? " · ${e.angle.round()}°" : ""}",
      children: [
        // A line is its two ends, so it is sized and turned by its length
        // and direction as drawn, not by a box (see LineElement.withEnds).
        CanvasControlGroup(
          label: "Length and direction",
          help: "A line is sized and turned by its two ends, as they are "
              "drawn: how long it is from its start, and which way it "
              "points, in degrees round from pointing right. Its start "
              "stays where it is. The buttons lay it level or stand it "
              "upright.",
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
                s.begin();
                s.write(e.withLength(v));
              },
              onCommit: s.commit,
            ),
            CanvasNumberField(
              key: const ValueKey("lineAngle"),
              label: "Direction",
              value: e.angle,
              min: -180,
              max: 180,
              decimals: 1,
              width: 54,
              onChanged: (v) {
                s.begin();
                s.write(e.withAngle(v));
              },
              onCommit: s.commit,
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
      ]);
}

/// _endsBit is what is drawn on the line's ends, which way it slopes, and
/// its dashes, in Look.
PanelBit _endsBit(LineElement e, StrokeEdit s) => PanelBit(PanelSection.look,
        summary: [
          if (e.startEnd != LineEnd.none) e.startEnd.label,
          if (e.endEnd != LineEnd.none) e.endEnd.label,
          if (e.dash > 0) "dashed" else "solid",
        ].join(" · "),
        children: [
          CanvasControlGroup(
            label: "Ends",
            help: "How the stroke is finished at each end -- square, round, "
                "an arrowhead -- and how big the ends are against the "
                "line's width. Swap ends puts each end's mark on the other. "
                "Sloping it the other way runs it from bottom left to top "
                "right across its box, its start still on the left.",
            rule: false,
            children: [
              ...strokeEndControls(s),
              CanvasToggle(
                key: const ValueKey("lineFlipped"),
                label: "Slope the other way",
                value: e.flipped,
                onChanged: (v) {
                  s.begin();
                  s.write(e.copyWith(flipped: v));
                  s.commit();
                },
              ),
            ],
          ),
          CanvasControlGroup(
            label: "Dashes",
            help: "How long each dash is. 0 is a solid line.",
            rule: false,
            children: [
              strokeDash(s, key: const ValueKey("lineDash"), quick: false),
            ],
          ),
        ]);
