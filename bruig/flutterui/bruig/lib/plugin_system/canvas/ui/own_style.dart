import 'dart:math' as math;

import 'package:bruig/components/paint_spec.dart' show PaintSpec;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart'
    show MotionPhase;
import 'package:bruig/plugin_system/canvas/model/own_motion.dart'
    show ownClipOf;
import 'package:bruig/plugin_system/canvas/ui/keys_strip.dart' show phaseColour;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// own_style.dart is an element's own ways to arrive, leave and loop in its
// motion chain (Ken, 2026-11-08: everything the sidebar's Animation
// sections had, in the chain, before those sections go). One adapter over
// the three kinds of own animation -- a box's (ElementAnimation), the words'
// (TextAnimation) and a chart's (ChartAnimation) -- for the Motion clips
// card's Preset, and the "Its own style" card that holds the rest: the
// curve, where a growing one starts, the gap between pieces, their order,
// how a cut cuts, a text's mark and copies, and the loop's every setting.

enum OwnStyleKind { element, text, chart }

/// OwnStyle is [element]'s own animation, whichever kind it has, read and
/// written alike.
class OwnStyle {
  final CanvasElement element;
  const OwnStyle(this.element);

  /// of is [e]'s, or null where it has no own animation.
  static OwnStyle? of(CanvasElement e) =>
      e is TextElement || e is ChartElement || CanvasController.animates(e)
          ? OwnStyle(e)
          : null;

  OwnStyleKind get kind => switch (element) {
        TextElement _ => OwnStyleKind.text,
        ChartElement _ => OwnStyleKind.chart,
        _ => OwnStyleKind.element,
      };

  ElementAnimation get _box => CanvasController.elementAnimationOf(element);
  TextAnimation get _text => (element as TextElement).animation;
  ChartAnimation get _chart => (element as ChartElement).animation;

  CanvasElement _withBox(ElementAnimation a) =>
      CanvasController.withElementAnimation(element, a);
  CanvasElement _withText(TextAnimation a) =>
      (element as TextElement).copyWith(animation: a);
  CanvasElement _withChart(ChartAnimation a) =>
      (element as ChartElement).copyWith(animation: a);

  /// presets are the ways it can arrive (or, [leaving], leave), by name.
  List<(String, String)> presets({bool leaving = false}) => switch (kind) {
        OwnStyleKind.element => [
            for (var p in ElementAnimationPreset.values)
              if (p != ElementAnimationPreset.none) (p.name, p.label)
          ],
        OwnStyleKind.text => [
            for (var p in TextAnimationPreset.values)
              if (p != TextAnimationPreset.none) (p.name, p.label)
          ],
        OwnStyleKind.chart => [
            for (var p in ChartAnimationPreset.values)
              if (p != ChartAnimationPreset.none &&
                  ((element as ChartElement).type.isCircular
                      ? p.suitsCircular
                      : p.suitsCartesian))
                (p.name, p.label)
          ],
      };

  /// preset is the name of the way it arrives (or leaves).
  String preset({bool leaving = false}) => switch (kind) {
        OwnStyleKind.element => (leaving ? _box.exit : _box.preset).name,
        OwnStyleKind.text => (leaving ? _text.exit : _text.preset).name,
        OwnStyleKind.chart => (leaving ? _chart.exit : _chart.preset).name,
      };

  String labelOf(String name) =>
      presets().where((p) => p.$1 == name).firstOrNull?.$2 ?? name;

  /// withPreset is it arriving (or leaving) [name]: a new arrival with the
  /// curve and cut it was made for, as the sidebar's applied it.
  CanvasElement withPreset(String name, {bool leaving = false}) {
    switch (kind) {
      case OwnStyleKind.element:
        var p = ElementAnimationPreset.values.byName(name);
        var a = _box;
        if (leaving) return _withBox(a.copyWith(exit: p));
        var changing = p != a.preset;
        return _withBox(a.copyWith(
            preset: p,
            ease: changing ? p.wants : null,
            effect: changing ? p.effect : null));
      case OwnStyleKind.text:
        var p = TextAnimationPreset.values.byName(name);
        var a = _text;
        if (leaving) return _withText(a.copyWith(exit: p));
        var changing = p != a.preset;
        return _withText(a.copyWith(
            preset: p,
            ease: changing ? p.wants : null,
            effect: changing ? p.effect : null));
      case OwnStyleKind.chart:
        var p = ChartAnimationPreset.values.byName(name);
        var a = _chart;
        return _withChart(
            leaving ? a.copyWith(exit: p) : a.copyWith(preset: p));
    }
  }

  ChartEase get ease => switch (kind) {
        OwnStyleKind.element => _box.ease,
        OwnStyleKind.text => _text.ease,
        OwnStyleKind.chart => _chart.ease,
      };

  CanvasElement withEase(ChartEase e) => switch (kind) {
        OwnStyleKind.element => _withBox(_box.copyWith(ease: e)),
        OwnStyleKind.text => _withText(_text.copyWith(ease: e)),
        OwnStyleKind.chart => _withChart(_chart.copyWith(ease: e)),
      };

  /// scale is where a growing arrival starts from -- the preset's own, as
  /// it plays, where none is set -- or null where nothing grows.
  double? get scale => switch (kind) {
        OwnStyleKind.element => _box.scales ? _box.scaleFor(_box.preset) : null,
        OwnStyleKind.text => _text.scales ? _text.scaleFor(_text.preset) : null,
        OwnStyleKind.chart => null,
      };

  CanvasElement withScale(double v) => switch (kind) {
        OwnStyleKind.element => _withBox(_box.copyWith(scale: v)),
        OwnStyleKind.text => _withText(_text.copyWith(scale: v)),
        OwnStyleKind.chart => element,
      };

  /// piecesInTurn is whether a text's pieces (see TextItem) come in one
  /// after another rather than together; null where it has none.
  bool? get piecesInTurn =>
      kind == OwnStyleKind.text && (element as TextElement).items.isNotEmpty
          ? _text.piecesInTurn
          : null;
  CanvasElement withPiecesInTurn(bool v) =>
      _withText(_text.copyWith(piecesInTurn: v));

  /// piecesGap is how far through one layer the next starts, where they
  /// come in turn.
  double? get piecesGap => piecesInTurn == true ? _text.piecesGap : null;
  CanvasElement withPiecesGap(double v) =>
      _withText(_text.copyWith(piecesGap: v));

  /// gap is how long after one piece -- a word, a bar -- the next starts,
  /// as a share of one's own movement; null for a box.
  double? get gap => switch (kind) {
        OwnStyleKind.element => null,
        OwnStyleKind.text => _text.gap,
        OwnStyleKind.chart => _chart.gap,
      };

  CanvasElement withGap(double v) => switch (kind) {
        OwnStyleKind.element => element,
        OwnStyleKind.text => _withText(_text.copyWith(gap: v)),
        OwnStyleKind.chart => _withChart(_chart.copyWith(gap: v)),
      };

  /// flipped is whether the pieces come last first; null for a box.
  bool? get flipped => switch (kind) {
        OwnStyleKind.element => null,
        OwnStyleKind.text => _text.flipOrder,
        OwnStyleKind.chart => _chart.flipOrder,
      };

  CanvasElement withFlipped(bool v) => switch (kind) {
        OwnStyleKind.element => element,
        OwnStyleKind.text => _withText(_text.copyWith(flipOrder: v)),
        OwnStyleKind.chart => _withChart(_chart.copyWith(flipOrder: v)),
      };

  /// inOrder is whether the pieces leave in the order they came; null for
  /// a box.
  bool? get inOrder => switch (kind) {
        OwnStyleKind.element => null,
        OwnStyleKind.text => _text.exitInOrder,
        OwnStyleKind.chart => _chart.exitInOrder,
      };

  CanvasElement withInOrder(bool v) => switch (kind) {
        OwnStyleKind.element => element,
        OwnStyleKind.text => _withText(_text.copyWith(exitInOrder: v)),
        OwnStyleKind.chart => _withChart(_chart.copyWith(exitInOrder: v)),
      };

  /// effect is how a cutting preset cuts, or null where none cuts.
  EffectSpec? get effect => switch (kind) {
        OwnStyleKind.element => _box.cuts ? _box.effect : null,
        OwnStyleKind.text => _text.cuts ? _text.effect : null,
        OwnStyleKind.chart => null,
      };

  CanvasElement withEffect(EffectSpec v) => switch (kind) {
        OwnStyleKind.element => _withBox(_box.copyWith(effect: v)),
        OwnStyleKind.text => _withText(_text.copyWith(effect: v)),
        OwnStyleKind.chart => element,
      };

  /// draw and echo are a text's mark and copies, where its preset has them.
  TextDrawSpec? get draw =>
      kind == OwnStyleKind.text && _text.draws ? _text.draw : null;
  TextEchoSpec? get echo =>
      kind == OwnStyleKind.text && _text.echoes ? _text.echo : null;

  CanvasElement withDraw(TextDrawSpec v) =>
      kind == OwnStyleKind.text ? _withText(_text.copyWith(draw: v)) : element;
  CanvasElement withEcho(TextEchoSpec v) =>
      kind == OwnStyleKind.text ? _withText(_text.copyWith(echo: v)) : element;

  /// direction and strength are where it comes from and how far, for the
  /// box's and the words' arrivals ([leaving], their ways out).
  bool get directed => kind != OwnStyleKind.chart;

  double strength({bool leaving = false}) => switch (kind) {
        OwnStyleKind.element => leaving ? _box.exitStrength : _box.strength,
        OwnStyleKind.text => leaving ? _text.exitStrength : _text.strength,
        OwnStyleKind.chart => 1,
      };

  CanvasElement withStrength(double v, {bool leaving = false}) =>
      switch (kind) {
        OwnStyleKind.element => _withBox(leaving
            ? _box.copyWith(exitStrength: v)
            : _box.copyWith(strength: v)),
        OwnStyleKind.text => _withText(leaving
            ? _text.copyWith(exitStrength: v)
            : _text.copyWith(strength: v)),
        OwnStyleKind.chart => element,
      };

  ElementLoop get loop => CanvasController.elementLoopOf(element);

  CanvasElement withLoop(ElementLoop v) => switch (kind) {
        OwnStyleKind.element => _withBox(_box.copyWith(loop: v)),
        OwnStyleKind.text => _withText(_text.copyWith(loop: v)),
        OwnStyleKind.chart => _withChart(_chart.copyWith(loop: v)),
      };
}

/// ownKinds are the element's own ways in, round and out, as the Motion
/// clips card's tabs have them.
const ownKinds = [MotionKind.arrive, MotionKind.loop, MotionKind.leave];

/// ownColour is what an own arrival, loop or leaving is drawn in: the Keys
/// strip's, the Chain's group, the tab.
Color ownKindColour(MotionKind kind) => phaseColour(switch (kind) {
      MotionKind.arrive => MotionPhase.arrive,
      MotionKind.leave => MotionPhase.leave,
      MotionKind.loop => MotionPhase.loop,
      _ => MotionPhase.free,
    });

/// OwnTabs is the Motion clips card's choice of the element's own arrival,
/// loop and leaving (Ken, 2026-11-12: "toggle between the 3 presets"):
/// each tab says its preset, or None; picked, the Chain shows it.
extension OwnTabs on CanvasController {
  /// ownTabOf is the tab the Chain shows for [e]: one picked, the own clip
  /// picked, or -- nothing yet -- its arrival; null for a clip of its own
  /// making, or an element with no own animation.
  MotionKind? ownTabOf(CanvasElement e) {
    if (OwnStyle.of(e) == null) return null;
    if (ownTab case var k?) return k;
    var m = e.base.motion;
    var id = pickedMotion ??
        [
          for (var s in m.slots)
            if (s.isNotEmpty) s,
          for (var p in m.placed) p.clip,
        ].firstOrNull;
    var c = id == null ? null : m.clip(id);
    if (c == null) return MotionKind.arrive;
    if (c.inside["own"] == true &&
        (c.kind == MotionKind.arrive || c.kind == MotionKind.leave)) {
      return c.kind;
    }
    return null;
  }

  /// ownTabOpen is whether [e]'s tab has no clip to show: not set up yet,
  /// or its loop, which plays without one.
  bool ownTabOpen(CanvasElement e) {
    var k = ownTabOf(e);
    return k != null && (k == MotionKind.loop || ownAnyOf(e, k) == null);
  }

  /// ownAnyOf is [e]'s own [kind] clip: on the timeline, else in a slot.
  MotionClip? ownAnyOf(CanvasElement e, MotionKind kind) {
    if (ownClipOf(e, kind) case (var c, _)) return c;
    return e.base.motion.clips
        .where((c) => c.kind == kind && c.inside["own"] == true)
        .firstOrNull;
  }

  /// ownPresetOf is the name of [e]'s own [kind] -- "" for none.
  String ownPresetOf(CanvasElement e, MotionKind kind) {
    var style = OwnStyle.of(e);
    if (style == null) return "";
    if (kind == MotionKind.loop) {
      return style.loop.on ? style.loop.preset.name : "";
    }
    if (ownAnyOf(e, kind) == null) return "";
    var name = style.preset(leaving: kind == MotionKind.leave);
    return name == "none" ? "" : name;
  }

  /// ownPresetLabel is it as the tab says it.
  String ownPresetLabel(CanvasElement e, MotionKind kind) {
    var name = ownPresetOf(e, kind);
    if (name.isEmpty) return "None";
    if (kind == MotionKind.loop) return LoopPreset.values.byName(name).label;
    return OwnStyle(e).labelOf(name);
  }

  /// ownPresetChoices are [kind]'s presets for [e], by name.
  List<(String, String)> ownPresetChoices(CanvasElement e, MotionKind kind) =>
      kind == MotionKind.loop
          ? [
              for (var p in LoopPreset.values)
                if (p != LoopPreset.none) (p.name, p.label)
            ]
          : OwnStyle(e).presets(leaving: kind == MotionKind.leave);

  /// showOwnTab picks [e]'s own [kind] in the Chain: its clip, where it has
  /// one, else the tab, to set it up.
  void showOwnTab(String element, MotionKind kind) {
    var e = document.elementById(element);
    if (e == null) return;
    if (kind != MotionKind.loop) {
      if (ownClipOf(e, kind) case (var c, var p)) {
        pickMotion(element, c.id, placement: p.id);
        return;
      }
      if (ownAnyOf(e, kind) case var c?) {
        pickMotion(element, c.id);
        return;
      }
    }
    ownTab = kind;
  }

  /// setOwnPreset makes [element]'s own [kind] preset [name], laid down
  /// as the settings panel lays it, or ("") takes it away; the Chain then
  /// shows it.
  void setOwnPreset(String element, MotionKind kind, String name) {
    var e = document.elementById(element);
    if (e == null) return;
    if (kind == MotionKind.loop) {
      var style = OwnStyle(e);
      beginInteraction();
      replaceElement(style.withLoop(style.loop.copyWith(
          preset: name.isEmpty
              ? LoopPreset.none
              : LoopPreset.values.byName(name))));
      endInteraction();
      ownTab = MotionKind.loop;
      return;
    }
    var leaving = kind == MotionKind.leave;
    var n = name.isEmpty ? "none" : name;
    switch (e) {
      case TextElement t:
        var p = TextAnimationPreset.values.byName(n);
        leaving ? applyTextExit(t, p) : applyTextAnimation(t, p);
      case ChartElement ch:
        var p = ChartAnimationPreset.values.byName(n);
        leaving ? applyChartExit(ch, p) : applyChartAnimation(ch, p);
      default:
        var p = ElementAnimationPreset.values.byName(n);
        leaving ? applyElementExit(e, p) : applyElementAnimation(e, p);
    }
    // Taken away: its tab stays, saying None.
    if (name.isEmpty) ownTab = kind;
  }
}

/// OwnTabsRow is the tabs, and -- where the tab picked has nothing yet, or
/// is the loop -- its Preset to set it up.
class OwnTabsRow extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  const OwnTabsRow(
      {required this.controller, required this.element, super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var e = element;
    var studio = MixerLook.of(context).studio;
    var on = c.ownTabOf(e);
    Widget tab(MotionKind kind) {
      var colour = ownKindColour(kind);
      var picked = on == kind;
      var label = c.ownPresetLabel(e, kind);
      var none = label == "None";
      return Expanded(
        child: Semantics(
          button: true,
          selected: picked,
          child: GestureDetector(
            key: ValueKey("ownTab-${kind.name}"),
            behavior: HitTestBehavior.opaque,
            onTap: () => c.showOwnTab(e.id, kind),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: picked ? colour.withValues(alpha: 0.16) : studio.inset,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: picked ? colour : studio.edge,
                    width: picked ? 1.5 : 1),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        switch (kind) {
                          MotionKind.arrive => "ARRIVE",
                          MotionKind.leave => "LEAVE",
                          _ => "LOOP",
                        },
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: colour)),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: none ? studio.muted : studio.text)),
                  ]),
            ),
          ),
        ),
      );
    }

    var open = on != null && c.ownTabOpen(e);
    return Column(
        key: const ValueKey("ownTabs"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            for (var (i, k) in ownKinds.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              tab(k),
            ],
          ]),
          if (open) ...[
            const SizedBox(height: 8),
            StudioDrop<String>(
              key: const ValueKey("ownTabPreset"),
              label: "Preset",
              value: c.ownPresetOf(e, on),
              width: double.infinity,
              options: [
                ("", "None"),
                ...c.ownPresetChoices(e, on),
              ],
              onChanged: (name) => c.setOwnPreset(e.id, on, name),
            ),
          ],
        ]);
  }
}

/// OwnStyleCard is the rest of [clip]'s own style, beside its Motion clips
/// card: for an arrival or a way out of the element's own, how it moves;
/// for a loop, the loop's every setting.
class OwnStyleCard extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip clip;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const OwnStyleCard(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  /// shows is whether [clip] of [e] has an own style to set out: an own
  /// arrival or way out, or a loop the element can play.
  static bool shows(CanvasElement e, MotionClip clip) {
    var style = OwnStyle.of(e);
    if (style == null) return false;
    var own = clip.inside["own"] == true;
    if (own &&
        (clip.kind == MotionKind.arrive || clip.kind == MotionKind.leave)) {
      return true;
    }
    return clip.kind == MotionKind.loop && style.loop.on;
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var c = controller;
    var style = OwnStyle(element);
    var leaving = clip.kind == MotionKind.leave;
    var looping = clip.kind == MotionKind.loop;
    const accent = Color(0xFF3FB08D);
    var rate = math.max(1, c.document.frameRate);
    void write(CanvasElement next, {bool transient = false}) {
      c.beginInteraction();
      c.replaceElement(next, transient: true);
      if (!transient) c.endInteraction();
    }

    DeviceKnob knob(
            String key,
            String label,
            String text,
            double value,
            double min,
            double max,
            double initial,
            CanvasElement Function(double v) set,
            {bool bipolar = false,
            bool log = false}) =>
        DeviceKnob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value.clamp(min, max),
          initial: initial,
          min: min,
          max: max,
          log: log,
          bipolar: bipolar,
          accent: accent,
          ink: skin.ink,
          onChanged: (v, {transient = false}) =>
              write(set(v), transient: transient),
          onCommit: c.endInteraction,
        );
    String pct(double v) => "${(v * 100).round()}%";

    List<Widget> moveControls() {
      var effect = style.effect;
      var draw = style.draw;
      var echo = style.echo;
      return [
        StudioDrop<ChartEase>(
          key: const ValueKey("ownEase"),
          label: "Curve",
          value: style.ease,
          options: [for (var e in ChartEase.values) (e, e.label)],
          onChanged: (e) => write(style.withEase(e)),
        ),
        if (style.directed)
          knob(
              "ownStyleStrength",
              "How far",
              pct(style.strength(leaving: leaving)),
              style.strength(leaving: leaving),
              0.25,
              3,
              1,
              (v) => style.withStrength(v, leaving: leaving)),
        if (style.scale case var scale?)
          knob(
              "ownScale",
              "From size",
              "${scale.toStringAsFixed(2)}×",
              scale,
              0.05,
              4,
              1,
              (v) => style.withScale((v * 100).roundToDouble() / 100),
              log: true),
        if (style.gap case var gap?)
          knob("ownGap", "Gap", "${(gap * 100).round()}%", gap, 0, 2, 0.5,
              (v) => style.withGap((v * 100).roundToDouble() / 100)),
        // A text's pieces: with the words, or each after the one before.
        if (style.piecesInTurn case var inTurn?)
          StudioDrop<bool>(
            key: const ValueKey("ownPiecesOrder"),
            label: "Its pieces",
            value: inTurn,
            options: const [(false, "Together"), (true, "One after another")],
            onChanged: (v) => write(style.withPiecesInTurn(v)),
          ),
        if (style.piecesGap case var g?)
          knob("ownPiecesGap", "Next starts", pct(g), g, 0, 1, 0.5,
              (v) => style.withPiecesGap((v * 100).roundToDouble() / 100)),
        if (style.flipped case var flipped?)
          StudioDrop<bool>(
            key: const ValueKey("ownOrder"),
            label: "Order",
            value: flipped,
            options: const [(false, "First to last"), (true, "Last to first")],
            onChanged: (v) => write(style.withFlipped(v)),
          ),
        if (leaving)
          if (style.inOrder case var inOrder?)
            StudioDrop<bool>(
              key: const ValueKey("ownInOrder"),
              label: "Leaves",
              value: inOrder,
              options: const [
                (true, "In the order it came"),
                (false, "The other way round"),
              ],
              onChanged: (v) => write(style.withInOrder(v)),
            ),
        // How a cutting one cuts.
        if (effect != null) ...[
          knob(
              "ownPieces",
              "Pieces",
              "${effect.pieces}",
              effect.pieces.toDouble(),
              2,
              40,
              10,
              (v) => style.withEffect(effect.copyWith(pieces: v.round()))),
          knob("ownScatter", "Scatter", pct(effect.scatter), effect.scatter, 0,
              2, 0.3, (v) => style.withEffect(effect.copyWith(scatter: v))),
          knob("ownSpin", "Spin", pct(effect.spin), effect.spin, 0, 1, 0,
              (v) => style.withEffect(effect.copyWith(spin: v))),
          knob("ownStagger", "Stagger", pct(effect.stagger), effect.stagger, 0,
              1, 0.5, (v) => style.withEffect(effect.copyWith(stagger: v))),
          StudioDrop<int>(
            key: const ValueKey("ownSeed"),
            label: "Pattern",
            value: effect.seed,
            options: [
              for (var i = 1; i <= math.max(8, effect.seed); i++)
                (i, "Pattern $i")
            ],
            onChanged: (v) => write(style.withEffect(effect.copyWith(seed: v))),
          ),
        ],
        // A text's mark: what is drawn, round it, and what the words do.
        if (draw != null) ...[
          StudioDrop<TextDrawStart>(
            key: const ValueKey("ownDrawStart"),
            label: "The words",
            value: draw.start,
            options: [for (var s in TextDrawStart.values) (s, s.label)],
            onChanged: (v) => write(style.withDraw(draw.copyWith(start: v))),
          ),
          knob(
              "ownDrawPad",
              "Padding",
              "${draw.padLeft.round()}",
              draw.padLeft,
              0,
              60,
              6,
              (v) => style.withDraw(draw.copyWith(
                  padLeft: v.roundToDouble(),
                  padRight: v.roundToDouble(),
                  padTop: v.roundToDouble() / 2,
                  padBottom: v.roundToDouble() / 2))),
          knob(
              "ownDrawRadius",
              "Corners",
              "${draw.radius.round()}",
              draw.radius,
              0,
              60,
              4,
              (v) => style.withDraw(draw.copyWith(radius: v.roundToDouble()))),
          _Swatches(
              key: const ValueKey("ownDrawColour"),
              label: "Mark",
              colour: draw.color,
              onChanged: (col) => write(style.withDraw(col == null
                  ? draw.copyWith(clearColor: true)
                  : draw.copyWith(color: col)))),
        ],
        // A text's copies.
        if (echo != null) ...[
          knob(
              "ownEchoCopies",
              "Copies",
              "${echo.copies}",
              echo.copies.toDouble(),
              1,
              12,
              4,
              (v) => style.withEcho(echo.copyWith(copies: v.round()))),
          knob("ownEchoApart", "Apart", pct(echo.spacing), echo.spacing, 0, 2,
              0.4, (v) => style.withEcho(echo.copyWith(spacing: v))),
          knob("ownEchoFade", "Fade", pct(echo.fade), echo.fade, 0, 1, 0.5,
              (v) => style.withEcho(echo.copyWith(fade: v))),
          knob("ownEchoShrink", "Shrink", pct(echo.shrink), echo.shrink, 0, 1,
              0, (v) => style.withEcho(echo.copyWith(shrink: v))),
          StudioDrop<bool>(
            key: const ValueKey("ownEchoResolve"),
            label: "At the end",
            value: echo.resolve,
            options: const [(true, "Comes together"), (false, "Stays apart")],
            onChanged: (v) => write(style.withEcho(echo.copyWith(resolve: v))),
          ),
        ],
      ];
    }

    List<Widget> loopControls() {
      var loop = style.loop;
      var preset = loop.preset;
      return [
        knob(
            "ownLoopCycle",
            "Once round",
            "${(loop.cycle / rate).toStringAsFixed(2)}s",
            loop.cycle / rate,
            1 / rate,
            20,
            1,
            (v) => style.withLoop(
                loop.copyWith(cycle: math.max(1, (v * rate).round()))),
            log: true),
        knob(
            "ownLoopGap",
            "Pause",
            "${(loop.gap / rate).toStringAsFixed(2)}s",
            loop.gap / rate,
            0,
            20,
            0,
            (v) => style
                .withLoop(loop.copyWith(gap: math.max(0, (v * rate).round())))),
        knob(
            "ownLoopRepeats",
            "Times",
            loop.repeats == 0 ? "For ever" : "${loop.repeats}",
            loop.repeats.toDouble(),
            0,
            50,
            0,
            (v) => style.withLoop(loop.copyWith(repeats: v.round()))),
        knob("ownLoopStrength", "Strength", pct(loop.strength), loop.strength,
            0, 3, 1, (v) => style.withLoop(loop.copyWith(strength: v))),
        StudioDrop<ChartEase>(
          key: const ValueKey("ownLoopEase"),
          label: "Curve",
          value: loop.ease,
          options: [for (var e in ChartEase.values) (e, e.label)],
          onChanged: (e) => write(style.withLoop(loop.copyWith(ease: e))),
        ),
        if (preset.banded) ...[
          knob("ownLoopBand", "Band", pct(loop.band), loop.band, 0.02, 1, 0.25,
              (v) => style.withLoop(loop.copyWith(band: v))),
          knob("ownLoopAngle", "Angle", "${loop.angle.round()}°", loop.angle,
              -180, 180, 0, (v) => style.withLoop(loop.copyWith(angle: v)),
              bipolar: true),
        ],
        if (preset.coloured)
          _Swatches(
              key: const ValueKey("ownLoopColour"),
              label: "Colour",
              colour: loop.colour.color,
              onChanged: (col) => write(style.withLoop(
                  loop.copyWith(colour: PaintSpec(col ?? loop.colour.color))))),
      ];
    }

    var name = looping
        ? "Its own loop: ${style.loop.preset.label}"
        : "${leaving ? "Its own way out" : "Its own arrival"}: "
            "${style.labelOf(style.preset(leaving: leaving))}";
    return DeviceFrame(
      id: "ownStyle",
      title: "Style",
      help: "How its own ${looping ? "loop" : leaving ? "way out" : "arrival"} "
          "plays, beside the clip that plays it: its curve, where a growing "
          "one starts, the gap between its words or bars and their order, how "
          "a cutting one cuts, a text's mark and copies, and a loop's every "
          "setting.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 340 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
      height: height,
      icon: Icons.auto_awesome_motion,
      accent: accent,
      summary: name,
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        PackWide(Text(name,
            key: const ValueKey("ownStyleName"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: look.studio.text))),
        DevicePack(
            key: const ValueKey("ownStylePack"),
            children: looping ? loopControls() : moveControls()),
      ],
    );
  }
}

/// _Swatches is a colour picked from a few -- or, [colour] null, its own --
/// labelled as a dropdown is.
class _Swatches extends StatelessWidget {
  final String label;
  final Color? colour;
  final ValueChanged<Color?> onChanged;
  const _Swatches(
      {required this.label,
      required this.colour,
      required this.onChanged,
      super.key});

  static const _choices = <Color?>[
    null,
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFE2B04A),
    Color(0xFFE5534B),
    Color(0xFF3D7EFF),
    Color(0xFF3FB08D),
  ];

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(label,
                maxLines: 1, style: TextStyle(fontSize: 10, color: s.muted)),
          ),
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (var (i, c) in _choices.indexed)
              InkWell(
                key: ValueKey("swatch-$label-$i"),
                onTap: () => onChanged(c),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c,
                    gradient: c == null
                        ? const SweepGradient(colors: [
                            Color(0xFFE5534B),
                            Color(0xFFE2B04A),
                            Color(0xFF3FB08D),
                            Color(0xFF3D7EFF),
                            Color(0xFFE5534B),
                          ])
                        : null,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: c?.toARGB32() == colour?.toARGB32()
                            ? s.text
                            : s.edge,
                        width: c?.toARGB32() == colour?.toARGB32() ? 2 : 1),
                  ),
                ),
              ),
          ]),
        ]);
  }
}

/// ownStudio is the studio's colours, for a caller without a look at hand.
StudioColors ownStudio(BuildContext context) => MixerLook.of(context).studio;
