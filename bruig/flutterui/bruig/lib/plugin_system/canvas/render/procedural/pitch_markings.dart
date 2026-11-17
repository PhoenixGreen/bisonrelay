part of 'pitch.dart';

// Each sport's markings, drawn in metres from its governing body's dimensions.
// Part of pitch.dart.

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
  // Dashed: ten metres either side of halfway, five in from each try line.
  for (var x in <double>[40, 60, 5, l - 5]) {
    pen.dashed(x, 0, x, w, 1, 1);
  }
  // The lines five and fifteen metres in from touch.
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
