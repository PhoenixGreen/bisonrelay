import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/type_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/fill_controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stroke_controls.dart';

// shape_settings.dart is a shape's panel (see element_panel.dart): quick
// strip, Content (which shape, its points or corners, its words, a bubble's
// tail) and Look (fill and outline). A control in the quick strip and its
// twin in a section are built by one function (_fillColour, _outline...),
// so the two cannot part.

/// _Shape is a shape in its panel and how to write it: what each piece of
/// the panel is handed.
class _Shape {
  final ShapeElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  const _Shape(this.e, this.write, this.begin, this.commit);

  /// now writes [next] as one step: a choice made in one press.
  void now(ShapeElement next) {
    begin();
    write(next);
    commit();
  }

  /// live writes [next] as a drag or a typed number goes; [commit] ends it.
  void live(ShapeElement next) {
    begin();
    write(next);
  }
}

/// shapePanel is a shape's settings, laid out by elementPanel.
Widget shapePanel(
    BuildContext context,
    CanvasController controller,
    ShapeElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var s = _Shape(e, write, begin, commit);
  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        panelRow([
          cell(
              CanvasDropdown<ShapeKind>(
                key: const ValueKey("quickShape"),
                label: "Shape",
                value: e.shape,
                options: [for (var k in ShapeKind.values) (k, k.label)],
                onChanged: (v) => s.now(e.withKind(v)),
              ),
              flex: 3,
              min: 110),
          if (e.painted.kind == TextFillKind.color)
            cell(_fillColour(s, key: const ValueKey("quickFill")), width: 104),
        ]),
        const SizedBox(height: 8),
        panelRow([
          cell(
              _outlineWidth(s,
                  key: const ValueKey("quickStroke"),
                  label: "Outline",
                  quick: true),
              width: 132),
          cell(
              _outlineColour(s,
                  key: const ValueKey("quickStrokeColour"),
                  label: "Outline colour"),
              width: 104),
        ]),
      ]),
      bits: [
        _kindBit(context, s),
        _lookBit(context, s),
        _wordsBit(s),
        if (e.shape == ShapeKind.speechBubble) _bubbleBit(s),
        // How it comes in, loops and goes is the Chain's Motion view.
      ]);
}

/// _fillColour is the shape's fill colour, or the fade it runs through.
Widget _fillColour(_Shape s, {Key? key}) => fadedColour(
      key: key,
      label: "Fill",
      color: s.e.fill,
      fade: s.e.fillFade,
      onColour: (c) => s.now(s.e.copyWith(fill: c)),
      onFade: (g) => s.now(
          g == null ? s.e.copyWith(flatFill: true) : s.e.copyWith(fillFade: g)),
    );

/// _outlineColour is the outline's colour or fade; given to a shape with
/// no outline it gives it one (ShapeElement.withOutline).
Widget _outlineColour(_Shape s, {Key? key, required String label}) =>
    fadedColour(
      key: key,
      label: label,
      color: s.e.strokeColor,
      fade: s.e.strokeFade,
      onColour: (c) => s.now(s.e.withOutline(color: c)),
      onFade: (g) => s.now(s.e.withOutline(fade: g, flat: g == null)),
    );

/// _outlineWidth is how thick the outline is, from none.
Widget _outlineWidth(_Shape s,
        {Key? key, required String label, required bool quick}) =>
    widthField(
      key: key,
      label: label,
      value: s.e.strokeWidth,
      min: 0,
      quick: quick,
      onChanged: (v) => s.live(s.e.copyWith(strokeWidth: v)),
      onCommit: s.commit,
    );

/// _kindBit is which shape it is, a star's points and a shape's corners, in
/// Content.
PanelBit _kindBit(BuildContext context, _Shape s) {
  var e = s.e;
  // Read while building: a tile's picture is drawn while painting, when the
  // theme cannot be asked.
  var ink = ThemeNotifier.of(context).colors.onSurfaceVariant;
  return PanelBit(PanelSection.content,
      summary: [
        e.shape.label,
        if (e.shape.hasPoints) "${e.points} points",
        if (e.hasCorners && e.corners.all > 0) "rounded",
      ].join(" · "),
      children: [
        // Shown, not named: each shape is a tile drawn as itself.
        CanvasTiles<ShapeKind>(
          key: const ValueKey("shapeKind"),
          label: "Which shape",
          foldAs: "shape.tiles.kind",
          help: "Which shape it is. Each tile is the shape itself. A square "
              "or a circle makes its box square and keeps it so.",
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
          onPick: (v) => s.now(e.withKind(v)),
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
                min: minStarPoints.toDouble(),
                max: maxStarPoints.toDouble(),
                width: 50,
                onChanged: (v) => s.live(e.copyWith(points: v.round())),
                onCommit: s.commit,
              ),
              CanvasNumberField(
                label: "Depth",
                decimals: 2,
                width: 62,
                value: e.innerRatio,
                min: minStarDepth,
                max: maxStarDepth,
                onChanged: (v) => s.live(e.copyWith(innerRatio: v)),
                onCommit: s.commit,
              ),
            ],
          ),
        if (e.hasCorners)
          CanvasControlGroup(
            label: "Corners",
            help: "How round its corners are: one number for all four, or "
                "split with the link to set each on its own.",
            rule: false,
            children: [
              ...cornerFields(
                  e.corners,
                  (c) => s.write(e.copyWith(
                      cornerRadius: c.all,
                      radTL: c.tl,
                      radTR: c.tr,
                      radBR: c.br,
                      radBL: c.bl,
                      clearCorners: true)),
                  s.commit,
                  prefix: "shape"),
            ],
          ),
      ]);
}

/// _lookBit is what the shape is filled with and its outline, in Look.
PanelBit _lookBit(BuildContext context, _Shape s) {
  var e = s.e;
  var painted = switch (e.painted.kind) {
    TextFillKind.color => "colour",
    var k => k.label.toLowerCase(),
  };
  return PanelBit(PanelSection.look,
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
              onChanged: (v) =>
                  s.now(e.copyWith(painted: e.painted.copyWith(kind: v))),
            ),
            if (e.painted.kind != TextFillKind.color)
              ...fillBits(context, e.painted,
                  (f) => s.write(e.copyWith(painted: f)), s.begin, s.commit,
                  keyPrefix: "shape"),
            if (e.painted.kind == TextFillKind.color) _fillColour(s),
          ],
        ),
        CanvasControlGroup(
          label: "Outline",
          help: "The line round the shape: how thick, and its colour. A "
              "colour chosen for a shape with no outline gives it one.",
          rule: false,
          children: [
            _outlineWidth(s, label: "Stroke", quick: false),
            _outlineColour(s, label: "Colour"),
          ],
        ),
      ]);
}

/// _wordsBit is the words written on the shape, the room kept round them
/// and how they are set, in Content.
PanelBit _wordsBit(_Shape s) {
  var e = s.e;
  return PanelBit(PanelSection.content,
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
              onChanged: (v) => s.write(e.copyWith(text: v)),
              onCommit: s.commit,
            ),
            ...roomFields(
                e.pad,
                (r) => s.write(e.copyWith(
                    padding: r.all,
                    padL: r.l,
                    padT: r.t,
                    padR: r.r,
                    padB: r.b,
                    clearRoom: true)),
                s.commit,
                prefix: "shape"),
          ],
        ),
        if (e.text.isNotEmpty)
          labelType(
              TypeEdit(
                  e.textSpec,
                  (spec) => s.write(e.copyWith(textSpec: spec)),
                  s.begin,
                  s.commit),
              remember: "shapeLabel"),
      ]);
}

/// _bubbleBit is a speech bubble's body and tail, in Content.
PanelBit _bubbleBit(_Shape s) {
  var e = s.e, b = e.bubble;
  void tail(SpeechBubbleSpec next) => s.live(e.copyWith(bubble: next));
  return PanelBit(PanelSection.content,
      summary: "${b.body.label} · ${b.tail.label} tail",
      children: [
        CanvasControlGroup(
          label: "Bubble",
          help: "The bubble's body, and its tail: which way it points, how "
              "long and wide it is, and -- curved -- how it curls.",
          rule: false,
          children: [
            CanvasDropdown<BubbleBody>(
              label: "Body",
              value: b.body,
              width: 104,
              options: [for (var b in BubbleBody.values) (b, b.label)],
              onChanged: (v) => s.now(e.copyWith(bubble: b.copyWith(body: v))),
            ),
            CanvasDropdown<BubbleTail>(
              label: "Tail",
              value: b.tail,
              width: 104,
              options: [for (var t in BubbleTail.values) (t, t.label)],
              onChanged: (v) => s.now(e.copyWith(bubble: b.copyWith(tail: v))),
            ),
            if (b.tail != BubbleTail.none) ...[
              CanvasNumberField(
                key: const ValueKey("bubbleTailAngle"),
                label: "Points to",
                value: b.tailAngle,
                min: -360,
                max: 360,
                width: 58,
                suffix: "°",
                onChanged: (v) => tail(b.copyWith(tailAngle: v)),
                onCommit: s.commit,
              ),
              CanvasNumberField(
                label: "Length",
                decimals: 2,
                width: 62,
                value: b.tailLength,
                min: SpeechBubbleSpec.minTailLength,
                max: SpeechBubbleSpec.maxTailLength,
                onChanged: (v) => tail(b.copyWith(tailLength: v)),
                onCommit: s.commit,
              ),
              CanvasNumberField(
                label: "Width",
                decimals: 2,
                width: 62,
                value: b.tailWidth,
                min: SpeechBubbleSpec.minTailWidth,
                max: SpeechBubbleSpec.maxTailWidth,
                onChanged: (v) => tail(b.copyWith(tailWidth: v)),
                onCommit: s.commit,
              ),
              if (b.tail == BubbleTail.curved)
                CanvasNumberField(
                  label: "Curl",
                  decimals: 2,
                  width: 62,
                  value: b.curl,
                  min: -1.5,
                  max: 1.5,
                  onChanged: (v) => tail(b.copyWith(curl: v)),
                  onCommit: s.commit,
                ),
            ],
          ],
        ),
      ]);
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
