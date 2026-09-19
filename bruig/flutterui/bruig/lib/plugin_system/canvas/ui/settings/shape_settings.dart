import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// shape settings.dart is a shape's settings.

List<Widget> shapeSettings(
        BuildContext context,
        CanvasController controller,
        ShapeElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    [
      // No caption: the panel header says "Shape settings" already, and a
      // group called Shape directly under it was the word twice.
      //
      // Which shape, what colour it is filled and stroked, and -- for the
      // shapes that have them -- how many points it has. The corners are
      // behind the button: five fields nobody sets on most shapes.
      CanvasMoreGroup(
          label: "Shape",
          hideCaption: true,
          remember: "shapeMore",
          // What the shape is and what is written on it are one question, so
          // no line between them and none after the label either.
          rule: false,
          tooltip: "How round its corners are",
          row: [
            CanvasDropdown<ShapeKind>(
              label: "Shape",
              value: e.shape,
              width: 128,
              options: [for (var s in ShapeKind.values) (s, s.label)],
              onChanged: (v) {
                begin();
                write(e.copyWith(shape: v));
                commit();
              },
            ),
            CanvasColorButton(
              label: "Fill",
              color: e.fill,
              gradient: e.fillFade,
              onChanged: (c) {
                begin();
                write(e.copyWith(fill: c));
                commit();
              },
              onGradientChanged: (g) {
                begin();
                write(g == null
                    ? e.copyWith(flatFill: true)
                    : e.copyWith(fillFade: g));
                commit();
              },
            ),
            CanvasNumberField(
              label: "Stroke",
              value: e.strokeWidth,
              min: 0,
              max: 200,
              decimals: 1,
              width: 54,
              onChanged: (v) => write(e.copyWith(strokeWidth: v)),
              onCommit: commit,
            ),
            CanvasColorButton(
              label: "Colour",
              color: e.strokeColor,
              gradient: e.strokeFade,
              onChanged: (c) {
                begin();
                write(e.copyWith(strokeColor: c));
                commit();
              },
              onGradientChanged: (g) {
                begin();
                write(g == null
                    ? e.copyWith(flatStroke: true)
                    : e.copyWith(strokeFade: g));
                commit();
              },
            ),
            if (e.shape.hasPoints) ...[
              CanvasNumberField(
                label: "Points",
                value: e.points.toDouble(),
                min: 3,
                max: 24,
                width: 50,
                onChanged: (v) => write(e.copyWith(points: v.round())),
                onCommit: commit,
              ),
              CanvasNumberField(
                label: "Depth",
                decimals: 2,
                width: 62,
                value: e.innerRatio,
                min: 0.05,
                max: 0.95,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(innerRatio: v));
                },
                onCommit: commit,
              ),
            ],
          ],
          more: [
            // The same four the frame round a picture has, and the same controls.
            // Only for the shapes that have corners: a circle has none, and a
            // field that does nothing is worse than no field.
            if (e.shape.hasCorners)
              ...cornerFields(
                  e.corners,
                  (c) => write(e.copyWith(
                      cornerRadius: c.all,
                      radTL: c.tl,
                      radTR: c.tr,
                      radBR: c.br,
                      radBL: c.bl,
                      clearCorners: true)),
                  commit,
                  prefix: "shape"),
          ]),
      CanvasMoreGroup(
        label: "Label",
        remember: "shapeLabelMore",
        rule: false,
        tooltip: "How far the label is kept from the edge",
        row: [
          // The empty field says what it is for, rather than a caption above
          // it repeating the group's own name in other words.
          CanvasTextField(
            label: "",
            hint: "Type text on the shape",
            value: e.text,
            width: 180,
            onChanged: (v) => write(e.copyWith(text: v)),
            onCommit: commit,
          ),
        ],
        more: [
          ...roomFields(
              e.pad,
              (r) => write(e.copyWith(
                  padding: r.all,
                  padL: r.l,
                  padT: r.t,
                  padR: r.r,
                  padB: r.b,
                  clearRoom: true)),
              commit,
              prefix: "shape"),
          CanvasHint("How far the label is kept from the shape's edge. At 0 "
              "the shape decides for itself — ${e.shape.label.toLowerCase()} "
              "needs more room than a rectangle does, and those are the "
              "numbers nobody should have to set. Any of them set replaces "
              "that."),
        ],
      ),
      // Only when it is a bubble: every one of these is meaningless on a star.
      if (e.shape == ShapeKind.speechBubble)
        CanvasMoreGroup(
            label: "Bubble",
            remember: "shapeBubbleMore",
            rule: false,
            tooltip: "Where the tail points, and how long it is",
            row: [
              CanvasDropdown<BubbleBody>(
                label: "Body",
                value: e.bubble.body,
                width: 104,
                options: [for (var b in BubbleBody.values) (b, b.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(bubble: e.bubble.copyWith(body: v)));
                  commit();
                },
              ),
              CanvasDropdown<BubbleTail>(
                label: "Tail",
                value: e.bubble.tail,
                width: 104,
                options: [for (var t in BubbleTail.values) (t, t.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(bubble: e.bubble.copyWith(tail: v)));
                  commit();
                },
              ),
            ],
            more: [
              // All the way round, rather than the bottom-left corner it used
              // to be nailed to.
              if (e.bubble.tail != BubbleTail.none) ...[
                CanvasNumberField(
                  key: const ValueKey("bubbleTailAngle"),
                  label: "Points",
                  value: e.bubble.tailAngle,
                  min: -360,
                  max: 360,
                  width: 58,
                  suffix: "°",
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(bubble: e.bubble.copyWith(tailAngle: v)));
                  },
                  onCommit: commit,
                ),
                CanvasNumberField(
                  label: "Length",
                  decimals: 2,
                  width: 62,
                  value: e.bubble.tailLength,
                  min: 0.05,
                  max: 1.2,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(bubble: e.bubble.copyWith(tailLength: v)));
                  },
                  onCommit: commit,
                ),
                CanvasNumberField(
                  label: "Width",
                  decimals: 2,
                  width: 62,
                  value: e.bubble.tailWidth,
                  min: 0.05,
                  max: 1,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(bubble: e.bubble.copyWith(tailWidth: v)));
                  },
                  onCommit: commit,
                ),
                if (e.bubble.tail == BubbleTail.curved)
                  CanvasNumberField(
                    label: "Curl",
                    decimals: 2,
                    width: 62,
                    value: e.bubble.curl,
                    min: -1.5,
                    max: 1.5,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(bubble: e.bubble.copyWith(curl: v)));
                    },
                    onCommit: commit,
                  ),
              ],
            ]),
      // The label's type, and only when there is a label to set.
      if (e.text.isNotEmpty)
        ...typeGroups(e.textSpec, (spec) => write(e.copyWith(textSpec: spec)),
            begin, commit,
            label: "Label type", remember: "shapeLabel", rule: false),
      // How it arrives, in a section of its own like a headline's: a handful
      // of choices made once and then left alone.
      boxed(
          context,
          elementAnimationSection(controller, e, e.animation,
              (a) => write(e.copyWith(animation: a)), begin, commit)),
    ];
