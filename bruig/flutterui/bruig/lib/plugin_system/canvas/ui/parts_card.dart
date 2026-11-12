import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/ui/preset_pair.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart'
    show vectorDrawn;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_layer_settings.dart'
    show staggerLayers;
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart'
    show groupStarts, withCue, withStagger;
import 'package:flutter/material.dart';

// parts_card.dart is the parts of an element that come in each in their
// own time -- a picture's layers, a drawing's shapes -- in its motion chain
// (Ken, 2026-11-08: what the sidebar's Animation sections had, in the
// chain). A list of them, the one picked set: when it comes in against the
// one before it, and what it does of its own -- a shape's own arrival, a
// layer's own loop; and for every part at once, one after another or all
// together.

/// PartsCard is [element]'s parts, when it has more than one.
class PartsCard extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const PartsCard(
      {required this.controller,
      required this.element,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  /// shows is whether [e] has parts of its own to time: two layers or
  /// more, or two shapes or more.
  static bool shows(CanvasElement e) => switch (e) {
        ImageElement i => i.stack.length > 1,
        VectorElement v => vectorDrawn(v.shapes ?? const []).length > 1,
        _ => false,
      };

  @override
  State<PartsCard> createState() => _PartsCardState();
}

/// _Part is one part as the card lists it.
typedef _Part = ({
  String name,
  VectorCue cue,
  int gap,
  bool own,
});

class _PartsCardState extends State<PartsCard> {
  int _picked = 1;

  CanvasController get c => widget.controller;

  List<_Part> _parts() => switch (widget.element) {
        ImageElement i => [
            for (var (n, l) in i.stack.indexed)
              (
                name: l.name.isEmpty ? "Layer ${n + 1}" : l.name,
                cue: l.cue,
                gap: l.cueGap,
                own: l.loop.on,
              ),
          ],
        VectorElement v => [
            for (var (n, d) in vectorDrawn(v.shapes ?? const []).indexed)
              (
                name: "Shape ${n + 1}",
                cue: d.style.cue,
                gap: d.style.cueGap,
                own: d.style.animation != null,
              ),
          ],
        _ => const [],
      };

  void _write(CanvasElement next, {bool transient = false}) {
    c.beginInteraction();
    c.replaceElement(next, transient: true);
    if (!transient) c.endInteraction();
  }

  /// _withCue is the element with part [at] coming in by [cue] after
  /// [gap] frames.
  CanvasElement _withCue(int at, {VectorCue? cue, int? gap}) =>
      switch (widget.element) {
        ImageElement i =>
          i.withLayer(i.stack[at].id, (l) => l.copyWith(cue: cue, cueGap: gap)),
        VectorElement v => withCue(v, at, cue: cue, gap: gap),
        var e => e,
      };

  void _stagger() {
    switch (widget.element) {
      case ImageElement i:
        staggerLayers(c, i);
      case VectorElement v:
        c.beginInteraction();
        c.replaceElement(withStagger(v, c.defaultAnimationFrames),
            transient: true);
        c.endInteraction();
      default:
    }
  }

  void _together() {
    switch (widget.element) {
      case ImageElement i:
        _write(withLayersTogether(i));
      case VectorElement v:
        var next = v;
        for (var g = 1; g < groupStarts(v).length; g++) {
          next = withCue(next, g, cue: VectorCue.together, gap: 0);
        }
        _write(next);
      default:
    }
  }

  /// _resetAll lets every part go of what it did of its own: each shape
  /// back to the drawing's animation, each layer's loop off.
  void _resetAll() {
    switch (widget.element) {
      case ImageElement i:
        var next = i;
        for (var l in i.stack) {
          if (l.loop.on) {
            next = next.withLayer(
                l.id,
                (x) =>
                    x.copyWith(loop: x.loop.copyWith(preset: LoopPreset.none)));
          }
        }
        _write(next);
      case VectorElement v:
        _write(v.copyWith(shapes: [
          for (var s in v.shapes ?? const <VectorShape>[])
            s.copyWith(clearAnimation: true),
        ]));
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var skin = DeviceSkin.studio(s);
    var parts = _parts();
    var at = math.max(0, math.min(_picked, parts.length - 1));
    var part = parts.isEmpty ? null : parts[at];
    var rate = math.max(1, c.document.frameRate);
    const accent = Color(0xFF3FB08D);
    var e = widget.element;
    var image = e is ImageElement;
    var noun = image ? "layer" : "shape";

    List<Widget> controls(DeviceTier tier) => [
          if (part != null)
            DevicePack(key: const ValueKey("partsPack"), children: [
              // The first comes in as the element arrives: no cue of its own.
              if (at > 0) ...[
                StudioDrop<VectorCue>(
                  key: const ValueKey("partCue"),
                  label: "Comes in",
                  value: part.cue,
                  options: [for (var q in VectorCue.values) (q, q.label)],
                  onChanged: (q) => _write(_withCue(at, cue: q)),
                ),
                if (part.cue == VectorCue.gap)
                  DeviceKnob(
                    key: const ValueKey("partGap"),
                    label: "Gap",
                    text: "${(part.gap / rate).toStringAsFixed(2)}s",
                    value: (part.gap / rate).clamp(-10.0, 10.0),
                    initial: 0.5,
                    min: -10,
                    max: 10,
                    bipolar: true,
                    accent: accent,
                    ink: skin.ink,
                    onChanged: (v, {transient = false}) => _write(
                        _withCue(at, gap: (v * rate).round()),
                        transient: transient),
                    onCommit: c.endInteraction,
                  ),
              ],
              // A shape's own arrival; a layer's own loop.
              if (e is VectorElement) ..._shapeArrival(e, at),
              if (e is ImageElement) ..._layerLoop(e, at, accent, skin.ink),
            ]),
          PackWide(Wrap(spacing: 5, runSpacing: 5, children: [
            _Chip(
                key: const ValueKey("partsStagger"),
                label: "One after another",
                onTap: _stagger),
            _Chip(
                key: const ValueKey("partsTogether"),
                label: "All together",
                onTap: _together),
            if (parts.any((x) => x.own))
              _Chip(
                  key: const ValueKey("partsResetAll"),
                  label: "Reset all",
                  onTap: _resetAll),
          ])),
        ];

    return DeviceFrame(
      id: "parts",
      title: image ? "Layers" : "Shapes",
      help: "The ${noun}s of it, each in its own time: when the picked one "
          "comes in against the one before it, and what it does of its own. "
          "One after another or All together sets every one at once.",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 440 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
      height: widget.height,
      icon: image ? Icons.layers_outlined : Icons.category_outlined,
      accent: accent,
      displayBeside: true,
      besideDisplay: 180,
      besideSettings: 260,
      summary: "${parts.length} ${noun}s",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: controls,
      display: Container(
        color: s.display,
        child: ListView.builder(
          itemCount: parts.length,
          itemExtent: 22,
          itemBuilder: (context, n) {
            var p = parts[n];
            return Material(
              color:
                  n == at ? accent.withValues(alpha: 0.22) : Colors.transparent,
              child: InkWell(
                key: ValueKey("partRow-$n"),
                onTap: () => setState(() => _picked = n),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Row(children: [
                    Expanded(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: s.text)),
                    ),
                    Text(
                        n == 0
                            ? "first"
                            : p.cue == VectorCue.gap
                                ? "+${(p.gap / rate).toStringAsFixed(1)}s"
                                : p.cue == VectorCue.together
                                    ? "with"
                                    : "after",
                        style: TextStyle(fontSize: 10, color: s.muted)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 8,
                      child: p.own
                          ? Container(
                              key: ValueKey("partOwn-$n"),
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: ownColour, shape: BoxShape.circle),
                            )
                          : null,
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// _shapeArrival is shape group [at]'s own arrival: the drawing's, or one
  /// of its own.
  List<Widget> _shapeArrival(VectorElement e, int at) {
    var starts = groupStarts(e);
    var base = at < starts.length ? starts[at] : 0;
    var shape = e.shapes![base];
    var own = shape.animation;
    // Its family, then which of them (Ken, 2026-11-12).
    return studioPresetPair<ElementAnimationPreset?>(
      key: "partArrival",
      familyLabel: "Arrives",
      noneLabel: "As the drawing",
      pair: PresetPair([
        for (var o in elementPresetOptions())
          PresetOption<ElementAnimationPreset?>(o.value, o.label, o.family),
      ], own?.preset, null),
      onChanged: (p) => _write(e.withShape(
          base,
          p == null
              ? shape.copyWith(clearAnimation: true)
              : shape.copyWith(
                  animation: (own ?? e.animation)
                      .copyWith(preset: p, ease: p.wants, effect: p.effect),
                  owns: {...shape.owns, ShapeAnimationPart.arriving}))),
    );
  }

  /// _layerLoop is layer [at]'s own loop: which, and how long round.
  List<Widget> _layerLoop(ImageElement e, int at, Color accent, Color ink) {
    var layer = e.stack[at];
    var loop = layer.loop;
    var rate = math.max(1, c.document.frameRate);
    CanvasElement withLoop(ElementLoop l) =>
        e.withLayer(layer.id, (x) => x.copyWith(loop: l));
    return [
      ...studioPresetPair<LoopPreset>(
        key: "partLoop",
        familyLabel: "Loops",
        noneLabel: "No",
        pair: PresetPair(loopPresetOptions(), loop.preset, LoopPreset.none),
        onChanged: (p) => _write(withLoop(loop.copyWith(preset: p))),
      ),
      if (loop.on) ...[
        DeviceKnob(
          key: const ValueKey("partLoopCycle"),
          label: "Once round",
          text: "${(loop.cycle / rate).toStringAsFixed(2)}s",
          value: (loop.cycle / rate).clamp(1 / rate, 20.0),
          initial: 1,
          min: 1 / rate,
          max: 20,
          log: true,
          accent: accent,
          ink: ink,
          onChanged: (v, {transient = false}) => _write(
              withLoop(loop.copyWith(cycle: math.max(1, (v * rate).round()))),
              transient: transient),
          onCommit: c.endInteraction,
        ),
        DeviceKnob(
          key: const ValueKey("partLoopStrength"),
          label: "Strength",
          text: "${(loop.strength * 100).round()}%",
          value: loop.strength.clamp(0.0, 3.0),
          initial: 1,
          min: 0,
          max: 3,
          accent: accent,
          ink: ink,
          onChanged: (v, {transient = false}) => _write(
              withLoop(loop.copyWith(strength: v)),
              transient: transient),
          onCommit: c.endInteraction,
        ),
      ],
    ];
  }
}

/// _Chip is a small button of the card.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Material(
      color: s.raised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: s.edge)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: TextStyle(fontSize: 10.5, color: s.text)),
        ),
      ),
    );
  }
}
