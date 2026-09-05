import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_animation.dart is how a chart arrives: which preset, how much its
// items overlap, and what the end of the movement does.
//
// It is a closed set of presets rather than a general mechanism, for the
// reason given on ChartAnimationPreset. The whole file is decisions about
// timing and nothing about drawing -- what a bar does with progressAt is the
// painter's business, which is why this can be read on its own.

/// chartAnimationSeconds is how long a preset runs when it is first applied.
///
/// A starting point, not a setting: the two keyframes it lays are dragged on
/// the timeline like anything else, which is where the length actually lives.
const int chartAnimationSeconds = 2;

/// ChartAnimationPreset is how a chart arrives.
///
/// Presets rather than a set of controls that could express all of them. What
/// somebody wants is "the bars grow up one after another"; what a general
/// mechanism asks is which property, over what range, with what stagger and
/// what easing, four times over -- and the answer is the same four answers
/// every time. The two things that genuinely vary are how much the items
/// overlap and what the end of the movement does, and those are settings.
enum ChartAnimationPreset {
  none("None", "The chart is simply there"),

  /// grow is the one anybody means. Bars rise out of the axis, horizontal bars
  /// run out from it, pie slices open out from the middle.
  grow("Grow", "Each one grows to its full size, in turn"),

  /// drawOn traces a line from its start to its end. For bars there is nothing
  /// to trace, so it grows them instead.
  drawOn("Draw on", "Lines are drawn along their length"),

  /// wipe reveals the plot left to right, everything in it at once. The one
  /// preset with nothing to stagger.
  wipe("Wipe across", "The whole plot is uncovered from the left"),

  /// sweep is wipe for a circle: the chart is uncovered clockwise.
  sweep("Sweep round", "The chart is uncovered clockwise from the top"),

  popIn("Pop in", "Each one springs up where it stands, in turn"),

  /// random is popIn with the order shuffled. What a scatter wants: points in
  /// a scatter have no order worth animating in -- left to right is a
  /// property of how they were typed rather than of what they mean -- and a
  /// cloud that fills in unevenly reads as a cloud arriving rather than as a
  /// row being dealt.
  random("Random", "Each one appears on its own, in no particular order"),

  fadeIn("Fade in", "Each one fades up, in turn");

  final String label;
  final String description;
  const ChartAnimationPreset(this.label, this.description);

  static ChartAnimationPreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => ChartAnimationPreset.none,
      );

  /// staggers is whether the items go one after another, which is what the gap
  /// setting decides. A wipe and a sweep move one edge across everything at
  /// once and have nothing to space out.
  bool get staggers => this != none && this != wipe && this != sweep;

  /// scrambles is whether the order things arrive in is shuffled.
  bool get scrambles => this == random;

  /// suitsCircular and suitsCartesian are which chart families a preset makes
  /// sense on. A wipe across a pie is a wipe across a circle, which reads as a
  /// mistake; a sweep round a bar chart is worse.
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
///
/// The reason this is a setting and not a fixed curve: a bar that eases to a
/// stop is a chart, and a bar that overshoots and settles is an advertisement,
/// and which of the two is wanted is not something a drawing routine can know.
enum ChartEase {
  linear("Linear"),
  easeOut("Ease out"),
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
      case ChartEase.easeOut:
        return 1 - math.pow(1 - t, 3).toDouble();
      case ChartEase.overshoot:
        // The standard back-out: one overshoot and a settle, no wobble.
        const c = 1.70158;
        var u = t - 1;
        return 1 + (c + 1) * u * u * u + c * u * u;
      case ChartEase.bounce:
        return _bounce(t);
      case ChartEase.spring:
        // A decaying oscillation. Three visible swings before it settles,
        // which is enough to read as a spring and few enough to stop being
        // charming on the fourth chart.
        var decay = math.pow(2, -9 * t).toDouble();
        return 1 - decay * math.cos(t * math.pi * 6);
    }
  }

  static double _bounce(double t) {
    const n = 7.5625, d = 2.75;
    if (t < 1 / d) return n * t * t;
    if (t < 2 / d) {
      var u = t - 1.5 / d;
      return n * u * u + 0.75;
    }
    if (t < 2.5 / d) {
      var u = t - 2.25 / d;
      return n * u * u + 0.9375;
    }
    var u = t - 2.625 / d;
    return n * u * u + 0.984375;
  }
}

/// ChartAnimation is how a chart draws itself on, and how much of it has.
///
/// The *timing* is not here. It is two keyframes on the element's own track,
/// pinning KeyframeChannel.reveal at 0 and at 1, so the length of the
/// animation is dragged on the timeline like everything else that moves. A
/// duration stored here would be a second timeline that the first one could
/// not see.
class ChartAnimation {
  final ChartAnimationPreset preset;

  /// gap is how long after one item starts before the next does, as a
  /// fraction of one item's own movement.
  ///
  /// 1 is strictly one after another: each finishes as the next begins. Below
  /// 1 they overlap, and 0 is all of them together. Above 1 leaves a pause
  /// between one finishing and the next starting.
  final double gap;

  final ChartEase ease;

  const ChartAnimation({
    this.preset = ChartAnimationPreset.none,
    this.gap = 0.55,
    this.ease = ChartEase.easeOut,
  });

  bool get on => preset != ChartAnimationPreset.none;

  ChartAnimation copyWith({
    ChartAnimationPreset? preset,
    double? gap,
    ChartEase? ease,
  }) =>
      ChartAnimation(
        preset: preset ?? this.preset,
        gap: gap ?? this.gap,
        ease: ease ?? this.ease,
      );

  /// progressAt is how far item [index] of [count] has got when the whole
  /// animation is [reveal] through.
  ///
  /// The arithmetic is in one place because the painter asks it for bars, for
  /// points, for slices and for series, and a stagger that meant something
  /// slightly different in four places is four animations that do not line up
  /// with each other.
  double progressAt(double reveal, int index, int count) {
    if (!on) return 1;
    if (reveal >= 1) return 1;
    if (reveal <= 0) return 0;
    if (!preset.staggers || count <= 1) return ease.apply(reveal);

    // The whole animation is one item's movement plus the gaps before every
    // later one, measured in item-movements.
    var step = gap.clamp(0.0, 4.0);
    var total = 1 + step * (count - 1);
    var place = preset.scrambles ? scrambled(index, count) : index.toDouble();
    var local = (reveal * total - step * place).clamp(0.0, 1.0);
    return ease.apply(local);
  }

  /// scrambled is where item [index] comes in the order things arrive, for the
  /// presets that shuffle. Not a whole number: two items may well arrive
  /// together, which is what random looks like.
  ///
  /// Arithmetic rather than a shuffled list, and the same answer every time
  /// rather than a fresh one. A chart is drawn once per frame and exported
  /// frame by frame in a separate pass, so anything that consulted a random
  /// number generator would deal the points differently on every frame and on
  /// every export -- which is not an animation, it is static.
  ///
  /// A mix rather than "multiply by a prime and take the remainder", which is
  /// the obvious version and is not random at all: the multiplier is only ever
  /// used modulo the count, so twelve items came out as a plain reversal and
  /// two series of six arrived one series at a time -- which is the exact
  /// thing this preset exists to avoid.
  static double scrambled(int index, int count) {
    if (count <= 1) return 0;
    return _mix(index) * (count - 1);
  }

  /// _mix avalanches an index into 0..1. Murmur3's finaliser, which is the
  /// standard answer to "spread these integers out" and is three multiplies.
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
        "gap": gap,
        "ease": ease.name,
      };

  factory ChartAnimation.fromJson(Map<String, dynamic> json) => ChartAnimation(
        preset: ChartAnimationPreset.fromName(json["preset"] as String?),
        gap: jsonDouble(json["gap"], 0.55).clamp(0.0, 4.0),
        ease: ChartEase.fromName(json["ease"] as String?),
      );
}
