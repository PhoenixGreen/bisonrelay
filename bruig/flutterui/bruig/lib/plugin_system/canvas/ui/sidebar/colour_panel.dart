import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_items.dart';
import 'package:flutter/material.dart';

// colour_panel.dart is the Design sidebar's Colour section: the colours of
// whatever is selected -- a shape's fill and line, a caption's words and its
// box -- as a pair of swatches, the one in front the one being chosen; the
// colour picker for it, always open; and an eyedropper that takes a colour
// off the canvas. The same picker a colour button opens, kept out where it
// can be used without opening anything.

/// ColourSlot is one colour of an element the Colour section can set: what
/// it is called, whether it is drawn as a line (a ring) or an area (a disc),
/// what it is now -- null for none -- and how the element is made with
/// another.
class ColourSlot {
  final String id;
  final String label;
  final bool ring;
  final Color? color;
  final GradientSpec? gradient;
  final bool canBeNone;
  final CanvasElement Function(Color? c) withColour;
  final CanvasElement Function(GradientSpec? g)? withGradient;

  const ColourSlot({
    required this.id,
    required this.label,
    required this.ring,
    required this.color,
    required this.withColour,
    this.gradient,
    this.canBeNone = true,
    this.withGradient,
  });
}

/// _strokeToSee is a line wide enough to be seen, for a shape given a line
/// colour while it had none.
double _strokeToSee(ShapeElement e) =>
    (math.min(e.width, e.height) * 0.015).clamp(1.0, 6.0);

/// colourSlotsFor is [e]'s colours: at most two -- the one that covers an
/// area, and the one that draws its line or its words.
List<ColourSlot> colourSlotsFor(CanvasController controller, CanvasElement e) {
  switch (e) {
    case VectorElement v when (v.shapes ?? const []).isNotEmpty:
      var shapes = v.shapes!;
      // The shapes picked -- with the select shapes tool, or one shape -- or
      // every shape, as the shape settings change them.
      var items = controller.vectorEditing == v.id
          ? controller.vectorItems
          : const <VectorItem>{};
      var picked = controller.vectorShape;
      var targets = <int>{
        for (var item in items) ...groupMembers(v, item.shape),
        if (items.isEmpty && picked >= 0 && picked < shapes.length)
          ...groupMembers(v, groupOf(v, picked)),
      };
      if (targets.isEmpty) {
        targets = {for (var i = 0; i < shapes.length; i++) i};
      }
      var first = shapes[targets.first];
      VectorElement each(VectorShape Function(VectorShape) edit) =>
          v.copyWith(shapes: [
            for (var (i, s) in shapes.indexed)
              targets.contains(i) ? edit(s) : s,
          ]);
      return [
        ColourSlot(
          id: "fill",
          label: "Fill",
          ring: false,
          color: first.fill,
          withColour: (c) => each((s) =>
              c == null ? s.copyWith(clearFill: true) : s.copyWith(fill: c)),
        ),
        ColourSlot(
          id: "line",
          label: "Line",
          ring: true,
          color: first.stroke,
          withColour: (c) => each((s) => c == null
              ? s.copyWith(clearStroke: true)
              : s.copyWith(
                  stroke: c, strokeWidth: s.strokeWidth > 0 ? null : 1)),
        ),
      ];
    case ShapeElement s:
      return [
        ColourSlot(
          id: "fill",
          label: "Fill",
          ring: false,
          color: s.fill.a == 0 ? null : s.fill,
          gradient: s.fillFade,
          withColour: (c) => s.copyWith(fill: c ?? const Color(0x00000000)),
          withGradient: (g) =>
              g == null ? s.copyWith(flatFill: true) : s.copyWith(fillFade: g),
        ),
        ColourSlot(
          id: "line",
          label: "Outline",
          ring: true,
          color: s.strokeWidth > 0 ? s.strokeColor : null,
          gradient: s.strokeFade,
          withColour: (c) => c == null
              ? s.copyWith(strokeWidth: 0)
              : s.copyWith(
                  strokeColor: c,
                  strokeWidth: s.strokeWidth > 0 ? null : _strokeToSee(s)),
          withGradient: (g) => g == null
              ? s.copyWith(flatStroke: true)
              : s.copyWith(strokeFade: g),
        ),
      ];
    case LineElement l:
      return [
        ColourSlot(
          id: "line",
          label: "Line",
          ring: true,
          color: l.color,
          gradient: l.fade,
          canBeNone: false,
          withColour: (c) => l.copyWith(color: c ?? l.color),
          withGradient: (g) =>
              g == null ? l.copyWith(flat: true) : l.copyWith(fade: g),
        ),
      ];
    case PathElement p:
      return [
        ColourSlot(
          id: "line",
          label: "Line",
          ring: true,
          color: p.color,
          gradient: p.fade,
          canBeNone: false,
          withColour: (c) => p.copyWith(color: c ?? p.color),
          withGradient: (g) =>
              g == null ? p.copyWith(flat: true) : p.copyWith(fade: g),
        ),
      ];
    case TextElement t:
      return [
        ColourSlot(
          id: "fill",
          label: "Box",
          ring: false,
          color: t.box.fill.a == 0 ? null : t.box.fill,
          gradient: t.box.fillFade,
          withColour: (c) => t.copyWith(
              box: t.box.copyWith(fill: c ?? const Color(0x00000000))),
          withGradient: (g) => t.copyWith(
              box: g == null
                  ? t.box.copyWith(flatFill: true)
                  : t.box.copyWith(fillFade: g)),
        ),
        ColourSlot(
          id: "line",
          label: "Text",
          ring: true,
          color: t.textSpec.color,
          gradient: t.textSpec.fade,
          canBeNone: false,
          withColour: (c) => t.copyWith(
              textSpec: t.textSpec.copyWith(color: c ?? t.textSpec.color)),
          withGradient: (g) => t.copyWith(
              textSpec: g == null
                  ? t.textSpec.copyWith(flatText: true)
                  : t.textSpec.copyWith(fade: g)),
        ),
      ];
    case ButtonElement b:
      return [
        ColourSlot(
          id: "fill",
          label: "Fill",
          ring: false,
          color: b.box.fill.a == 0 ? null : b.box.fill,
          gradient: b.box.fillFade,
          withColour: (c) => b.copyWith(
              box: b.box.copyWith(fill: c ?? const Color(0x00000000))),
          withGradient: (g) => b.copyWith(
              box: g == null
                  ? b.box.copyWith(flatFill: true)
                  : b.box.copyWith(fillFade: g)),
        ),
        ColourSlot(
          id: "line",
          label: "Text",
          ring: true,
          color: b.textSpec.color,
          canBeNone: false,
          withColour: (c) => b.copyWith(
              textSpec: b.textSpec.copyWith(color: c ?? b.textSpec.color)),
        ),
      ];
    default:
      return const [];
  }
}

/// ColourPanel is the Colour section of the Design sidebar.
class ColourPanel extends StatefulWidget {
  final CanvasController controller;
  const ColourPanel({required this.controller, super.key});

  @override
  State<ColourPanel> createState() => _ColourPanelState();
}

class _ColourPanelState extends State<ColourPanel> {
  CanvasController get controller => widget.controller;

  /// _active is the slot being chosen: the one drawn in front.
  String _active = "fill";

  /// _settle closes a run of picker changes into one undo step, once the
  /// picker has been still a moment.
  Timer? _settle;

  @override
  void dispose() {
    _done();
    super.dispose();
  }

  void _done() {
    _settle?.cancel();
    _settle = null;
    controller.endInteraction();
  }

  /// _write puts [next] in, as part of the change the picker is making.
  void _write(CanvasElement next) {
    controller.beginInteraction();
    controller.replaceElement(next, transient: true);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 600), _done);
  }

  /// _now puts [next] in as a change of its own.
  void _now(CanvasElement next) {
    _done();
    controller.replaceElement(next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var e = controller.selected;
          var slots =
              e == null ? const <ColourSlot>[] : colourSlotsFor(controller, e);
          if (e == null || slots.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                  e == null
                      ? "Select something to choose its colours."
                      : "Its colours are in its settings.",
                  style: Theme.of(context).textTheme.bodySmall),
            );
          }
          var active = slots.firstWhere((s) => s.id == _active,
              orElse: () => slots.first);
          var other = slots.where((s) => s != active).firstOrNull;
          // Scrolled, in whatever room the column gives it.
          return SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Swatches(
                    front: active,
                    back: other,
                    onPick: (s) => setState(() => _active = s.id),
                    onSwap: other == null
                        ? null
                        : () {
                            var a = active.color, b = other.color;
                            var swapped = active.withColour(b);
                            var fresh = colourSlotsFor(controller, swapped)
                                .firstWhere((s) => s.id == other.id);
                            _now(fresh.withColour(a));
                          },
                    onNone: active.canBeNone
                        ? () => _now(active.withColour(null))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(active.label,
                            key: const ValueKey("colourActive"),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Row(children: [
                          CanvasIconButton(
                            key: const ValueKey("colourDropper"),
                            icon: Icons.colorize,
                            tooltip: "Pick colour",
                            tight: true,
                            active: controller.sampling,
                            onPressed: () => controller.sampling
                                ? controller.stopSampling()
                                : controller.startSampling((c) {
                                    var now = controller.selected;
                                    if (now == null) return;
                                    var slot = colourSlotsFor(controller, now)
                                        .where((s) => s.id == active.id)
                                        .firstOrNull;
                                    if (slot != null) _now(slot.withColour(c));
                                  }),
                          ),
                          // The colour the eyedropper last took: pressed,
                          // it is given to the colour being chosen again.
                          _Dot(
                            key: const ValueKey("colourSampled"),
                            color: controller.sampled,
                            onTap: controller.sampled == null
                                ? null
                                : () =>
                                    _now(active.withColour(controller.sampled)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) => AppColorPicker(
                    key: ValueKey("colourPicker-${e.id}-${active.id}"),
                    color: active.color ?? const Color(0xFFFFFFFF),
                    gradient: active.gradient,
                    width: box.maxWidth,
                    onChanged: (c) => _write(active.withColour(c)),
                    onGradientChanged: active.withGradient == null
                        ? null
                        : (g) => _write(active.withGradient!(g)),
                  ),
                ),
              ],
            ),
          ));
        },
      );
}

/// _Swatches is the pair: the colour being chosen in front, as a disc or a
/// ring, and the other behind it -- pressed, it comes to the front. Beside
/// them, the arrows that swap the two, and below, the swatch that sets the
/// one in front to none.
class _Swatches extends StatelessWidget {
  final ColourSlot front;
  final ColourSlot? back;
  final ValueChanged<ColourSlot> onPick;
  final VoidCallback? onSwap;
  final VoidCallback? onNone;

  const _Swatches(
      {required this.front,
      required this.back,
      required this.onPick,
      required this.onSwap,
      required this.onNone});

  @override
  Widget build(BuildContext context) {
    var outline = Theme.of(context).colorScheme.outline;
    // Round to the pointer as well as to the eye -- the corners of the one
    // in front lie over the one behind -- so the clip is outermost, round
    // the tooltip's own catch as well.
    Widget swatch(ColourSlot s, double size) => ClipOval(
          child: Tooltip(
            message: s.label,
            child: GestureDetector(
              key: ValueKey("colourSlot-${s.id}"),
              onTap: () => onPick(s),
              child: CustomPaint(
                size: Size.square(size),
                painter: _SwatchPainter(s, outline),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 92,
      height: 76,
      child: Stack(clipBehavior: Clip.none, children: [
        if (back case var b?) Positioned(left: 0, top: 0, child: swatch(b, 44)),
        Positioned(
            left: back == null ? 10 : 20,
            top: back == null ? 6 : 16,
            child: swatch(front, 48)),
        if (onSwap != null)
          Positioned(
            left: 56,
            top: 0,
            child: InkWell(
              key: const ValueKey("colourSwap"),
              onTap: onSwap,
              child: Tooltip(
                message: "Swap",
                child: Icon(Icons.swap_horiz, size: 16, color: outline),
              ),
            ),
          ),
        Positioned(
          left: 0,
          top: 56,
          child: Tooltip(
            message: "None",
            child: GestureDetector(
              key: const ValueKey("colourNone"),
              onTap: onNone,
              child: CustomPaint(
                size: const Size.square(18),
                painter: _NonePainter(outline, enabled: onNone != null),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// _SwatchPainter draws a colour as a disc -- or, for a line, a thick ring
/// -- with a slash through white where it is none.
class _SwatchPainter extends CustomPainter {
  final ColourSlot slot;
  final Color outline;
  _SwatchPainter(this.slot, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    var colour = slot.color;
    var paint = Paint();
    if (slot.gradient case var g?) {
      paint.shader = LinearGradient(colors: [colour ?? Colors.white, g.to])
          .createShader(Offset.zero & size);
    } else {
      paint.color = colour ?? Colors.white;
    }
    if (slot.ring) {
      var width = r * 0.42;
      canvas.drawCircle(
          c,
          r - width / 2,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = width);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline);
      canvas.drawCircle(
          c,
          r - width,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline);
    } else {
      canvas.drawCircle(c, r, paint);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline);
    }
    if (colour == null) {
      canvas.drawLine(
          c + Offset(-r * 0.7, r * 0.7),
          c + Offset(r * 0.7, -r * 0.7),
          Paint()
            ..color = const Color(0xFFE53935)
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.slot.color != slot.color ||
      old.slot.gradient != slot.gradient ||
      old.slot.ring != slot.ring;
}

/// _NonePainter is the small white swatch with a red slash: none.
class _NonePainter extends CustomPainter {
  final Color outline;
  final bool enabled;
  _NonePainter(this.outline, {required this.enabled});

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    var fade = enabled ? 1.0 : 0.35;
    canvas.drawCircle(
        c, r, Paint()..color = Colors.white.withValues(alpha: fade));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline);
    canvas.drawLine(
        c + Offset(-r * 0.7, r * 0.7),
        c + Offset(r * 0.7, -r * 0.7),
        Paint()
          ..color = const Color(0xFFE53935).withValues(alpha: fade)
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_NonePainter old) => old.enabled != enabled;
}

/// _Dot is the colour the eyedropper last took, as a small disc.
class _Dot extends StatelessWidget {
  final Color? color;
  final VoidCallback? onTap;
  const _Dot({required this.color, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var outline = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: "Use again",
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? Colors.transparent,
              border: Border.all(color: outline),
            ),
          ),
        ),
      ),
    );
  }
}
