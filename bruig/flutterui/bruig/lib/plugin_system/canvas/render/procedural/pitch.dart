import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:flutter/painting.dart';

part 'pitch_ground.dart';
part 'pitch_markings.dart';
part 'pitch_stadium.dart';

// pitch.dart draws a marked playing surface. Every sport is drawn in metres
// from its governing body's dimensions, line widths included. The ground is
// put on the page by a homography ([_View.ground], via Canvas.transform), so
// markings stay true from any camera; what stands up off it (goals, stands)
// is projected a point at a time. The surface is the background colour, the
// markings the foreground, and what is painted (a key, run-off) the accent.

// --------------------------------------------------------------------------
// The mapping
// --------------------------------------------------------------------------

/// PitchMetrics maps a sport's metres onto a flat pitch across the page, so
/// presets can place a 4-4-2 in metres (see [pitchRect]).
class PitchMetrics {
  /// area is the field of play itself.
  final Rect area;

  final double lengthMetres;
  final double widthMetres;

  const PitchMetrics(this.area, this.lengthMetres, this.widthMetres);

  /// scale is pixels per metre. The two axes share one.
  double get scale => area.width / lengthMetres;

  /// at maps metres from the field's bottom-left (x along it) to the canvas.
  Offset at(double xMetres, double yMetres) => Offset(
        area.left + xMetres * scale,
        area.bottom - yMetres * scale,
      );

  double m(double metres) => metres * scale;
}

/// pitchInset is the margin left round the pitch, of the shorter side.
const double pitchInset = 0.045;

/// pitchRect is where [sport]'s field lands in [rect], as on a tactics board.
PitchMetrics pitchRect(Rect rect, PitchSport sport) {
  var field = _Field.of(sport);
  var view = _View.fit(
      rect, ProceduralSpec(style: ProceduralStyle.pitch, sport: sport), field);
  var a = view.project(0, field.width), b = view.project(field.length, 0);
  return PitchMetrics(Rect.fromPoints(a, b), field.length, field.width);
}

/// PitchPlacement puts a point on a pitch as it is drawn: camera, zoom,
/// position and turn. A linked team keeps its players in the pitch's metres
/// and asks this where they land, so they move with the pitch in perspective.
class PitchPlacement {
  final _View _view;
  final _Field _field;
  final Offset _pivot;
  final double _turn;

  /// visibleFrom is where along the field half a pitch starts; -1e9 for all.
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

  /// page is where [x], [y] (metres along and across) and [z] up land.
  Offset page(double x, double y, [double z = 0]) =>
      _turned(_view.project(x, y, z), _turn);

  /// field is the point on the field under [page], or null where none is.
  Offset? field(Offset page) => _view.unproject(_turned(page, -_turn));

  /// scaleAt is how many pixels a metre standing at [x], [y] takes up.
  double scaleAt(double x, double y) => _view.pixelsPerMetreAt(x, y);

  /// depthOf is how far [x], [y] is from the camera, for drawing order.
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

/// _Field is one sport's field of play in metres: size, line width, apron.
class _Field {
  final PitchSport sport;
  final double length, width;

  /// line is the regulation width of a marking.
  final double line;

  /// apron is playing ground round the field: in-goal, end zones, run-off.
  final Rect apron;

  /// fitsField is whether a flat view fits the field of play alone, not the
  /// apron, for pitches whose players are placed in its metres (_View._window).
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

/// _View is which part of the ground is seen, from where, and fitted where.
class _View {
  final double cx, cy;
  final bool upright;
  final double azimuth;
  final double elevation;

  /// side is the camera swung round to one side of the picture, in radians:
  /// tilting the ground about the page's own upright.
  final double side;

  /// distance is from camera to ground's middle; nought for no perspective.
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

  /// ground is the matrix that puts the ground, in metres, on the page.
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

  /// pixelsPerMetreAt is how big a metre standing upright at [x], [y] looks.
  double pixelsPerMetreAt(double x, double y) {
    if (distance <= 0) return scale;
    var depth = camera(x, y, 0).$3;
    return scale * distance / math.max(distance * 0.05, distance + depth);
  }

  /// unproject is the ground point under [page], or null above the horizon.
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

  bool get flat => elevation > math.pi / 2 - 0.01 && side.abs() < 0.01;

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

    // Fitted to the corners of what must be seen, and the stands' tops.
    var points = <(double, double, double)>[
      for (var x in [window.left, window.right])
        for (var y in [window.top, window.bottom]) (x, y, 0),
    ];
    if (spec.choice("surround") == 1) {
      // Round exactly what is drawn of the stands (not the near one, nor an
      // open ground's corners), so none is cut off and no frame is wasted.
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

    // Then zoomed about the frame's middle and moved (Size and position).
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

/// PitchCamera is a pitch's viewpoint in the settings' terms: degrees of
/// tilt (up, sideways) and turn, perspective strength, and the picture's move.
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
    // Half a pitch is cut at the halfway line, not run out of the frame.
    var shown = _View._window(spec, field, true);
    canvas.clipRect(Rect.fromLTRB(shown.left, -1000, 1000, 1000));
  }
  if (surround == 1) {
    // The stadium's floor: the concourse between the boards and the stands.
    canvas.drawRect(_View._window(spec, field, false).inflate(5),
        Paint()..color = _darken(spec.background, 0.55));
  }
  if (surround == 2) {
    // The track first; the field fills the infield inside its kerb.
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
  _drawStadium(canvas, view, field, spec, all, items, far, near);
  canvas.restore();

  if (spec.on("floodlights")) _floodlights(canvas, rect, view, field, spec);
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
