part of 'pitch.dart';

// What stands up off the ground: goals, boards, the stands in tiers and the
// floodlights, projected a point at a time and drawn through a depth of field.
// Part of pitch.dart.

/// _standDepth is how far the stands run back from the boards, and
/// _standHeight how high they rise: in proportion to the field (an arena
/// round a court is not a stadium round a postage stamp), times "standSize".
double _standDepth(Rect window, [ProceduralSpec? spec]) =>
    (math.max(window.width, window.height) * 0.24).clamp(7.0, 26.0) *
    (spec?.p("standSize") ?? 1);

double _standHeight(Rect window, [ProceduralSpec? spec]) =>
    _standDepth(window, spec) * 0.62;

/// _tiers is how many tiers the stands have, and _tierGap the walkway between.
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

  // Corners joined by straights, each cut into pieces so sorting by distance
  // from the camera works piece by piece; as many at every distance out,
  // from the window alone, so one ring's points pair with the next's.
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

/// _standOpen is whether the stand between [a] and [b] is an open corner.
bool _standOpen(Rect window, ProceduralSpec spec, Offset a, Offset b) {
  var mid = (a + b) / 2;
  return spec.choice("corners") == 1 &&
      (mid.dx < window.left || mid.dx > window.right) &&
      (mid.dy < window.top || mid.dy > window.bottom);
}

/// _standFacing is whether the stand between [a] and [b] looks towards the
/// camera over the pitch; one facing away is the near stand.
bool _standFacing(_View view, Rect window, Offset a, Offset b) {
  if (view.flat) return true;
  var mid = (a + b) / 2;
  var out = mid - window.center;
  var d0 = view.depthOf(mid.dx, mid.dy);
  var d1 = view.depthOf(mid.dx + out.dx * 0.01, mid.dy + out.dy * 0.01);
  return d1 >= d0;
}

/// _facingAmount is how squarely the stand between [a] and [b] faces the
/// camera: one straight across the pitch, falling to nought at the near one.
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

/// _standShown is whether the picture is fitted round the stand between [a]
/// and [b]: built and facing the camera. A near stand may run out of frame.
bool _standShown(
        _View view, Rect window, ProceduralSpec spec, Offset a, Offset b) =>
    !_standOpen(window, spec, a, b) && _standFacing(view, window, a, b);

/// _inFront is whether [x], [y], [z] is far enough in front of the camera
/// to draw; a near stand can surround it, and behind projects to nonsense.
bool _inFront(_View view, double x, double y, double z) =>
    view.distance <= 0 ||
    view.distance + view.depthOf(x, y, z) > view.distance * 0.15;

/// _stadiumExtent is every point the stands reach, to fit the picture round.
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

/// _pylonFeet is where the floodlight pylons stand: the corners, only the
/// far ones when the camera looks across, as a near one blocks everything.
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

/// _stadium is the boards round the pitch and the stands behind them, in
/// tiers, roofed and full, leaving out a near stand the camera is in.
void _stadium(ui.Canvas canvas, _View view, _Field f, ProceduralSpec spec,
    Rect ground, List<(double, void Function())> items,
    {required List<(double, void Function())> far,
    required List<(double, void Function())> near}) {
  var window0 = _View._window(spec, f, false);
  var reach0 = _standReach(window0, spec);
  var top0 = _standTop(window0, spec);
  var showNear = spec.p("nearStands") > 0;

  /// into is the list the stand between [a] and [b] goes in: far, near, or
  /// none (an open corner, or near-stand pieces round the camera).
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

  // The stands: tiers of rising seat rows, a walkway between, each higher.
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

  // The back wall along the top, and any roof over the back of the stand or
  // all of it: pitched down towards the pitch, ribbed, with a fascia.
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

        // The sheet, darker at the back and lit towards its leading edge,
        // fading out where the stand turns towards the camera.
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

/// _drawStadium draws what stands up off the ground, furthest first: [items]
/// (goals, boards) sharp, the stadium ([far], [near]) through a depth of
/// field, each piece blurred and near ones faded by distance, so focus falls
/// off gradually. The stadium is clipped to outside the pitch's outline.
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
          // The stanchion behind the end line, the arm, the board, the ring.
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
