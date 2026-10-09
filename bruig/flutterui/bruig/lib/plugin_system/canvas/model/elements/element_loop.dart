import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';

// element_loop.dart is an element's loop: a motion it goes on repeating --
// after it has arrived, or on its own -- until the scene ends, or for so
// many times. Part of the same Animation section an element's arrival and
// exit are; a third thing it can do, not a second animation system.

/// LoopFamily is a kind of loop, as the Animation section groups them.
enum LoopFamily {
  motion("Motion"),
  light("Light & colour"),
  line("Line"),
  effect("Effects");

  final String label;
  const LoopFamily(this.label);
}

/// LoopPreset is one loop.
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
  glitch("Glitch bursts", LoopFamily.effect);

  final String label;
  final LoopFamily family;
  const LoopPreset(this.label, this.family);

  /// moves is whether it is a motion -- the element moved, turned, sized or
  /// faded as a whole -- rather than something drawn over or into it. See
  /// ElementLoop.poseAt and paintLoopEffect.
  bool get moves => family == LoopFamily.motion || this == jelly;

  /// coloured is whether its colour means anything.
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

  /// banded is whether it sweeps a band, whose width and angle mean
  /// something.
  bool get banded => this == shimmer || this == colourWave;

  static LoopPreset fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => none);

  static List<LoopPreset> inFamily(LoopFamily family) => [
        for (var p in values)
          if (p != none && p.family == family) p,
      ];
}

/// ElementLoop is how an element loops.
class ElementLoop {
  final LoopPreset preset;

  /// cycle is how many frames one go round takes, and gap how many it then
  /// rests for before the next.
  final int cycle;
  final int gap;

  /// repeats is how many times it goes round, or 0 for until it ends.
  final int repeats;

  /// strength is how far, how big, how much -- 1 as the preset is, 2 twice
  /// that, a half half.
  final double strength;

  /// ease is how each go round is paced.
  final ChartEase ease;

  /// colour is the colour it draws with -- a shimmer's band, a wave, a
  /// glow, the sparkles, the ants, the trace -- or a gradient, for a wave.
  final PaintSpec colour;

  /// band is how wide a swept band is, as a share of the element across;
  /// angle the way it leans, in degrees from upright.
  final double band;
  final double angle;

  /// from is the frame it starts on, or null for as the element's arrival
  /// finishes -- or the scene's start, with no arrival. to is the frame it
  /// stops on, or null for the scene's end.
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
  /// stops -- the element's arrival's end, or the scene's start, to the
  /// scene's end, unless set -- shortened to its repeats. [arrived] is
  /// where the arrival finishes, null with none; [last] the scene's last
  /// frame.
  (int, int) span({int? arrived, required int last}) {
    var start = from ?? arrived ?? 0;
    var end = to ?? last;
    if (repeats > 0) {
      end = math.min(end, start + repeats * (cycle + gap) - gap - 1);
    }
    return (start, math.max(start, end));
  }

  /// phaseAt is how far round the loop is at [frame], eased -- 0 to 1 --
  /// and which go round it is on, counting from nought; or null where the
  /// loop is not playing then: before it starts, after it stops, or resting
  /// between two goes round.
  (double, int)? phaseAt(int frame, {int? arrived, required int last}) {
    if (!on) return null;
    var (start, end) = span(arrived: arrived, last: last);
    if (frame < start || frame > end) return null;
    var period = math.max(1, cycle + math.max(0, gap));
    var into = (frame - start) % period;
    if (into >= cycle) return null;
    var p = ease.apply(into / math.max(1, cycle)).clamp(0.0, 1.0);
    return (p, (frame - start) ~/ period);
  }

  /// poseAt is how the element is moved, turned, sized and faded by the
  /// loop at [frame] -- for a loop that moves it; see LoopPreset.moves --
  /// or null where it is not playing then, or draws instead of moving.
  LoopPose? poseAt(int frame, {int? arrived, required int last}) {
    if (!preset.moves) return null;
    var phase = phaseAt(frame, arrived: arrived, last: last);
    if (phase == null) return null;
    return _motion(preset, phase.$1, strength);
  }

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        if (cycle != 24) "cycle": cycle,
        if (gap != 0) "gap": gap,
        if (repeats != 0) "repeats": repeats,
        if (strength != 1) "strength": strength,
        if (ease != ChartEase.linear) "ease": ease.name,
        if (colour != const PaintSpec(Color(0xFFFFFFFF)))
          "colour": colour.toJson(),
        if (band != 0.3) "band": band,
        if (angle != 20) "angle": angle,
        if (from != null) "from": from,
        if (to != null) "to": to,
      };

  factory ElementLoop.fromJson(Map<String, dynamic> json) => ElementLoop(
        preset: LoopPreset.fromName(json["preset"] as String?),
        cycle: math.max(1, jsonInt(json["cycle"], 24)),
        gap: math.max(0, jsonInt(json["gap"], 0)),
        repeats: math.max(0, jsonInt(json["repeats"], 0)),
        strength: jsonDouble(json["strength"], 1).clamp(0.0, 5.0),
        ease: json["ease"] == null
            ? ChartEase.linear
            : ChartEase.fromName(json["ease"] as String?),
        colour: json["colour"] == null
            ? const PaintSpec(Color(0xFFFFFFFF))
            : PaintSpec.fromJson(json["colour"], const Color(0xFFFFFFFF)),
        band: jsonDouble(json["band"], 0.3).clamp(0.02, 1.0),
        angle: jsonDouble(json["angle"], 20),
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

/// _motion is [preset] at [p] of the way round, [s] strong.
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
      // Up and down as a ball goes, squashed where it lands and stretched
      // as it leaves the ground.
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

/// arrivalEnd is the frame [element]'s arrival finishes on -- its last
/// reveal keyframe -- or null with none.
int? arrivalEnd(CanvasElement element) {
  int? end;
  for (var key in element.track?.keys ?? const <Keyframe>[]) {
    if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
    end = end == null ? key.frame : math.max(end, key.frame);
  }
  return end;
}
