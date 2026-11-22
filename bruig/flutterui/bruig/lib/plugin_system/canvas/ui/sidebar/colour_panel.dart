import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_items.dart';

// colour_panel.dart is the Design sidebar's Colour section: the selection's
// colours (or the background's three) as swatches, the chosen one in front;
// an always-open compact picker; and an eyedropper taking canvas colours.

/// ColourSlot is one colour the Colour section can set: its name, whether
/// it is a line (a ring) or an area (a disc), its value (null for none), and
/// how it is set, colour and fade. [transient] is for a change still being
/// made: see CanvasController.replaceElement.
class ColourSlot {
  final String id;
  final String label;
  final bool ring;
  final Color? color;
  final GradientSpec? gradient;
  final bool canBeNone;
  final void Function(Color? c, {required bool transient}) setColour;

  /// setGradient sets its fade; null for a colour that cannot fade.
  final void Function(GradientSpec? g, {required bool transient})? setGradient;

  const ColourSlot({
    required this.id,
    required this.label,
    required this.ring,
    required this.color,
    this.gradient,
    required this.setColour,
    this.setGradient,
    this.canBeNone = true,
  });
}

/// colourSlotsFor is the colours the Colour section offers: the selected
/// element's area and line or words colours, or the background's three when
/// nothing (or the background) is selected. None for several elements
/// selected together, which have no one colour to show.
List<ColourSlot> colourSlotsFor(CanvasController controller) {
  if (controller.selection.length > 1) return const [];
  var e = controller.selected;
  if (e == null) return _backgroundSlots(controller);

  // One of the element's colours: [withColour] is the element in another
  // colour (null for none), [withGradient] the element fading to another,
  // left out where that colour cannot fade.
  ColourSlot slot({
    required String id,
    required String label,
    required bool ring,
    required Color? color,
    required CanvasElement Function(Color? c) withColour,
    GradientSpec? gradient,
    CanvasElement Function(GradientSpec? g)? withGradient,
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
        setGradient: withGradient == null
            ? null
            : (g, {required transient}) => controller
                .replaceElement(withGradient(g), transient: transient),
      );

  switch (e) {
    // An empty drawing: the colours its shapes will be drawn in, by any
    // tool. A fade belongs to a shape, once there is one.
    case VectorElement v
        when (v.shapes ?? const []).isEmpty && v.assetId.isEmpty:
      return [
        ColourSlot(
          id: "fill",
          label: "Fill",
          ring: false,
          color: controller.vectorShapeFill,
          setColour: (c, {required transient}) {
            controller.vectorShapeFill = c;
            if (c != null) controller.vectorPencilFill = c;
          },
        ),
        ColourSlot(
          id: "line",
          label: "Line",
          ring: true,
          color: controller.vectorShapeLine,
          setColour: (c, {required transient}) {
            controller.vectorShapeLine = c;
            if (c != null) controller.vectorPencilColour = c;
          },
        ),
      ];
    case VectorElement v when (v.shapes ?? const []).isNotEmpty:
      var shapes = v.shapes!;
      // The shapes picked (with the select tool, or one shape), or every
      // shape, as the shape settings change them.
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
            id: "fill",
            label: "Fill",
            ring: false,
            color: first.fill,
            gradient: first.fillFade,
            withColour: (c) => each((s) =>
                c == null ? s.copyWith(clearFill: true) : s.copyWith(fill: c)),
            withGradient: (g) => each((s) => g == null
                ? s.copyWith(flatFill: true)
                : s.copyWith(fill: s.fill ?? g.to, fillFade: g))),
        slot(
            id: "line",
            label: "Line",
            ring: true,
            color: first.stroke,
            gradient: first.strokeFade,
            withColour: (c) => each((s) => c == null
                ? s.copyWith(clearStroke: true)
                : s.copyWith(
                    stroke: c, strokeWidth: s.strokeWidth > 0 ? null : 1)),
            withGradient: (g) => each((s) => g == null
                ? s.copyWith(flatStroke: true)
                : s.copyWith(
                    stroke: s.stroke ?? g.to,
                    strokeWidth: s.strokeWidth > 0 ? null : 1,
                    strokeFade: g))),
      ];
    // A drawing still as its file draws it: one tint over the whole of it
    // (see VectorElement.tint). None is the file's own colours.
    case VectorElement v:
      return [
        slot(
            id: "tint",
            label: "Tint",
            ring: false,
            color: v.tint,
            withColour: (c) =>
                c == null ? v.copyWith(clearTint: true) : v.copyWith(tint: c)),
      ];
    // A chart's colours are its series' (a pie's slices'), up to a row.
    case ChartElement c when c.type.isCircular:
      var slices = c.data.categories.length.clamp(0, 8);
      return [
        for (var i = 0; i < slices; i++)
          slot(
              id: "slice$i",
              label: c.data.categories[i].isEmpty
                  ? "${i + 1}"
                  : c.data.categories[i],
              ring: false,
              color: sliceColour(c, i),
              withColour: (x) => c.copyWith(sliceColors: [
                    for (var j = 0; j < c.data.categories.length; j++)
                      j == i ? (x ?? sliceColour(c, j)) : sliceColour(c, j),
                  ]),
              canBeNone: false),
      ];
    case ChartElement c:
      var series = c.data.series;
      return [
        for (var (i, one) in series.take(8).indexed)
          slot(
              id: "series$i",
              label: one.name.isEmpty ? "Series ${i + 1}" : one.name,
              ring: false,
              color: one.color,
              withColour: (x) => c.copyWith(
                      data: c.data.copyWith(series: [
                    for (var (j, s) in series.indexed)
                      j == i ? s.copyWith(color: x ?? s.color) : s,
                  ])),
              canBeNone: false),
      ];
    // A counter: its number, the words either side of it, and its box.
    case CounterElement n:
      return [
        slot(
            id: "number",
            label: "Number",
            ring: false,
            color: n.numberSpec.color,
            withColour: (x) => n.copyWith(
                numberSpec:
                    n.numberSpec.copyWith(color: x ?? n.numberSpec.color)),
            canBeNone: false),
        slot(
            id: "words",
            label: "Words",
            ring: false,
            color: n.affixSpec.color,
            withColour: (x) => n.copyWith(
                affixSpec: n.affixSpec.copyWith(color: x ?? n.affixSpec.color)),
            canBeNone: false),
        slot(
            id: "box",
            label: "Box",
            ring: false,
            color: n.box.fill.a == 0 ? null : n.box.fill,
            withColour: (x) => n.copyWith(
                box: n.box.copyWith(fill: x ?? const Color(0x00000000)))),
      ];
    // A table: its heading row's fill, and the words in it and below it.
    case TableElement t:
      return [
        slot(
            id: "header",
            label: "Heading",
            ring: false,
            color: t.headerFill,
            withColour: (x) =>
                t.copyWith(headerFill: x ?? const Color(0x00000000))),
        slot(
            id: "headerText",
            label: "Heading words",
            ring: false,
            color: t.headerSpec.color,
            withColour: (x) => t.copyWith(
                headerSpec:
                    t.headerSpec.copyWith(color: x ?? t.headerSpec.color)),
            canBeNone: false),
        slot(
            id: "cellText",
            label: "Words",
            ring: false,
            color: t.cellSpec.color,
            withColour: (x) => t.copyWith(
                cellSpec: t.cellSpec.copyWith(color: x ?? t.cellSpec.color)),
            canBeNone: false),
      ];
    case ShapeElement s:
      return [
        slot(
            id: "fill",
            label: "Fill",
            ring: false,
            color: s.fill.a == 0 ? null : s.fill,
            gradient: s.fillFade,
            withColour: (c) => s.copyWith(fill: c ?? const Color(0x00000000)),
            withGradient: (g) => g == null
                ? s.copyWith(flatFill: true)
                : s.copyWith(fillFade: g)),
        slot(
            id: "line",
            label: "Outline",
            ring: true,
            color: s.strokeWidth > 0 ? s.strokeColor : null,
            gradient: s.strokeFade,
            withColour: (c) => c == null
                ? s.copyWith(strokeWidth: 0)
                : s.copyWith(
                    strokeColor: c,
                    strokeWidth: s.strokeWidth > 0 ? null : strokeToSee(s)),
            withGradient: (g) => g == null
                ? s.copyWith(flatStroke: true)
                : s.copyWith(
                    strokeFade: g,
                    strokeWidth: s.strokeWidth > 0 ? null : strokeToSee(s))),
      ];
    case LineElement l:
      return [
        slot(
            id: "line",
            label: "Line",
            ring: true,
            color: l.color,
            gradient: l.fade,
            withColour: (c) => l.copyWith(color: c ?? l.color),
            withGradient: (g) =>
                g == null ? l.copyWith(flat: true) : l.copyWith(fade: g),
            canBeNone: false),
      ];
    case PathElement p:
      return [
        slot(
            id: "line",
            label: "Line",
            ring: true,
            color: p.color,
            gradient: p.fade,
            withColour: (c) => p.copyWith(color: c ?? p.color),
            withGradient: (g) =>
                g == null ? p.copyWith(flat: true) : p.copyWith(fade: g),
            canBeNone: false),
      ];
    case TextElement t:
      return [
        slot(
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
                    : t.box.copyWith(fillFade: g))),
        slot(
            id: "line",
            label: "Text",
            ring: true,
            color: t.textSpec.color,
            gradient: t.textSpec.fade,
            withColour: (c) => t.copyWith(
                textSpec: t.textSpec.copyWith(color: c ?? t.textSpec.color)),
            withGradient: (g) => t.copyWith(
                textSpec: g == null
                    ? t.textSpec.copyWith(flatText: true)
                    : t.textSpec.copyWith(fade: g)),
            canBeNone: false),
      ];
    case ButtonElement b:
      return [
        slot(
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
                    : b.box.copyWith(fillFade: g))),
        slot(
            id: "line",
            label: "Text",
            ring: true,
            color: b.textSpec.color,
            gradient: b.textSpec.fade,
            withColour: (c) => b.copyWith(
                textSpec: b.textSpec.copyWith(color: c ?? b.textSpec.color)),
            withGradient: (g) => b.copyWith(
                textSpec: g == null
                    ? b.textSpec.copyWith(flatText: true)
                    : b.textSpec.copyWith(fade: g)),
            canBeNone: false),
      ];
    default:
      return const [];
  }
}

/// _backgroundSlots is the background's base and its pattern's two colours.
List<ColourSlot> _backgroundSlots(CanvasController controller) {
  var bg = controller.document.editedBackground;
  var spec = bg.spec;
  // None is clear: the base shows through, and the pattern's colour drops.
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

  /// _settle makes a run of picker changes one undo step once it is still.
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

  /// _now makes [change] a change of its own: one undo step, however written.
  void _now(void Function() change) {
    _done();
    controller.beginInteraction();
    change();
    controller.endInteraction();
  }

  /// _canSwap is whether [a] and [b] can change colours: not when one has
  /// no colour and the other must have one (a text's words cannot take its
  /// box's "none").
  static bool _canSwap(ColourSlot a, ColourSlot b) =>
      (b.color != null || a.canBeNone) && (a.color != null || b.canBeNone);

  /// _slot is slot [id] as it is now, after whatever was just written.
  ColourSlot? _slot(String id) =>
      colourSlotsFor(controller).where((s) => s.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) => CanvasWatch<int>(
        // Every change but the view's and frames of play (revision): neither
        // changes what this shows.
        listenable: controller,
        select: () => controller.revision,
        builder: (context, _) {
          var slots = colourSlotsFor(controller);
          if (slots.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                  controller.selection.length > 1
                      ? "Each one's colours are in its settings."
                      : "Its colours are in its settings.",
                  style: Theme.of(context).textTheme.bodySmall),
            );
          }
          var active = slots.firstWhere((s) => s.id == _active,
              orElse: () => slots.first);
          var owner = controller.selected?.id ?? "background";
          // With two colours, the other one, to swap with.
          var other =
              slots.length == 2 ? slots.firstWhere((s) => s != active) : null;
          // The swatches, then the eyedropper and the colour it last took.
          var leading = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Swatches(
                slots: slots,
                active: active,
                onPick: (s) => setState(() => _active = s.id),
                swaps: other != null,
                onSwap: other == null || !_canSwap(active, other)
                    ? null
                    : () {
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
                // colour there for the chosen slot. Drawn small, not as an
                // IconButton, which keeps a 40px square whatever it is told.
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
                      // Drawn: the icon font's stroke is heavier.
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
          // Scrolled where short of room, with no bar, as the column is.
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
                      // Offered only for a colour that can fade.
                      onGradientChanged: switch (active.setGradient) {
                        var set? => (g) =>
                            _write(() => set(g, transient: true)),
                        null => null,
                      },
                      // A saved colour replaced everywhere: replaceColour.
                      onReplaceEverywhere: (from, to) {
                        _done();
                        controller.replaceColour(from, to);
                      },
                    ),
                  ),
                ),
              ));
        },
      );
}

/// _Swatches is the colours, each offset down and right from the one
/// before, the chosen one on top; pressing a swatch chooses it. Beside two,
/// arrows that swap them; below, a swatch that sets the chosen one to none.
class _Swatches extends StatelessWidget {
  final List<ColourSlot> slots;
  final ColourSlot active;
  final ValueChanged<ColourSlot> onPick;

  /// swaps is whether the arrows are drawn (there are two colours); onSwap
  /// is null while those two cannot change places, and the arrows are faint.
  final bool swaps;
  final VoidCallback? onSwap;
  final VoidCallback? onNone;

  const _Swatches(
      {required this.slots,
      required this.active,
      required this.onPick,
      required this.swaps,
      required this.onSwap,
      required this.onNone});

  /// _size is a swatch's, and _step how far each sits from the one before.
  static const double _size = 28;
  static const Offset _step = Offset(13, 11);

  @override
  Widget build(BuildContext context) {
    var outline = Theme.of(context).colorScheme.outline;
    // Clipped round, outermost (around the tooltip too), so the pointer
    // meets the circle the eye sees: the one in front overlaps the others.
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
      width: span + (swaps ? 17 : 2),
      height: tall + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var (i, s) in order)
          Positioned(left: _step.dx * i, top: _step.dy * i, child: swatch(s)),
        if (swaps)
          Positioned(
            left: span + 2,
            top: 0,
            child: InkWell(
              key: const ValueKey("colourSwap"),
              onTap: onSwap,
              child: Tooltip(
                message: "Swap",
                child: Icon(Icons.swap_horiz,
                    size: 14,
                    color: onSwap == null
                        ? outline.withValues(alpha: 0.35)
                        : outline),
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

/// _SwatchPainter draws a colour as a disc (a line's as a thick ring), white
/// slashed where it is none, the chosen one brighter edged.
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
