part of 'pitch.dart';

// The ground itself: the surface's finish (grass, wood, clay, ice) and the
// running track round a field, with its lanes, starts and field events. Part of
// pitch.dart.

int _autoSurface(PitchSport sport) => switch (sport) {
      PitchSport.basketball || PitchSport.basketballNba => PitchSurface.wood,
      PitchSport.futsal || PitchSport.tennis => PitchSurface.hardCourt,
      PitchSport.iceHockey => PitchSurface.ice,
      PitchSport.hockey => PitchSurface.plain,
      _ => PitchSurface.stripes,
    };

/// _surface lays the apron a shade darker (or in the accent, as run-off) and
/// the field of play in the background colour, finished as the surface asks.
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
      // The mowing pattern: bands along the length (and across, for checks).
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
      // A little unevenness, so the bands are grass and not paint.
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

/// _woodFloor is a maple floor: shaded strips with staggered board joints.
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

/// _trackInner and _trackLane are the inside radius of a 400 m track's first
/// lane and the width of a lane; _trackStraight is the length of a straight.
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

/// _oval is the track's shape [r] metres out from its middle.
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

/// _track lays the running track's ground (verge, lanes, kerb) before the
/// field fills the infield; the field events follow in _trackDetails.
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

/// _trackDetails paints the finish line and lane numbers, the staggered
/// starts round the first bend, and the field events in the infield's ends.
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
  // The throws in the other: shot circle and discus cage, sectors inward.
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

/// _trackOutside is the long jump: runway, board and pit by the back straight.
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
