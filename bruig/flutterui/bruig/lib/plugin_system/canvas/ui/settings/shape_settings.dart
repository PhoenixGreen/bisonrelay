import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// shape settings.dart is a shape's settings.

List<Widget> shapeSettings(
    BuildContext context,
    CanvasController controller,
    ShapeElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  // Read while building: a tile's picture is drawn while painting, and the
  // theme cannot be asked for then.
  var ink = ThemeNotifier.of(context).colors.onSurfaceVariant;
  var painted = switch (e.painted.kind) {
    TextFillKind.color => "colour",
    var k => k.label.toLowerCase(),
  };
  return [
    section(e, "shape",
        icon: Icons.category_outlined,
        title: "Shape",
        summary: [
          e.shape.label,
          if (e.shape.hasPoints) "${e.points} points",
          if (e.shape.hasCorners && e.corners.all > 0) "rounded",
        ].join(" · "),
        initiallyOpen: true,
        children: [
          // Shown rather than named: each shape is a tile drawn as itself.
          CanvasTiles<ShapeKind>(
            key: const ValueKey("shapeKind"),
            label: "Which shape",
            foldAs: "shape.tiles.kind",
            help: "Which shape it is. Each tile is the shape itself.",
            columns: 4,
            previewHeight: 34,
            tiles: [
              for (var k in ShapeKind.values)
                CanvasTile(k, k.label,
                    drawnFrom: (k, ink),
                    paint: (canvas, size) =>
                        _ShapeTilePainter(k, ink).paint(canvas, size)),
            ],
            selected: (k) => e.shape == k,
            keyOf: (k) => "shapeKind-${k.name}",
            onPick: (v) {
              begin();
              write(e.copyWith(shape: v));
              commit();
            },
          ),
          if (e.shape.hasPoints)
            CanvasControlGroup(
              label: "Points",
              help: "How many points the star has, and how deep the cuts "
                  "between them go.",
              rule: false,
              children: [
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
            ),
          if (e.shape.hasCorners)
            CanvasControlGroup(
              label: "Corners",
              help: "How round its corners are: one number for all four, or "
                  "split with the link to set each on its own.",
              rule: false,
              children: [
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
              ],
            ),
        ]),
    section(e, "fill",
        icon: Icons.format_color_fill,
        title: "Fill and outline",
        summary: "Filled with $painted · "
            "${e.strokeWidth > 0 ? "outline ${shortNumber(e.strokeWidth)}" : "no outline"}",
        children: [
          CanvasControlGroup(
            label: "Fill",
            help: "What the shape is painted with: a colour, a picture or a "
                "pattern, cut to its own outline.",
            rule: false,
            children: [
              CanvasDropdown<TextFillKind>(
                key: const ValueKey("shapeFillKind"),
                label: "Painted with",
                value: e.painted.kind,
                width: 118,
                options: [for (var k in TextFillKind.values) (k, k.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(painted: e.painted.copyWith(kind: v)));
                  commit();
                },
              ),
              if (e.painted.kind != TextFillKind.color)
                ...fillBits(context, e.painted,
                    (f) => write(e.copyWith(painted: f)), begin, commit,
                    keyPrefix: "shape"),
              if (e.painted.kind == TextFillKind.color)
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
            ],
          ),
          CanvasControlGroup(
            label: "Outline",
            help: "The line round the shape: how thick, and its colour. A "
                "colour chosen for a shape with no outline gives it one.",
            rule: false,
            children: [
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
                  write(e.copyWith(
                      strokeColor: c,
                      strokeWidth: e.strokeWidth > 0 ? null : strokeToSee(e)));
                  commit();
                },
                onGradientChanged: (g) {
                  begin();
                  write(g == null
                      ? e.copyWith(flatStroke: true)
                      : e.copyWith(
                          strokeFade: g,
                          strokeWidth:
                              e.strokeWidth > 0 ? null : strokeToSee(e)));
                  commit();
                },
              ),
            ],
          ),
        ]),
    section(e, "label",
        icon: Icons.title,
        title: "Label",
        summary: e.text.isEmpty ? "No words on it" : "\"${e.text}\"",
        children: [
          CanvasControlGroup(
            label: "Words",
            help: "Words written on the shape, and how far they are kept "
                "from its edge. At 0 the shape decides for itself -- "
                "${e.shape.label.toLowerCase()} needs more room than a "
                "rectangle does. Any number set replaces that.",
            rule: false,
            children: [
              CanvasTextField(
                label: "",
                hint: "Type text on the shape",
                value: e.text,
                width: 180,
                onChanged: (v) => write(e.copyWith(text: v)),
                onCommit: commit,
              ),
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
            ],
          ),
          if (e.text.isNotEmpty)
            ...typeGroups(e.textSpec,
                (spec) => write(e.copyWith(textSpec: spec)), begin, commit,
                label: "Label type", remember: "shapeLabel", rule: false),
        ]),
    if (e.shape == ShapeKind.speechBubble)
      section(e, "bubble",
          icon: Icons.chat_bubble_outline,
          title: "Bubble",
          summary: "${e.bubble.body.label} · ${e.bubble.tail.label} tail",
          children: [
            CanvasControlGroup(
              label: "Bubble",
              help: "The bubble's body, and its tail: which way it points, "
                  "how long and wide it is, and -- curved -- how it curls.",
              rule: false,
              children: [
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
                      write(
                          e.copyWith(bubble: e.bubble.copyWith(tailAngle: v)));
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
                      write(
                          e.copyWith(bubble: e.bubble.copyWith(tailLength: v)));
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
                      write(
                          e.copyWith(bubble: e.bubble.copyWith(tailWidth: v)));
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
              ],
            ),
          ]),
    animationPanelSection(controller, e, e.animation,
        (a) => write(e.copyWith(animation: a)), begin, commit),
  ];
}

class _ShapeTilePainter extends CustomPainter {
  final ShapeKind kind;
  final Color colour;
  _ShapeTilePainter(this.kind, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var side = math.min(size.width, size.height) * 0.72;
    var box = Rect.fromCenter(
        center: size.center(Offset.zero), width: side * 1.3, height: side);
    var path = shapePath(kind, box, cornerRadius: side * 0.12);
    canvas.drawPath(path, Paint()..color = colour.withValues(alpha: 0.35));
    canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_ShapeTilePainter old) =>
      old.kind != kind || old.colour != colour;
}
