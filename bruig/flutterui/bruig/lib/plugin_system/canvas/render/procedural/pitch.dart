import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:flutter/painting.dart';

// pitch.dart draws a marked playing surface.
//
// Drawn rather than shipped as a photograph, and the reasons are the same ones
// that make the whole canvas vector: it exports sharp at any width, it takes
// the document's own colours, it weighs nothing, and -- the one that matters
// for publication -- the markings are where the laws put them. Every sport is
// drawn in metres from its governing body's own dimensions, line widths
// included, so a 5 cm basketball line is a fifth of the width of a 25 cm
// football line on the same page, as it is on the floor.
//
// The pitch is drawn on the ground, and the ground is then seen: from
// straight above, from an isometric angle, or from a broadcast camera in the
// stand. Seeing it is a projection of the ground plane onto the page -- a
// homography, which a canvas can apply to everything drawn on it -- so the
// markings stay true however the pitch is looked at, and the things that
// stand up off it (goals, posts, hoops, stands) are put through the same
// projection a point at a time.
//
// The colours come from the spec: the surface is the background, the
// markings are the foreground, and the accent is what is painted -- a key, an
// end zone, the run-off round a court, the seats.

// --------------------------------------------------------------------------
// The mapping
// --------------------------------------------------------------------------

/// PitchMetrics is the mapping from a sport's metres onto the canvas, for a
/// pitch seen flat and lying across the page.
///
/// Handed back by [pitchRect] so the presets can place a 4-4-2 in metres and
/// have it land where the markings say it should.
class PitchMetrics {
  /// area is the field of play itself.
  final Rect area;

  /// lengthMetres and widthMetres are the sport's own dimensions.
  final double lengthMetres;
  final double widthMetres;

  const PitchMetrics(this.area, this.lengthMetres, this.widthMetres);

  /// scale is pixels per metre. The two axes share one.
  double get scale => area.width / lengthMetres;

  /// at maps a point in metres -- from the field's bottom-left corner, x
  /// along its length -- onto the canvas.
  Offset at(double xMetres, double yMetres) => Offset(
        area.left + xMetres * scale,
        area.bottom - yMetres * scale,
      );

  /// m converts a length in metres to pixels.
  double m(double metres) => metres * scale;
}

/// pitchInset is how much of the rectangle is left round the pitch, as a
/// fraction of its shorter side.
const double pitchInset = 0.045;

/// pitchRect is where [sport]'s field of play lands inside [rect], seen flat
/// and lying across the page -- the way a tactics board is drawn.
PitchMetrics pitchRect(Rect rect, PitchSport sport) {
  var field = _Field.of(sport);
  var view = _View.fit(
      rect, ProceduralSpec(style: ProceduralStyle.pitch, sport: sport), field);
  var a = view.project(0, field.width), b = view.project(field.length, 0);
  return PitchMetrics(Rect.fromPoints(a, b), field.length, field.width);
}

/// _Field is one sport's field of play, in metres: its size, the width of
/// its lines, and what lies round it that belongs in the picture.
class _Field {
  final PitchSport sport;
  final double length, width;

  /// line is the regulation width of a marking.
  final double line;

  /// apron is the ground round the field of play that is part of the
  /// playing area: in-goal areas, end zones, the run-off round a court.
  final Rect apron;

  /// fitsField is whether the picture is fitted to the field of play alone
  /// rather than to the apron -- the football pitch, whose players are
  /// placed in its own metres. See pitchRect.
  final bool fitsField;

  const _Field(this.sport, this.length, this.width, this.line, this.apron,
      {this.fitsField = false});

  static _Field of(PitchSport sport) {
    switch (sport) {
      case PitchSport.football:
        return const _Field(
            PitchSport.football, 105, 68, 0.12, Rect.fromLTRB(-3, -3, 108, 71),
            fitsField: true);
      case PitchSport.futsal:
        return const _Field(
            PitchSport.futsal, 40, 20, 0.08, Rect.fromLTRB(-2, -2, 42, 22));
      case PitchSport.basketball:
        return const _Field(
            PitchSport.basketball, 28, 15, 0.05, Rect.fromLTRB(-2, -2, 30, 17));
      case PitchSport.basketballNba:
        return const _Field(PitchSport.basketballNba, 28.65, 15.24, 0.0508,
            Rect.fromLTRB(-2, -2, 30.65, 17.24));
      case PitchSport.tennis:
        // The run-off a professional court has round it: 6.40 m behind each
        // baseline and 3.66 m beside each sideline.
        return const _Field(PitchSport.tennis, 23.77, 10.97, 0.05,
            Rect.fromLTRB(-6.4, -3.66, 30.17, 14.63));
      case PitchSport.hockey:
        return const _Field(PitchSport.hockey, 91.4, 55, 0.075,
            Rect.fromLTRB(-4, -3, 95.4, 58));
      case PitchSport.iceHockey:
        return const _Field(PitchSport.iceHockey, 60.96, 25.91, 0.0508,
            Rect.fromLTRB(-0.3, -0.3, 61.26, 26.21));
      case PitchSport.rugby:
        // Ten metres of in-goal at each end.
        return const _Field(
            PitchSport.rugby, 100, 70, 0.1, Rect.fromLTRB(-10, -2, 110, 72));
      case PitchSport.rugbyLeague:
        return const _Field(PitchSport.rugbyLeague, 100, 68, 0.1,
            Rect.fromLTRB(-8, -2, 108, 70));
      case PitchSport.americanFootball:
        // The whole 120 yards, end zones included, with the six-foot border.
        return const _Field(PitchSport.americanFootball, 109.728, 48.768,
            0.1016, Rect.fromLTRB(-1.83, -1.83, 111.558, 50.598));
      case PitchSport.blank:
        return const _Field(
            PitchSport.blank, 105, 68, 0.12, Rect.fromLTRB(-3, -3, 108, 71),
            fitsField: true);
    }
  }

  Rect get field => Rect.fromLTWH(0, 0, length, width);
}

/// _View is how the ground is seen: which part of it, which way round, from
/// where, and fitted into which rectangle of the page.
class _View {
  final double cx, cy;
  final bool upright;
  final double azimuth;
  final double elevation;

  /// distance is the camera's distance from the middle of the ground, for a
  /// view in perspective; nought for one without.
  final double distance;
  double scale = 1, ox = 0, oy = 0;

  _View(this.cx, this.cy, this.upright, this.azimuth, this.elevation,
      this.distance);

  /// _rows is the plane's x and y on the ground, as rows of a matrix.
  (List<double>, List<double>) _rows() {
    var u = [1.0, 0.0, -cx], v = [0.0, 1.0, -cy];
    if (upright) {
      var nu = [-v[0], -v[1], -v[2]];
      v = u;
      u = nu;
    }
    var ca = math.cos(azimuth), sa = math.sin(azimuth);
    var px = [for (var i = 0; i < 3; i++) u[i] * ca - v[i] * sa];
    var py = [for (var i = 0; i < 3; i++) u[i] * sa + v[i] * ca];
    return (px, py);
  }

  /// camera is a point on or above the ground in the camera's own units,
  /// before the fit: across, up, and how far away.
  (double, double, double) camera(double x, double y, double z) {
    var (pr, qr) = _rows();
    var px = pr[0] * x + pr[1] * y + pr[2];
    var py = qr[0] * x + qr[1] * y + qr[2];
    var sp = math.sin(elevation), cp = math.cos(elevation);
    var up = py * sp + z * cp;
    var depth = py * cp - z * sp;
    if (distance <= 0) return (px, up, depth);
    var k = distance / math.max(distance * 0.05, distance + depth);
    return (px * k, up * k, depth);
  }

  Offset project(double x, double y, [double z = 0]) {
    var (a, b, _) = camera(x, y, z);
    return Offset(ox + a * scale, oy - b * scale);
  }

  double depthOf(double x, double y, [double z = 0]) => camera(x, y, z).$3;

  /// ground is the matrix that puts the ground plane, in metres, onto the
  /// page -- to hand to Canvas.transform.
  Float64List ground() {
    var (pr, qr) = _rows();
    var sp = math.sin(elevation), cp = math.cos(elevation);
    var persp = distance > 0;
    var w = persp
        ? [cp * qr[0], cp * qr[1], distance + cp * qr[2]]
        : [0.0, 0.0, 1.0];
    var f = persp ? distance : 1.0;
    var hx = [for (var i = 0; i < 3; i++) ox * w[i] + scale * f * pr[i]];
    var hy = [for (var i = 0; i < 3; i++) oy * w[i] - scale * f * sp * qr[i]];
    return Float64List.fromList([
      hx[0], hy[0], 0, w[0], //
      hx[1], hy[1], 0, w[1], //
      0, 0, 1, 0, //
      hx[2], hy[2], 0, w[2],
    ]);
  }

  /// pixelsPerMetre is how big a metre is in the middle of the picture.
  double get pixelsPerMetre => scale;

  /// flat is whether the ground is seen from straight above.
  bool get flat => elevation > math.pi / 2 - 0.01;

  /// fit is the view [spec] asks for, fitted into [rect].
  static _View fit(Rect rect, ProceduralSpec spec, _Field field) {
    var half = spec.choice("area") == 1;
    var window = _window(spec, field, half);
    var kind = spec.choice("view");
    var tilt = spec.p("tilt");
    var spin = spec.p("spin") * math.pi / 180;
    var reach = math.max(window.width, window.height);
    var view = switch (kind) {
      PitchViewKind.isometric => _View(
          window.center.dx,
          window.center.dy,
          spec.choice("runs") == 1,
          math.pi / 4 + spin,
          (24 + tilt * 30) * math.pi / 180,
          0),
      PitchViewKind.broadcast => _View(
          window.center.dx,
          window.center.dy,
          spec.choice("runs") == 1,
          spin,
          (14 + tilt * 46) * math.pi / 180,
          reach * 1.25),
      PitchViewKind.endOn => _View(
          window.center.dx,
          window.center.dy,
          spec.choice("runs") == 1,
          -math.pi / 2 + spin,
          (14 + tilt * 46) * math.pi / 180,
          reach * 1.25),
      _ => _View(window.center.dx, window.center.dy, spec.choice("runs") == 1,
          0, math.pi / 2, 0),
    };

    // Fitted to the corners of what has to be seen, and to the tops of the
    // stands where there are any.
    var points = <(double, double, double)>[
      for (var x in [window.left, window.right])
        for (var y in [window.top, window.bottom]) (x, y, 0),
    ];
    if (spec.choice("surround") == 1) {
      // The tops of the stands -- but not the near one, which is left out
      // where the camera is in it, and would otherwise be fitted round as
      // empty space at the foot of the picture.
      var outer = _standOuter(window);
      var middle = view.depthOf(window.center.dx, window.center.dy);
      for (var x in [outer.left, outer.center.dx, outer.right]) {
        for (var y in [outer.top, outer.center.dy, outer.bottom]) {
          if (x == outer.center.dx && y == outer.center.dy) continue;
          if (!view.flat && view.depthOf(x, y) < middle - 1) continue;
          points.add((x, y, _standHeight(window)));
        }
      }
    }
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var (x, y, z) in points) {
      var (a, b, _) = view.camera(x, y, z);
      minX = math.min(minX, a);
      maxX = math.max(maxX, a);
      minY = math.min(minY, b);
      maxY = math.max(maxY, b);
    }
    var available =
        rect.deflate(math.min(rect.width, rect.height) * pitchInset);
    var bw = math.max(1e-6, maxX - minX), bh = math.max(1e-6, maxY - minY);
    view.scale =
        math.max(0.0, math.min(available.width / bw, available.height / bh));
    view.ox = available.center.dx - view.scale * (minX + maxX) / 2;
    view.oy = available.center.dy + view.scale * (minY + maxY) / 2;
    return view;
  }

  /// _window is the part of the ground that is shown, in metres.
  static Rect _window(ProceduralSpec spec, _Field field, bool half) {
    var plain = spec.choice("surround") == 0 &&
        spec.choice("view") == PitchViewKind.flat;
    var box = plain && field.fitsField ? field.field : field.apron;
    if (spec.choice("surround") == 2)
      box = box.expandToInclude(_trackOuter(field));
    if (half) {
      box = Rect.fromLTRB(
          field.length / 2 - field.line * 4, box.top, box.right, box.bottom);
    }
    return box;
  }
}

// --------------------------------------------------------------------------
// Drawing on the ground
// --------------------------------------------------------------------------

/// _Pen draws markings on the ground, in metres.
class _Pen {
  final ui.Canvas canvas;
  final Paint stroke;
  final Paint fill;
  final double minimum;
  _Pen(this.canvas, Color colour, double width, this.minimum)
      : stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(width, minimum)
          ..strokeCap = StrokeCap.butt
          ..color = colour,
        fill = Paint()..color = colour;

  _Pen withColour(Color c, [double? width]) =>
      _Pen(canvas, c, width ?? stroke.strokeWidth, minimum);

  _Pen thick(double width) => _Pen(canvas, stroke.color, width, minimum);

  void line(double x1, double y1, double x2, double y2) =>
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);

  void rect(double x1, double y1, double x2, double y2) =>
      canvas.drawRect(Rect.fromPoints(Offset(x1, y1), Offset(x2, y2)), stroke);

  void box(double x1, double y1, double x2, double y2, Paint paint) =>
      canvas.drawRect(Rect.fromPoints(Offset(x1, y1), Offset(x2, y2)), paint);

  void circle(double x, double y, double r) =>
      canvas.drawCircle(Offset(x, y), r, stroke);

  void dot(double x, double y, double r) =>
      canvas.drawCircle(Offset(x, y), math.max(r, minimum * 0.8), fill);

  /// arc is the part of a circle from [start] through [sweep], in radians
  /// measured from the length of the field towards its far side.
  void arc(double x, double y, double r, double start, double sweep) =>
      canvas.drawArc(Rect.fromCircle(center: Offset(x, y), radius: r), start,
          sweep, false, stroke);

  void dashed(
      double x1, double y1, double x2, double y2, double on, double off) {
    var a = Offset(x1, y1), b = Offset(x2, y2);
    var total = (b - a).distance;
    if (total <= 0) return;
    var dir = (b - a) / total;
    for (var d = 0.0; d < total; d += on + off) {
      canvas.drawLine(a + dir * d, a + dir * math.min(total, d + on), stroke);
    }
  }

  void dashedArc(double x, double y, double r, double start, double sweep,
      double on, double off) {
    var length = r * sweep.abs();
    var sign = sweep.sign;
    for (var d = 0.0; d < length; d += on + off) {
      var a0 = start + sign * d / r;
      var a1 = start + sign * math.min(length, d + on) / r;
      canvas.drawArc(Rect.fromCircle(center: Offset(x, y), radius: r), a0,
          a1 - a0, false, stroke);
    }
  }

  /// text is [s] lying on the ground at [x], [y], its foot towards
  /// [facing] -- the direction somebody reading it stands in.
  void text(String s, double x, double y, double height, double facing,
      Color colour) {
    var tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontFamily: "Inter",
              fontWeight: FontWeight.w700,
              fontSize: 100,
              height: 1,
              letterSpacing: 12,
              color: colour)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(x, y);
    // The ground's y runs up the page and a canvas's down it, so the words
    // are turned the right way up before they are turned to face.
    canvas.rotate(facing + math.pi / 2);
    canvas.scale(height / 72, -height / 72);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 - 6));
    canvas.restore();
  }
}

/// paintPitch draws the surface, its markings and what stands on it.
void paintPitch(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var field = _Field.of(spec.sport);
  var view = _View.fit(rect, spec, field);
  if (view.scale <= 0) return;
  var surround = spec.choice("surround");
  var painted = spec.on("painted");

  // What is round it all.
  canvas.drawRect(rect, Paint()..color = _darken(spec.background, 0.45));
  if (!view.flat) {
    // A sky of sorts, where the ground stops short of the top of the frame.
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            _darken(spec.background, 0.7),
            _darken(spec.background, 0.45),
          ]));
  }

  var lineColour = spec.foreground.withValues(
      alpha: (spec.foreground.a * (0.55 + spec.intensity * 0.45)).clamp(0, 1));
  var weight = spec.p("lineWeight");
  var minimum = 0.9 / view.pixelsPerMetre;

  canvas.save();
  canvas.clipRect(rect);
  canvas.save();
  canvas.transform(view.ground());

  var ground = _View._window(spec, field, false).inflate(surround == 1 ? 8 : 4);
  var half = spec.choice("area") == 1;
  if (half) {
    // Half a pitch is half a pitch: cut at the halfway line rather than
    // running on out of the frame.
    var shown = _View._window(spec, field, true);
    canvas.clipRect(Rect.fromLTRB(shown.left, -1000, 1000, 1000));
  }
  if (surround == 1) {
    // The stadium's floor: the concourse between the boards and the stands.
    canvas.drawRect(_View._window(spec, field, false).inflate(5),
        Paint()..color = _darken(spec.background, 0.55));
  }
  if (surround == 2) _track(canvas, field, spec);
  _surface(canvas, field, spec, ground, painted);

  var pen = _Pen(canvas, lineColour, field.line * weight, minimum);
  switch (spec.sport) {
    case PitchSport.football:
      _football(pen, field, spec);
    case PitchSport.futsal:
      _futsal(pen, field, spec);
    case PitchSport.basketball:
      _basketballFiba(pen, field, spec, painted);
    case PitchSport.basketballNba:
      _basketballNba(pen, field, spec, painted);
    case PitchSport.tennis:
      _tennis(pen, field, spec);
    case PitchSport.hockey:
      _hockey(pen, field, spec);
    case PitchSport.iceHockey:
      _iceHockey(pen, field, spec, weight);
    case PitchSport.rugby:
      _rugbyUnion(pen, field, spec);
    case PitchSport.rugbyLeague:
      _rugbyLeague(pen, field, spec);
    case PitchSport.americanFootball:
      _gridiron(pen, field, spec, painted);
    case PitchSport.blank:
      pen.rect(0, 0, field.length, field.width);
  }
  canvas.restore();

  // What stands up off the ground, furthest first.
  var items = <(double, void Function())>[];
  if (surround == 1) _stadium(canvas, view, field, spec, ground, items);
  if (spec.on("goals")) {
    _goals(canvas, view, field, spec, items,
        from: half ? _View._window(spec, field, true).left : -1e9);
  }
  items.sort((a, b) => b.$1.compareTo(a.$1));
  for (var (_, draw) in items) {
    draw();
  }
  canvas.restore();

  if (spec.on("floodlights")) _floodlights(canvas, rect, view, field, spec);
}

// --------------------------------------------------------------------------
// Surfaces
// --------------------------------------------------------------------------

int _autoSurface(PitchSport sport) => switch (sport) {
      PitchSport.basketball || PitchSport.basketballNba => PitchSurface.wood,
      PitchSport.futsal || PitchSport.tennis => PitchSurface.hardCourt,
      PitchSport.iceHockey => PitchSurface.ice,
      PitchSport.hockey => PitchSurface.plain,
      _ => PitchSurface.stripes,
    };

/// _surface lays the playing surface: over the apron in a slightly darker
/// shade -- or in the accent, where the run-off is painted -- and over the
/// field of play in the background colour, finished as the surface asks.
void _surface(ui.Canvas canvas, _Field field, ProceduralSpec spec, Rect ground,
    bool painted) {
  var kind = spec.choice("surface");
  if (kind == PitchSurface.auto) kind = _autoSurface(field.sport);
  var bg = spec.background;
  var ice = field.sport == PitchSport.iceHockey;
  var shape = ice
      ? (Path()
        ..addRRect(
            RRect.fromRectAndRadius(field.field, const Radius.circular(8.53))))
      : (Path()..addRect(field.field));

  // The apron.
  if (!ice) {
    var runoff = painted &&
            (field.sport == PitchSport.tennis ||
                field.sport == PitchSport.hockey ||
                field.sport == PitchSport.futsal)
        ? spec.accent
        : _darken(bg, kind == PitchSurface.wood ? 0.18 : 0.08);
    canvas.drawRect(field.apron, Paint()..color = runoff);
  }
  canvas.drawPath(shape, Paint()..color = bg);

  canvas.save();
  canvas.clipPath(ice ? shape : (Path()..addRect(_surfaceArea(field, kind))));
  var area = _surfaceArea(field, kind);
  switch (kind) {
    case PitchSurface.stripes:
    case PitchSurface.checks:
      // The mowing pattern: bands along the length, the grass lying two
      // ways -- and, for checks, across it too.
      var bands = 4 + (spec.density * 18).round() * 1;
      var w = field.length / bands;
      var light = Paint()..color = _lighten(bg, 0.06 + spec.variation * 0.05);
      var dark = Paint()..color = _darken(bg, 0.04 + spec.variation * 0.03);
      var first = ((area.left) / w).floor() - 1;
      var last = ((area.right) / w).ceil() + 1;
      var rows = kind == PitchSurface.checks
          ? math.max(2, (field.width / w).round())
          : 1;
      var h = field.width / rows;
      for (var i = first; i <= last; i++) {
        for (var j = 0; j < rows + 2; j++) {
          var odd = kind == PitchSurface.checks ? (i + j).isOdd : i.isOdd;
          if (!odd) continue;
          canvas.drawRect(
              Rect.fromLTWH(i * w, area.top + (j - 1) * h, w,
                  kind == PitchSurface.checks ? h : area.height + h * 2),
              light);
        }
      }
      if (kind == PitchSurface.checks) break;
      // And a little unevenness, so the bands are grass and not paint.
      _speckle(canvas, area, spec, dark, 0.8);
    case PitchSurface.wood:
      _woodFloor(canvas, area, spec);
    case PitchSurface.hardCourt:
      _speckle(canvas, area, spec,
          Paint()..color = _lighten(bg, 0.08).withValues(alpha: 0.5), 0.12);
    case PitchSurface.clay:
      _clay(canvas, area, spec);
    case PitchSurface.ice:
      _ice(canvas, area, spec);
    default:
      break;
  }
  canvas.restore();
}

/// _surfaceArea is where the surface's own finish goes: the whole apron for
/// grass, which runs right up to the boards, and the court alone for a floor.
Rect _surfaceArea(_Field field, int kind) =>
    kind == PitchSurface.stripes || kind == PitchSurface.checks
        ? field.apron
        : field.field;

void _speckle(ui.Canvas canvas, Rect area, ProceduralSpec spec, Paint paint,
    double size) {
  if (spec.variation <= 0) return;
  var count =
      (area.width * area.height / (size * size) * 0.08).round().clamp(0, 30000);
  var points = Float32List(count * 2);
  for (var i = 0; i < count; i++) {
    points[i * 2] = area.left + hash(spec.seed, i, 1) * area.width;
    points[i * 2 + 1] = area.top + hash(spec.seed, i, 2) * area.height;
  }
  canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = paint.color.withValues(alpha: paint.color.a * spec.variation)
        ..strokeWidth = size
        ..strokeCap = StrokeCap.round);
}

/// _woodFloor is a maple floor: strips along the length, each its own shade,
/// with the joints between the boards staggered.
void _woodFloor(ui.Canvas canvas, Rect area, ProceduralSpec spec) {
  const strip = 0.0571; // 2¼ inches, the width of a maple floor board.
  var bg = spec.background;
  var count = (area.height / strip).ceil();
  var paint = Paint();
  var joint = Paint()
    ..color = _darken(bg, 0.35).withValues(alpha: 0.35)
    ..strokeWidth = 0.006;
  for (var j = 0; j < count; j++) {
    var y = area.top + j * strip;
    // Each strip a little lighter or darker, which is what reads as wood.
    var shade = (hash(spec.seed, j, 7) - 0.5) * 0.16 * (0.4 + spec.variation);
    paint.color = shade > 0 ? _lighten(bg, shade) : _darken(bg, -shade);
    canvas.drawRect(Rect.fromLTWH(area.left, y, area.width, strip), paint);
    // The boards' ends, staggered from strip to strip.
    var x = area.left + hash(spec.seed, j, 9) * 2.4;
    while (x < area.right) {
      canvas.drawLine(Offset(x, y), Offset(x, y + strip), joint);
      x += 1.2 + hash(spec.seed + j, x.round(), 3) * 1.8;
    }
  }
  // The grain and the varnish's sheen, faintly.
  var noise = ValueNoise(spec.seed);
  var streak = Paint()..strokeWidth = strip * 0.3;
  for (var j = 0; j < count; j += 2) {
    var y = area.top + (j + 0.5) * strip;
    var f = noise.at(j * 0.13, 0.5);
    streak.color = _darken(bg, 0.12).withValues(alpha: 0.2 * f);
    canvas.drawLine(Offset(area.left, y), Offset(area.right, y), streak);
  }
}

/// _clay is a clay court: the surface scuffed paler and darker in patches.
void _clay(ui.Canvas canvas, Rect area, ProceduralSpec spec) {
  var rnd = SeededRandom(spec.seed);
  for (var i = 0; i < 180; i++) {
    var c = Offset(area.left + rnd.next() * area.width,
        area.top + rnd.next() * area.height);
    var r = 0.6 + rnd.next() * 2.5;
    var light = rnd.next() < 0.5;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            (light
                    ? _lighten(spec.background, 0.12)
                    : _darken(spec.background, 0.1))
                .withValues(alpha: 0.35 * (0.3 + spec.variation)),
            spec.background.withValues(alpha: 0),
          ]));
  }
}

/// _ice is a rink's ice: faint arcs where skates have cut it.
void _ice(ui.Canvas canvas, Rect area, ProceduralSpec spec) {
  var rnd = SeededRandom(spec.seed);
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.02
    ..color = _darken(spec.background, 0.12)
        .withValues(alpha: 0.35 * (0.3 + spec.variation));
  for (var i = 0; i < 260; i++) {
    var c = Offset(area.left + rnd.next() * area.width,
        area.top + rnd.next() * area.height);
    var r = 1 + rnd.next() * 6;
    var start = rnd.next() * math.pi * 2;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start,
        0.3 + rnd.next() * 0.8, false, paint);
  }
}

// --------------------------------------------------------------------------
// The markings, each from its own governing body
// --------------------------------------------------------------------------

/// _ends runs [draw] once for each end of the field, with a function
/// measuring inwards from that end's line and the direction inwards.
void _ends(
    _Field f,
    void Function(double Function(double) x, double inward, double facing)
        draw) {
  draw((d) => d, 1, 0);
  draw((d) => f.length - d, -1, math.pi);
}

/// _football: the Laws of the Game, for a 105 by 68 metre pitch.
void _football(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  pen.rect(0, 0, l, w);
  pen.line(l / 2, 0, l / 2, w);
  pen.circle(l / 2, w / 2, 9.15);
  pen.dot(l / 2, w / 2, 0.15);
  _ends(f, (x, inward, facing) {
    pen.rect(x(0), (w - 40.32) / 2, x(16.5), (w + 40.32) / 2);
    pen.rect(x(0), (w - 18.32) / 2, x(5.5), (w + 18.32) / 2);
    pen.dot(x(11), w / 2, 0.11);
    // The arc is the part of the circle round the spot outside the area.
    var reach = math.acos((16.5 - 11) / 9.15);
    pen.arc(x(11), w / 2, 9.15, facing - reach, reach * 2);
    // The optional marks, off the pitch, 9.15 m from each corner arc.
    for (var y in [0.0, w]) {
      var out = y == 0 ? -1.0 : 1.0;
      pen.line(x(10.15), y, x(10.15), y + out * 0.6);
    }
    for (var y in [10.15, w - 10.15]) {
      pen.line(x(0), y, x(-0.6), y);
    }
  });
  _cornerArcs(pen, f, 1);
}

void _cornerArcs(_Pen pen, _Field f, double r) {
  var l = f.length, w = f.width;
  pen.arc(0, 0, r, 0, math.pi / 2);
  pen.arc(0, w, r, -math.pi / 2, math.pi / 2);
  pen.arc(l, 0, r, math.pi / 2, math.pi / 2);
  pen.arc(l, w, r, math.pi, math.pi / 2);
}

/// _futsal: the Futsal Laws of the Game, for a 40 by 20 metre court.
void _futsal(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  pen.rect(0, 0, l, w);
  pen.line(l / 2, 0, l / 2, w);
  pen.circle(l / 2, w / 2, 3);
  pen.dot(l / 2, w / 2, 0.1);
  _ends(f, (x, inward, facing) {
    // The penalty area: quarter circles of 6 m from each post, joined by a
    // straight 3.16 m line.
    var low = w / 2 - 1.58, high = w / 2 + 1.58;
    pen.arc(x(0), low, 6, facing - math.pi / 2 * inward, math.pi / 2 * inward);
    pen.arc(x(0), high, 6, facing, math.pi / 2 * inward);
    pen.line(x(6), low, x(6), high);
    pen.dot(x(6), w / 2, 0.1);
    pen.dot(x(10), w / 2, 0.1);
    // Marks 5 m either side of the second penalty mark.
    for (var y in [w / 2 - 5, w / 2 + 5]) {
      pen.line(x(10), y - 0.04, x(10), y + 0.04);
      pen.dot(x(10), y, 0.05);
    }
    // Marks off the court, 5 m from each corner arc.
    for (var y in [0.0, w]) {
      var out = y == 0 ? -1.0 : 1.0;
      pen.line(x(5.25), y, x(5.25), y + out * 0.4);
    }
  });
  _cornerArcs(pen, f, 0.25);
  // The substitution zones, on the bench side: lines 5 and 10 m from the
  // halfway line, across the touchline.
  for (var d in [-10.0, -5.0, 5.0, 10.0]) {
    pen.line(l / 2 + d, -0.4, l / 2 + d, 0.4);
  }
}

/// _basketballFiba: FIBA's Official Basketball Rules, a 28 by 15 m court.
void _basketballFiba(_Pen pen, _Field f, ProceduralSpec spec, bool painted) {
  var l = f.length, w = f.width;
  var paint = Paint()..color = spec.accent;
  _basketball(
    pen,
    f,
    painted ? paint : null,
    basket: 1.575,
    key: 4.9,
    keyDepth: 5.8,
    freeThrow: 1.8,
    threeRadius: 6.75,
    threeSide: 0.9,
    board: 1.2,
    boardWidth: 1.8,
    noCharge: 1.25,
    noChargeStraight: true,
    centre: 1.8,
    centreInner: 0,
    laneMarks: const [(1.75, 0.1), (2.7, 0.4), (3.95, 0.1), (4.9, 0.1)],
    markOut: 0.1,
  );
  pen.line(l / 2, -0.15, l / 2, w + 0.15);
  // Throw-in lines on the scorer's side, 8.325 m from each end line.
  _ends(f, (x, inward, facing) {
    pen.line(x(8.325), w, x(8.325), w + 0.15);
  });
}

/// _basketballNba: the NBA's 94 by 50 foot court.
void _basketballNba(_Pen pen, _Field f, ProceduralSpec spec, bool painted) {
  var l = f.length, w = f.width;
  var paint = Paint()..color = spec.accent;
  _basketball(
    pen,
    f,
    painted ? paint : null,
    basket: 1.6,
    key: 4.877,
    keyDepth: 5.791,
    freeThrow: 1.829,
    threeRadius: 7.239,
    threeSide: 0.914,
    board: 1.219,
    boardWidth: 1.829,
    noCharge: 1.219,
    noChargeStraight: false,
    centre: 1.829,
    centreInner: 0.61,
    laneMarks: const [
      (2.134, 0.051),
      (2.438, 0.305),
      (3.353, 0.051),
      (4.267, 0.051)
    ],
    markOut: 0.152,
  );
  pen.line(l / 2, 0, l / 2, w);
  // The coaching boxes: 28 feet from each end line, three feet out.
  _ends(f, (x, inward, facing) {
    pen.line(x(8.534), w, x(8.534), w + 0.914);
    pen.line(x(8.534), 0, x(8.534), 0.914);
  });
}

void _basketball(
  _Pen pen,
  _Field f,
  Paint? paint, {
  required double basket,
  required double key,
  required double keyDepth,
  required double freeThrow,
  required double threeRadius,
  required double threeSide,
  required double board,
  required double boardWidth,
  required double noCharge,
  required bool noChargeStraight,
  required double centre,
  required double centreInner,
  required List<(double, double)> laneMarks,
  required double markOut,
}) {
  var l = f.length, w = f.width;
  if (paint != null) {
    pen.canvas.drawCircle(Offset(l / 2, w / 2), centre, paint);
  }
  pen.rect(0, 0, l, w);
  pen.circle(l / 2, w / 2, centre);
  if (centreInner > 0) pen.circle(l / 2, w / 2, centreInner);

  _ends(f, (x, inward, facing) {
    var lo = (w - key) / 2, hi = (w + key) / 2;
    if (paint != null) pen.box(x(0), lo, x(keyDepth), hi, paint);
    pen.rect(x(0), lo, x(keyDepth), hi);
    // The free-throw circle: solid on the court side, dashed in the lane.
    pen.arc(x(keyDepth), w / 2, freeThrow, facing - math.pi / 2, math.pi);
    pen.dashedArc(x(keyDepth), w / 2, freeThrow, facing + math.pi / 2, math.pi,
        0.31, 0.31);
    // The lane marks, out from each side of the lane.
    for (var (at, size) in laneMarks) {
      for (var (y, out) in [(lo, -1.0), (hi, 1.0)]) {
        pen.box(x(at), y, x(at + size), y + out * markOut, pen.fill);
      }
    }
    // The three-point line: straight from the end line, then the arc.
    var side = w / 2 - threeSide;
    var meet = basket +
        math.sqrt(math.max(0, threeRadius * threeRadius - side * side));
    pen.line(x(0), threeSide, x(meet), threeSide);
    pen.line(x(0), w - threeSide, x(meet), w - threeSide);
    var reach = math.asin((side / threeRadius).clamp(-1.0, 1.0));
    pen.arc(x(basket), w / 2, threeRadius, facing - reach, reach * 2);
    // The no-charge semicircle.
    pen.arc(x(basket), w / 2, noCharge, facing - math.pi / 2, math.pi);
    if (noChargeStraight) {
      pen.line(x(basket), w / 2 - noCharge, x(board), w / 2 - noCharge);
      pen.line(x(basket), w / 2 + noCharge, x(board), w / 2 + noCharge);
    }
    // The backboard and the ring, as seen from above.
    pen.thick(0.05).line(
        x(board), w / 2 - boardWidth / 2, x(board), w / 2 + boardWidth / 2);
    pen.thick(0.02).circle(x(basket), w / 2, 0.2286);
    pen.thick(0.02).line(x(board), w / 2, x(basket - 0.2286), w / 2);
  });
}

/// _tennis: the ITF's Rules of Tennis, a 23.77 by 10.97 m doubles court.
void _tennis(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  var s = (w - 8.23) / 2;
  // The baselines may be up to 10 cm wide, and usually are.
  var base = pen.thick(math.max(pen.stroke.strokeWidth, 0.1));
  base.line(0, 0, 0, w);
  base.line(l, 0, l, w);
  pen.line(0, 0, l, 0);
  pen.line(0, w, l, w);
  pen.line(0, s, l, s);
  pen.line(0, w - s, l, w - s);
  for (var x in [l / 2 - 6.4, l / 2 + 6.4]) {
    pen.line(x, s, x, w - s);
  }
  pen.line(l / 2 - 6.4, w / 2, l / 2 + 6.4, w / 2);
  // The centre marks, 10 cm inside each baseline.
  pen.line(0, w / 2, 0.1, w / 2);
  pen.line(l, w / 2, l - 0.1, w / 2);
  // The net, its cord and its posts 0.914 m outside the doubles court.
  pen.thick(0.06).line(l / 2, -0.914, l / 2, w + 0.914);
  pen.dot(l / 2, -0.914, 0.06);
  pen.dot(l / 2, w + 0.914, 0.06);
}

/// _hockey: FIH's Rules of Hockey, a 91.4 by 55 m pitch.
void _hockey(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  pen.rect(0, 0, l, w);
  pen.line(l / 2, 0, l / 2, w);
  pen.line(22.9, 0, 22.9, w);
  pen.line(l - 22.9, 0, l - 22.9, w);
  _ends(f, (x, inward, facing) {
    var low = w / 2 - 1.83, high = w / 2 + 1.83;
    // The shooting circle: quarter circles of 14.63 m from the posts, joined
    // by a straight 3.66 m line.
    void circle(double r, bool dashed) {
      if (dashed) {
        pen.dashedArc(x(0), low, r, facing - math.pi / 2 * inward,
            math.pi / 2 * inward, 0.3, 3);
        pen.dashed(x(r), low, x(r), high, 0.3, 3);
        pen.dashedArc(x(0), high, r, facing, math.pi / 2 * inward, 0.3, 3);
      } else {
        pen.arc(
            x(0), low, r, facing - math.pi / 2 * inward, math.pi / 2 * inward);
        pen.line(x(r), low, x(r), high);
        pen.arc(x(0), high, r, facing, math.pi / 2 * inward);
      }
    }

    circle(14.63, false);
    // The broken line five metres outside it.
    circle(19.63, true);
    pen.dot(x(6.475), w / 2, 0.075);
    // The penalty-corner marks on the back line, 5 and 10 m from the posts,
    // and the long-corner marks on the side lines, 5 m from the back line.
    for (var d in [5.0, 10.0]) {
      for (var y in [low - d, high + d]) {
        pen.line(x(0), y, x(0.3), y);
      }
    }
    pen.line(x(5), 0, x(5), 0.3);
    pen.line(x(5), w, x(5), w - 0.3);
  });
}

/// _iceHockey: the NHL's 200 by 85 foot rink.
void _iceHockey(_Pen pen, _Field f, ProceduralSpec spec, double weight) {
  var l = f.length, w = f.width;
  var red = pen.withColour(spec.accent, 0.0508 * weight);
  var blue = pen.withColour(spec.foreground, 0.0508 * weight);
  var rink = RRect.fromRectAndRadius(f.field, const Radius.circular(8.53));
  pen.canvas.save();
  pen.canvas.clipRRect(rink);
  // The thick lines: red at the middle, blue a little way either side.
  red.thick(0.3048 * weight).line(l / 2, 0, l / 2, w);
  for (var x in [23.01, l - 23.01]) {
    blue.thick(0.3048 * weight).line(x, 0, x, w);
  }
  blue.circle(l / 2, w / 2, 4.572);
  blue.dot(l / 2, w / 2, 0.1524);
  // The referee's crease against the boards.
  red.arc(l / 2, 0, 3.048, 0, math.pi);

  _ends(f, (x, inward, facing) {
    red.line(x(3.353), 0, x(3.353), w);
    // The goal crease, painted, and the trapezoid behind the net.
    var crease = Path()
      ..moveTo(x(3.353), w / 2 - 1.219)
      ..lineTo(x(3.353 + 1.372), w / 2 - 1.219)
      ..arcTo(Rect.fromCircle(center: Offset(x(3.353), w / 2), radius: 1.829),
          facing - 0.729 * inward, 1.458 * inward, false)
      ..lineTo(x(3.353), w / 2 + 1.219)
      ..close();
    pen.canvas.drawPath(
        crease, Paint()..color = spec.foreground.withValues(alpha: 0.28));
    pen.canvas.drawPath(crease, red.stroke);
    red.line(x(3.353), w / 2 - 3.353, x(0), w / 2 - 4.267);
    red.line(x(3.353), w / 2 + 3.353, x(0), w / 2 + 4.267);
    // The end-zone face-off circles, their hash marks and their spots.
    for (var side in [-1.0, 1.0]) {
      var cx = x(3.353 + 6.096), cy = w / 2 + side * 6.706;
      red.circle(cx, cy, 4.572);
      red.dot(cx, cy, 0.3048);
      for (var dx in [-0.43, 0.43]) {
        for (var dy in [-1.0, 1.0]) {
          red.line(cx + dx, cy + dy * 4.572, cx + dx, cy + dy * 5.182);
        }
      }
      // The L-shaped marks round the spot.
      for (var sx in [-1.0, 1.0]) {
        for (var sy in [-1.0, 1.0]) {
          var px = cx + sx * 0.61, py = cy + sy * 0.457;
          red.line(px, py, px + sx * 1.22, py);
          red.line(px, py, px, py + sy * 0.914);
        }
      }
      // The neutral-zone spots, five feet inside the blue line.
      red.dot(x(23.01 + 0.152 + 1.524), cy, 0.3048);
    }
  });
  pen.canvas.restore();
  // The boards.
  pen.canvas.drawRRect(
      rink,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.25
        ..color = _darken(spec.background, 0.65));
}

/// _rugbyUnion: World Rugby's Law 1, a 100 by 70 m field of play with ten
/// metres of in-goal at each end.
void _rugbyUnion(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  var inGoal = 10.0;
  if (spec.on("painted")) {
    var p = Paint()..color = spec.accent.withValues(alpha: 0.22);
    pen.box(-inGoal, 0, 0, w, p);
    pen.box(l, 0, l + inGoal, w, p);
  }
  pen.rect(-inGoal, 0, l + inGoal, w);
  for (var x in <double>[0, 22, 50, 78, l]) {
    pen.line(x, 0, x, w);
  }
  // Dashed: ten metres either side of halfway, and five in from each try
  // line.
  for (var x in <double>[40, 60, 5, l - 5]) {
    pen.dashed(x, 0, x, w, 1, 1);
  }
  // And the lines five and fifteen metres in from touch.
  for (var y in <double>[5, 15, w - 15, w - 5]) {
    pen.dashed(0, y, l, y, 1, 4);
  }
  pen.line(l / 2 - 0.5, w / 2, l / 2 + 0.5, w / 2);
}

/// _rugbyLeague: the Rugby League laws, a 100 by 68 m field with eight
/// metres of in-goal.
void _rugbyLeague(_Pen pen, _Field f, ProceduralSpec spec) {
  var l = f.length, w = f.width;
  var inGoal = 8.0;
  if (spec.on("painted")) {
    var p = Paint()..color = spec.accent.withValues(alpha: 0.22);
    pen.box(-inGoal, 0, 0, w, p);
    pen.box(l, 0, l + inGoal, w, p);
  }
  pen.rect(-inGoal, 0, l + inGoal, w);
  for (var x = 0.0; x <= l; x += 10) {
    pen.line(x, 0, x, w);
  }
  // Short dashes ten and twenty metres in from touch on every line.
  for (var y in <double>[10, 20, w - 20, w - 10]) {
    for (var x = 10.0; x < l; x += 10) {
      pen.line(x - 0.5, y, x + 0.5, y);
    }
  }
  if (spec.on("numbers")) {
    var colour = pen.stroke.color;
    for (var x = 10.0; x < l; x += 10) {
      var n = (x <= 50 ? x : l - x).round();
      var label = n == 50 ? "50" : "$n";
      pen.text(label, x, 6, 2.2, -math.pi / 2, colour);
      pen.text(label, x, w - 6, 2.2, math.pi / 2, colour);
    }
  }
}

/// _gridiron: the NFL's 120 by 53⅓ yard field, end zones included.
void _gridiron(_Pen pen, _Field f, ProceduralSpec spec, bool painted) {
  const yd = 0.9144;
  var l = f.length, w = f.width;
  var colour = pen.stroke.color;
  // The six-foot white border round the field.
  var border = Paint()..color = colour;
  pen.box(-1.83, -1.83, l + 1.83, 0, border);
  pen.box(-1.83, w, l + 1.83, w + 1.83, border);
  pen.box(-1.83, 0, 0, w, border);
  pen.box(l, 0, l + 1.83, w, border);
  if (painted) {
    var p = Paint()..color = spec.accent;
    pen.box(0, 0, 10 * yd, w, p);
    pen.box(l - 10 * yd, 0, l, w, p);
  }
  // A yard line every five yards, the goal lines among them.
  for (var y = 10; y <= 110; y += 5) {
    pen.line(y * yd, 0, y * yd, w);
  }
  // Every other yard: a short mark at each sideline and at each hash.
  var hash = 21.56; // 70'9" in from each sideline.
  for (var y = 11; y < 110; y++) {
    var x = y * yd;
    if (y % 5 != 0) {
      pen.line(x, 0.1, x, 0.71);
      pen.line(x, w - 0.1, x, w - 0.71);
    }
    pen.line(x, hash - 0.61, x, hash);
    pen.line(x, w - hash, x, w - hash + 0.61);
  }
  // The try line for a two-point conversion, two yards out.
  for (var x in [12 * yd, l - 12 * yd]) {
    pen.line(x, w / 2 - yd / 2, x, w / 2 + yd / 2);
  }
  if (spec.on("numbers")) {
    // Six feet tall, their tops nine yards from the sideline, with the
    // arrows pointing to the nearer goal.
    for (var n = 10; n <= 50; n += 10) {
      for (var x in {(10 + n) * yd, l - (10 + n) * yd}) {
        for (var (y, facing) in [
          (8 * yd, -math.pi / 2),
          (w - 8 * yd, math.pi / 2)
        ]) {
          pen.text("$n", x, y, 1.83, facing, colour);
          if (n == 50) continue;
          var toward = x < l / 2 ? -1.0 : 1.0;
          var ax = x + toward * 1.95;
          var path = Path()
            ..moveTo(ax + toward * 0.46, y)
            ..lineTo(ax, y - 0.23)
            ..lineTo(ax, y + 0.23)
            ..close();
          pen.canvas.drawPath(path, Paint()..color = colour);
        }
      }
    }
  }
}

// --------------------------------------------------------------------------
// What stands up off the ground
// --------------------------------------------------------------------------

/// _standDepth is how far the stands run back from the boards, and
/// _standHeight how high they rise: in proportion to what they are round, so
/// an arena round a court is not a football stadium round a postage stamp.
double _standDepth(Rect window) =>
    (math.max(window.width, window.height) * 0.24).clamp(7.0, 26.0);
double _standHeight(Rect window) => _standDepth(window) * 0.62;

Rect _standOuter(Rect window) => window.inflate(5 + _standDepth(window));

/// _trackOuter is the outside of a 400 m running track round the field.
Rect _trackOuter(_Field f) {
  var c = f.field.center;
  return Rect.fromCenter(
      center: c, width: 84.39 + 2 * 46.26, height: 2 * 46.26);
}

/// _track is a standard 400 m track round the field: two straights of
/// 84.39 m, bends of 36.5 m radius, eight lanes of 1.22 m.
void _track(ui.Canvas canvas, _Field f, ProceduralSpec spec) {
  var c = f.field.center;
  RRect oval(double r) => RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 84.39 + 2 * r, height: 2 * r),
      Radius.circular(r));
  canvas.drawRRect(oval(36.5 + 8 * 1.22 + 1),
      Paint()..color = _darken(spec.background, 0.3));
  canvas.drawRRect(
      oval(36.5 + 8 * 1.22), Paint()..color = const Color(0xFFB4513A));
  canvas.drawRRect(oval(36.5), Paint()..color = _darken(spec.background, 0.12));
  var lane = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..color = const Color(0xE6FFFFFF);
  for (var i = 0; i <= 8; i++) {
    canvas.drawRRect(oval(36.5 + i * 1.22), lane);
  }
}

/// _ring is points round a rounded rectangle [d] metres outside [window].
List<Offset> _ring(Rect window, double d, double corner) {
  var r = corner + d;
  var box = window.inflate(d);
  var pts = <Offset>[];
  void arc(Offset c, double start) {
    for (var i = 0; i <= 6; i++) {
      var a = start + i / 6 * math.pi / 2;
      pts.add(c + Offset(math.cos(a), math.sin(a)) * r);
    }
  }

  // Corners, joined by the straights between them; each straight cut into
  // pieces so that sorting by distance from the camera works piece by piece.
  // As many pieces at every distance out, worked out from the window alone,
  // so that one ring's points pair with the next ring's.
  var along = math.max(1, ((window.width - 2 * corner) / 6).round());
  var across = math.max(1, ((window.height - 2 * corner) / 6).round());
  void straight(Offset a, Offset b, int n) {
    for (var i = 1; i < n; i++) {
      pts.add(Offset.lerp(a, b, i / n)!);
    }
  }

  arc(Offset(box.right - r, box.bottom - r), 0);
  straight(pts.last, Offset(box.left + r, box.bottom), along);
  arc(Offset(box.left + r, box.bottom - r), math.pi / 2);
  straight(pts.last, Offset(box.left, box.top + r), across);
  arc(Offset(box.left + r, box.top + r), math.pi);
  straight(pts.last, Offset(box.right - r, box.top), along);
  arc(Offset(box.right - r, box.top + r), math.pi * 1.5);
  straight(pts.last, Offset(box.right, box.bottom - r), across);
  return pts;
}

/// _stadium is the boards round the pitch and the stands rising behind
/// them -- the near stand left out where the camera is in it.
void _stadium(ui.Canvas canvas, _View view, _Field f, ProceduralSpec spec,
    Rect ground, List<(double, void Function())> items) {
  var window = _View._window(spec, f, false);
  var centre = window.center;
  var seat = spec.accent;
  var concrete = _darken(spec.background, 0.62);

  bool facesCamera(Offset a, Offset b) {
    if (view.flat) return false;
    // A stand whose seats face away from the camera is the near one: what
    // the camera would see is its back, from inside it.
    var mid = (a + b) / 2;
    var out = mid - centre;
    var d0 = view.depthOf(mid.dx, mid.dy);
    var d1 = view.depthOf(mid.dx + out.dx * 0.01, mid.dy + out.dy * 0.01);
    return d1 < d0;
  }

  void quad(List<Offset> pts, Color colour) {
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = colour);
  }

  // The advertising boards, a metre high, two metres outside the apron.
  var boards = _ring(window, 2, 2);
  for (var i = 0; i < boards.length; i++) {
    var a = boards[i], b = boards[(i + 1) % boards.length];
    if ((b - a).distance < 0.01) continue;
    var panel = i.isEven ? seat : _lighten(seat, 0.25);
    var d = view.depthOf((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    items.add((
      d,
      () {
        quad([
          view.project(a.dx, a.dy),
          view.project(b.dx, b.dy),
          view.project(b.dx, b.dy, 0.9),
          view.project(a.dx, a.dy, 0.9),
        ], panel);
      }
    ));
  }

  // The stands: rows of seats rising away from the pitch.
  const rows = 22;
  var rings = [
    for (var r = 0; r <= rows; r++)
      _ring(window, 5 + r * _standDepth(window) / rows, 6),
  ];
  for (var r = 0; r < rows; r++) {
    var z0 = 1.5 + r * _standHeight(window) / rows,
        z1 = z0 + _standHeight(window) / rows;
    var inner = rings[r], outer = rings[r + 1];
    for (var i = 0; i < inner.length; i++) {
      var j = (i + 1) % inner.length;
      if (facesCamera(inner[i], inner[j])) continue;
      var aisle = i % 9 == 0;
      var tone = aisle
          ? _lighten(concrete, 0.25)
          : (r.isEven ? _darken(seat, 0.25) : _darken(seat, 0.4));
      // A little of the crowd in it: no two blocks of seats quite alike.
      var crowd = (hash(spec.seed, i, r) - 0.5) * 0.16 * (0.4 + spec.variation);
      tone = crowd > 0 ? _lighten(tone, crowd) : _darken(tone, -crowd);
      var d = view.depthOf((inner[i].dx + outer[j].dx) / 2,
          (inner[i].dy + outer[j].dy) / 2, (z0 + z1) / 2);
      items.add((
        d,
        () {
          // The riser, then the tread on top of it.
          quad([
            view.project(inner[i].dx, inner[i].dy, z0),
            view.project(inner[j].dx, inner[j].dy, z0),
            view.project(inner[j].dx, inner[j].dy, z1),
            view.project(inner[i].dx, inner[i].dy, z1),
          ], _darken(tone, 0.3));
          quad([
            view.project(inner[i].dx, inner[i].dy, z1),
            view.project(inner[j].dx, inner[j].dy, z1),
            view.project(outer[j].dx, outer[j].dy, z1),
            view.project(outer[i].dx, outer[i].dy, z1),
          ], tone);
        }
      ));
    }
  }
  // The roof's edge along the top of the stands.
  var top = rings.last;
  for (var i = 0; i < top.length; i++) {
    var j = (i + 1) % top.length;
    if (facesCamera(top[i], top[j])) continue;
    var z = 1.5 + _standHeight(window);
    var d = view.depthOf(top[i].dx, top[i].dy, z) - 0.5;
    items.add((
      d,
      () {
        quad([
          view.project(top[i].dx, top[i].dy, z),
          view.project(top[j].dx, top[j].dy, z),
          view.project(top[j].dx, top[j].dy, z + 2.5),
          view.project(top[i].dx, top[i].dy, z + 2.5),
        ], _darken(concrete, 0.3));
      }
    ));
  }
}

/// _goals is what each sport scores into, standing up off the ground.
void _goals(ui.Canvas canvas, _View view, _Field f, ProceduralSpec spec,
    List<(double, void Function())> items,
    {double from = -1e9}) {
  var l = f.length, w = f.width;
  var white = spec.foreground;
  var px = math.max(1.2, view.pixelsPerMetre * 0.12);
  Paint post([Color? c, double width = 1]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = px * width
    ..color = c ?? white;
  var net = Paint()..color = white.withValues(alpha: 0.16);
  var mesh = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, px * 0.25)
    ..color = white.withValues(alpha: 0.35);

  Offset p(double x, double y, [double z = 0]) => view.project(x, y, z);
  // Only the ones on the part of the ground that is shown.
  void add(double x, double y, void Function() draw) {
    if (x < from) return;
    items.add((view.depthOf(x, y, 1), draw));
  }

  /// box is a goal frame: posts [width] apart on the line at [x], [height]
  /// high, with its net running [depth] back.
  void box(double x, double inward, double width, double height, double depth,
      {Color? colour, bool backboard = false}) {
    var lo = w / 2 - width / 2, hi = w / 2 + width / 2;
    var back = x - inward * depth;
    add(x, w / 2, () {
      var net3 = [
        // The back, and the two sides.
        [
          p(back, lo),
          p(back, hi),
          p(back, hi, height * 0.8),
          p(back, lo, height * 0.8)
        ],
        [p(x, lo), p(back, lo), p(back, lo, height * 0.8), p(x, lo, height)],
        [p(x, hi), p(back, hi), p(back, hi, height * 0.8), p(x, hi, height)],
        [
          p(x, lo, height),
          p(x, hi, height),
          p(back, hi, height * 0.8),
          p(back, lo, height * 0.8)
        ],
      ];
      for (var face in net3) {
        canvas.drawPath(Path()..addPolygon(face, true), net);
        canvas.drawPath(Path()..addPolygon(face, true), mesh);
      }
      if (backboard) {
        canvas.drawPath(
            Path()
              ..addPolygon([
                p(back, lo),
                p(back, hi),
                p(back, hi, 0.46),
                p(back, lo, 0.46)
              ], true),
            Paint()..color = _darken(spec.background, 0.5));
      }
      var frame = post(colour);
      canvas.drawLine(p(x, lo), p(x, lo, height), frame);
      canvas.drawLine(p(x, hi), p(x, hi, height), frame);
      canvas.drawLine(p(x, lo, height), p(x, hi, height), frame);
    });
  }

  /// hPosts are a rugby goal: uprights [apart] apart on the line at [x],
  /// with a crossbar three metres up.
  void hPosts(double x, double apart, double tall) {
    var lo = w / 2 - apart / 2, hi = w / 2 + apart / 2;
    add(x, w / 2, () {
      var pads = post(spec.accent, 3.5);
      canvas.drawLine(p(x, lo), p(x, lo, 1.8), pads);
      canvas.drawLine(p(x, hi), p(x, hi, 1.8), pads);
      var upright = post(white, 1.2);
      canvas.drawLine(p(x, lo), p(x, lo, tall), upright);
      canvas.drawLine(p(x, hi), p(x, hi, tall), upright);
      canvas.drawLine(p(x, lo, 3), p(x, hi, 3), upright);
    });
  }

  switch (f.sport) {
    case PitchSport.football:
      box(0, 1, 7.32, 2.44, 2);
      box(l, -1, 7.32, 2.44, 2);
    case PitchSport.futsal:
      box(0, 1, 3, 2, 1);
      box(l, -1, 3, 2, 1);
    case PitchSport.hockey:
      box(0, 1, 3.66, 2.14, 1.2, backboard: true);
      box(l, -1, 3.66, 2.14, 1.2, backboard: true);
    case PitchSport.iceHockey:
      box(3.353, 1, 1.829, 1.219, 1.016, colour: spec.accent);
      box(l - 3.353, -1, 1.829, 1.219, 1.016, colour: spec.accent);
    case PitchSport.rugby:
      hPosts(0, 5.6, 13);
      hPosts(l, 5.6, 13);
    case PitchSport.rugbyLeague:
      hPosts(0, 5.5, 13);
      hPosts(l, 5.5, 13);
    case PitchSport.americanFootball:
      // A single-standard post: up from behind the end line, then forward
      // over it, a crossbar ten feet up and uprights thirty-five feet above.
      for (var (x, inward) in [(0.0, 1.0), (l, -1.0)]) {
        var lo = w / 2 - 2.82, hi = w / 2 + 2.82;
        add(x, w / 2, () {
          var yellow = post(const Color(0xFFF2C230), 1.4);
          var base = x - inward * 1.83;
          canvas.drawLine(p(base, w / 2), p(base, w / 2, 2.6), yellow);
          canvas.drawLine(p(base, w / 2, 2.6), p(x, w / 2, 3.05), yellow);
          canvas.drawLine(p(x, lo, 3.05), p(x, hi, 3.05), yellow);
          canvas.drawLine(p(x, lo, 3.05), p(x, lo, 13.72), yellow);
          canvas.drawLine(p(x, hi, 3.05), p(x, hi, 13.72), yellow);
        });
      }
    case PitchSport.basketball:
    case PitchSport.basketballNba:
      var nba = f.sport == PitchSport.basketballNba;
      var basket = nba ? 1.6 : 1.575, board = nba ? 1.219 : 1.2;
      var bw = nba ? 1.829 : 1.8;
      for (var (x0, inward) in [(0.0, 1.0), (l, -1.0)]) {
        double x(double d) => x0 + inward * d;
        add(x(board), w / 2, () {
          // The stanchion behind the end line, the arm, the board and the
          // ring at ten feet.
          var stand = post(_darken(spec.background, 0.6), 1.6);
          canvas.drawLine(p(x(-1.2), w / 2), p(x(-1.2), w / 2, 2.9), stand);
          canvas.drawLine(
              p(x(-1.2), w / 2, 2.9), p(x(board), w / 2, 2.9), stand);
          canvas.drawPath(
              Path()
                ..addPolygon([
                  p(x(board), w / 2 - bw / 2, 2.9),
                  p(x(board), w / 2 + bw / 2, 2.9),
                  p(x(board), w / 2 + bw / 2, 3.95),
                  p(x(board), w / 2 - bw / 2, 3.95),
                ], true),
              Paint()..color = const Color(0x55FFFFFF));
          canvas.drawPath(
              Path()
                ..addPolygon([
                  p(x(board), w / 2 - bw / 2, 2.9),
                  p(x(board), w / 2 + bw / 2, 2.9),
                  p(x(board), w / 2 + bw / 2, 3.95),
                  p(x(board), w / 2 - bw / 2, 3.95),
                ], true),
              post(white, 0.5));
          var ring = <Offset>[
            for (var k = 0; k <= 16; k++)
              p(x(basket) + math.cos(k / 16 * math.pi * 2) * 0.2286,
                  w / 2 + math.sin(k / 16 * math.pi * 2) * 0.2286, 3.05),
          ];
          canvas.drawPath(Path()..addPolygon(ring, true),
              post(const Color(0xFFE8622A), 0.6));
        });
      }
    case PitchSport.tennis:
      add(l / 2, w / 2, () {
        var lo = -0.914, hi = w + 0.914;
        var face = [
          p(l / 2, lo),
          p(l / 2, hi),
          p(l / 2, hi, 1.07),
          p(l / 2, w / 2, 0.914),
          p(l / 2, lo, 1.07),
        ];
        canvas.drawPath(Path()..addPolygon(face, true),
            Paint()..color = const Color(0x66000000));
        canvas.drawPath(Path()..addPolygon(face, true), mesh);
        var band = post(white, 0.6);
        canvas.drawLine(p(l / 2, lo, 1.07), p(l / 2, w / 2, 0.914), band);
        canvas.drawLine(p(l / 2, w / 2, 0.914), p(l / 2, hi, 1.07), band);
        var postPaint = post(_darken(spec.background, 0.6));
        canvas.drawLine(p(l / 2, lo), p(l / 2, lo, 1.07), postPaint);
        canvas.drawLine(p(l / 2, hi), p(l / 2, hi, 1.07), postPaint);
      });
    case PitchSport.blank:
      break;
  }
}

/// _floodlights are four soft pools of light from the corners.
void _floodlights(
    ui.Canvas canvas, Rect rect, _View view, _Field f, ProceduralSpec spec) {
  var r = math.max(rect.width, rect.height) * 0.55;
  canvas.saveLayer(rect, Paint());
  for (var (x, y) in [
    (0.0, 0.0),
    (f.length, 0.0),
    (0.0, f.width),
    (f.length, f.width)
  ]) {
    var c = view.project(x, y);
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
