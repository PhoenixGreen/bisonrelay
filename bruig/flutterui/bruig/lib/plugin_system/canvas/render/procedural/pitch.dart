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

/// PitchPlacement is where a pitch puts a point on it, as it is drawn: with
/// its camera, its zoom, its position and its turn.
///
/// What a team linked to the pitch stands on. The team keeps its players in
/// the pitch's own metres and asks this where they are, so that moving,
/// turning, zooming or tilting the pitch carries them with it -- in
/// perspective, smaller towards the far touchline.
class PitchPlacement {
  final _View _view;
  final _Field _field;
  final Offset _pivot;
  final double _turn;

  /// visibleFrom is the length along the field from which it is shown, for
  /// half a pitch; nought for the whole of it.
  final double visibleFrom;

  /// reference is how many pixels a metre is on this pitch drawn flat,
  /// across and unzoomed -- what a team's dot sizes are measured against.
  final double reference;

  PitchPlacement._(this._view, this._field, this._pivot, this._turn,
      this.visibleFrom, this.reference);

  double get length => _field.length;
  double get width => _field.width;
  PitchSport get sport => _field.sport;

  /// flat is whether the pitch is seen from straight above.
  bool get flat => _view.flat;

  /// page is where [x], [y] -- metres along and across the field -- and
  /// [z] metres above it land on the page.
  Offset page(double x, double y, [double z = 0]) =>
      _turned(_view.project(x, y, z), _turn);

  /// field is the point on the field under [page], or null where there is
  /// no field under it.
  Offset? field(Offset page) => _view.unproject(_turned(page, -_turn));

  /// scaleAt is how many pixels a metre standing at [x], [y] takes up.
  double scaleAt(double x, double y) => _view.pixelsPerMetreAt(x, y);

  /// depthOf is how far [x], [y] is from the camera, for drawing nearer
  /// things over further ones.
  double depthOf(double x, double y) => _view.depthOf(x, y);

  Offset _turned(Offset p, double by) {
    if (by == 0) return p;
    var c = math.cos(by), s = math.sin(by);
    var d = p - _pivot;
    return _pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }
}

/// pitchPlacement is where [spec]'s pitch, drawn into [rect], puts things.
PitchPlacement pitchPlacement(Rect rect, ProceduralSpec spec) {
  var field = _Field.of(spec.sport);
  var view = _View.fit(rect, spec, field);
  var half = spec.choice("area") == 1;
  return PitchPlacement._(
    view,
    field,
    rect.center,
    spec.rotation * math.pi / 180,
    half ? _View._window(spec, field, true).left : -1e9,
    pitchRect(rect, spec.sport).scale,
  );
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

  /// side is the camera swung round to one side of the picture, in radians:
  /// tilting the ground about the page's own upright.
  final double side;

  /// distance is the camera's distance from the middle of the ground, for a
  /// view in perspective; nought for one without.
  final double distance;
  double scale = 1, ox = 0, oy = 0;

  _View(this.cx, this.cy, this.upright, this.azimuth, this.elevation,
      this.distance,
      [this.side = 0]);

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
    // Swung round to the side: across and depth turned about the upright.
    var ch = math.cos(side), sh = math.sin(side);
    var across = px * ch - depth * sh;
    depth = px * sh + depth * ch;
    if (distance <= 0) return (across, up, depth);
    var k = distance / math.max(distance * 0.05, distance + depth);
    return (across * k, up * k, depth);
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
    var ch = math.cos(side), sh = math.sin(side);
    // On the ground: across, up and depth are each a row in x, y and 1.
    var across = [for (var i = 0; i < 3; i++) pr[i] * ch - cp * qr[i] * sh];
    var depth = [for (var i = 0; i < 3; i++) pr[i] * sh + cp * qr[i] * ch];
    var up = [for (var i = 0; i < 3; i++) sp * qr[i]];
    var persp = distance > 0;
    var w = persp ? [depth[0], depth[1], distance + depth[2]] : [0.0, 0.0, 1.0];
    var f = persp ? distance : 1.0;
    var hx = [for (var i = 0; i < 3; i++) ox * w[i] + scale * f * across[i]];
    var hy = [for (var i = 0; i < 3; i++) oy * w[i] - scale * f * up[i]];
    return Float64List.fromList([
      hx[0], hy[0], 0, w[0], //
      hx[1], hy[1], 0, w[1], //
      0, 0, 1, 0, //
      hx[2], hy[2], 0, w[2],
    ]);
  }

  /// pixelsPerMetre is how big a metre is in the middle of the picture.
  double get pixelsPerMetre => scale;

  /// pixelsPerMetreAt is how big a metre standing upright at [x], [y] looks
  /// -- smaller the further it is from the camera.
  double pixelsPerMetreAt(double x, double y) {
    if (distance <= 0) return scale;
    var depth = camera(x, y, 0).$3;
    return scale * distance / math.max(distance * 0.05, distance + depth);
  }

  /// unproject is the point on the ground under [page], or null where the
  /// ground is not under it at all -- above the horizon.
  Offset? unproject(Offset page) {
    var m = ground();
    // The homography's own three rows, out of the 4x4 it is handed in as.
    var a = m[0], b = m[4], c = m[12];
    var d = m[1], e = m[5], f = m[13];
    var g = m[3], h = m[7], i = m[15];
    var det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-12) return null;
    // The inverse, by cofactors, applied to (X, Y, 1).
    var x = page.dx, y = page.dy;
    var gx = (e * i - f * h) * x + (c * h - b * i) * y + (b * f - c * e);
    var gy = (f * g - d * i) * x + (a * i - c * g) * y + (c * d - a * f);
    var gw = (d * h - e * g) * x + (b * g - a * h) * y + (a * e - b * d);
    if (gw.abs() < 1e-12) return null;
    var wx = gx / gw, wy = gy / gw;
    // Behind the camera is not on the ground in front of it.
    if (distance > 0 && distance + camera(wx, wy, 0).$3 <= 0) return null;
    return Offset(wx, wy);
  }

  /// flat is whether the ground is seen from straight above.
  bool get flat => elevation > math.pi / 2 - 0.01 && side.abs() < 0.01;

  /// fit is the view [spec] asks for, fitted into [rect].
  static _View fit(Rect rect, ProceduralSpec spec, _Field field) {
    var half = spec.choice("area") == 1;
    var window = _window(spec, field, half);
    var cam = pitchCamera(spec);
    var reach = math.max(window.width, window.height);
    var view = _View(
      window.center.dx,
      window.center.dy,
      spec.choice("runs") == 1,
      cam.turn * math.pi / 180,
      (90 - cam.tilt) * math.pi / 180,
      // Perspective as how close the camera is: none at nought, which is a
      // drawing rather than a photograph, and a wide lens at one.
      cam.perspective <= 0 ? 0 : reach * (1 + (1 - cam.perspective) * 6),
      cam.side * math.pi / 180,
    );

    // Fitted to the corners of what has to be seen, and to the tops of the
    // stands where there are any.
    var points = <(double, double, double)>[
      for (var x in [window.left, window.right])
        for (var y in [window.top, window.bottom]) (x, y, 0),
    ];
    if (spec.choice("surround") == 1) {
      // Round exactly what is drawn of the stands -- the near one is left
      // out where the camera is in it, and the corners of an open ground --
      // so none of it is cut off at the frame and none of the frame is left
      // empty for it.
      points.addAll(_stadiumExtent(view, window, spec));
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

    // Then zoomed about the middle of the frame, and moved: the Size and
    // the two position settings.
    var c = available.center;
    var zoom = (spec.scale / 0.05).clamp(0.05, 20.0);
    view.scale *= zoom;
    view.ox = c.dx + (view.ox - c.dx) * zoom + cam.x * rect.width / 2;
    view.oy = c.dy + (view.oy - c.dy) * zoom - cam.y * rect.height / 2;
    return view;
  }

  /// _window is the part of the ground that is shown, in metres.
  static Rect _window(ProceduralSpec spec, _Field field, bool half) {
    var plain = spec.choice("surround") == 0 &&
        spec.choice("view") == PitchViewKind.flat;
    var box = plain && field.fitsField ? field.field : field.apron;
    if (spec.choice("surround") == 2) {
      box = box.expandToInclude(_trackOuter(field, spec));
    }
    if (half) {
      box = Rect.fromLTRB(
          field.length / 2 - field.line * 4, box.top, box.right, box.bottom);
    }
    return box;
  }
}

/// PitchCamera is where a pitch is seen from, in the settings' own terms:
/// degrees of tilt up and down and to the side, degrees of turn on the
/// ground, how strong the perspective is, and where the picture is moved to.
typedef PitchCamera = ({
  double tilt,
  double side,
  double turn,
  double perspective,
  double x,
  double y,
});

/// pitchCamera is [spec]'s camera. See pitchCameraParams.
PitchCamera pitchCamera(ProceduralSpec spec) {
  var p = pitchCameraParams(spec.params);
  double get(String id) => p[id] ?? 0;
  return (
    tilt: get("tiltV").clamp(0.0, 80.0),
    side: get("tiltH").clamp(-60.0, 60.0),
    turn: get("turn"),
    perspective: get("perspective").clamp(0.0, 1.0),
    x: get("panX").clamp(-3.0, 3.0),
    y: get("panY").clamp(-3.0, 3.0),
  );
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
void paintPitch(ui.Canvas canvas, Rect rect, ProceduralSpec spec,
    {Rect? cover}) {
  var field = _Field.of(spec.sport);
  var all = cover ?? rect;
  var view = _View.fit(rect, spec, field);
  if (view.scale <= 0) return;
  var surround = spec.choice("surround");
  var painted = spec.on("painted");

  // What is round it all.
  canvas.drawRect(all, Paint()..color = _darken(spec.background, 0.45));
  if (!view.flat) {
    // A sky of sorts, where the ground stops short of the top of the frame.
    canvas.drawRect(
        all,
        Paint()
          ..shader = ui.Gradient.linear(all.topCenter, all.bottomCenter, [
            _darken(spec.background, 0.7),
            _darken(spec.background, 0.45),
          ]));
  }

  var lineColour = spec.foreground.withValues(
      alpha: (spec.foreground.a * (0.55 + spec.intensity * 0.45)).clamp(0, 1));
  var weight = spec.p("lineWeight");
  var minimum = 0.9 / view.pixelsPerMetre;

  canvas.save();
  canvas.clipRect(all);
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
  if (surround == 2) {
    // The track goes down first, and the field fills the infield inside
    // its kerb -- not a rectangle of grass laid over the bends.
    _track(canvas, field, spec);
    canvas.save();
    canvas.clipRRect(_oval(field, _trackInner - 0.2));
    canvas.drawRRect(_oval(field, _trackInner),
        Paint()..color = _darken(spec.background, 0.08));
  }
  _surface(canvas, field, spec, ground, painted,
      infield: surround == 2 ? _oval(field, _trackInner).outerRect : null);

  var pen = _Pen(canvas, lineColour, field.line * weight, minimum);
  if (surround == 2) {
    _trackDetails(pen, field, spec);
    canvas.restore();
    _trackOutside(pen, field, spec);
  }
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
  var far = <(double, void Function())>[];
  var near = <(double, void Function())>[];
  if (surround == 1) {
    _stadium(canvas, view, field, spec, ground, items, far: far, near: near);
  }
  if (spec.on("goals")) {
    _goals(canvas, view, field, spec, items,
        from: half ? _View._window(spec, field, true).left : -1e9);
  }
  // Furthest first, the stands softened by how far they are from the pitch
  // -- a little behind it, more and more in front of it, where they fade as
  // well -- and never over the pitch itself.
  _drawStadium(canvas, view, field, spec, all, items, far, near);
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
    bool painted,
    {Rect? infield}) {
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
    canvas.drawRect(infield ?? field.apron, Paint()..color = runoff);
  }
  canvas.drawPath(shape, Paint()..color = bg);

  canvas.save();
  var area = _surfaceArea(field, kind);
  // Round a track, grass runs right out to the kerb.
  if (infield != null && area == field.apron) area = infield;
  canvas.clipPath(ice ? shape : (Path()..addRect(area)));
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
/// an arena round a court is not a football stadium round a postage stamp --
/// and as big again as the stadium's Size asks.
double _standDepth(Rect window, [ProceduralSpec? spec]) =>
    (math.max(window.width, window.height) * 0.24).clamp(7.0, 26.0) *
    (spec?.p("standSize") ?? 1);
double _standHeight(Rect window, [ProceduralSpec? spec]) =>
    _standDepth(window, spec) * 0.62;

/// _tiers is how many tiers the stands are built in, and _tierGap the
/// walkway between one and the next.
int _tiers(ProceduralSpec? spec) => (spec?.p("tiers") ?? 1).round().clamp(1, 3);
const double _tierGap = 1.4;

/// _standReach is how far out from the window the back of the stands is.
double _standReach(Rect window, [ProceduralSpec? spec]) =>
    5 + _standDepth(window, spec) + _tierGap * (_tiers(spec) - 1);

/// _standTop is how high the top of the stands is, roof and all.
double _standTop(Rect window, [ProceduralSpec? spec]) =>
    1.5 +
    _standHeight(window, spec) +
    1.8 * (_tiers(spec) - 1) +
    ((spec?.choice("roof") ?? 0) > 0 ? 3.5 : 2.5);

/// _trackInner and _trackLane are the inside of a 400 m track's first lane
/// and the width of a lane; _trackStraight its two straights.
const double _trackInner = 36.5, _trackLane = 1.22, _trackStraight = 84.39;

int _lanes(ProceduralSpec spec) => spec.p("lanes").round().clamp(4, 10);

/// _trackOuter is everything a track brings round the field: the lanes, the
/// verge outside them and the long-jump runway along the back straight.
Rect _trackOuter(_Field f, [ProceduralSpec? spec]) {
  var c = f.field.center;
  var outer = _trackInner + (spec == null ? 8 : _lanes(spec)) * _trackLane;
  return Rect.fromCenter(
      center: c,
      width: _trackStraight + 2 * (outer + 2.5),
      height: 2 * (outer + 9));
}

/// _oval is the track's shape [r] metres out from its middle: two straights
/// and two bends.
RRect _oval(_Field f, double r) => RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: f.field.center, width: _trackStraight + 2 * r, height: 2 * r),
    Radius.circular(r));

const _trackColours = [
  Color(0xFFB4513A), // the classic red
  Color(0xFF2F5FA8), // blue
  Color(0xFF3E7D4A), // green
  Color(0xFF6E6E70), // grey
  Color(0xFF6A3F8E), // purple
];

/// _track is the running track's ground: the verge round it, the lanes and
/// the kerb. Laid before the field, which then fills the infield inside the
/// kerb; the field events go on after it -- see _trackDetails.
void _track(ui.Canvas canvas, _Field f, ProceduralSpec spec) {
  var lanes = _lanes(spec);
  var outer = _trackInner + lanes * _trackLane;
  var colour = _trackColours[spec.choice("trackColour").clamp(0, 4)];
  // The verge, and the track itself.
  canvas.drawRRect(
      _oval(f, outer + 2.5), Paint()..color = _darken(spec.background, 0.22));
  canvas.drawRRect(_oval(f, outer), Paint()..color = colour);
  // The rubber's grain, faintly.
  canvas.save();
  canvas.clipRRect(_oval(f, outer));
  _speckle(canvas, _oval(f, outer).outerRect, spec,
      Paint()..color = _lighten(colour, 0.15).withValues(alpha: 0.6), 0.25);
  canvas.restore();
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..color = const Color(0xEEFFFFFF);
  for (var i = 1; i <= lanes; i++) {
    canvas.drawRRect(_oval(f, _trackInner + i * _trackLane), line);
  }
  // The kerb: a raised rim along the inside of the first lane.
  canvas.drawRRect(
      _oval(f, _trackInner - 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.2
        ..color = const Color(0xFFE8E8E8));
}

/// _trackDetails is what is painted on a track and in its infield: the
/// finish line and the lane numbers, the staggered starts round the first
/// bend, and the field events in the two ends of the infield.
void _trackDetails(_Pen pen, _Field f, ProceduralSpec spec) {
  var lanes = _lanes(spec);
  var outer = _trackInner + lanes * _trackLane;
  var colour = _trackColours[spec.choice("trackColour").clamp(0, 4)];
  var c = f.field.center;
  var canvas = pen.canvas;
  var white = pen.withColour(const Color(0xF2FFFFFF), 0.05);
  var home = c.dy - _trackInner; // the home straight runs along the bottom
  var finishX = c.dx + _trackStraight / 2 - 2;

  if (spec.on("markings")) {
    // The finish line, and the lane numbers before it.
    white.thick(0.05).line(finishX, home, finishX, c.dy - outer);
    for (var i = 0; i < lanes; i++) {
      var y = home - (i + 0.5) * _trackLane;
      white.text("${i + 1}", finishX - 2.2, y, 0.8, -math.pi / 2,
          const Color(0xF2FFFFFF));
    }
    // The staggered starts for a full lap, round the first bend: each lane
    // starts further on by the extra its bend is longer.
    var bend = Offset(c.dx + _trackStraight / 2, c.dy);
    for (var i = 1; i < lanes; i++) {
      var r = _trackInner + (i + 0.3) * _trackLane;
      var stagger = 2 * math.pi * i * _trackLane;
      var a = -math.pi / 2 + stagger / r / 2;
      var p0 = bend +
          Offset(math.cos(a), math.sin(a)) * (_trackInner + i * _trackLane);
      var p1 = bend +
          Offset(math.cos(a), math.sin(a)) *
              (_trackInner + (i + 1) * _trackLane);
      canvas.drawLine(p0, p1, white.stroke);
    }
  }

  if (!spec.on("fieldEvents")) return;
  var surface = Paint()..color = colour;
  // The high jump: a fan of track surface in one end of the infield.
  var hj = Offset(f.field.left - 16, c.dy);
  canvas.drawArc(Rect.fromCircle(center: hj, radius: 14), -math.pi / 2, math.pi,
      true, surface);
  canvas.drawRect(
      Rect.fromCenter(center: hj + const Offset(-1.2, 0), width: 3, height: 5),
      Paint()..color = const Color(0xFF2F5FA8));
  // The throws in the other: the shot circle and the discus cage, with the
  // lines of their sectors running into the infield.
  var shot = Offset(f.field.right + 22, c.dy - 7);
  var disc = Offset(f.field.right + 22, c.dy + 7);
  for (var (at, r) in [(shot, 1.0675), (disc, 1.25)]) {
    canvas.drawCircle(at, r + 0.6, Paint()..color = const Color(0xFFB9B9B9));
    canvas.drawCircle(at, r, Paint()..color = const Color(0xFF8E8E8E));
    canvas.drawCircle(at, r, white.stroke);
    for (var s in [-1.0, 1.0]) {
      var a = math.pi + s * 0.3048; // the sector's 34.92 degrees
      canvas.drawLine(at + Offset(math.cos(a), math.sin(a)) * r,
          at + Offset(math.cos(a), math.sin(a)) * 16, white.stroke);
    }
  }
  canvas.drawArc(
      Rect.fromCircle(center: disc, radius: 3.2),
      0.6,
      math.pi * 2 - 1.2,
      false,
      pen.withColour(const Color(0xFF2B2B2B), 0.12).stroke);
}

/// _trackOutside is the long jump, outside the back straight: a runway on a
/// strip of verge, its board and its sand pit.
void _trackOutside(_Pen pen, _Field f, ProceduralSpec spec) {
  if (!spec.on("fieldEvents")) return;
  var outer = _trackInner + _lanes(spec) * _trackLane;
  var colour = _trackColours[spec.choice("trackColour").clamp(0, 4)];
  var c = f.field.center;
  var canvas = pen.canvas;
  var white = pen.withColour(const Color(0xF2FFFFFF), 0.05);
  var surface = Paint()..color = colour;
  var y = c.dy + outer + 4.5;
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(c.dx - 33, c.dy + outer, c.dx + 23, y + 3),
          const Radius.circular(2)),
      Paint()..color = _darken(spec.background, 0.22));
  canvas.drawRect(
      Rect.fromLTWH(c.dx - 30, y - _trackLane / 2, 40, _trackLane), surface);
  canvas.drawRect(Rect.fromLTWH(c.dx + 10.5, y - 1.4, 9, 2.8),
      Paint()..color = const Color(0xFFE3CF9A));
  canvas.drawLine(Offset(c.dx + 9.5, y - _trackLane / 2),
      Offset(c.dx + 9.5, y + _trackLane / 2), white.stroke);
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

/// _standOpen is whether the stand between [a] and [b] is in a corner of a
/// ground whose corners are open, and so not built at all.
bool _standOpen(Rect window, ProceduralSpec spec, Offset a, Offset b) {
  var mid = (a + b) / 2;
  return spec.choice("corners") == 1 &&
      (mid.dx < window.left || mid.dx > window.right) &&
      (mid.dy < window.top || mid.dy > window.bottom);
}

/// _standFacing is whether the stand between [a] and [b] faces the camera:
/// its seats look towards it over the pitch. One that faces away is the
/// near stand, between the camera and the pitch.
bool _standFacing(_View view, Rect window, Offset a, Offset b) {
  if (view.flat) return true;
  var mid = (a + b) / 2;
  var out = mid - window.center;
  var d0 = view.depthOf(mid.dx, mid.dy);
  var d1 = view.depthOf(mid.dx + out.dx * 0.01, mid.dy + out.dy * 0.01);
  return d1 >= d0;
}

/// _facingAmount is how squarely the stand between [a] and [b] faces the
/// camera: one for a stand straight across the pitch from it, falling to
/// nought where the stands turn into the near one.
double _facingAmount(_View view, Rect window, Offset a, Offset b) {
  if (view.flat) return 1;
  var mid = (a + b) / 2;
  var out = mid - window.center;
  var len = out.distance;
  if (len < 1e-6) return 1;
  var d0 = view.depthOf(mid.dx, mid.dy);
  var d1 = view.depthOf(mid.dx + out.dx / len, mid.dy + out.dy / len);
  var most = math.max(math.cos(view.elevation).abs(), 0.05);
  return ((d1 - d0) / most).clamp(0.0, 1.0);
}

/// _standShown is whether the stand between [a] and [b] is one the picture
/// is fitted round: built, and facing the camera. The near stand is drawn
/// too where it is asked for -- see _stadium -- but in front of the picture,
/// soft, and running out of the frame as the stand nearest a camera does.
bool _standShown(
        _View view, Rect window, ProceduralSpec spec, Offset a, Offset b) =>
    !_standOpen(window, spec, a, b) && _standFacing(view, window, a, b);

/// _inFront is whether [x], [y], [z] is far enough in front of the camera
/// to be drawn: a near stand can stand round the camera itself, and what is
/// behind it projects to nonsense.
bool _inFront(_View view, double x, double y, double z) =>
    view.distance <= 0 ||
    view.distance + view.depthOf(x, y, z) > view.distance * 0.15;

/// _stadiumExtent is every point the stands reach, for fitting the picture
/// round exactly what is drawn of them.
Iterable<(double, double, double)> _stadiumExtent(
    _View view, Rect window, ProceduralSpec spec) sync* {
  var back = _ring(window, _standReach(window, spec), 6);
  var top = _standTop(window, spec);
  for (var i = 0; i < back.length; i++) {
    var a = back[i], b = back[(i + 1) % back.length];
    if (!_standShown(view, window, spec, a, b)) continue;
    yield (a.dx, a.dy, top);
    yield (a.dx, a.dy, 0);
  }
  if (spec.on("pylons")) {
    for (var p in _pylonFeet(view, window, spec)) {
      yield (p.dx, p.dy, _pylonHeight(window, spec) + 3);
      yield (p.dx, p.dy, 0);
    }
  }
}

/// _pylonFeet is where the floodlight pylons stand: at the corners, and
/// only the far ones where the camera looks across the ground -- a near one
/// would stand in front of everything.
List<Offset> _pylonFeet(_View view, Rect window, ProceduralSpec spec) {
  var box = window.inflate(_standReach(window, spec) + 2);
  var middle = view.depthOf(window.center.dx, window.center.dy);
  return [
    for (var p in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight])
      if (view.flat || view.depthOf(p.dx, p.dy) >= middle) p,
  ];
}

double _pylonHeight(Rect window, ProceduralSpec spec) =>
    _standTop(window, spec) * 1.25 + 4;

/// _stadium is the boards round the pitch and the stands rising behind
/// them, in tiers, under a roof, full of people -- the near stand left out
/// where the camera is in it.
void _stadium(ui.Canvas canvas, _View view, _Field f, ProceduralSpec spec,
    Rect ground, List<(double, void Function())> items,
    {required List<(double, void Function())> far,
    required List<(double, void Function())> near}) {
  var window0 = _View._window(spec, f, false);
  var reach0 = _standReach(window0, spec);
  var top0 = _standTop(window0, spec);
  var showNear = spec.p("nearStands") > 0;

  /// into is the list the stand between [a] and [b] is drawn from: the far
  /// stands, the near ones, or none -- an open corner, or a piece of the
  /// near stand the camera is standing in.
  List<(double, void Function())>? into(Offset a, Offset b) {
    if (_standOpen(window0, spec, a, b)) return null;
    if (_standFacing(view, window0, a, b)) return far;
    if (!showNear) return null;
    var out = (a + b) / 2 - window0.center;
    var dir = out / math.max(out.distance, 1e-6);
    for (var p in [a, b]) {
      var back = p + dir * reach0;
      if (!_inFront(view, p.dx, p.dy, 0) ||
          !_inFront(view, back.dx, back.dy, top0)) {
        return null;
      }
    }
    return near;
  }

  var window = _View._window(spec, f, false);
  var seat = spec.accent;
  var concrete = _darken(spec.background, 0.62);
  var tiers = _tiers(spec);
  var depth = _standDepth(window, spec), height = _standHeight(window, spec);

  void quad(List<Offset> pts, Color colour) {
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = colour);
  }

  // The advertising boards, a metre high, two metres outside the apron.
  var boardKind = spec.choice("boards");
  if (boardKind != 2) {
    var boards = _ring(window, 2, 2);
    for (var i = 0; i < boards.length; i++) {
      var a = boards[i], b = boards[(i + 1) % boards.length];
      if ((b - a).distance < 0.01) continue;
      Color panel;
      if (boardKind == 1) {
        // LED boards: bright, and running through colours along the ground.
        panel = HSVColor.fromAHSV(
                1, ((i * 23 + spec.seed * 37) % 360).toDouble(), 0.75, 1)
            .toColor();
      } else {
        panel = i.isEven ? seat : _lighten(seat, 0.25);
      }
      var d = view.depthOf((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      items.add((
        d,
        () {
          var face = [
            view.project(a.dx, a.dy),
            view.project(b.dx, b.dy),
            view.project(b.dx, b.dy, 0.9),
            view.project(a.dx, a.dy, 0.9),
          ];
          quad(face, panel);
          if (boardKind == 1) {
            canvas.drawPath(
                Path()..addPolygon(face, true),
                Paint()
                  ..color = panel.withValues(alpha: 0.5)
                  ..maskFilter = MaskFilter.blur(
                      BlurStyle.normal, view.pixelsPerMetre * 0.6));
          }
        }
      ));
    }
  }

  // The stands: a tier of rows of seats, rising away from the pitch, then a
  // walkway, then the next tier set further back and higher.
  var crowd = spec.p("crowd");
  const people = [
    Color(0xFFF2F2F2),
    Color(0xFF1C2333),
    Color(0xFFE0B48A),
    Color(0xFFD03A2E),
    Color(0xFFF2C230),
    Color(0xFF7A4B2E),
  ];
  var perTier = (22 / tiers).ceil();
  double? topRing;
  for (var t = 0; t < tiers; t++) {
    var d0 = 5 + t * (depth / tiers + _tierGap);
    var z0 = 1.5 + t * (height / tiers + 1.8);
    var rings = [
      for (var r = 0; r <= perTier; r++)
        _ring(window, d0 + r * depth / tiers / perTier, 6),
    ];
    for (var r = 0; r < perTier; r++) {
      var za = z0 + r * height / tiers / perTier,
          zb = za + height / tiers / perTier;
      var inner = rings[r], outer = rings[r + 1];
      for (var i = 0; i < inner.length; i++) {
        var j = (i + 1) % inner.length;
        var list = into(inner[i], inner[j]);
        if (list == null) continue;
        var aisle = i % 9 == 0;
        var tone = aisle
            ? _lighten(concrete, 0.25)
            : (r.isEven ? _darken(seat, 0.25) : _darken(seat, 0.4));
        var shade = (hash(spec.seed, i, r + t * 40) - 0.5) *
            0.16 *
            (0.4 + spec.variation);
        tone = shade > 0 ? _lighten(tone, shade) : _darken(tone, -shade);
        var d = view.depthOf((inner[i].dx + outer[j].dx) / 2,
            (inner[i].dy + outer[j].dy) / 2, (za + zb) / 2);
        var seed = i * 131 + r * 17 + t * 7919;
        list.add((
          d,
          () {
            quad([
              view.project(inner[i].dx, inner[i].dy, za),
              view.project(inner[j].dx, inner[j].dy, za),
              view.project(inner[j].dx, inner[j].dy, zb),
              view.project(inner[i].dx, inner[i].dy, zb),
            ], _darken(tone, 0.3));
            quad([
              view.project(inner[i].dx, inner[i].dy, zb),
              view.project(inner[j].dx, inner[j].dy, zb),
              view.project(outer[j].dx, outer[j].dy, zb),
              view.project(outer[i].dx, outer[i].dy, zb),
            ], tone);
            // The crowd: a head here and there, as full as the ground is.
            if (crowd <= 0 || aisle) return;
            var many = (crowd * 9).round();
            var dot = Paint()..strokeCap = StrokeCap.round;
            var size = view.pixelsPerMetre * 0.55;
            for (var k = 0; k < many; k++) {
              var u = hash(spec.seed + 3, seed, k),
                  v = hash(spec.seed + 5, seed, k);
              if (hash(spec.seed + 7, seed, k) > crowd) continue;
              var a = Offset.lerp(inner[i], inner[j], u)!;
              var b = Offset.lerp(outer[i], outer[j], u)!;
              var p = Offset.lerp(a, b, v * 0.6)!;
              dot
                ..color = people[
                    (hash(spec.seed + 9, seed, k) * people.length).floor() %
                        people.length]
                ..strokeWidth = math.max(1.0, size);
              canvas.drawPoints(ui.PointMode.points,
                  [view.project(p.dx, p.dy, zb + 0.5)], dot);
            }
          }
        ));
      }
    }
    // The fascia between this tier and the one above it.
    var top = z0 + height / tiers;
    topRing = top;
    if (t < tiers - 1) {
      var edge = _ring(window, d0 + depth / tiers, 6);
      for (var i = 0; i < edge.length; i++) {
        var j = (i + 1) % edge.length;
        var list = into(edge[i], edge[j]);
        if (list == null) continue;
        var d = view.depthOf(edge[i].dx, edge[i].dy, top + 0.9);
        list.add((
          d,
          () => quad([
                view.project(edge[i].dx, edge[i].dy, top),
                view.project(edge[j].dx, edge[j].dy, top),
                view.project(edge[j].dx, edge[j].dy, top + 1.8),
                view.project(edge[i].dx, edge[i].dy, top + 1.8),
              ], i.isEven ? seat : _darken(seat, 0.2))
        ));
      }
    }
  }

  // The back wall along the top, and a roof over the rows where there is
  // one: a canopy over the back of the stand, or the whole of it -- pitched
  // down towards the pitch, ribbed, with a fascia along its leading edge.
  var reach = _standReach(window, spec);
  var back = _ring(window, reach, 6);
  var z = topRing ?? 1.5 + height;
  var roof = spec.choice("roof");
  var front = roof == 0
      ? null
      : _ring(window, reach - depth * (roof == 1 ? 0.45 : 0.95), 6);
  var rz = z + 3.5; // the roof's back edge
  var lip = rz - 1.2; // and its leading edge, lower
  var wallTop = roof == 0 ? z + 2.5 : rz;
  for (var i = 0; i < back.length; i++) {
    var j = (i + 1) % back.length;
    // Not over the near stand: its roof and its back wall are above and
    // behind the camera, and from there would be a sheet across the pitch.
    var list = into(back[i], back[j]);
    if (list == null || identical(list, near)) continue;
    list.add((
      view.depthOf(back[i].dx, back[i].dy, z) - 0.5,
      () => quad([
            view.project(back[i].dx, back[i].dy, z),
            view.project(back[j].dx, back[j].dy, z),
            view.project(back[j].dx, back[j].dy, wallTop),
            view.project(back[i].dx, back[i].dy, wallTop),
          ], _darken(concrete, 0.3))
    ));
    if (front == null) continue;
    var fadeOf = _facingAmount(view, window, back[i], back[j]);
    list.add((
      view.depthOf(front[i].dx, front[i].dy, rz) - 1,
      () {
        Offset mid(int k, double t) => Offset.lerp(back[k], front[k], t)!;
        Offset at(int k, double t) {
          var m = mid(k, t);
          return view.project(m.dx, m.dy, rz + (lip - rz) * t);
        }

        // The sheet, darker at the back where it meets the wall and lit
        // towards its leading edge -- and fading out where the stand turns
        // towards the camera, rather than stopping dead.
        var fade = (fadeOf / 0.35).clamp(0.0, 1.0);
        fade = fade * fade * (3 - 2 * fade);
        if (fade <= 0.01) return;
        quad([at(i, 0), at(j, 0), at(j, 0.5), at(i, 0.5)],
            const Color(0xFFAEB4BD).withValues(alpha: fade));
        quad([at(i, 0.5), at(j, 0.5), at(j, 1), at(i, 1)],
            const Color(0xFFD3D8DF).withValues(alpha: fade));
        // A rib along every other panel joint.
        if (i.isEven) {
          canvas.drawLine(
              at(i, 0),
              at(i, 1),
              Paint()
                ..strokeWidth = math.max(0.8, view.pixelsPerMetre * 0.18)
                ..color =
                    const Color(0x55394049).withValues(alpha: 0.33 * fade));
        }
        // The fascia: a deep band hanging from the leading edge.
        var f0 = front[i], f1 = front[j];
        quad([
          view.project(f0.dx, f0.dy, lip),
          view.project(f1.dx, f1.dy, lip),
          view.project(f1.dx, f1.dy, lip - 1.4),
          view.project(f0.dx, f0.dy, lip - 1.4),
        ], const Color(0xFFE9ECF0).withValues(alpha: fade));
        canvas.drawLine(
            view.project(f0.dx, f0.dy, lip - 1.4),
            view.project(f1.dx, f1.dy, lip - 1.4),
            Paint()
              ..strokeWidth = math.max(0.8, view.pixelsPerMetre * 0.12)
              ..color = const Color(0x66000000).withValues(alpha: 0.4 * fade));
      }
    ));
  }

  // Floodlight pylons at the four corners.
  if (spec.on("pylons")) {
    var tall = _pylonHeight(window, spec);
    for (var foot in _pylonFeet(view, window, spec)) {
      far.add((
        view.depthOf(foot.dx, foot.dy, tall / 2) - 2,
        () {
          var pole = Paint()
            ..strokeWidth = math.max(1.5, view.pixelsPerMetre * 0.9)
            ..color = const Color(0xFF9EA4AC);
          canvas.drawLine(view.project(foot.dx, foot.dy),
              view.project(foot.dx, foot.dy, tall), pole);
          var head = view.project(foot.dx, foot.dy, tall + 1.5);
          var w = view.pixelsPerMetre * 4.5;
          canvas.drawCircle(
              head,
              w * 1.4,
              Paint()
                ..shader = ui.Gradient.radial(head, w * 1.4, [
                  const Color(0xAAFFF6D8),
                  const Color(0x00FFF6D8),
                ]));
          canvas.drawRect(
              Rect.fromCenter(center: head, width: w, height: w * 0.55),
              Paint()..color = const Color(0xFFFFF8E2));
          canvas.drawRect(
              Rect.fromCenter(center: head, width: w, height: w * 0.55),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(1.0, w * 0.06)
                ..color = const Color(0xFF5A5F66));
        }
      ));
    }
  }
}

/// _drawStadium draws what stands up off the ground, furthest first: the
/// pitch's own goals and boards sharp, and the stadium ([far] and [near])
/// through a depth of field -- each piece blurred, and the nearer ones faded,
/// by how far it is from the pitch, so the focus falls off gradually rather
/// than at the line where one stand becomes the next. The stadium is clipped
/// out of the pitch's outline: it never lies over the pitch.
void _drawStadium(
    ui.Canvas canvas,
    _View view,
    _Field field,
    ProceduralSpec spec,
    Rect frame,
    List<(double, void Function())> items,
    List<(double, void Function())> far,
    List<(double, void Function())> near) {
  var all = <(double, void Function(), bool)>[
    for (var (d, f) in items) (d, f, false),
    for (var (d, f) in far) (d, f, true),
    for (var (d, f) in near) (d, f, true),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  if (all.isEmpty) return;

  var window = _View._window(spec, field, false);
  var depths = [
    for (var p in [
      window.topLeft,
      window.topRight,
      window.bottomLeft,
      window.bottomRight
    ])
      view.depthOf(p.dx, p.dy),
  ];
  var nearest = depths.reduce(math.min), furthest = depths.reduce(math.max);
  var span = math.max(furthest - nearest, 1.0);
  var dof = spec.p("depthOfField");
  var fade = spec.p("nearStands");
  var ppm = view.pixelsPerMetre;
  const steps = 10;

  /// look is how a stadium piece [d] deep is drawn: its blur in pixels and
  /// its opacity, in steps so that pieces alike are drawn together.
  (double, double) look(double d) {
    if (d > furthest) {
      var u = ((d - furthest) / (span * 0.6)).clamp(0.0, 1.0);
      u = (u * steps).round() / steps;
      return (dof * ppm * 0.35 * u, 1);
    }
    if (d < nearest + span * 0.15) {
      var n = ((nearest + span * 0.15 - d) / (span * 0.45)).clamp(0.0, 1.0);
      n = (n * steps).round() / steps;
      var eased = n * n * (3 - 2 * n);
      return (
        ppm * (0.1 + dof * 0.9) * eased,
        1 + (fade - 1) * eased,
      );
    }
    return (0, 1);
  }

  // The pitch's outline, out to the boards, as the camera sees it.
  var outline = Path()
    ..addPolygon([
      for (var p in _ring(window, 2, 2)) view.project(p.dx, p.dy),
    ], true);
  var outside = Path.combine(
      PathOperation.difference, Path()..addRect(frame.inflate(4)), outline);

  var i = 0;
  while (i < all.length) {
    var graded = all[i].$3;
    var (blur, opacity) = graded ? look(all[i].$1) : (0.0, 1.0);
    var j = i;
    while (j < all.length &&
        all[j].$3 == graded &&
        (!graded || look(all[j].$1) == (blur, opacity))) {
      j++;
    }
    if (opacity > 0.01) {
      canvas.save();
      if (graded) canvas.clipPath(outside);
      var layered = blur > 0.3 || opacity < 1;
      if (layered) {
        var paint = Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
        if (blur > 0.3) {
          var sigma = blur.clamp(0.0, 24.0);
          paint.imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);
        }
        canvas.saveLayer(null, paint);
      }
      for (var k = i; k < j; k++) {
        all[k].$2();
      }
      if (layered) canvas.restore();
      canvas.restore();
    }
    i = j;
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
