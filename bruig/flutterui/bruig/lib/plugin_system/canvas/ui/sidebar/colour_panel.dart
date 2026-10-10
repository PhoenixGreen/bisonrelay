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
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_items.dart';
import 'package:flutter/material.dart';

// colour_panel.dart is the Design sidebar's Colour section: the colours of
// whatever is selected -- a shape's fill and line, a caption's words and its
// box, or, with nothing selected, the background's three -- as swatches,
// the one in front the one being chosen; the colour picker for it, always
// open and laid out small; and an eyedropper that takes a colour off the
// canvas.

/// ColourSlot is one colour the Colour section can set: what it is called,
/// whether it is drawn as a line (a ring) or an area (a disc), what it is
/// now -- null for none -- and how it is set, colour and fade. [transient]
/// is for a change still being made: see CanvasController.replaceElement.
class ColourSlot {
  final String id;
  final String label;
  final bool ring;
  final Color? color;
  final GradientSpec? gradient;
  final bool canBeNone;
  final void Function(Color? c, {required bool transient}) setColour;
  final void Function(GradientSpec? g, {required bool transient}) setGradient;

  const ColourSlot({
    required this.id,
    required this.label,
    required this.ring,
    required this.color,
    required this.gradient,
    required this.setColour,
    required this.setGradient,
    this.canBeNone = true,
  });
}

/// _strokeToSee is a line wide enough to be seen, for a shape given a line
/// colour while it had none.
double _strokeToSee(ShapeElement e) =>
    (math.min(e.width, e.height) * 0.015).clamp(1.0, 6.0);

/// colourSlotsFor is the colours the Colour section offers now: the
/// selected element's -- the one that covers an area, and the one that
/// draws its line or its words -- or, with nothing selected, or the
/// background picked, the background's three.
List<ColourSlot> colourSlotsFor(CanvasController controller) {
  var e = controller.selected;
  if (e == null) return _backgroundSlots(controller);

  ColourSlot slot(
    String id,
    String label,
    bool ring,
    Color? color,
    GradientSpec? gradient,
    CanvasElement Function(Color? c) withColour,
    CanvasElement Function(GradientSpec? g) withGradient, {
    bool canBeNone = true,
  }) =>
      ColourSlot(
        id: id,
        label: label,
        ring: ring,
        color: color,
        gradient: gradient,
        canBeNone: canBeNone,
        setColour: (c, {required transient}) =>
            controller.replaceElement(withColour(c), transient: transient),
        setGradient: (g, {required transient}) =>
            controller.replaceElement(withGradient(g), transient: transient),
      );

  switch (e) {
    // A drawing with nothing in it yet: the colours its shapes will be
    // drawn in -- by the shapes tool, the pencil and the pen alike -- so a
    // new drawing starts in them. A fade is a shape's own, once there is
    // one to have it.
    case VectorElement v
        when (v.shapes ?? const []).isEmpty && v.assetId.isEmpty:
      return [
        ColourSlot(
          id: "fill",
          label: "Fill",
          ring: false,
          color: controller.vectorShapeFill,
          gradient: null,
          setColour: (c, {required transient}) {
            controller.vectorShapeFill = c;
            if (c != null) controller.vectorPencilFill = c;
          },
          setGradient: (_, {required transient}) {},
        ),
        ColourSlot(
          id: "line",
          label: "Line",
          ring: true,
          color: controller.vectorShapeLine,
          gradient: null,
          setColour: (c, {required transient}) {
            controller.vectorShapeLine = c;
            if (c != null) controller.vectorPencilColour = c;
          },
          setGradient: (_, {required transient}) {},
        ),
      ];
    case VectorElement v when (v.shapes ?? const []).isNotEmpty:
      var shapes = v.shapes!;
      // The shapes picked -- with the select shapes tool, or one shape --
      // or every shape, as the shape settings change them.
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
        slot(
            "fill",
            "Fill",
            false,
            first.fill,
            first.fillFade,
            (c) => each((s) =>
                c == null ? s.copyWith(clearFill: true) : s.copyWith(fill: c)),
            (g) => each((s) => g == null
                ? s.copyWith(flatFill: true)
                : s.copyWith(fill: s.fill ?? g.to, fillFade: g))),
        slot(
            "line",
            "Line",
            true,
            first.stroke,
            first.strokeFade,
            (c) => each((s) => c == null
                ? s.copyWith(clearStroke: true)
                : s.copyWith(
                    stroke: c, strokeWidth: s.strokeWidth > 0 ? null : 1)),
            (g) => each((s) => g == null
                ? s.copyWith(flatStroke: true)
                : s.copyWith(
                    stroke: s.stroke ?? g.to,
                    strokeWidth: s.strokeWidth > 0 ? null : 1,
                    strokeFade: g))),
      ];
    case ShapeElement s:
      return [
        slot(
            "fill",
            "Fill",
            false,
            s.fill.a == 0 ? null : s.fill,
            s.fillFade,
            (c) => s.copyWith(fill: c ?? const Color(0x00000000)),
            (g) => g == null
                ? s.copyWith(flatFill: true)
                : s.copyWith(fillFade: g)),
        slot(
            "line",
            "Outline",
            true,
            s.strokeWidth > 0 ? s.strokeColor : null,
            s.strokeFade,
            (c) => c == null
                ? s.copyWith(strokeWidth: 0)
                : s.copyWith(
                    strokeColor: c,
                    strokeWidth: s.strokeWidth > 0 ? null : _strokeToSee(s)),
            (g) => g == null
                ? s.copyWith(flatStroke: true)
                : s.copyWith(
                    strokeFade: g,
                    strokeWidth: s.strokeWidth > 0 ? null : _strokeToSee(s))),
      ];
    case LineElement l:
      return [
        slot(
            "line",
            "Line",
            true,
            l.color,
            l.fade,
            (c) => l.copyWith(color: c ?? l.color),
            (g) => g == null ? l.copyWith(flat: true) : l.copyWith(fade: g),
            canBeNone: false),
      ];
    case PathElement p:
      return [
        slot(
            "line",
            "Line",
            true,
            p.color,
            p.fade,
            (c) => p.copyWith(color: c ?? p.color),
            (g) => g == null ? p.copyWith(flat: true) : p.copyWith(fade: g),
            canBeNone: false),
      ];
    case TextElement t:
      return [
        slot(
            "fill",
            "Box",
            false,
            t.box.fill.a == 0 ? null : t.box.fill,
            t.box.fillFade,
            (c) => t.copyWith(
                box: t.box.copyWith(fill: c ?? const Color(0x00000000))),
            (g) => t.copyWith(
                box: g == null
                    ? t.box.copyWith(flatFill: true)
                    : t.box.copyWith(fillFade: g))),
        slot(
            "line",
            "Text",
            true,
            t.textSpec.color,
            t.textSpec.fade,
            (c) => t.copyWith(
                textSpec: t.textSpec.copyWith(color: c ?? t.textSpec.color)),
            (g) => t.copyWith(
                textSpec: g == null
                    ? t.textSpec.copyWith(flatText: true)
                    : t.textSpec.copyWith(fade: g)),
            canBeNone: false),
      ];
    case ButtonElement b:
      return [
        slot(
            "fill",
            "Fill",
            false,
            b.box.fill.a == 0 ? null : b.box.fill,
            b.box.fillFade,
            (c) => b.copyWith(
                box: b.box.copyWith(fill: c ?? const Color(0x00000000))),
            (g) => b.copyWith(
                box: g == null
                    ? b.box.copyWith(flatFill: true)
                    : b.box.copyWith(fillFade: g))),
        slot(
            "line",
            "Text",
            true,
            b.textSpec.color,
            b.textSpec.fade,
            (c) => b.copyWith(
                textSpec: b.textSpec.copyWith(color: c ?? b.textSpec.color)),
            (g) => b.copyWith(
                textSpec: g == null
                    ? b.textSpec.copyWith(flatText: true)
                    : b.textSpec.copyWith(fade: g)),
            canBeNone: false),
      ];
    default:
      return const [];
  }
}

/// _backgroundSlots is the background's three colours: its base, and the
/// pattern's own two.
List<ColourSlot> _backgroundSlots(CanvasController controller) {
  var bg = controller.document.editedBackground;
  var spec = bg.spec;
  // None is the colour gone clear: the base shows what is behind the
  // canvas, and the pattern's colour leaves the pattern.
  const clear = Color(0x00000000);
  Color? shown(Color c) => c.a == 0 ? null : c;
  void set(ProceduralSpec next, bool transient) =>
      controller.setBackground(bg.copyWith(spec: next), transient: transient);
  return [
    ColourSlot(
      id: "base",
      label: "Base",
      ring: false,
      color: shown(spec.background),
      gradient: spec.gradient,
      setColour: (c, {required transient}) =>
          set(spec.copyWith(background: c ?? clear), transient),
      setGradient: (g, {required transient}) => set(
          g == null
              ? spec.copyWith(flatBackground: true)
              : spec.copyWith(gradient: g),
          transient),
    ),
    ColourSlot(
      id: "main",
      label: "Main",
      ring: false,
      color: shown(spec.foreground),
      gradient: spec.foregroundFade,
      setColour: (c, {required transient}) =>
          set(spec.copyWith(foreground: c ?? clear), transient),
      setGradient: (g, {required transient}) => set(
          g == null
              ? spec.copyWith(flatForeground: true)
              : spec.copyWith(foregroundFade: g),
          transient),
    ),
    ColourSlot(
      id: "accent",
      label: "Accent",
      ring: false,
      color: shown(spec.accent),
      gradient: spec.accentFade,
      setColour: (c, {required transient}) =>
          set(spec.copyWith(accent: c ?? clear), transient),
      setGradient: (g, {required transient}) => set(
          g == null
              ? spec.copyWith(flatAccent: true)
              : spec.copyWith(accentFade: g),
          transient),
    ),
  ];
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

  /// _write makes [change] part of the change the picker is making.
  void _write(void Function() change) {
    controller.beginInteraction();
    change();
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 600), _done);
  }

  /// _now makes [change] a change of its own: one undo step, however many
  /// writes it is.
  void _now(void Function() change) {
    _done();
    controller.beginInteraction();
    change();
    controller.endInteraction();
  }

  /// _slot is slot [id] as it is now, after whatever was just written.
  ColourSlot? _slot(String id) =>
      colourSlotsFor(controller).where((s) => s.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var slots = colourSlotsFor(controller);
          if (slots.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text("Its colours are in its settings.",
                  style: Theme.of(context).textTheme.bodySmall),
            );
          }
          var active = slots.firstWhere((s) => s.id == _active,
              orElse: () => slots.first);
          var owner = controller.selected?.id ?? "background";
          var two = slots.length == 2;
          // The swatches, and to the right of them the eyedropper and the
          // colour it last took.
          var leading = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Swatches(
                slots: slots,
                active: active,
                onPick: (s) => setState(() => _active = s.id),
                onSwap: !two
                    ? null
                    : () {
                        var other = slots.firstWhere((s) => s != active);
                        var a = active.color, b = other.color;
                        _now(() {
                          active.setColour(b, transient: true);
                          _slot(other.id)?.setColour(a, transient: true);
                        });
                      },
                onNone: active.canBeNone
                    ? () => _now(() => active.setColour(null, transient: true))
                    : null,
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                // The eyedropper: its next press on the canvas takes the
                // colour there for the colour being chosen.
                // Drawn small, not as an IconButton: that keeps a 40px
                // square round itself whatever it is told, which is room
                // the numbers beside it need.
                Tooltip(
                  message: "Pick colour",
                  child: InkWell(
                    key: const ValueKey("colourDropper"),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => controller.sampling
                        ? controller.stopSampling()
                        : controller.startSampling((c) => _now(() =>
                            _slot(active.id)?.setColour(c, transient: true))),
                    child: SizedBox.square(
                      dimension: 24,
                      // Drawn rather than the icon font's, whose stroke is
                      // heavier than the swatches beside it.
                      child: CustomPaint(
                        painter: _DropperPainter(controller.sampling
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                // The colour it last took: pressed, given again.
                _Dot(
                  key: const ValueKey("colourSampled"),
                  color: controller.sampled,
                  onTap: controller.sampled == null
                      ? null
                      : () => _now(() => active.setColour(controller.sampled,
                          transient: true)),
                ),
              ]),
            ],
          );
          // Scrolled where there is not the room, with no bar -- as every
          // other panel in the column is.
          return ScrollConfiguration(
              behavior: const CanvasNoScrollbar(),
              child: SingleChildScrollView(
                child: Padding(
                  // Clear of the panel's heading above.
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                  child: LayoutBuilder(
                    builder: (context, box) => AppColorPicker(
                      key: ValueKey("colourPicker-$owner-${active.id}"),
                      compact: true,
                      leading: leading,
                      color: active.color ?? const Color(0xFFFFFFFF),
                      gradient: active.gradient,
                      width: box.maxWidth,
                      onChanged: (c) =>
                          _write(() => active.setColour(c, transient: true)),
                      onGradientChanged: (g) =>
                          _write(() => active.setGradient(g, transient: true)),
                    ),
                  ),
                ),
              ));
        },
      );
}

/// _Swatches is the colours, each in its own place -- the first top left,
/// the next down and to the right of it -- the one being chosen drawn over
/// the others; pressed, a swatch is the one being chosen. Beside them, for
/// two, the arrows that swap them; below, the swatch that sets the one being
/// chosen to none.
class _Swatches extends StatelessWidget {
  final List<ColourSlot> slots;
  final ColourSlot active;
  final ValueChanged<ColourSlot> onPick;
  final VoidCallback? onSwap;
  final VoidCallback? onNone;

  const _Swatches(
      {required this.slots,
      required this.active,
      required this.onPick,
      required this.onSwap,
      required this.onNone});

  /// _size is a swatch's, and _step how far each sits from the one before.
  static const double _size = 28;
  static const Offset _step = Offset(13, 11);

  @override
  Widget build(BuildContext context) {
    var outline = Theme.of(context).colorScheme.outline;
    // Round to the pointer as well as to the eye -- the corners of the one
    // in front lie over the others -- so the clip is outermost, round the
    // tooltip's own catch as well.
    Widget swatch(ColourSlot s) => ClipOval(
          child: Tooltip(
            message: s.label,
            child: GestureDetector(
              key: ValueKey("colourSlot-${s.id}"),
              onTap: () => onPick(s),
              child: CustomPaint(
                size: const Size.square(_size),
                painter: _SwatchPainter(s, outline, chosen: s == active),
              ),
            ),
          ),
        );
    var span = _size + _step.dx * (slots.length - 1);
    var tall = _size + _step.dy * (slots.length - 1);
    // Each where it belongs; the one being chosen last, so on top.
    var order = [
      for (var (i, s) in slots.indexed)
        if (s != active) (i, s),
      for (var (i, s) in slots.indexed)
        if (s == active) (i, s),
    ];
    return SizedBox(
      width: span + (onSwap == null ? 2 : 17),
      height: tall + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var (i, s) in order)
          Positioned(left: _step.dx * i, top: _step.dy * i, child: swatch(s)),
        if (onSwap != null)
          Positioned(
            left: span + 2,
            top: 0,
            child: InkWell(
              key: const ValueKey("colourSwap"),
              onTap: onSwap,
              child: Tooltip(
                message: "Swap",
                child: Icon(Icons.swap_horiz, size: 14, color: outline),
              ),
            ),
          ),
        Positioned(
          left: 0,
          top: tall - 12,
          child: Tooltip(
            message: "None",
            child: GestureDetector(
              key: const ValueKey("colourNone"),
              onTap: onNone,
              child: CustomPaint(
                size: const Size.square(12),
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
/// -- with a slash through white where it is none, and a brighter edge on
/// the one being chosen.
class _SwatchPainter extends CustomPainter {
  final ColourSlot slot;
  final Color outline;
  final bool chosen;
  _SwatchPainter(this.slot, this.outline, {required this.chosen});

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    var colour = slot.color;
    var paint = Paint();
    if (slot.gradient case var g?) {
      paint.shader = PaintSpec(colour ?? Colors.white, gradient: g)
          .shaderFor(Offset.zero & size);
    } else {
      paint.color = colour ?? Colors.white;
    }
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = chosen ? 1.6 : 1
      ..color = chosen ? const Color(0xFFFFFFFF) : outline;
    if (slot.ring) {
      var width = r * 0.42;
      canvas.drawCircle(
          c,
          r - width / 2,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = width);
      canvas.drawCircle(c, r, edge);
      canvas.drawCircle(
          c,
          r - width,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline);
    } else {
      canvas.drawCircle(c, r, paint);
      canvas.drawCircle(c, r, edge);
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
      old.slot.ring != slot.ring ||
      old.chosen != chosen;
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
      padding: const EdgeInsets.only(left: 5),
      child: Tooltip(
        message: "Use again",
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 18,
            height: 18,
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

/// _DropperPainter draws the eyedropper in a fine line: the tube leaning
/// down to its tip, the collar across it, and the bulb at the top.
class _DropperPainter extends CustomPainter {
  final Color colour;
  _DropperPainter(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var k = size.shortestSide;
    Offset at(double x, double y) => Offset(x * k, y * k);
    var line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    // Along the diagonal: laid out upright about the middle, then turned.
    canvas.translate(k / 2, k / 2);
    canvas.rotate(math.pi / 4);
    canvas.translate(-k / 2, -k / 2);
    // The tube, the tip below it, the collar and the bulb above.
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(at(0.44, 0.38), at(0.56, 0.78)),
            Radius.circular(k * 0.04)),
        line);
    canvas.drawLine(at(0.5, 0.78), at(0.5, 0.9), line);
    canvas.drawLine(at(0.36, 0.38), at(0.64, 0.38), line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(at(0.42, 0.1), at(0.58, 0.38)),
            Radius.circular(k * 0.08)),
        line..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DropperPainter old) => old.colour != colour;
}
