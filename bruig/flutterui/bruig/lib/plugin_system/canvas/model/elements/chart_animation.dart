import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// chart_animation.dart is how a chart arrives and leaves: which preset, how
// much its items overlap, and what the end of the movement does. Timing only;
// what a bar does with progressAt is the painter's business.

/// chartAnimationSeconds is how long a new arrival runs when nothing else
/// says; the timeline is where its length then lives.
const int chartAnimationSeconds = 2;

/// ChartAnimationPreset is how a chart arrives. A closed set of presets: what
/// genuinely varies (overlap and easing) is a setting on [ChartAnimation].
enum ChartAnimationPreset {
  none("None", "The chart is simply there"),

  /// grow raises bars out of the axis and opens pie slices from the middle.
  grow("Grow", "Each one grows to its full size, in turn"),

  /// drawOn traces a line from its start to its end. For bars there is nothing
  /// to trace, so it grows them instead.
  drawOn("Draw on", "Lines are drawn along their length"),

  /// wipe reveals the plot left to right, everything in it at once.
  wipe("Wipe across", "The whole plot is uncovered from the left"),

  /// sweep is wipe for a circle: the chart is uncovered clockwise.
  sweep("Sweep round", "The chart is uncovered clockwise from the top"),

  popIn("Pop in", "Each one springs up where it stands, in turn"),

  /// random is popIn with the order shuffled, for a scatter, whose points
  /// have no meaningful order.
  random("Random", "Each one appears on its own, in no particular order"),

  fadeIn("Fade in", "Each one fades up, in turn");

  final String label;
  final String description;
  const ChartAnimationPreset(this.label, this.description);

  static ChartAnimationPreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => ChartAnimationPreset.none,
      );

  /// staggers is whether the items go one after another (spaced by the gap
  /// setting); a wipe and a sweep move one edge across everything at once.
  bool get staggers => this != none && this != wipe && this != sweep;

  /// scrambles is whether the order things arrive in is shuffled.
  bool get scrambles => this == random;

  /// suitsCircular and suitsCartesian are which chart families a preset makes
  /// sense on.
  bool get suitsCircular =>
      this == none ||
      this == grow ||
      this == sweep ||
      this == popIn ||
      this == random ||
      this == fadeIn;

  bool get suitsCartesian => this != sweep;
}

/// ChartEase is what the end of an item's movement does.
enum ChartEase {
  linear("Linear"),
  easeIn("Ease in"),
  easeOut("Ease out"),
  easeInOut("Ease in & out"),
  overshoot("Overshoot"),
  bounce("Bounce"),
  spring("Spring");

  final String label;
  const ChartEase(this.label);

  static ChartEase fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => ChartEase.easeOut);

  /// apply maps 0..1 onto the eased value, which may leave 0..1 on the way --
  /// that is what an overshoot is.
  double apply(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    switch (this) {
      case ChartEase.linear:
        return t;
      case ChartEase.easeIn:
        return t * t * t;
      case ChartEase.easeOut:
        return 1 - math.pow(1 - t, 3).toDouble();
      case ChartEase.easeInOut:
        return t < 0.5
            ? 4 * t * t * t
            : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
      case ChartEase.overshoot:
        // The standard back-out: one overshoot and a settle, no wobble.
        const c = 1.70158;
        var u = t - 1;
        return 1 + (c + 1) * u * u * u + c * u * u;
      case ChartEase.bounce:
        return bounceOut(t);
      case ChartEase.spring:
        // A decaying oscillation: three visible swings before it settles.
        var decay = math.pow(2, -9 * t).toDouble();
        return 1 - decay * math.cos(t * math.pi * 6);
    }
  }
}

/// staggeredProgress is how far item [index] of [count] has got when a
/// staggered animation is [reveal] through. Shared by charts (bars, points,
/// slices, series) and text (letters, words, lines) so their staggers agree.
double staggeredProgress(
  double reveal,
  int index,
  int count, {
  required bool on,
  required bool staggers,
  required bool scrambles,
  required bool flipOrder,
  required double gap,
  required ChartEase ease,
}) {
  if (!on) return 1;
  if (reveal >= 1) return 1;
  if (reveal <= 0) return 0;
  if (!staggers || count <= 1) return ease.apply(reveal);

  // The whole animation is one item's movement plus the gaps before every
  // later one, measured in item-movements.
  var step = gap.clamp(0.0, 4.0);
  var total = 1 + step * (count - 1);
  var place =
      scrambles ? ChartAnimation.scrambled(index, count) : index.toDouble();
  // On the way out the movement runs backwards, so the last item goes first;
  // flipping the places empties it from the front instead.
  if (flipOrder) place = (count - 1) - place;
  var local = (reveal * total - step * place).clamp(0.0, 1.0);
  return ease.apply(local);
}

/// ChartAnimation is how a chart draws itself on and off.
///
/// The timing is not here: it is the element's arrival and leaving on the
/// timeline, which drive KeyframeChannel.reveal and close from 0 to 1. A
/// duration stored here would be a second timeline the first could not see.
class ChartAnimation {
  final ChartAnimationPreset preset;

  /// exit is how the chart leaves, using the same presets played backwards:
  /// bars sink into the axis, a wipe uncovers in reverse, slices close. It is
  /// timed separately (KeyframeChannel.close) and shares [gap] and [ease]
  /// with the entrance.
  final ChartAnimationPreset exit;

  /// exitInOrder empties the chart the way it filled, first item first.
  /// Without it the exit is the entrance run backwards, so the last item
  /// leaves first.
  final bool exitInOrder;

  /// flipOrder reverses which item is staggered first. Not saved: [leaving]
  /// sets it from [exitInOrder] on the copy drawn for the way out.
  final bool flipOrder;

  /// gap is how long after one item starts before the next does, as a
  /// fraction of one item's own movement: 1 is strictly one after another,
  /// below 1 they overlap (0 is all together), above 1 leaves a pause.
  final double gap;

  final ChartEase ease;

  /// length is how many frames a new arrival or exit is laid down with, or 0
  /// for [chartAnimationSeconds]. Dragging it on the timeline does not write
  /// back here. Same as TextAnimation.length.
  final int length;

  /// seriesInTurn brings a chart of several series in one series after
  /// another, each in its share of the arrival, rather than all of them
  /// together (Ken's privacy video: five series arrived as one). See
  /// seriesInTurnReveal.
  final bool seriesInTurn;

  const ChartAnimation({
    this.seriesInTurn = false,
    this.preset = ChartAnimationPreset.none,
    this.exit = ChartAnimationPreset.none,
    this.exitInOrder = false,
    this.flipOrder = false,
    this.gap = 0.55,
    this.ease = ChartEase.easeOut,
    this.length = 0,
    this.loop = const ElementLoop(),
  });

  /// loop is what the chart goes on doing after it has arrived, or instead
  /// of arriving: see ElementLoop.
  final ElementLoop loop;

  /// any is whether there is anything to it: an arrival, an exit or a loop.
  bool get any => on || closes || loop.on;

  bool get on => preset != ChartAnimationPreset.none;

  /// closes is whether the chart has a way out as well as a way in.
  bool get closes => exit != ChartAnimationPreset.none;

  /// leaving is this animation as it is played on the way out: the exit
  /// preset in the entrance's place, so the painter need not know which half
  /// it is drawing.
  ChartAnimation get leaving => copyWith(preset: exit, flipOrder: exitInOrder);

  ChartAnimation copyWith({
    ChartAnimationPreset? preset,
    ChartAnimationPreset? exit,
    bool? exitInOrder,
    bool? flipOrder,
    double? gap,
    ChartEase? ease,
    int? length,
    ElementLoop? loop,
    bool? seriesInTurn,
  }) =>
      ChartAnimation(
        seriesInTurn: seriesInTurn ?? this.seriesInTurn,
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        exitInOrder: exitInOrder ?? this.exitInOrder,
        flipOrder: flipOrder ?? this.flipOrder,
        gap: gap ?? this.gap,
        ease: ease ?? this.ease,
        length: length ?? this.length,
        loop: loop ?? this.loop,
      );

  /// progressAt is how far item [index] of [count] has got when the whole
  /// animation is [reveal] through. See [staggeredProgress].
  double progressAt(double reveal, int index, int count) => staggeredProgress(
        reveal,
        index,
        count,
        on: on,
        staggers: preset.staggers,
        scrambles: preset.scrambles,
        flipOrder: flipOrder,
        gap: gap,
        ease: ease,
      );

  /// scrambled is where item [index] comes in the arrival order for the
  /// presets that shuffle; not a whole number, so items may arrive together.
  ///
  /// Deterministic, because every frame and every export must deal the same
  /// order. A hash rather than "multiply by a prime mod count", which gives
  /// visible patterns (twelve items came out as a plain reversal).
  static double scrambled(int index, int count) {
    if (count <= 1) return 0;
    return _mix(index) * (count - 1);
  }

  /// _mix avalanches an index into 0..1 with Murmur3's finaliser.
  static double _mix(int index) {
    var x = (index + 1) & 0xFFFFFFFF;
    x ^= x >>> 16;
    x = (x * 0x85EBCA6B) & 0xFFFFFFFF;
    x ^= x >>> 13;
    x = (x * 0xC2B2AE35) & 0xFFFFFFFF;
    x ^= x >>> 16;
    return x / 0xFFFFFFFF;
  }

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        if (closes) "exit": exit.name,
        if (closes && exitInOrder) "exitOrder": true,
        "gap": gap,
        "ease": ease.name,
        if (length > 0) "length": length,
        if (loop.on) "loop": loop.toJson(),
        if (seriesInTurn) "seriesInTurn": true,
      };

  factory ChartAnimation.fromJson(Map<String, dynamic> json) => ChartAnimation(
        preset: ChartAnimationPreset.fromName(jsonStr(json["preset"])),
        exit: ChartAnimationPreset.fromName(jsonStr(json["exit"])),
        exitInOrder: jsonBool(json["exitOrder"], false),
        gap: jsonDouble(json["gap"], 0.55).clamp(0.0, 4.0),
        ease: ChartEase.fromName(jsonStr(json["ease"])),
        length: jsonInt(json["length"], 0).clamp(0, 100000),
        seriesInTurn: jsonBool(json["seriesInTurn"], false),
        loop: json["loop"] is Map<String, dynamic>
            ? ElementLoop.fromJson(json["loop"] as Map<String, dynamic>)
            : const ElementLoop(),
      );
}

/// seriesInTurnReveal is how far series [index] of [count] has got when a
/// chart arriving series by series is [reveal] through: each its share of
/// the arrival, one after another.
double seriesInTurnReveal(double reveal, int index, int count) {
  if (count <= 1) return reveal;
  return ((reveal * count) - index).clamp(0.0, 1.0).toDouble();
}
