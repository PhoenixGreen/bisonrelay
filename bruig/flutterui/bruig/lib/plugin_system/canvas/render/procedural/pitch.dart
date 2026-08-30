import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:flutter/painting.dart';

// pitch.dart draws a marked playing surface.
//
// Drawn rather than shipped as a photograph, and the reasons are the same ones
// that make the whole canvas vector: it exports sharp at any width, it takes
// the document's own colours, it weighs nothing, and -- the one that actually
// matters for this feature -- the markings are in known places. A tactics
// diagram is only worth anything if the halfway line is the halfway line, and
// a background image stretched to the canvas puts every player in the wrong
// position by however much the aspect was wrong.
//
// So everything below is in metres, from each sport's own laws, and one
// transform maps metres onto the rectangle. The pitch is letterboxed inside
// whatever rectangle it is given rather than stretched to it, which is why
// [pitchRect] exists and why the player presets place their dots through it.
//
// The colours come from the spec, not from the sport: the grass is the
// background, the markings are the foreground, and the accent is the mowing
// stripe and the floodlight. A pitch in a document's own palette is the point
// -- a green rectangle is available anywhere.

/// PitchMetrics is the mapping from a sport's metres onto the canvas.
///
/// Handed back by [pitchRect] so the presets can place a 4-4-2 in metres and
/// have it land where the markings say it should, rather than in fractions of
/// a rectangle that would be wrong the moment the canvas changed shape.
class PitchMetrics {
  /// area is the playing surface itself, inside the surround.
  final Rect area;

  /// lengthMetres and widthMetres are the sport's own dimensions.
  final double lengthMetres;
  final double widthMetres;

  const PitchMetrics(this.area, this.lengthMetres, this.widthMetres);

  /// scale is pixels per metre. The two axes share one, which is what keeps
  /// the centre circle a circle.
  double get scale => area.width / lengthMetres;

  /// at maps a point in metres -- measured from the pitch's own bottom-left
  /// corner, with x along its length -- onto the canvas.
  Offset at(double xMetres, double yMetres) => Offset(
        area.left + xMetres * scale,
        area.bottom - yMetres * scale,
      );

  /// m converts a length in metres to pixels.
  double m(double metres) => metres * scale;
}

/// pitchInset is how much of the rectangle is surround rather than pitch, as a
/// fraction. There is always some: a pitch drawn hard against the edge of the
/// frame has its touchline markings half cut off, and a player standing on the
/// touchline has nowhere to be.
const double pitchInset = 0.045;

/// pitchRect works out where the surface goes inside [rect], keeping the
/// sport's own proportions and centring what is left over.
PitchMetrics pitchRect(Rect rect, PitchSport sport) {
  var available = rect.deflate(math.min(rect.width, rect.height) * pitchInset);
  var aspect = sport.aspect;

  var width = available.width;
  var height = width / aspect;
  if (height > available.height) {
    height = available.height;
    width = height * aspect;
  }

  var area = Rect.fromCenter(
      center: available.center, width: width, height: height);
  var length = switch (sport) {
    PitchSport.football || PitchSport.blank => 105.0,
    PitchSport.basketball => 28.0,
    PitchSport.tennis => 23.77,
    PitchSport.hockey => 91.4,
    PitchSport.rugby => 100.0,
    PitchSport.americanFootball => 109.7,
  };
  return PitchMetrics(area, length, length / aspect);
}

/// paintPitch draws the surface and its markings.
void paintPitch(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var metrics = pitchRect(rect, spec.sport);
  var area = metrics.area;

  // The surround first, then the surface, so the pitch sits on something
  // rather than floating on the document's background.
  canvas.drawRect(rect, Paint()..color = _darken(spec.background, 0.45));
  canvas.drawRect(area, Paint()..color = spec.background);

  _mowingStripes(canvas, area, spec);
  _turfTexture(canvas, area, spec);

  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, metrics.m(0.12))
    ..color = spec.foreground.withValues(
        alpha: (spec.foreground.a * (0.55 + spec.intensity * 0.45))
            .clamp(0, 1));

  switch (spec.sport) {
    case PitchSport.football:
      _football(canvas, metrics, line, spec);
    case PitchSport.basketball:
      _basketball(canvas, metrics, line);
    case PitchSport.tennis:
      _tennis(canvas, metrics, line);
    case PitchSport.hockey:
      _hockey(canvas, metrics, line);
    case PitchSport.rugby:
      _rugby(canvas, metrics, line);
    case PitchSport.americanFootball:
      _americanFootball(canvas, metrics, line, spec);
    case PitchSport.blank:
      canvas.drawRect(area, line);
  }

  if (spec.intensity > 0) _floodlights(canvas, rect, area, spec);
}

/// _mowingStripes are the bands a roller leaves. Alternating slightly lighter
/// and darker than the grass rather than a separate colour, because that is
/// what they are -- the same grass lying two different ways.
void _mowingStripes(ui.Canvas canvas, Rect area, ProceduralSpec spec) {
  var bands = 4 + (spec.density * 18).round();
  if (bands < 2) return;
  var w = area.width / bands;
  for (var i = 0; i < bands; i++) {
    if (i.isOdd) continue;
    canvas.drawRect(
      Rect.fromLTWH(area.left + i * w, area.top, w, area.height),
      Paint()..color = _lighten(spec.background, 0.06 + spec.variation * 0.05),
    );
  }
}

/// _turfTexture is a faint noise over the grass. Cheap, and the difference
/// between a pitch and two green rectangles.
void _turfTexture(ui.Canvas canvas, Rect area, ProceduralSpec spec) {
  if (spec.variation <= 0) return;
  var noise = ValueNoise(spec.seed);
  var cell = math.max(6.0, area.height / 40);
  var cols = (area.width / cell).ceil();
  var rows = (area.height / cell).ceil();
  var paint = Paint();
  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var f = noise.fbm(ix * 0.18, iy * 0.18, octaves: 3);
      paint.color = Color.fromRGBO(
          0, 0, 0, ((f - 0.5) * 0.12 * spec.variation).clamp(0.0, 0.08));
      canvas.drawRect(
          Rect.fromLTWH(area.left + ix * cell, area.top + iy * cell, cell, cell),
          paint);
    }
  }
}

/// _floodlights are four soft pools of light from the corners, as in a night
/// match seen from above.
void _floodlights(ui.Canvas canvas, Rect rect, Rect area, ProceduralSpec spec) {
  var r = math.max(rect.width, rect.height) * 0.55;
  var corners = [
    Offset(area.left, area.top),
    Offset(area.right, area.top),
    Offset(area.left, area.bottom),
    Offset(area.right, area.bottom),
  ];
  canvas.saveLayer(rect, Paint());
  for (var c in corners) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r, [
          spec.accent.withValues(alpha: 0.11 * spec.intensity),
          spec.accent.withValues(alpha: 0),
        ]),
    );
  }
  canvas.restore();
}

// --------------------------------------------------------------------------
// The markings, each from its own sport's laws
// --------------------------------------------------------------------------

/// _football is a full pitch: 105 by 68 metres, with everything the laws put
/// on it.
void _football(
    ui.Canvas canvas, PitchMetrics p, Paint line, ProceduralSpec spec) {
  var a = p.area;
  var w = p.widthMetres;

  canvas.drawRect(a, line);
  canvas.drawLine(p.at(52.5, 0), p.at(52.5, w), line);
  canvas.drawCircle(p.at(52.5, w / 2), p.m(9.15), line);
  canvas.drawCircle(p.at(52.5, w / 2), p.m(0.35), Paint()..color = line.color);

  for (var end in [0.0, 1.0]) {
    // end is 0 for the left goal and 1 for the right; every distance below is
    // measured from that goal line inwards, which is how the laws state them.
    double x(double fromLine) =>
        end == 0 ? fromLine : p.lengthMetres - fromLine;

    // Penalty area: 16.5m deep, 40.32m wide, centred.
    canvas.drawRect(
        Rect.fromPoints(p.at(x(0), (w - 40.32) / 2),
            p.at(x(16.5), (w + 40.32) / 2)),
        line);
    // Goal area: 5.5m deep, 18.32m wide.
    canvas.drawRect(
        Rect.fromPoints(p.at(x(0), (w - 18.32) / 2),
            p.at(x(5.5), (w + 18.32) / 2)),
        line);

    var spot = p.at(x(11), w / 2);
    canvas.drawCircle(spot, p.m(0.35), Paint()..color = line.color);

    // The penalty arc is the part of the 9.15m circle around the spot that
    // falls outside the penalty area -- drawn as an arc rather than a clipped
    // circle so the line inside the box is genuinely absent rather than
    // painted over.
    var reach = math.acos((16.5 - 11) / 9.15);
    canvas.drawArc(
      Rect.fromCircle(center: spot, radius: p.m(9.15)),
      end == 0 ? -reach : math.pi - reach,
      reach * 2,
      false,
      line,
    );

    // Goal: 7.32m wide, drawn 2m deep behind the line.
    var goal = Rect.fromPoints(
      p.at(x(0), (w - 7.32) / 2),
      p.at(end == 0 ? -2.0 : p.lengthMetres + 2.0, (w + 7.32) / 2),
    );
    canvas.drawRect(goal, line);
    canvas.drawRect(
        goal, Paint()..color = spec.foreground.withValues(alpha: 0.10));
  }

  // Corner arcs, 1m.
  for (var cx in [0.0, p.lengthMetres]) {
    for (var cy in [0.0, w]) {
      var start = cx == 0
          ? (cy == 0 ? -math.pi / 2 : 0.0)
          : (cy == 0 ? math.pi : math.pi / 2);
      canvas.drawArc(
          Rect.fromCircle(center: p.at(cx, cy), radius: p.m(1)),
          start,
          math.pi / 2,
          false,
          line);
    }
  }
}

/// _basketball is a 28 by 15 metre court.
void _basketball(ui.Canvas canvas, PitchMetrics p, Paint line) {
  var a = p.area;
  var w = p.widthMetres;
  canvas.drawRect(a, line);
  canvas.drawLine(p.at(14, 0), p.at(14, w), line);
  canvas.drawCircle(p.at(14, w / 2), p.m(1.8), line);

  for (var end in [0, 1]) {
    double x(double d) => end == 0 ? d : p.lengthMetres - d;

    // The key: 4.9m wide, 5.8m deep, with the free-throw circle on its edge.
    canvas.drawRect(
        Rect.fromPoints(
            p.at(x(0), (w - 4.9) / 2), p.at(x(5.8), (w + 4.9) / 2)),
        line);
    canvas.drawCircle(p.at(x(5.8), w / 2), p.m(1.8), line);

    // Three-point line: an arc of 6.75m from the basket, met by two straights
    // 0.9m from each sideline.
    var basket = p.at(x(1.575), w / 2);
    var corner = 0.9;
    canvas.drawLine(p.at(x(0), corner), p.at(x(2.99), corner), line);
    canvas.drawLine(p.at(x(0), w - corner), p.at(x(2.99), w - corner), line);
    canvas.drawArc(
      Rect.fromCircle(center: basket, radius: p.m(6.75)),
      end == 0 ? -math.pi / 2 : math.pi / 2,
      math.pi,
      false,
      line,
    );
  }
}

/// _tennis is a 23.77 by 10.97 metre court, doubles width.
void _tennis(ui.Canvas canvas, PitchMetrics p, Paint line) {
  var a = p.area;
  var w = p.widthMetres;
  var singlesInset = (w - 8.23) / 2;

  canvas.drawRect(a, line);
  canvas.drawLine(p.at(0, singlesInset), p.at(p.lengthMetres, singlesInset), line);
  canvas.drawLine(
      p.at(0, w - singlesInset), p.at(p.lengthMetres, w - singlesInset), line);

  // Service lines, 6.4m from the net either way, and the centre service line
  // between them.
  for (var x in [11.885 - 6.4, 11.885 + 6.4]) {
    canvas.drawLine(p.at(x, singlesInset), p.at(x, w - singlesInset), line);
  }
  canvas.drawLine(p.at(11.885 - 6.4, w / 2), p.at(11.885 + 6.4, w / 2), line);

  // The net, drawn heavier than the markings because it is the one thing on a
  // tennis court that is not paint.
  canvas.drawLine(
      p.at(11.885, -0.5),
      p.at(11.885, w + 0.5),
      Paint()
        ..color = line.color
        ..strokeWidth = line.strokeWidth * 2.2);
}

/// _hockey is a 91.4 by 55 metre pitch with its two shooting circles.
void _hockey(ui.Canvas canvas, PitchMetrics p, Paint line) {
  var w = p.widthMetres;
  canvas.drawRect(p.area, line);
  canvas.drawLine(p.at(45.7, 0), p.at(45.7, w), line);
  for (var x in [22.9, 68.5]) {
    canvas.drawLine(p.at(x, 0), p.at(x, w), line);
  }

  for (var end in [0, 1]) {
    double x(double d) => end == 0 ? d : p.lengthMetres - d;
    // The D: a 14.63m arc from each goal post, joined by a straight across the
    // goalmouth.
    for (var post in [(w - 3.66) / 2, (w + 3.66) / 2]) {
      canvas.drawArc(
        Rect.fromCircle(center: p.at(x(0), post), radius: p.m(14.63)),
        end == 0
            ? (post < w / 2 ? -math.pi / 2 : 0)
            : (post < w / 2 ? math.pi : math.pi / 2),
        math.pi / 2,
        false,
        line,
      );
    }
    canvas.drawLine(p.at(x(14.63), (w - 3.66) / 2),
        p.at(x(14.63), (w + 3.66) / 2), line);
  }
}

/// _rugby is a 100 metre field of play with its 22s and dashed 10s.
void _rugby(ui.Canvas canvas, PitchMetrics p, Paint line) {
  var w = p.widthMetres;
  canvas.drawRect(p.area, line);
  canvas.drawLine(p.at(50, 0), p.at(50, w), line);
  for (var x in [22.0, 78.0]) {
    canvas.drawLine(p.at(x, 0), p.at(x, w), line);
  }
  // The 10m lines are dashed, as are the 5m and 15m lines running the length.
  for (var x in [40.0, 60.0]) {
    _dashedLine(canvas, p.at(x, 0), p.at(x, w), line, p.m(1.5), p.m(1.0));
  }
  for (var y in [5.0, 15.0, w - 15, w - 5]) {
    _dashedLine(canvas, p.at(0, y), p.at(p.lengthMetres, y), line, p.m(1.0),
        p.m(2.0));
  }
}

/// _americanFootball is a 100 yard field with two end zones and yard lines
/// every five.
void _americanFootball(
    ui.Canvas canvas, PitchMetrics p, Paint line, ProceduralSpec spec) {
  var w = p.widthMetres;
  canvas.drawRect(p.area, line);

  // End zones, 10 yards each, tinted so they read without needing a label.
  var endZone = p.m(9.14);
  for (var r in [
    Rect.fromLTWH(p.area.left, p.area.top, endZone, p.area.height),
    Rect.fromLTWH(p.area.right - endZone, p.area.top, endZone, p.area.height),
  ]) {
    canvas.drawRect(r, Paint()..color = spec.accent.withValues(alpha: 0.14));
    canvas.drawRect(r, line);
  }

  var yard = p.m(0.9144);
  for (var y = 5; y <= 95; y += 5) {
    var x = p.area.left + endZone + y * yard;
    canvas.drawLine(Offset(x, p.area.top), Offset(x, p.area.bottom),
        y % 10 == 0 ? line : (Paint()
          ..color = line.color.withValues(alpha: line.color.a * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.strokeWidth * 0.7));
  }
  // Hash marks, at the two inbound lines.
  for (var y in [w * 0.36, w * 0.64]) {
    _dashedLine(canvas, p.at(9.14, y), p.at(p.lengthMetres - 9.14, y), line,
        p.m(0.6), p.m(0.3));
  }
}

void _dashedLine(
    ui.Canvas canvas, Offset a, Offset b, Paint paint, double on, double off) {
  var total = (b - a).distance;
  if (total <= 0 || on <= 0) return;
  var dir = (b - a) / total;
  var d = 0.0;
  while (d < total) {
    var next = math.min(d + on, total);
    canvas.drawLine(a + dir * d, a + dir * next, paint);
    d = next + off;
  }
}

Color _lighten(Color c, double amount) => Color.fromARGB(
      (c.a * 255).round(),
      ((c.r * 255) + (255 - c.r * 255) * amount).round().clamp(0, 255),
      ((c.g * 255) + (255 - c.g * 255) * amount).round().clamp(0, 255),
      ((c.b * 255) + (255 - c.b * 255) * amount).round().clamp(0, 255),
    );

Color _darken(Color c, double amount) => Color.fromARGB(
      (c.a * 255).round(),
      (c.r * 255 * (1 - amount)).round().clamp(0, 255),
      (c.g * 255 * (1 - amount)).round().clamp(0, 255),
      (c.b * 255 * (1 - amount)).round().clamp(0, 255),
    );
