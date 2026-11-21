import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';

// element_loop.dart is an element's loop: a motion it repeats after it
// arrives, or alone, until the scene ends or so many times.

/// LoopFamily is a kind of loop, as the Own style card groups them.
enum LoopFamily {
  motion("Motion"),
  light("Light & colour"),
  line("Line"),
  effect("Effects"),

  /// drift is a picture moving slowly inside its frame (a pan and zoom over a
  /// still), once across the loop's span. Offered for pictures only.
  drift("Drift");

  final String label;
  const LoopFamily(this.label);
}

enum LoopPreset {
  none("None", LoopFamily.motion),

  /// float bobs gently up and down.
  float("Float", LoopFamily.motion),

  /// sway rocks to and fro about its middle.
  sway("Sway", LoopFamily.motion),

  /// pulse swells and settles, once a cycle.
  pulse("Pulse", LoopFamily.motion),

  /// breathe swells slowly and fades a little as it does.
  breathe("Breathe", LoopFamily.motion),

  /// bounce hops up and lands, squashing as it does.
  bounce("Bounce", LoopFamily.motion),

  /// spin turns all the way round, once a cycle.
  spin("Spin", LoopFamily.motion),

  /// wiggle shakes from side to side and settles.
  wiggle("Wiggle", LoopFamily.motion),

  /// orbit drifts round a small circle.
  orbit("Orbit", LoopFamily.motion),

  /// heartbeat beats twice, then rests.
  heartbeat("Heartbeat", LoopFamily.motion),

  /// swing hangs from its top edge and swings like a pendulum.
  swing("Swing", LoopFamily.motion),

  /// shimmer sweeps a bright band through it, at an angle.
  shimmer("Shimmer", LoopFamily.light),

  /// colourWave sweeps a band of colour -- or a gradient -- through it.
  colourWave("Colour wave", LoopFamily.light),

  /// colourCycle turns its colours round the colour wheel.
  colourCycle("Colour cycle", LoopFamily.light),

  /// glowPulse swells a glow round it and lets it fade.
  glowPulse("Glow pulse", LoopFamily.light),

  /// sparkle twinkles glints over it.
  sparkle("Sparkle", LoopFamily.light),

  /// neonFlicker stutters, as a failing neon tube does.
  neonFlicker("Neon flicker", LoopFamily.light),

  /// drawOn draws its outline on, fills it in, then takes it off again.
  drawOn("Draw on & off", LoopFamily.line),

  /// marchingAnts runs dashes round its outline.
  marchingAnts("Marching ants", LoopFamily.line),

  /// trace runs a bright spark round its outline.
  trace("Trace", LoopFamily.line),

  /// jelly wobbles, squashing and stretching, and settles.
  jelly("Jelly", LoopFamily.effect),

  /// ripple runs a wave through it, side to side.
  ripple("Ripple", LoopFamily.effect),

  /// glitch breaks into torn, colour-split slices in short bursts.
  glitch("Glitch bursts", LoopFamily.effect),

  /// The drifts move the picture inside its still frame, once across the
  /// loop.
  driftIn("Zoom in", LoopFamily.drift),
  driftOut("Zoom out", LoopFamily.drift),
  driftLeft("Pan left", LoopFamily.drift),
  driftRight("Pan right", LoopFamily.drift),
  driftUp("Pan up", LoopFamily.drift),
  driftDown("Pan down", LoopFamily.drift);

  final String label;
  final LoopFamily family;
  const LoopPreset(this.label, this.family);

  /// moves is whether it moves, turns, sizes or fades the whole element,
  /// not drawing over or into it. See ElementLoop.poseAt, paintLoopEffect.
  bool get moves => family == LoopFamily.motion || this == jelly;

  bool get coloured => switch (this) {
        shimmer ||
        colourWave ||
        glowPulse ||
        sparkle ||
        marchingAnts ||
        trace ||
        neonFlicker =>
          true,
        _ => false,
      };

  /// drifts is whether it moves a picture inside its frame, once across its
  /// span, rather than going round. See ElementLoop.driftAt.
  bool get drifts => family == LoopFamily.drift;

  /// banded is whether it sweeps a band, whose width and angle matter.
  bool get banded => this == shimmer || this == colourWave;

  static LoopPreset fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => none);

  static List<LoopPreset> inFamily(LoopFamily family) => [
        for (var p in values)
          if (p != none && p.family == family) p,
      ];
}

class ElementLoop {
  final LoopPreset preset;

  /// cycle is the frames one go round takes; gap the rest after it.
  final int cycle;
  final int gap;

  /// repeats is how many times it goes round, or 0 for until it ends.
  final int repeats;

  /// strength is how far, how big, how much: 1 as the preset is, 2 twice.
  final double strength;

  final ChartEase ease;

  /// colour is what it draws with (a shimmer's band, a wave, a glow, the
  /// sparkles, the ants, the trace), or a gradient for a wave.
  final PaintSpec colour;

  /// band is how wide a swept band is, as a share of the element across;
  /// angle the way it leans, in degrees from upright.
  final double band;
  final double angle;

  /// from is its first frame, or null for the arrival's end (or the scene's
  /// start); to its last, or null for the scene's end.
  final int? from;
  final int? to;

  const ElementLoop({
    this.preset = LoopPreset.none,
    this.cycle = 24,
    this.gap = 0,
    this.repeats = 0,
    this.strength = 1,
    this.ease = ChartEase.linear,
    this.colour = const PaintSpec(Color(0xFFFFFFFF)),
    this.band = 0.3,
    this.angle = 20,
    this.from,
    this.to,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ElementLoop();

  bool get on => preset != LoopPreset.none;

  ElementLoop copyWith({
    LoopPreset? preset,
    int? cycle,
    int? gap,
    int? repeats,
    double? strength,
    ChartEase? ease,
    PaintSpec? colour,
    double? band,
    double? angle,
    int? from,
    int? to,
    bool clearFrom = false,
    bool clearTo = false,
  }) =>
      ElementLoop(
        preset: preset ?? this.preset,
        cycle: cycle ?? this.cycle,
        gap: gap ?? this.gap,
        repeats: repeats ?? this.repeats,
        strength: strength ?? this.strength,
        ease: ease ?? this.ease,
        colour: colour ?? this.colour,
        band: band ?? this.band,
        angle: angle ?? this.angle,
        from: clearFrom ? null : from ?? this.from,
        to: clearTo ? null : to ?? this.to,
      );

  /// span is the frames it plays across: from where it starts to where it
  /// stops (see [from]), shortened to its repeats. [arrived] is where the
  /// arrival finishes, null with none; [last] the scene's last frame.
  (int, int) span({int? arrived, required int last}) {
    var start = from ?? arrived ?? 0;
    var end = to ?? last;
    if (repeats > 0) {
      end = math.min(end, start + repeats * (cycle + gap) - gap - 1);
    }
    return (start, math.max(start, end));
  }

  /// phaseAt is how far round the loop is at [frame], eased 0 to 1, and which
  /// go round it is on, from nought; null where it is not playing: before it
  /// starts, after it stops, or resting between goes.
  (double, int)? phaseAt(int frame, {int? arrived, required int last}) {
    // A drift does not go round; see driftAt.
    if (!on || preset.drifts) return null;
    var (start, end) = span(arrived: arrived, last: last);
    if (frame < start || frame > end) return null;
    var period = math.max(1, cycle + math.max(0, gap));
    var into = (frame - start) % period;
    if (into >= cycle) return null;
    var p = ease.apply(into / math.max(1, cycle)).clamp(0.0, 1.0);
    return (p, (frame - start) ~/ period);
  }

  /// driftAt is how far through a drift is at [frame], eased (0 before it
  /// starts, 1 after), or null for a loop that is not one: once across the
  /// whole span, ignoring cycle, rest and repeats. [frame] may fall between
  /// frames while the editor plays; see betweenFrames.
  double? driftAt(num frame, {int? arrived, required int last}) {
    if (!on || !preset.drifts) return null;
    var start = from ?? arrived ?? 0;
    var end = math.max(start, to ?? last);
    var t = end <= start ? 1.0 : (frame - start) / (end - start);
    return ease.apply(t.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  /// poseAt is how the loop moves, turns, sizes and fades the element at
  /// [frame] (see LoopPreset.moves), or null where it does not.
  LoopPose? poseAt(int frame, {int? arrived, required int last}) {
    if (!preset.moves) return null;
    var phase = phaseAt(frame, arrived: arrived, last: last);
    if (phase == null) return null;
    return _motion(preset, phase.$1, strength);
  }

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        if (cycle != _defaults.cycle) "cycle": cycle,
        if (gap != _defaults.gap) "gap": gap,
        if (repeats != _defaults.repeats) "repeats": repeats,
        if (strength != _defaults.strength) "strength": strength,
        if (ease != _defaults.ease) "ease": ease.name,
        if (colour != _defaults.colour) "colour": colour.toJson(),
        if (band != _defaults.band) "band": band,
        if (angle != _defaults.angle) "angle": angle,
        if (from != null) "from": from,
        if (to != null) "to": to,
      };

  factory ElementLoop.fromJson(Map<String, dynamic> json) => ElementLoop(
        preset: LoopPreset.fromName(jsonStr(json["preset"])),
        cycle: math.max(1, jsonInt(json["cycle"], _defaults.cycle)),
        gap: math.max(0, jsonInt(json["gap"], _defaults.gap)),
        repeats: math.max(0, jsonInt(json["repeats"], _defaults.repeats)),
        strength:
            jsonDouble(json["strength"], _defaults.strength).clamp(0.0, 5.0),
        ease: json["ease"] == null
            ? ChartEase.linear
            : ChartEase.fromName(jsonStr(json["ease"])),
        colour: json["colour"] == null
            ? const PaintSpec(Color(0xFFFFFFFF))
            : PaintSpec.fromJson(json["colour"], const Color(0xFFFFFFFF)),
        band: jsonDouble(json["band"], _defaults.band).clamp(0.02, 1.0),
        angle: jsonDouble(json["angle"], _defaults.angle),
        from: json["from"] is int ? json["from"] as int : null,
        to: json["to"] is int ? json["to"] as int : null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementLoop &&
          other.preset == preset &&
          other.cycle == cycle &&
          other.gap == gap &&
          other.repeats == repeats &&
          other.strength == strength &&
          other.ease == ease &&
          other.colour == colour &&
          other.band == band &&
          other.angle == angle &&
          other.from == from &&
          other.to == to;

  @override
  int get hashCode => Object.hash(preset, cycle, gap, repeats, strength, ease,
      colour, band, angle, from, to);
}

/// LoopPose is the loop's say over the element at one frame: moved by [dx]
/// and [dy] (shares of its width and height), turned [turn] degrees and
/// sized [sx] by [sy] about [pivot] (a share of its box, the middle being
/// (0.5, 0.5)), and faded to [opacity].
class LoopPose {
  final double dx;
  final double dy;
  final double turn;
  final double sx;
  final double sy;
  final double opacity;
  final Offset pivot;

  const LoopPose({
    this.dx = 0,
    this.dy = 0,
    this.turn = 0,
    this.sx = 1,
    this.sy = 1,
    this.opacity = 1,
    this.pivot = const Offset(0.5, 0.5),
  });
}

/// _bump is a smooth hump [width] wide, centred on [at], peaking at 1.
double _bump(double p, double at, double width) {
  var d = (p - at) / width;
  return math.exp(-d * d * 4);
}

LoopPose _motion(LoopPreset preset, double p, double s) {
  const tau = 2 * math.pi;
  switch (preset) {
    case LoopPreset.none:
      return const LoopPose();
    case LoopPreset.float:
      return LoopPose(dy: -math.sin(tau * p) * 0.06 * s);
    case LoopPreset.sway:
      return LoopPose(turn: math.sin(tau * p) * 6 * s);
    case LoopPreset.pulse:
      var up = math.pow(math.sin(math.pi * p), 2).toDouble() * 0.1 * s;
      return LoopPose(sx: 1 + up, sy: 1 + up);
    case LoopPreset.breathe:
      var swell = (1 - math.cos(tau * p)) / 2;
      return LoopPose(
          sx: 1 + swell * 0.06 * s,
          sy: 1 + swell * 0.06 * s,
          opacity: 1 - swell * 0.25 * math.min(1, s));
    case LoopPreset.bounce:
      // Up and down as a ball goes, squashed landing, stretched leaving.
      var height = math.sin(math.pi * p).abs();
      var land = _bump(p, 0, 0.12) + _bump(p, 1, 0.12);
      return LoopPose(
          dy: -height * 0.18 * s,
          sx: 1 + land * 0.12 * s,
          sy: 1 - land * 0.12 * s + height * 0.04 * s,
          pivot: const Offset(0.5, 1));
    case LoopPreset.spin:
      return LoopPose(turn: 360 * p * (s < 0 ? -1 : 1));
    case LoopPreset.wiggle:
      return LoopPose(turn: math.sin(tau * 3 * p) * 5 * s * (1 - p));
    case LoopPreset.orbit:
      return LoopPose(
          dx: math.cos(tau * p) * 0.05 * s, dy: math.sin(tau * p) * 0.05 * s);
    case LoopPreset.heartbeat:
      var beat = _bump(p, 0.1, 0.12) + 0.7 * _bump(p, 0.32, 0.12);
      return LoopPose(sx: 1 + beat * 0.12 * s, sy: 1 + beat * 0.12 * s);
    case LoopPreset.swing:
      return LoopPose(
          turn: math.sin(tau * p) * 12 * s, pivot: const Offset(0.5, 0));
    case LoopPreset.jelly:
      // Wide and short, then tall and thin, smaller each time, settling --
      // from its base, as a jelly sits on a plate.
      var wobble = math.sin(tau * 2.5 * p) * math.pow(1 - p, 1.5) * 0.14 * s;
      return LoopPose(
          sx: 1 + wobble, sy: 1 - wobble, pivot: const Offset(0.5, 1));
    default:
      return const LoopPose();
  }
}

/// arrivalEnd is the frame [element]'s arrival finishes on, at [rate]
/// frames a second, or null with none. See own_motion.dart.
int? arrivalEnd(CanvasElement element, int rate) => ownEnd(element, rate);
