import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';

// character_painter.dart draws a character: its rig, dressed and given a
// face, in its style.
//
// Back to front, the way a person is put together on paper: long hair behind
// the head, then the legs and shoes, the body and what is worn on it, the
// arms over the body, and the head last. Every shape is filled and then
// edged a shade darker than itself, which is what makes the Feature cartoon
// style read as one drawing rather than coloured shapes laid on top of one
// another.

/// paintCharacter draws [e] as it is on [frame]: posed, its face set, and
/// blinking and breathing at [frameRate].
/// [editing] is the stage, where a character can be shown bare while it is
/// designed; never in anything made from the canvas.
void paintCharacter(Canvas canvas, Rect box, CharacterElement e, int frame,
    {int frameRate = 12, bool editing = false}) {
  var life = lifeAt(e, frame, frameRate);
  var (pose, face) = e.performanceAt(frame, frameRate);
  paintCharacterFigure(canvas, box, e.dna, pose,
      face: face, life: life, bare: editing && e.bareView);
}

/// paintCharacterFigure draws [dna] in [pose], filling the height of [box].
/// What the settings panel's tiles draw, with no element behind them.
void paintCharacterFigure(
    Canvas canvas, Rect box, CharacterDna dna, CharacterPose pose,
    {CharacterFace face = CharacterFace.rest,
    LifeAt life = LifeAt.none,
    bool bare = false}) {
  if (box.height <= 0) return;
  var rig = CharacterRig.of(dna, pose, box, breath: life.breath);
  _Drawing(canvas, rig, dna, face, life, bare: bare).draw();
}

class _Drawing {
  final Canvas canvas;
  final CharacterRig rig;
  final CharacterDna dna;
  final CharacterFace face;
  final LifeAt life;

  /// bare is the body without its clothes -- the editor's bare view.
  final bool bare;

  _Drawing(this.canvas, this.rig, this.dna, this.face, this.life,
      {this.bare = false});

  double get u => rig.unit;

  /// edge is how thick every outline is.
  double get edge => math.max(0.6, u * 0.022);

  /// garments is what is drawn on the body, innermost first: nothing in
  /// the bare view.
  List<Garment> get garments => bare ? const [] : dna.worn;

  Iterable<(int, Garment)> _wearing(bool Function(Garment) which) sync* {
    for (var (i, g) in garments.indexed) {
      if (which(g)) yield (i, g);
    }
  }

  /// bodyFacing is how much of the body's front is towards the reader.
  double get bodyFacing => math.cos(rig.yaw * math.pi / 180);

  void draw() {
    // Long hair hangs behind the head, until the head turns away and it is
    // the thing in front -- see _head.
    if (dna.hairStyle == HairStyle.long && facing >= -0.3) _inHead(_backHair);
    // A cape hangs behind the body, until the body turns away from the
    // reader and it is the thing in front.
    if (bodyFacing >= -0.2) _capes();
    _legs();
    _skirts();
    // An arm turned away goes behind the body, an arm towards the reader in
    // front of it. Facing the reader both are a hair in front.
    var near = -u * 0.01;
    _arms(far: true, near: near);
    _neck();
    _torso();
    _neckwear();
    _arms(far: false, near: near);
    if (bodyFacing < -0.2) _capes();
    _inHead(_head);
  }

  // ---- the body ----

  double get _leg => rig.thigh + rig.shin;

  /// _along is the stretch of [limb] from [from] to [to] of its length,
  /// as the joints it passes through.
  List<Offset> _along(CharacterLimb limb, double from, double to) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    var (upper, lower) = rig.lengths(limb);
    var whole = upper + lower;
    Offset at(double t) {
      var d = t * whole;
      return d <= upper
          ? Offset.lerp(a, b, upper == 0 ? 0 : d / upper)!
          : Offset.lerp(b, c, lower == 0 ? 0 : (d - upper) / lower)!;
    }

    var split = upper / whole;
    return [
      at(from),
      if (from < split && to > split) b,
      at(math.max(from, to)),
    ];
  }

  void _legs() {
    // The far leg first, so the near one crosses in front of it.
    var legs = [CharacterLimb.legL, CharacterLimb.legR]
      ..sort((a, b) => rig.depths[a]!.compareTo(rig.depths[b]!));
    var seated = <(int, Garment)>[];
    for (var limb in legs) {
      _stroke(_along(limb, 0, 1), rig.legWidth, dna.skin);
      _foot(limb, dna.skin, bareFoot: true);
      for (var (i, g) in _wearing((g) => g.kind.coversLegs)) {
        var from = g.kind.from, to = math.max(from + 0.02, g.lengthOr);
        _cloth(null, g, i,
            line: _along(limb, from, math.min(1, to)),
            width: rig.legWidth * 1.12 * g.fitOr,
            part: limb.index,
            hem: true);
        if (g.kind == GarmentKind.socks) _foot(limb, g.color);
        if (from == 0 && !seated.any((s) => s.$1 == i)) seated.add((i, g));
      }
      for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.shoes)) {
        _shoe(limb, g, i);
      }
    }
    // The seat, so trousers meet between the legs instead of leaving the
    // background showing where two round-ended legs part.
    for (var (i, g) in seated) {
      var seat = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: rig.hips + Offset(0, rig.legWidth * 0.2),
                width: (rig.hipL - rig.hipR).distance +
                    rig.legWidth * 1.12 * g.fitOr,
                height: rig.legWidth * 1.3),
            Radius.circular(rig.legWidth * 0.4)));
      _cloth(seat, g, i, part: 9);
    }
  }

  void _skirts() {
    for (var (i, g) in _wearing((g) =>
        g.kind.shape == GarmentShape.skirt ||
        g.kind.shape == GarmentShape.dress)) {
      _cloth(_skirt(g.lengthOr * _leg, g.kind.flare, g.fitOr), g, i,
          part: 10, hem: true);
    }
  }

  /// _skirt is a flared skirt from the waist, [length] long and [flare]
  /// times as wide at the hem as at the waist.
  Path _skirt(double length, double flare, double fit) {
    var top = rig.hips.dy - rig.legWidth * 0.3;
    var turned = bodyFacing.abs() + 0.75 * math.sin(rig.yaw * math.pi / 180).abs();
    var half = rig.hipHalf * 1.05 * fit * turned;
    var hem = top + length;
    var hemHalf = half * flare;
    var cx = rig.hips.dx;
    return Path()
      ..moveTo(cx - half, top)
      ..lineTo(cx + half, top)
      ..lineTo(cx + hemHalf, hem)
      ..quadraticBezierTo(cx, hem + length * 0.1, cx - hemHalf, hem)
      ..close();
  }

  /// _footBox is where a foot is drawn: its middle, how it tips, and how
  /// long it is -- longer side on, where it points the way the body faces.
  (Offset, double, double, double) _footBox(CharacterLimb limb) {
    var ankle = rig.end(limb);
    var shinTurn = turnOf(rig.end(limb) - rig.middle(limb));
    var drop = rig.below * CharacterRig.footDrop;
    var outward = limb.onLeft ? -1.0 : 1.0;
    var turned = rig.yaw * math.pi / 180;
    var across = math.cos(turned).abs(), side = math.sin(turned);
    var centre = ankle +
        Offset(outward * rig.legWidth * 0.22 * across - side * rig.legWidth * 0.55,
            drop * 0.45);
    // A foot keeps flat to the floor however the shin is turned, only
    // tipping a little with it, or a kick would point the sole at the sky.
    return (
      centre,
      shinTurn * 0.25 * math.pi / 180,
      rig.legWidth * (1.75 * across + 2.6 * side.abs()),
      drop
    );
  }

  void _foot(CharacterLimb limb, Color colour, {bool bareFoot = false}) {
    var (centre, tip, length, drop) = _footBox(limb);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(tip);
    var scale = bareFoot ? 0.86 : 0.95;
    _fill(
        Path()
          ..addOval(Rect.fromCenter(
              center: Offset.zero,
              width: length * scale,
              height: drop * 1.0 * scale)),
        colour);
    canvas.restore();
  }

  void _shoe(CharacterLimb limb, Garment g, int i) {
    var (centre, tip, length, drop) = _footBox(limb);
    var colour = faded(g.color, g.condition.fade);
    if (g.kind == GarmentKind.boots) {
      // A boot comes up the shin as far as its length says.
      _cloth(null, g, i,
          line: _along(limb, 1 - g.lengthOr * 0.5, 1),
          width: rig.legWidth * 1.2,
          part: 20 + limb.index);
    }
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(tip);
    switch (g.kind) {
      case GarmentKind.sandals:
        // Straps over the foot, which shows between them.
        var strap = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = drop * 0.28
          ..color = colour;
        for (var x in [-0.18, 0.15]) {
          canvas.drawLine(Offset(length * x, -drop * 0.45),
              Offset(length * x, drop * 0.45), strap);
        }
        canvas.drawLine(Offset(-length * 0.45, drop * 0.48),
            Offset(length * 0.45, drop * 0.48), strap..strokeWidth = drop * 0.18);
      case GarmentKind.heels:
        _fill(
            Path()
              ..addOval(Rect.fromCenter(
                  center: Offset(0, -drop * 0.1),
                  width: length * 0.85,
                  height: drop * 0.9)),
            colour);
        _fill(
            Path()
              ..addRect(Rect.fromLTWH(
                  -length * 0.08, drop * 0.2, length * 0.16, drop * 0.55)),
            colour);
      default:
        var shoe = Path()
          ..addOval(Rect.fromCenter(
              center: Offset.zero, width: length, height: drop * 1.15));
        _fill(shoe, colour);
        if (g.kind == GarmentKind.trainers) {
          // The sole, in the second colour.
          canvas.save();
          canvas.clipPath(shoe);
          canvas.drawRect(
              Rect.fromLTWH(-length, drop * 0.22, length * 2, drop),
              Paint()..color = g.color2);
          canvas.restore();
          canvas.drawPath(shoe, _edgePaint(colour));
        }
    }
    canvas.restore();
  }

  void _neck() =>
      _stroke([rig.neck + Offset(0, -u * 0.1), rig.chest],
          rig.limbWidth * 1.15, dna.skin);

  /// _torsoFrame is the body's own directions on the page: across it, up
  /// it, and how wide it is drawn turned the way it is.
  (Offset, Offset, double, double) get _torsoFrame {
    var spine = rig.bodyTurn * math.pi / 180;
    var across = Offset(math.cos(spine), math.sin(spine));
    var up = Offset(math.sin(spine), -math.cos(spine));
    // Turned, the body is as wide as it is deep: about six tenths of its
    // width, side on.
    var turned = rig.yaw * math.pi / 180;
    var front = math.cos(turned).abs(), side = math.sin(turned).abs();
    return (
      across,
      up,
      rig.shoulderHalf * (front + 0.6 * side),
      rig.hipHalf * 1.12 * (front + 0.75 * side)
    );
  }

  /// _torsoPath is the body, or a garment over it [fit] loose and coming
  /// [length] down: 1 is to the hips, more is on down the legs.
  Path _torsoPath({double fit = 1, double length = 1}) {
    var (across, up, half0, low0) = _torsoFrame;
    var half = half0 * fit, low = low0 * fit;
    var topL = rig.chest + across * half;
    var topR = rig.chest - across * half;
    double hemY;
    double hemHalf;
    if (length <= 1) {
      hemY = rig.chest.dy + (rig.hips.dy + rig.legWidth * 0.15 - rig.chest.dy) * length;
      hemHalf = half + (low - half) * length;
    } else {
      hemY = rig.hips.dy + rig.legWidth * 0.15 + (length - 1) * _leg;
      // Past the hips a garment hangs round both legs, a little wider.
      hemHalf = low * (1 + 0.35 * math.min(1, length - 1));
    }
    var botL = Offset(rig.hips.dx + hemHalf, hemY);
    var botR = Offset(rig.hips.dx - hemHalf, hemY);
    return Path()
      ..moveTo(topL.dx, topL.dy)
      ..quadraticBezierTo(rig.chest.dx + up.dx * u * 0.12,
          rig.chest.dy + up.dy * u * 0.12, topR.dx, topR.dy)
      ..quadraticBezierTo(
          topR.dx - across.dx * u * 0.06, (topR.dy + botR.dy) / 2, botR.dx, botR.dy)
      ..quadraticBezierTo(rig.hips.dx, hemY + rig.legWidth * 0.3, botL.dx, botL.dy)
      ..quadraticBezierTo(topL.dx + across.dx * u * 0.06, (topL.dy + botL.dy) / 2,
          topL.dx, topL.dy)
      ..close();
  }

  void _torso() {
    _fill(_torsoPath(), dna.skin);
    for (var (i, g) in garments.indexed) {
      switch (g.kind.shape) {
        case GarmentShape.torso:
          _cloth(_torsoPath(fit: g.fitOr, length: g.lengthOr), g, i,
              part: 30, hem: true);
          _frontOf(g);
        case GarmentShape.dress:
          _cloth(_torsoPath(fit: g.fitOr, length: 1), g, i, part: 30);
          _frontOf(g);
        case GarmentShape.legs when g.kind == GarmentKind.overalls:
          // The bib and the straps.
          var (across, up, half, low) = _torsoFrame;
          var top = Offset.lerp(rig.chest, rig.hips, 0.35)!;
          var bib = Path()
            ..moveTo(top.dx + across.dx * half * 0.5, top.dy)
            ..lineTo(top.dx - across.dx * half * 0.5, top.dy)
            ..lineTo(rig.hips.dx - low * g.fitOr, rig.hips.dy + rig.legWidth * 0.2)
            ..lineTo(rig.hips.dx + low * g.fitOr, rig.hips.dy + rig.legWidth * 0.2)
            ..close();
          _cloth(bib, g, i, part: 31);
          var strap = Paint()
            ..strokeWidth = rig.limbWidth * 0.35
            ..strokeCap = StrokeCap.round
            ..color = faded(g.color, g.condition.fade);
          for (var s in [-1.0, 1.0]) {
            canvas.drawLine(top + across * (s * half * 0.4),
                rig.chest + across * (s * half * 0.62), strap);
          }
        default:
          break;
      }
    }
  }

  /// _frontOf is what is on the front of a garment -- a hood and pocket, a
  /// collar and buttons, a front left open -- going round with the body,
  /// and not there from behind, except a hood, which hangs down the back.
  void _frontOf(Garment g) {
    var (across, up, half, _) = _torsoFrame;
    var colour = faded(g.color, g.condition.fade);
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = edge * 1.4
      ..color = _shade(colour);
    var front = bodyFacing;
    if (front < 0.35) {
      if (g.kind == GarmentKind.hoodie && front < -0.3) {
        _fill(
            Path()
              ..addOval(Rect.fromCenter(
                  center: rig.chest - up * (u * 0.05),
                  width: half * 1.1,
                  height: u * 0.55)),
            Color.lerp(colour, const Color(0xFF000000), 0.12)!);
      }
      return;
    }
    var side = math.sin(rig.yaw * math.pi / 180);
    canvas.save();
    canvas.translate(-side * half * 0.4, 0);
    var collar = rig.chest + up * (u * 0.02);
    Offset off(double a, double b) => collar + across * (half * a) - up * (u * b);
    var hem = rig.chest.dy + (rig.hips.dy - rig.chest.dy) * g.lengthOr;
    switch (g.kind) {
      case GarmentKind.hoodie:
        canvas.drawPath(
            Path()
              ..moveTo(off(0.55, 0).dx, off(0.55, 0).dy)
              ..quadraticBezierTo(off(0, 0.35).dx, off(0, 0.35).dy,
                  off(-0.55, 0).dx, off(-0.55, 0).dy),
            line..strokeWidth = edge * 2.2);
        var pocket = Offset.lerp(rig.chest, rig.hips, 0.72)!;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: pocket, width: half * 0.95, height: u * 0.3),
                Radius.circular(u * 0.08)),
            line..strokeWidth = edge * 1.2);
        var string = Paint()
          ..strokeWidth = edge * 1.3
          ..strokeCap = StrokeCap.round
          ..color = g.color2.withValues(alpha: 0.85);
        for (var s in [-1.0, 1.0]) {
          var from = off(s * 0.18, 0.12);
          canvas.drawLine(from, from - up * (u * 0.38), string);
        }
      case GarmentKind.shirt || GarmentKind.polo:
        canvas.drawPath(
            Path()
              ..moveTo(off(0.3, 0).dx, off(0.3, 0).dy)
              ..lineTo(off(0, 0.3).dx, off(0, 0.3).dy)
              ..lineTo(off(-0.3, 0).dx, off(-0.3, 0).dy),
            line);
        var dot = Paint()..color = _shade(colour);
        var buttons = g.kind == GarmentKind.polo ? 2 : 4;
        for (var b = 1; b <= buttons; b++) {
          canvas.drawCircle(
              Offset.lerp(off(0, 0.3), Offset(rig.chest.dx, hem), b / (buttons + 1.5))!,
              edge * 1.3,
              dot);
        }
      case GarmentKind.jacket ||
            GarmentKind.blazer ||
            GarmentKind.coat ||
            GarmentKind.cardigan:
        // Open down the front, with lapels.
        canvas.drawLine(off(0, 0.25), Offset(rig.chest.dx, hem), line);
        if (g.kind != GarmentKind.cardigan) {
          for (var s in [-1.0, 1.0]) {
            var lapel = Path()
              ..moveTo(off(s * 0.4, 0).dx, off(s * 0.4, 0).dy)
              ..lineTo(off(s * 0.05, 0.6).dx, off(s * 0.05, 0.6).dy)
              ..lineTo(off(s * 0.28, 0.25).dx, off(s * 0.28, 0.25).dy)
              ..close();
            _fill(lapel, Color.lerp(colour, g.color2, 0.25)!);
          }
        }
      case GarmentKind.sweater:
        canvas.drawLine(Offset(rig.chest.dx - half, hem - u * 0.05),
            Offset(rig.chest.dx + half, hem - u * 0.05), line);
        continue neckline;
      neckline:
      default:
        var deep = g.kind == GarmentKind.tank ||
                g.kind == GarmentKind.vest ||
                g.kind == GarmentKind.blouse ||
                g.kind == GarmentKind.swimsuit
            ? 0.24
            : 0.16;
        if (g.kind == GarmentKind.braTop) break;
        canvas.drawPath(
            Path()
              ..moveTo(off(0.32, 0).dx, off(0.32, 0).dy)
              ..quadraticBezierTo(off(0, deep).dx, off(0, deep).dy,
                  off(-0.32, 0).dx, off(-0.32, 0).dy),
            line);
    }
    canvas.restore();
  }

  void _capes() {
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.cape)) {
      var (across, _, half, _) = _torsoFrame;
      var top = rig.chest;
      var hemY = rig.hips.dy + g.lengthOr * _leg;
      var hemHalf = half * g.kind.flare;
      var cape = Path()
        ..moveTo((top + across * half).dx, (top + across * half).dy)
        ..lineTo((top - across * half).dx, (top - across * half).dy)
        ..lineTo(rig.hips.dx - hemHalf, hemY)
        ..quadraticBezierTo(rig.hips.dx, hemY + u * 0.2, rig.hips.dx + hemHalf, hemY)
        ..close();
      _cloth(cape, g, i, part: 40, hem: true);
    }
  }

  void _neckwear() {
    var (across, up, half, _) = _torsoFrame;
    if (bodyFacing < 0.2) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    canvas.save();
    canvas.translate(-side * half * 0.4, 0);
    var collar = rig.chest + up * (u * 0.02);
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.neck)) {
      var colour = faded(g.color, g.condition.fade);
      switch (g.kind) {
        case GarmentKind.tie:
          var knot = collar - up * (u * 0.14);
          var tip = Offset.lerp(rig.chest, rig.hips, 0.62)!;
          var tie = Path()
            ..moveTo(knot.dx - u * 0.05, knot.dy)
            ..lineTo(knot.dx + u * 0.05, knot.dy)
            ..lineTo(tip.dx + u * 0.07, tip.dy - u * 0.08)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - u * 0.07, tip.dy - u * 0.08)
            ..close();
          _cloth(tie, g, i, part: 50);
        case GarmentKind.bowTie:
          var c = collar - up * (u * 0.1);
          for (var s in [-1.0, 1.0]) {
            _fill(
                Path()
                  ..moveTo(c.dx, c.dy)
                  ..lineTo(c.dx + s * u * 0.13, c.dy - u * 0.07)
                  ..lineTo(c.dx + s * u * 0.13, c.dy + u * 0.07)
                  ..close(),
                colour);
          }
          _fill(Path()..addOval(Rect.fromCircle(center: c, radius: u * 0.035)),
              colour);
        case GarmentKind.scarf:
          var band = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: collar - up * (u * 0.06),
                    width: half * 1.1,
                    height: u * 0.2),
                Radius.circular(u * 0.08)));
          _cloth(band, g, i, part: 51);
          var tail = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(collar.dx + half * 0.15, collar.dy, u * 0.16, u * 0.6),
                Radius.circular(u * 0.05)));
          _cloth(tail, g, i, part: 52, hem: true);
        case GarmentKind.necklace:
          var chain = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = edge * 1.2
            ..color = colour;
          var low = collar + up * (-u * 0.25);
          canvas.drawPath(
              Path()
                ..moveTo((collar + across * (half * 0.35)).dx,
                    (collar + across * (half * 0.35)).dy)
                ..quadraticBezierTo(low.dx, low.dy,
                    (collar - across * (half * 0.35)).dx,
                    (collar - across * (half * 0.35)).dy),
              chain);
          _fill(
              Path()
                ..addOval(Rect.fromCircle(
                    center: low + up * (u * 0.11), radius: u * 0.04)),
              g.color2);
        default:
          break;
      }
    }
    canvas.restore();
  }

  /// _arms draws the arms turned away from the reader with [far], and the
  /// rest without -- [near] being how far behind the middle of the body an
  /// arm can be and still count as in front -- each with its sleeves.
  void _arms({required bool far, required double near}) {
    for (var limb in [CharacterLimb.armL, CharacterLimb.armR]) {
      if ((rig.depths[limb]! < near) != far) continue;
      var shoulder = rig.root(limb), elbow = rig.middle(limb);
      var wrist = rig.end(limb);
      _stroke([shoulder, elbow, wrist], rig.limbWidth, dna.skin);
      var forward = wrist - elbow;
      var hand = wrist +
          (forward.distance == 0
              ? Offset.zero
              : forward / forward.distance * rig.handRadius * 0.5);
      _fill(Path()..addOval(Rect.fromCircle(center: hand, radius: rig.handRadius)),
          dna.skin);
      for (var (i, g) in _wearing((g) => g.kind.hasSleeves)) {
        var sleeve = g.sleeveOr;
        if (sleeve <= 0) continue;
        _cloth(null, g, i,
            line: _along(limb, 0, math.min(0.97, sleeve)),
            width: rig.limbWidth * 1.14 * g.fitOr,
            part: 60 + limb.index,
            hem: true);
      }
    }
  }

  // ---- what is worn on the head ----

  void _glasses(double w) {
    for (var (_, g) in _wearing((g) => g.kind.shape == GarmentShape.glasses)) {
      var frame = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.025
        ..color = g.color;
      var eyeY = u * 0.06 + _nodShift;
      var lenses = <Rect>[];
      for (var s in [-1.0, 1.0]) {
        var toward = _toward(s * 0.42);
        if (toward < 0.15) continue;
        var c = Offset(_across(s * 0.42, w), eyeY);
        lenses.add(Rect.fromCenter(
            center: c, width: u * 0.24 * toward, height: u * 0.2));
      }
      for (var r in lenses) {
        if (g.kind == GarmentKind.sunglasses) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.06)),
              Paint()..color = const Color(0xE0151515));
        }
        if (g.kind == GarmentKind.roundGlasses) {
          canvas.drawOval(r, frame);
        } else {
          canvas.drawRRect(
              RRect.fromRectAndRadius(r, Radius.circular(u * 0.04)), frame);
        }
      }
      if (lenses.length == 2) {
        canvas.drawLine(Offset(lenses[0].right, eyeY - u * 0.02),
            Offset(lenses[1].left, eyeY - u * 0.02), frame);
      }
    }
  }

  void _hats(double w, double h) {
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.hat)) {
      var colour = faded(g.color, g.condition.fade);
      var shift = _across(0, w) * 0.3;
      switch (g.kind) {
        case GarmentKind.cap:
          var dome = Path()
            ..addArc(
                Rect.fromCenter(
                    center: Offset(0, -h * 0.35), width: w * 2.1, height: h * 1.5),
                math.pi,
                math.pi)
            ..close();
          _cloth(dome, g, i, part: 70);
          // The peak sticks out the way the face points.
          var peak = Path()
            ..addOval(Rect.fromCenter(
                center: Offset(shift * 2.2, -h * 0.36),
                width: w * (1.2 + 0.6 * (1 - facing.abs())),
                height: h * 0.18));
          _fill(peak, Color.lerp(colour, g.color2, 0.3)!);
        case GarmentKind.beanie:
          var dome = Path()
            ..addArc(
                Rect.fromCenter(
                    center: Offset(0, -h * 0.3), width: w * 2.12, height: h * 1.7),
                math.pi,
                math.pi)
            ..close();
          _cloth(dome, g, i, part: 70);
          _fill(
              Path()
                ..addRRect(RRect.fromRectAndRadius(
                    Rect.fromLTWH(-w * 1.07, -h * 0.42, w * 2.14, h * 0.24),
                    Radius.circular(h * 0.08))),
              Color.lerp(colour, const Color(0xFF000000), 0.12)!);
        case GarmentKind.topHat:
          _fill(
              Path()
                ..addOval(Rect.fromCenter(
                    center: Offset(0, -h * 0.72), width: w * 2.4, height: h * 0.3)),
              colour);
          _cloth(
              Path()
                ..addRect(Rect.fromLTWH(-w * 0.75, -h * 1.75, w * 1.5, h * 1.05)),
              g,
              i,
              part: 70);
          canvas.drawRect(Rect.fromLTWH(-w * 0.75, -h * 0.95, w * 1.5, h * 0.16),
              Paint()..color = g.color2);
        case GarmentKind.sunHat:
          _fill(
              Path()
                ..addOval(Rect.fromCenter(
                    center: Offset(0, -h * 0.55), width: w * 3.2, height: h * 0.55)),
              colour);
          _cloth(
              Path()
                ..addArc(
                    Rect.fromCenter(
                        center: Offset(0, -h * 0.55), width: w * 1.6, height: h * 1.3),
                    math.pi,
                    math.pi)
                ..close(),
              g,
              i,
              part: 70);
        case GarmentKind.crown:
          var crown = Path()..moveTo(-w * 0.7, -h * 0.75);
          for (var k = 0; k <= 4; k++) {
            var x = -w * 0.7 + w * 1.4 * k / 4;
            crown.lineTo(x, k.isEven ? -h * 1.35 : -h * 1.0);
          }
          crown
            ..lineTo(w * 0.7, -h * 0.75)
            ..close();
          _fill(crown, colour);
        default:
          break;
      }
    }
  }

  // ---- cloth ----

  /// _capsule is a round-ended band [width] thick through [points]: an arm,
  /// a leg, a sleeve -- as a shape, so it can be cut and patterned.
  Path _capsule(List<Offset> points, double width) {
    var r = width / 2;
    // Each piece joined to the last, so there is one outline round the
    // whole of it: pieces merely added together keep their own outlines,
    // and every elbow and knee showed a circle.
    var out = Path()..addOval(Rect.fromCircle(center: points.first, radius: r));
    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i], b = points[i + 1];
      var d = b - a;
      var piece = Path()..addOval(Rect.fromCircle(center: b, radius: r));
      if (d.distance >= 1e-6) {
        var n = Offset(-d.dy, d.dx) / d.distance * r;
        piece.addPolygon([a + n, b + n, b - n, a - n], true);
        piece = Path.combine(PathOperation.union, piece, Path());
      }
      out = Path.combine(PathOperation.union, out, piece);
    }
    return out;
  }

  /// _stroke is a round-ended band [width] thick through [points], edged
  /// the way [_fill] edges a shape. Drawn as a stroke rather than a shape
  /// because a stroke has no seams: a band made of pieces showed a sliver
  /// at every elbow and knee.
  void _stroke(List<Offset> points, double width, Color colour) {
    var path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    var stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        path,
        stroke
          ..strokeWidth = width + edge * 2
          ..color = _shade(colour));
    canvas.drawPath(
        path,
        stroke
          ..strokeWidth = width
          ..color = colour);
  }

  /// _cloth draws garment [g] -- the [i]th worn -- as [shape], or as a band
  /// [width] wide along [line] (a sleeve, a trouser leg): its colour washed
  /// out as much as it is faded, its pattern, dirt and patches, and cut
  /// through where it is ripped, so what is under it shows. [part] keeps
  /// two pieces of one garment from wearing the same way; [hem] says its
  /// lower edge is a hem, which frays.
  void _cloth(Path? shape, Garment g, int i,
      {List<Offset>? line,
      double width = 0,
      int part = 0,
      bool hem = false}) {
    var c = g.condition;
    var seed = g.seed + i * 7919 + g.kind.index * 104729 + part * 31337;
    var colour = faded(g.color, c.fade);
    // What the pattern is kept inside, and where rips may fall.
    var area = shape ?? _capsule(line!, width);
    var bounds = area.getBounds();
    var cut = c.rips > 0 || (hem && c.frays > 0);
    if (cut) canvas.saveLayer(bounds.inflate(edge * 3 + width), Paint());
    if (shape != null) {
      canvas.drawPath(shape, Paint()..color = colour);
    } else {
      _stroke(line!, width, colour);
    }
    canvas.save();
    canvas.clipPath(area);
    _pattern(bounds, g, seed);
    _wear(area, bounds, g, colour, seed);
    canvas.restore();
    if (shape != null) canvas.drawPath(shape, _edgePaint(colour));
    if (cut) {
      canvas.drawPath(_holes(area, bounds, c, seed, hem),
          Paint()..blendMode = BlendMode.clear);
      canvas.restore();
    }
  }

  /// _holes is where [c]'s rips go through a piece of cloth, and the bites
  /// a frayed hem takes out of its bottom edge.
  Path _holes(Path area, Rect bounds, GarmentCondition c, int seed, bool hem) {
    var holes = Path();
    var rips = (c.rips * 4).round();
    for (var k = 0, placed = 0; k < 24 && placed < rips; k++) {
      var at = Offset(bounds.left + bounds.width * wearUnit(seed, k * 2),
          bounds.top + bounds.height * (0.25 + 0.7 * wearUnit(seed, k * 2 + 1)));
      if (!area.contains(at)) continue;
      placed++;
      var size = u * (0.03 + 0.05 * c.rips) * (0.6 + 0.8 * wearUnit(seed, 100 + k));
      holes.addPolygon([
        for (var p = 0; p < 7; p++)
          at +
              Offset(math.cos(p / 7 * 2 * math.pi), math.sin(p / 7 * 2 * math.pi)) *
                  (size * (0.55 + 0.45 * wearUnit(seed, 200 + k * 7 + p)))
                  .toDouble()
                  .clamp(0.0, double.infinity),
      ], true);
    }
    if (hem && c.frays > 0) {
      var bites = 6 + (c.frays * 10).round();
      for (var k = 0; k < bites; k++) {
        var x = bounds.left + bounds.width * (k + wearUnit(seed, 300 + k)) / bites;
        var deep = u * 0.05 * c.frays * (0.4 + wearUnit(seed, 400 + k));
        holes.addPolygon([
          Offset(x - deep * 0.6, bounds.bottom + edge * 2),
          Offset(x, bounds.bottom - deep),
          Offset(x + deep * 0.6, bounds.bottom + edge * 2),
        ], true);
      }
    }
    return holes;
  }

  /// _wear is the dirt and the patches on a piece of cloth.
  void _wear(Path area, Rect bounds, Garment g, Color colour, int seed) {
    var c = g.condition;
    if (c.dirt > 0) {
      var dirt = Paint()
        ..color = const Color(0xFF6B4E2E).withValues(alpha: 0.3 + 0.2 * c.dirt);
      var blots = (c.dirt * 10).round();
      for (var k = 0; k < blots; k++) {
        // Lower down more than higher up: dirt is splashed up from the
        // ground.
        var y = bounds.top +
            bounds.height * (1 - math.pow(wearUnit(seed, 500 + k), 2.2));
        var at = Offset(bounds.left + bounds.width * wearUnit(seed, 600 + k), y);
        canvas.drawOval(
            Rect.fromCenter(
                center: at,
                width: u * (0.04 + 0.08 * wearUnit(seed, 700 + k)),
                height: u * (0.03 + 0.05 * wearUnit(seed, 800 + k))),
            dirt);
      }
    }
    if (c.patches > 0) {
      var patches = (c.patches * 3).round();
      for (var k = 0, placed = 0; k < 20 && placed < patches; k++) {
        var at = Offset(bounds.left + bounds.width * wearUnit(seed, 900 + k),
            bounds.top + bounds.height * wearUnit(seed, 1000 + k));
        if (!area.contains(at)) continue;
        placed++;
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate((wearUnit(seed, 1100 + k) - 0.5) * 0.6);
        var size = u * (0.09 + 0.05 * wearUnit(seed, 1200 + k));
        var patch = Rect.fromCenter(
            center: Offset.zero, width: size, height: size * 0.85);
        canvas.drawRect(
            patch, Paint()..color = Color.lerp(colour, g.color2, 0.55)!);
        canvas.drawRect(
            patch.deflate(size * 0.1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = edge * 0.7
              ..color = _shade(colour, 0.5));
        canvas.restore();
      }
    }
  }

  /// _pattern prints [g]'s pattern over [bounds], in its second colour.
  void _pattern(Rect bounds, Garment g, int seed) {
    var ink = Paint()..color = g.color2.withValues(alpha: 0.85);
    var step = u * 0.1;
    switch (g.pattern) {
      case GarmentPattern.plain:
        return;
      case GarmentPattern.stripes:
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawRect(
              Rect.fromLTWH(bounds.left, y, bounds.width, step * 0.45), ink);
        }
      case GarmentPattern.pinstripe:
        var line = Paint()
          ..strokeWidth = math.max(0.5, u * 0.008)
          ..color = g.color2.withValues(alpha: 0.7);
        for (var x = bounds.left; x < bounds.right; x += step * 0.6) {
          canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), line);
        }
      case GarmentPattern.check:
        var soft = Paint()..color = g.color2.withValues(alpha: 0.4);
        for (var y = bounds.top; y < bounds.bottom; y += step * 1.4) {
          canvas.drawRect(Rect.fromLTWH(bounds.left, y, bounds.width, step * 0.6), soft);
        }
        for (var x = bounds.left; x < bounds.right; x += step * 1.4) {
          canvas.drawRect(Rect.fromLTWH(x, bounds.top, step * 0.6, bounds.height), soft);
        }
      case GarmentPattern.dots:
        var row = 0;
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          var x0 = bounds.left + (row.isEven ? 0 : step / 2);
          row++;
          for (var x = x0; x < bounds.right; x += step) {
            canvas.drawCircle(Offset(x, y), u * 0.018, ink);
          }
        }
      case GarmentPattern.camo:
        var dark = Paint()..color = Color.lerp(g.color2, const Color(0xFF000000), 0.35)!;
        var blobs = (bounds.width * bounds.height / (u * u * 0.03)).ceil().clamp(4, 60);
        for (var k = 0; k < blobs; k++) {
          var at = Offset(bounds.left + bounds.width * wearUnit(seed, 1300 + k),
              bounds.top + bounds.height * wearUnit(seed, 1400 + k));
          canvas.drawOval(
              Rect.fromCenter(
                  center: at,
                  width: u * (0.08 + 0.1 * wearUnit(seed, 1500 + k)),
                  height: u * (0.05 + 0.06 * wearUnit(seed, 1600 + k))),
              k.isEven ? ink : dark);
        }
    }
  }

  Paint _edgePaint(Color colour) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = edge
    ..color = _shade(colour);

  /// _inHead draws [what] in the head's own space: the middle of the head
  /// at the origin, tilted with it.
  void _inHead(void Function() what) {
    canvas.save();
    canvas.translate(rig.headCentre.dx, rig.headCentre.dy);
    canvas.rotate(rig.headTurn * math.pi / 180);
    what();
    canvas.restore();
  }

  /// yaw is how far the head is turned from the reader, in radians:
  /// towards the page's left as it grows.
  double get yaw => (face[FaceControl.turn] + rig.yaw) * math.pi / 180;

  /// facing is how much of the face is towards the reader: 1 straight on,
  /// 0 side on, below 0 turned away.
  double get facing => math.cos(yaw);

  /// _across is where a feature [phi] round the head from the front of the
  /// face is, across a head [w] wide: a point on a turning ball, seen from
  /// the front.
  double _across(double phi, double w) => w * math.sin(phi - yaw);

  /// _toward is how far a feature [phi] round the head faces the reader.
  double _toward(double phi) => math.cos(phi - yaw);

  /// _nodShift is how far down the face's features move as the head nods.
  double get _nodShift =>
      rig.headRadii.height * 0.35 * math.sin(face[FaceControl.nod] * math.pi / 180);

  void _backHair() {
    var r = rig.headRadii;
    var back = Path()
      ..moveTo(-r.width * 1.12, -r.height * 0.1)
      ..quadraticBezierTo(-r.width * 1.25, r.height * 1.6, -r.width * 0.9,
          r.height * 1.9)
      ..lineTo(r.width * 0.9, r.height * 1.9)
      ..quadraticBezierTo(
          r.width * 1.25, r.height * 1.6, r.width * 1.12, -r.height * 0.1)
      ..close();
    _fill(back, dna.hair);
  }

  void _head() {
    var r = rig.headRadii;
    var w = r.width, h = r.height;
    // Ears turned away go behind the head, ears turned towards the reader
    // in front of it, so a head in profile shows one ear on its cheek.
    var ears = [-math.pi / 2, math.pi / 2];
    void ear(double phi) => _fill(
        Path()
          ..addOval(Rect.fromCircle(
              center: Offset(_across(phi, w * 0.98), u * 0.06 - _nodShift * 0.4),
              radius: u * 0.1)),
        dna.skin);
    for (var phi in ears) {
      if (_toward(phi) < 0.3) ear(phi);
    }
    var head = Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2));
    _fill(head, dna.skin);
    // The hair going round the back of the head, bounded by a hairline that
    // curves round the head as it turns: a sliver at each side straight on,
    // half the head side on, all of it from behind.
    if (dna.hairStyle != HairStyle.bald) {
      if (_backOfHead(w, h) case var back?) {
        canvas.drawPath(back, Paint()..color = dna.hair);
        canvas.drawPath(
            head,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = edge
              ..color = _shade(dna.hair));
      }
    }
    if (facing > -0.2) _nose(w, front: false);
    for (var phi in ears) {
      if (_toward(phi) >= 0.3) ear(phi);
    }
    _hair(r);
    if (facing > -0.15) {
      _face(w);
      _glasses(w);
    }
    if (dna.hairStyle == HairStyle.long && facing < -0.3) _backHair();
    _hats(w, h);
  }

  /// _backOfHead is the part of a head [w] by [h] the hair covers, seen
  /// from the front as it turns: everything further round the head than
  /// [_hairline] from the middle of the face. Null when none of it shows.
  Path? _backOfHead(double w, double h) {
    // Less than half the head, so what shows of it is one piece. On a ball,
    // a line of longitude is the same share of the way across at every
    // height -- only the width it is a share of changes.
    double? lo, hi;
    for (var k = 0; k <= 48; k++) {
      var a = _hairline + (2 * math.pi - 2 * _hairline) * k / 48 - yaw;
      if (math.cos(a) <= 0) continue;
      var v = math.sin(a);
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    if (lo == null || hi == null || hi - lo < 0.01) return null;
    var left = <Offset>[], right = <Offset>[];
    for (var k = 0; k <= 32; k++) {
      var y = -h + 2 * h * k / 32;
      var across = w * math.sqrt(math.max(0.0, 1 - (y / h) * (y / h)));
      left.add(Offset(lo * across, y));
      right.add(Offset(hi * across, y));
    }
    return Path()..addPolygon([...left, ...right.reversed], true);
  }

  /// _hairline is how far round the head from the middle of the face the
  /// skin goes before the hair starts, in radians: a little past the ears.
  static const double _hairline = 1.85;

  void _hair(Size r) {
    if (dna.hairStyle == HairStyle.bald) return;
    var w = r.width, h = r.height;
    var behind = Rect.fromCenter(
        center: Offset.zero, width: w * 2.16, height: h * 2.16);
    // The crown: the top of the head is hair whichever way it is turned,
    // or a three-quarter view shows a bald patch between the fringe and
    // the hair going round the back.
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2)));
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, -h * 1.25), width: w * 2.8, height: h * 1.4),
        Paint()..color = dna.hair);
    canvas.restore();
    var shift = _across(0, w) * 0.45;
    if (dna.hairStyle == HairStyle.bun) {
      _fill(
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(-shift * 0.6, -h * 1.08), radius: u * 0.21)),
          dna.hair);
    }
    if (dna.hairStyle == HairStyle.curly) {
      // Curls round the top of the head, laid by a fixed rule so the same
      // character has the same curls in every frame and every export.
      for (var i = 0; i <= 8; i++) {
        var a = math.pi * (1.05 + i * 0.9 / 8);
        _fill(
            Path()
              ..addOval(Rect.fromCircle(
                  center:
                      Offset(math.cos(a) * w * 0.98, math.sin(a) * h * 0.92),
                  radius: u * 0.13)),
            dna.hair);
      }
    }
    if (facing < -0.3) return;
    // The fringe goes round with the face.
    var cap = Path()
      ..moveTo(-w * 1.04, h * 0.12)
      ..cubicTo(-w * 1.08, -h * 1.28, w * 1.08, -h * 1.28, w * 1.04, h * 0.12)
      ..cubicTo(w * 0.86, -h * 0.4, w * 0.2, -h * 0.62, -w * 0.12, -h * 0.5)
      ..cubicTo(-w * 0.5, -h * 0.3, -w * 0.84, -h * 0.2, -w * 1.04, h * 0.12)
      ..close();
    canvas.save();
    canvas.clipPath(Path()..addOval(behind));
    canvas.translate(shift, 0);
    canvas.scale(0.55 + 0.45 * facing.clamp(0.0, 1.0), 1);
    _fill(cap, dna.hair);
    canvas.restore();
  }

  /// _nose is the nose: a hook straight on, and turned past a ¾ view a
  /// point standing out from the side of the face.
  void _nose(double w, {required bool front}) {
    var side = math.sin(yaw);
    var y = u * 0.12 + _nodShift;
    if (side.abs() < 0.55) {
      if (!front) return;
      var x = _across(0, w * 0.95);
      canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..quadraticBezierTo(
                x + u * 0.05 * (side >= 0 ? -1 : 1).toDouble() * -1,
                y + u * 0.07,
                x - u * 0.01,
                y + u * 0.08),
          _feature(u * 0.03, _shade(dna.skin, 0.45)));
      return;
    }
    if (front) return;
    // In profile: a point past the outline, which way the face is turned.
    var dir = side > 0 ? -1.0 : 1.0;
    var x = _across(0, w * 0.97);
    var out = u * 0.13 * (side.abs() - 0.45).clamp(0.0, 0.55) / 0.55;
    var tip = Path()
      ..moveTo(x, y - u * 0.04)
      ..lineTo(x + dir * out, y + u * 0.1)
      ..lineTo(x, y + u * 0.13)
      ..close();
    _fill(tip, dna.skin);
  }

  void _face(double w) {
    var dy = _nodShift;
    var eyeY = u * 0.06 + dy;
    var white = Paint()..color = const Color(0xFFFFFFFF);
    var lid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge
      ..color = _shade(dna.skin);
    var lookX = (face[FaceControl.lookX] + life.lookX).clamp(-1.0, 1.0);
    var lookY = (face[FaceControl.lookY] + life.lookY).clamp(-1.0, 1.0);
    var open = face[FaceControl.eyesOpen] * (1 - life.blink);
    var squint = face[FaceControl.squint];
    for (var side in [-1.0, 1.0]) {
      var phi = side * 0.42;
      var toward = _toward(phi);
      if (toward < 0.12) continue;
      var c = Offset(_across(phi, w), eyeY);
      var ew = u * 0.17 * toward, eh = u * 0.21;
      var height = eh * open * (1 - 0.45 * squint);
      if (height < eh * 0.14) {
        // Shut: a curve where the lid meets.
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - ew / 2, c.dy)
              ..quadraticBezierTo(c.dx, c.dy + eh * 0.22, c.dx + ew / 2, c.dy),
            _feature(u * 0.028, _shade(dna.skin, 0.55)));
      } else {
        // A squint pushes up from below, so the eye keeps its top.
        var box = Rect.fromLTWH(c.dx - ew / 2,
            c.dy - eh / 2 + (eh - height) * (squint > 0 ? 0.25 : 0.5), ew, height);
        canvas.drawOval(box, white);
        canvas.save();
        canvas.clipPath(Path()..addOval(box));
        var iris = c +
            Offset(lookX * u * 0.04 * toward, -lookY * u * 0.035 + u * 0.015);
        canvas.drawOval(
            Rect.fromCenter(
                center: iris, width: u * 0.124 * toward, height: u * 0.124),
            Paint()..color = dna.eyes);
        canvas.drawOval(
            Rect.fromCenter(
                center: iris, width: u * 0.068 * toward, height: u * 0.068),
            Paint()..color = const Color(0xFF1B1512));
        canvas.drawCircle(iris + Offset(-u * 0.022, -u * 0.035), u * 0.017, white);
        canvas.restore();
        canvas.drawOval(box, lid);
      }
      _brow(c, side, toward);
      if (toward > 0.3) {
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(_across(side * 0.62, w), u * 0.24 + dy),
                width: u * 0.14 * toward,
                height: u * 0.08),
            Paint()
              ..color = const Color(0xFFFF7B7B).withValues(
                  alpha: (0.22 + 0.2 * face[FaceControl.smile]).clamp(0.0, 0.5)));
      }
    }
    _nose(w, front: true);
    _mouth(w);
  }

  /// _brow is the brow over the eye at [c]: raised, squeezed together and
  /// down in a frown, its inner end lifted in worry.
  void _brow(Offset c, double side, double toward) {
    var raise = face[FaceControl.browRaise];
    var squeeze = face[FaceControl.browSqueeze];
    var worry = face[FaceControl.browWorry];
    var y = c.dy - u * 0.16 - raise * u * 0.055;
    var inner = Offset(
        c.dx - side * (u * 0.08 + squeeze * u * 0.02) * toward,
        y + u * 0.01 + squeeze * u * 0.06 - worry * u * 0.07);
    var outer = Offset(c.dx + side * u * 0.09 * toward,
        y + u * 0.01 - squeeze * u * 0.01 + worry * u * 0.03);
    var mid = Offset((inner.dx + outer.dx) / 2,
        math.min(inner.dy, outer.dy) - u * 0.04 * (1 - squeeze * 0.6));
    canvas.drawPath(
        Path()
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, outer.dx, outer.dy),
        _feature(u * 0.035,
            dna.hairStyle == HairStyle.bald ? _shade(dna.skin) : dna.hair));
  }

  /// _mouth is a mouth shape when one is set -- speech -- or else the mouth
  /// the face's own controls make.
  void _mouth(double w) {
    var at = Offset(_across(0, w * 0.88), u * 0.3 + _nodShift);
    var across = (0.35 + 0.65 * facing.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(across, 1);
    if (face.mouth == MouthShape.rest) {
      _restMouth();
    } else {
      // The shapes are drawn about 22 units across; a mouth is about a
      // fifth of a head.
      var k = u * 0.0095 * (1 + 0.25 * face[FaceControl.wide]);
      canvas.scale(k, k);
      _shape(face.mouth);
    }
    canvas.restore();
  }

  static const _lips = Color(0xFF5A2A22);
  static const _tongue = Color(0xFFE0707A);

  void _restMouth() {
    var smile = face[FaceControl.smile];
    var jaw = face[FaceControl.jaw];
    var wide = face[FaceControl.wide];
    var half = u * 0.1 * (1 + 0.4 * wide.clamp(-0.6, 1.0));
    var corner = -smile * u * 0.05;
    if (jaw < 0.06) {
      if (wide < -0.5) {
        // Pursed.
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: u * 0.07, height: u * 0.06),
            _feature(u * 0.03, _lips));
        return;
      }
      canvas.drawPath(
          Path()
            ..moveTo(-half, corner)
            ..quadraticBezierTo(0, smile * u * 0.1, half, corner),
          _feature(u * 0.032, _lips));
      return;
    }
    var top = smile > 0 ? smile * u * 0.02 : smile * u * 0.03;
    var bottom = top + jaw * u * 0.24 + math.max(0, smile) * u * 0.05;
    var mouth = Path()
      ..moveTo(-half, corner)
      ..quadraticBezierTo(0, top, half, corner)
      ..quadraticBezierTo(0, bottom * 1.3, -half, corner)
      ..close();
    canvas.drawPath(mouth, Paint()..color = _lips);
    canvas.save();
    canvas.clipPath(mouth);
    if (smile > 0.3) {
      canvas.drawRect(Rect.fromLTRB(-half, top - u * 0.05, half, top + u * 0.025),
          Paint()..color = const Color(0xFFFFFFFF));
    }
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, bottom * 1.05),
            width: half * 1.1,
            height: bottom * 0.5),
        Paint()..color = _tongue);
    canvas.restore();
    canvas.drawPath(mouth, _feature(edge, _shade(_lips, 0.2)));
  }

  /// _shape draws [m] in units about 22 across, centred on the mouth.
  void _shape(MouthShape m) {
    var dark = Paint()..color = _lips;
    var teeth = Paint()..color = const Color(0xFFFFFFFF);
    var tongue = Paint()..color = _tongue;
    Rect oval(double cx, double cy, double rx, double ry) =>
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
    RRect bar(double l, double t, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));
    switch (m) {
      case MouthShape.rest:
        return;
      case MouthShape.closed:
        canvas.drawLine(const Offset(-9, 0), const Offset(9, 0),
            _feature(3.6, _lips));
      case MouthShape.teeth:
        canvas.drawRRect(bar(-10, -4, 20, 8, 4), dark);
        canvas.drawRRect(bar(-8, -3, 16, 3, 1.5), teeth);
      case MouthShape.open:
        canvas.drawOval(oval(0, 0, 11, 6.5), dark);
        canvas.drawRRect(bar(-8, -6, 16, 3, 1.5), teeth);
        canvas.drawOval(oval(0, 3.5, 6, 2.5), tongue);
      case MouthShape.wide:
        canvas.drawOval(oval(0, 1, 12, 11), dark);
        canvas.drawRRect(bar(-8, -9, 16, 3, 1.5), teeth);
        canvas.drawOval(oval(0, 7, 7, 3.5), tongue);
      case MouthShape.round:
        canvas.drawOval(oval(0, 0, 8, 8), dark);
        canvas.drawOval(oval(0, 4, 4.5, 2), tongue);
      case MouthShape.pucker:
        canvas.drawOval(oval(0, 0, 5, 6), dark);
        canvas.drawOval(oval(0, 0, 5, 6),
            _feature(2, const Color(0xFFC9605C)));
      case MouthShape.lip:
        canvas.drawRRect(bar(-10, -3, 20, 7, 3.5), dark);
        canvas.drawRRect(bar(-8, -4, 16, 4, 1.5), teeth);
        canvas.drawPath(
            Path()
              ..moveTo(-9, 4)
              ..quadraticBezierTo(0, 1, 9, 4),
            _feature(2.4, const Color(0xFFC9605C)));
      case MouthShape.tongue:
        canvas.drawOval(oval(0, 0, 10, 8), dark);
        canvas.drawOval(oval(0, -2, 5, 3.5), tongue);
    }
  }

  Paint _feature(double width, Color colour) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = width
    ..color = colour;

  // ---- drawing helpers ----

  /// _fill fills [path] with [colour] and edges it a shade darker.
  void _fill(Path path, Color colour) {
    canvas.drawPath(path, Paint()..color = colour);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = edge
          ..color = _shade(colour));
  }

}

/// _shade is [c] darkened by [by], for the edge drawn round it.
Color _shade(Color c, [double by = 0.32]) =>
    Color.lerp(c, const Color(0xFF000000), by)!;
