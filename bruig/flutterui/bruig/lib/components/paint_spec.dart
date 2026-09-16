import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// paint_spec.dart is "what something is coloured in": one colour, or several
// with a fade between them.
//
// Here rather than in the canvas, because the point of it is that a gradient
// is set where a colour is set. Anywhere in the app that opens the picker
// gets gradients for free the day it asks for a PaintSpec instead of a Color,
// and nothing has to grow a row of gradient settings of its own beside the
// swatch.

/// GradientStop is one colour and how far along the fade it is reached.
class GradientStop {
  final Color color;

  /// at is 0 at the start of the run and 1 at the end.
  final double at;

  /// bias is where the change *into* this colour is half done, as a fraction
  /// of the span before it.
  ///
  /// 0.5 is the even fade. Pulled towards 0 the change happens early and the
  /// rest of the span is nearly this colour already; pulled towards 1 it
  /// happens late. One per span rather than one for the whole gradient,
  /// because the tightness of the change from red to orange has nothing to do
  /// with the tightness of the change from orange to black -- and it is shown
  /// as a handle either side of the colour you have hold of, which is the
  /// same thing said in the picture.
  final double bias;

  const GradientStop(this.color, this.at, {this.bias = 0.5});

  GradientStop copyWith({Color? color, double? at, double? bias}) =>
      GradientStop(color ?? this.color, at ?? this.at, bias: bias ?? this.bias);

  Map<String, dynamic> toJson() => {
        "c": paintColorToJson(color),
        "at": at,
        if (bias != 0.5) "bias": bias,
      };

  factory GradientStop.fromJson(Map<String, dynamic> json) => GradientStop(
        paintColorFromJson(json["c"], const Color(0xFF101820)),
        json["at"] is num ? (json["at"] as num).toDouble() : 1,
        bias: json["bias"] is num ? (json["bias"] as num).toDouble() : 0.5,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GradientStop &&
          other.color == color &&
          other.at == at &&
          other.bias == bias;

  @override
  int get hashCode => Object.hash(color, at, bias);
}

/// GradientSpec is the colours after the first one, and how they are reached.
///
/// Its presence *is* the gradient being on -- there is no flag. A thing
/// either fades or it does not, and a "gradient, off" that still has to be
/// carried around and checked is the shape that puts a Fade toggle beside
/// every swatch.
///
/// The first colour is not in here: it is the PaintSpec's own, so a swatch
/// that has always answered with one colour still does. [start] is where that
/// first colour stops being itself.
class GradientSpec {
  /// start is how far along the run the first colour stays flat.
  final double start;

  /// to is the second colour, and [end] is where it is reached.
  ///
  /// Held as a pair rather than as the first entry of [more] so that the
  /// two-colour gradient nearly every colour wants stays a const expression
  /// with two obvious fields -- which is what the presets and half the
  /// element defaults are written as.
  final Color to;
  final double end;

  /// toBias is where the change from the first colour into [to] is half done,
  /// as a fraction of the span. The second colour's [GradientStop.bias], held
  /// out here with the rest of that stop.
  final double toBias;

  /// more are the third colour and any after it, in the order reached.
  /// Empty for the two-colour case.
  final List<GradientStop> more;

  /// angle is the direction it runs in, in degrees read off a compass: 0 runs
  /// upwards, 90 to the right. Ignored by a radial one, which runs outwards.
  ///
  /// The same convention a text shadow's direction uses, because an app with
  /// two ways of saying "which way" is an app where neither is memorable.
  final double angle;

  /// radial runs it out from the middle instead of across.
  final bool radial;

  const GradientSpec({
    this.start = 0,
    this.to = const Color(0xFF101820),
    this.end = 1,
    this.toBias = 0.5,
    this.more = const [],
    this.angle = 180,
    this.radial = false,
  });

  /// ramp is every colour after the base one, in order: the second, then any
  /// after it. What the picker walks and what the shader is built from.
  List<GradientStop> get ramp => [GradientStop(to, end, bias: toBias), ...more];

  /// withRamp puts such a list back, splitting the second colour out again.
  GradientSpec withRamp(List<GradientStop> ramp) {
    if (ramp.isEmpty) return this;
    return copyWith(
      to: ramp.first.color,
      end: ramp.first.at,
      toBias: ramp.first.bias,
      more: ramp.length > 1 ? ramp.sublist(1) : const [],
    );
  }

  /// count is how many colours the fade runs through, the base one included.
  int get count => more.length + 2;

  GradientSpec copyWith({
    double? start,
    Color? to,
    double? end,
    double? toBias,
    List<GradientStop>? more,
    double? angle,
    bool? radial,
  }) =>
      GradientSpec(
        start: start ?? this.start,
        to: to ?? this.to,
        end: end ?? this.end,
        toBias: toBias ?? this.toBias,
        more: more ?? this.more,
        angle: angle ?? this.angle,
        radial: radial ?? this.radial,
      );

  /// withStop replaces one colour in the ramp. Index 0 is the second colour.
  GradientSpec withStop(int index, GradientStop stop) {
    var out = ramp;
    if (index < 0 || index >= out.length) return this;
    return withRamp([
      for (var i = 0; i < out.length; i++) i == index ? stop : out[i],
    ]);
  }

  /// plus adds a colour in the largest gap between the stops there already
  /// are, and says where in the ramp it landed.
  ///
  /// The largest gap rather than the end, so pressing add never puts one on
  /// top of another and never crowds one end of a fade that is already busy.
  /// The index comes back because the thing you want after adding a colour is
  /// to choose it, and a sorted list does not say where the new one went.
  (GradientSpec, int) plus() {
    var out = ramp;
    var places = positions;
    var widest = 0;
    for (var i = 0; i < places.length - 1; i++) {
      if (places[i + 1] - places[i] > places[widest + 1] - places[widest]) {
        widest = i;
      }
    }
    var at = (places[widest] + places[widest + 1]) / 2;
    var index = widest; // the ramp is the places list without its first entry
    var next = [...out]..insert(index, GradientStop(colourAt(at), at));
    return (withRamp(next), index);
  }

  /// minus takes one away, or answers null where taking it away would leave
  /// nothing to fade to -- which is a flat colour, and the caller's business.
  GradientSpec? minus(int index) {
    var out = ramp;
    if (out.length <= 1) return null;
    return withRamp([
      for (var i = 0; i < out.length; i++)
        if (i != index) out[i],
    ]);
  }

  /// colourAt is roughly what colour the fade is at [at], so a newly added
  /// stop starts as the colour that was already there rather than as a jump.
  Color colourAt(double at) {
    var out = ramp;
    var previous = start;
    Color? before;
    for (var stop in out) {
      if (at <= stop.at) {
        var span = stop.at - previous;
        var t = span <= 0 ? 1.0 : ((at - previous) / span).clamp(0.0, 1.0);
        return before == null ? stop.color : Color.lerp(before, stop.color, t)!;
      }
      previous = stop.at;
      before = stop.color;
    }
    return out.last.color;
  }

  /// positions are every stop's place, in order and never on top of each
  /// other.
  ///
  /// Two stops at one place is a hard edge, which is a fair thing to want;
  /// two stops at the *same* number is a gradient ui refuses to build, so
  /// they are held a hair apart.
  List<double> get positions {
    var out = [start.clamp(0.0, 1.0)];
    for (var stop in ramp) {
      var at = stop.at.clamp(0.0, 1.0);
      if (at <= out.last) at = math.min(1.0, out.last + 0.001);
      out.add(at);
    }
    // Pushed off the end by that nudge: walk back down instead.
    for (var i = out.length - 1; i > 0; i--) {
      if (out[i] <= out[i - 1]) out[i - 1] = math.max(0.0, out[i] - 0.001);
    }
    return out;
  }

  /// endsOf is where a linear gradient starts and finishes across [area].
  ///
  /// Corner to corner through the middle rather than edge to edge, so a
  /// gradient set at 45 degrees actually reaches both colours in the corners
  /// it is pointing at.
  (Offset, Offset) endsOf(Rect area) {
    var radians = angle * math.pi / 180;
    // Screen coordinates have y going down, and the angle is read off a
    // compass: up is -y.
    var dx = math.sin(radians);
    var dy = -math.cos(radians);
    var reach = (area.width.abs() * dx).abs() + (area.height.abs() * dy).abs();
    var half = Offset(dx, dy) * (reach / 2);
    return (area.center - half, area.center + half);
  }

  Map<String, dynamic> toJson() => {
        if (start != 0) "start": start,
        "to": paintColorToJson(to),
        if (end != 1) "end": end,
        if (toBias != 0.5) "toBias": toBias,
        if (more.isNotEmpty) "more": [for (var s in more) s.toJson()],
        "angle": angle,
        if (radial) "radial": true,
      };

  factory GradientSpec.fromJson(Map<String, dynamic> json) {
    var raw = json["more"];
    return GradientSpec(
      start: json["start"] is num ? (json["start"] as num).toDouble() : 0,
      to: paintColorFromJson(json["to"], const Color(0xFF101820)),
      end: json["end"] is num ? (json["end"] as num).toDouble() : 1,
      toBias: json["toBias"] is num ? (json["toBias"] as num).toDouble() : 0.5,
      more: raw is List
          ? [
              for (var s in raw)
                if (s is Map) GradientStop.fromJson(s.cast<String, dynamic>()),
            ]
          : const [],
      angle: json["angle"] is num ? (json["angle"] as num).toDouble() : 180,
      radial: json["radial"] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GradientSpec &&
          other.start == start &&
          other.to == to &&
          other.end == end &&
          other.toBias == toBias &&
          other.angle == angle &&
          other.radial == radial &&
          _sameStops(other.more, more);

  @override
  int get hashCode =>
      Object.hash(start, to, end, toBias, angle, radial, Object.hashAll(more));
}

bool _sameStops(List<GradientStop> a, List<GradientStop> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// PaintSpec is a colour, and optionally more to fade to.
class PaintSpec {
  final Color color;

  /// gradient is null for the almost everything that is one colour.
  final GradientSpec? gradient;

  const PaintSpec(this.color, {this.gradient});

  bool get fades => gradient != null;

  PaintSpec copyWith(
          {Color? color, GradientSpec? gradient, bool plain = false}) =>
      PaintSpec(
        color ?? this.color,
        gradient: plain ? null : (gradient ?? this.gradient),
      );

  /// colours and places are every colour in the fade and where each is
  /// reached, the base colour included and each span's bias already worked in.
  ///
  /// Public because the picker draws the same thing the painters do: a
  /// preview built from its own idea of the gradient is a preview that can be
  /// wrong.
  (List<Color>, List<double>) rampFor({double alpha = 1}) {
    var g = gradient!;
    Color dim(Color c) => alpha >= 1 ? c : c.withValues(alpha: c.a * alpha);

    var places = g.positions;
    var colours = [dim(color), for (var s in g.ramp) dim(s.color)];
    var biases = [for (var s in g.ramp) s.bias];
    if (biases.every((b) => (b - 0.5).abs() < 0.001)) return (colours, places);

    // A shader only knows straight lines between stops, so a span whose
    // change is not even is drawn as several straight lines. Eight to a span
    // is enough that no eye finds the corners and few enough that a gradient
    // stays a cheap thing to paint.
    const steps = 8;
    var outColours = <Color>[];
    var outPlaces = <double>[];
    for (var i = 0; i < colours.length - 1; i++) {
      var bias = biases[i].clamp(0.05, 0.95);
      // The exponent that puts the halfway colour at the bias: at t = bias
      // the two colours are mixed evenly, which is what a midpoint handle
      // means.
      var gamma = math.log(0.5) / math.log(bias);
      if ((bias - 0.5).abs() < 0.001) {
        outColours.add(colours[i]);
        outPlaces.add(places[i]);
        continue;
      }
      for (var s = 0; s < steps; s++) {
        var t = s / steps;
        outColours.add(Color.lerp(
            colours[i], colours[i + 1], math.pow(t, gamma).toDouble())!);
        outPlaces.add(places[i] + (places[i + 1] - places[i]) * t);
      }
    }
    outColours.add(colours.last);
    outPlaces.add(places.last);
    return (outColours, outPlaces);
  }

  /// shaderFor is the shader to paint [area] with, or null when this is one
  /// flat colour and the caller should just use [color].
  ///
  /// alpha scales every colour, for the callers that fade a whole thing in.
  ui.Shader? shaderFor(Rect area, {double alpha = 1}) {
    var g = gradient;
    if (g == null || area.isEmpty) return null;
    var (colours, places) = rampFor(alpha: alpha);
    if (g.radial) {
      return ui.Gradient.radial(
        area.center,
        math.max(area.width, area.height) / 2,
        colours,
        places,
      );
    }
    var (a, b) = g.endsOf(area);
    return ui.Gradient.linear(a, b, colours, places);
  }

  /// toJson is an int when this is one colour and a map when it fades, so a
  /// document written before gradients existed still reads, and one written
  /// after it stays as small as it was for the colours that never fade.
  dynamic toJson() => gradient == null
      ? paintColorToJson(color)
      : {"c": paintColorToJson(color), "g": gradient!.toJson()};

  factory PaintSpec.fromJson(dynamic v,
      [Color fallback = const Color(0xFFFFFFFF)]) {
    if (v is Map) {
      var map = v.cast<String, dynamic>();
      return PaintSpec(
        paintColorFromJson(map["c"], fallback),
        gradient: map["g"] is Map
            ? GradientSpec.fromJson((map["g"] as Map).cast<String, dynamic>())
            : null,
      );
    }
    return PaintSpec(paintColorFromJson(v, fallback));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaintSpec && other.color == color && other.gradient == gradient;

  @override
  int get hashCode => Object.hash(color, gradient);
}

/// paintColorToJson and paintColorFromJson are 0xAARRGGBB as a plain integer:
/// the same encoding a saved canvas has always used for a colour.
int paintColorToJson(Color c) =>
    (_channel(c.a) << 24) |
    (_channel(c.r) << 16) |
    (_channel(c.g) << 8) |
    _channel(c.b);

int _channel(double v) => (v * 255).round().clamp(0, 255);

Color paintColorFromJson(dynamic v,
        [Color fallback = const Color(0xFFFFFFFF)]) =>
    v is num ? Color(v.toInt()) : fallback;
