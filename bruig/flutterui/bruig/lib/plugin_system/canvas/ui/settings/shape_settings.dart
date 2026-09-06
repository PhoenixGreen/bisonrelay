import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// shape settings.dart is a shape's settings.

List<Widget> shapeSettings(ShapeElement e, SettingsWrite write,
        VoidCallback begin, VoidCallback commit) =>
    [
      // No caption: the panel header says "Shape settings" already, and a
      // group called Shape directly under it was the word twice.
      CanvasControlGroup(label: "Shape", hideCaption: true, children: [
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
          onChanged: (c) {
            begin();
            write(e.copyWith(fill: c));
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
          onChanged: (c) {
            begin();
            write(e.copyWith(strokeColor: c));
            commit();
          },
        ),
        CanvasNumberField(
          label: "Radius",
          value: e.cornerRadius,
          min: 0,
          max: 400,
          width: 54,
          onChanged: (v) => write(e.copyWith(cornerRadius: v)),
          onCommit: commit,
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
      ]),
      CanvasControlGroup(label: "Label", children: [
        // The empty field says what it is for, rather than a caption above it
        // repeating the group's own name in other words.
        CanvasTextField(
          label: "",
          hint: "Type text on the shape",
          value: e.text,
          width: 180,
          onChanged: (v) => write(e.copyWith(text: v)),
          onCommit: commit,
        ),
      ]),
      // Only when it is a bubble: every one of these is meaningless on a star.
      if (e.shape == ShapeKind.speechBubble)
        CanvasControlGroup(label: "Bubble", children: [
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
          if (e.bubble.tail != BubbleTail.none) ...[
            // All the way round, rather than the bottom-left corner it used
            // to be nailed to.
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
            label: "Label type"),
    ];
