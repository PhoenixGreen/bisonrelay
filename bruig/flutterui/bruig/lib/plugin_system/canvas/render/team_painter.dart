import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// team_painter.dart draws a team: where each player stands -- on the team's
// own box, or on the pitch it is linked to -- and what each one looks like.
//
// A linked team keeps its players in the pitch's own metres, its own half of
// the field, and asks the pitch where those metres are on the page. So the
// team goes wherever the pitch goes: moved, turned, zoomed, tilted, in
// perspective. The stage asks the same questions here when a player is
// clicked or dragged, so where a player is drawn and where a player is
// picked up can never disagree.

/// TeamGround is the pitch a linked team stands on, as it is on the page.
class TeamGround {
  final PitchPlacement place;

  /// toPage and fromPage carry a point between the pitch's own rectangle
  /// and the page, for a pitch that is an element with a move and a turn of
  /// its own. The identity for the canvas's background.
  final Offset Function(Offset) toPage;
  final Offset Function(Offset) fromPage;

  const TeamGround(this.place, this.toPage, this.fromPage);

  /// page is where a point on the field lands on the page.
  Offset page(double x, double y, [double z = 0]) =>
      toPage(place.page(x, y, z));

  /// field is the point of the field under a point on the page.
  Offset? field(Offset page) => place.field(fromPage(page));
}

Offset _same(Offset p) => p;

/// teamGround is the pitch [team] is linked to, or null where it is not
/// linked or what it is linked to is not a pitch.
TeamGround? teamGround(CanvasDocument? doc, TeamElement team, int frame) {
  if (!team.linked || doc == null) return null;
  if (team.link == teamLinkBackground) {
    var spec = doc.drawnBackground.spec;
    if (spec.style != ProceduralStyle.pitch) return null;
    return TeamGround(pitchPlacement(doc.size.rect, spec), _same, _same);
  }
  var element = doc.elementById(team.link) ??
      doc.masterScene?.elements.where((e) => e.id == team.link).firstOrNull;
  if (element is! BackgroundElement ||
      element.spec.style != ProceduralStyle.pitch) {
    return null;
  }
  var (forward, back) = elementTransform(element, frame);
  return TeamGround(
      pitchPlacement(element.bounds, element.spec), forward, back);
}

/// PitchChoice is a pitch a team can stand on: what links to it, what it is
/// called, and what it is.
typedef PitchChoice = ({
  String link,
  String label,
  PitchSport sport,
  double reference,
  Rect area,
});

/// pitchChoices is every pitch in [doc] a team can stand on: the canvas's
/// background where it is one, and every background element that is one.
List<PitchChoice> pitchChoices(CanvasDocument doc) => [
      if (doc.drawnBackground.spec.style == ProceduralStyle.pitch)
        (
          link: teamLinkBackground,
          label: "Canvas background",
          sport: doc.drawnBackground.spec.sport,
          reference:
              pitchRect(doc.size.rect, doc.drawnBackground.spec.sport).scale,
          area: doc.size.rect,
        ),
      for (var e in doc.elements)
        if (e is BackgroundElement && e.spec.style == ProceduralStyle.pitch)
          (
            link: e.id,
            label: e.name.isEmpty ? "Pitch" : e.name,
            sport: e.spec.sport,
            reference: pitchRect(e.bounds, e.spec.sport).scale,
            area: e.bounds,
          ),
    ];

/// elementTransform is how [e] is moved, turned and sized on [frame], as a
/// pair of functions taking a point in its own rectangle to the page and
/// back -- the same transform the renderer applies before drawing it.
(Offset Function(Offset), Offset Function(Offset)) elementTransform(
    CanvasElement e, int frame) {
  var pose = e.track?.at(frame) ?? Keyframe.rest;
  var b = e.bounds;
  var c = b.center;
  var spin = e.rotationRadians;
  var a = e.anchorIn(b);
  var turn = pose.rotate * math.pi / 180;
  var size = pose.scale == 0 ? 1.0 : pose.scale;
  Offset rotate(Offset p, Offset about, double by) {
    if (by == 0) return p;
    var co = math.cos(by), si = math.sin(by);
    var d = p - about;
    return about + Offset(d.dx * co - d.dy * si, d.dx * si + d.dy * co);
  }

  Offset forward(Offset p) {
    var q = rotate(a + (p - a) * size, a, turn);
    q = rotate(q, c, spin);
    return q.translate(pose.dx, pose.dy);
  }

  Offset back(Offset p) {
    var q = p.translate(-pose.dx, -pose.dy);
    q = rotate(q, c, -spin);
    q = rotate(q, a, -turn);
    return a + (q - a) / size;
  }

  return (forward, back);
}

/// PlayerPlace is where one player is on one frame.
class PlayerPlace {
  /// ground is where they stand, and centre where their token is drawn --
  /// the same on a pitch seen from above, and lifted to stand up off it on
  /// one seen at an angle.
  final Offset ground;
  final Offset centre;

  /// size is how much bigger or smaller than its set size their token is
  /// drawn: the pitch's zoom, and its perspective.
  final double size;

  /// depth is how far from the camera they are, for drawing nearer players
  /// over further ones.
  final double depth;

  /// shown is whether they are on the part of the pitch that is drawn.
  final bool shown;

  /// field is where they are in the pitch's metres, for a linked team.
  final Offset? field;

  const PlayerPlace(
      this.ground, this.centre, this.size, this.depth, this.shown, this.field);
}

/// teamFieldPoint is where [spot] rests on a pitch [place]s, in metres: the
/// team's own half -- the far one when it attacks the other way -- with
/// across measured down the team's box, as it always was.
Offset teamFieldPoint(TeamElement team, PlayerSpot spot, PitchPlacement place) {
  var half = place.length / 2;
  return Offset(
      (team.mirrored ? half : 0) + spot.dx * half, place.width * (1 - spot.dy));
}

/// spotFromField is the stored position of a player standing at [field].
(double, double) spotFromField(
    TeamElement team, Offset field, PitchPlacement place) {
  var half = place.length / 2;
  return (
    (field.dx - (team.mirrored ? half : 0)) / half,
    1 - field.dy / place.width
  );
}

/// playerPlace is where [spot] of [team] is on [frame].
PlayerPlace playerPlace(
    TeamGround? g, TeamElement team, PlayerSpot spot, int frame) {
  if (g == null) {
    var c = team.centreAt(spot, frame);
    return PlayerPlace(c, c, 1, 0, true, null);
  }
  var place = g.place;
  var rest = teamFieldPoint(team, spot, place);
  var x = rest.dx, y = rest.dy;
  // A run is kept in design units, as an element's is; on a pitch it is
  // read as metres at the pitch's flat size, across the page being along
  // the field and down it being across.
  var track = spot.track;
  if (track != null && !track.isEmpty) {
    var pose = track.at(frame);
    x += pose.dx / place.reference;
    y -= pose.dy / place.reference;
  }
  var size = place.scaleAt(x, y) / place.reference;
  var ground = g.page(x, y);
  var centre =
      place.flat ? ground : g.page(x, y, team.radiusOf(spot) / place.reference);
  return PlayerPlace(ground, centre, size, place.depthOf(x, y),
      x >= place.visibleFrom - 1, Offset(x, y));
}

/// paintTeam draws every player in a team.
///
/// In list order, which is what Bring forward and Send to back move a player
/// through -- except on a pitch seen at an angle, where the nearer players
/// are drawn over the further ones whatever the list says, as they would be.
void paintTeam(ui.Canvas canvas, Rect bounds, TeamElement e, int frame,
    {CanvasDocument? document, CanvasImageSource? images}) {
  if (e.dotRadius <= 0) return;
  var g = teamGround(document, e, frame);
  var places = [
    for (var spot in e.players) playerPlace(g, e, spot, frame),
  ];
  var order = [for (var i = 0; i < e.players.length; i++) i];
  if (g != null && !g.place.flat) {
    order.sort((a, b) => places[b].depth.compareTo(places[a].depth));
  }

  if (e.showRuns) {
    for (var i in order) {
      _paintRun(canvas, g, e, e.players[i], i);
    }
  }
  for (var i in order) {
    var spot = e.players[i];
    var at = places[i];
    if (spot.hidden || !at.shown) continue;
    if (spot.ball) {
      _paintBall(canvas, e, spot, at, g, frame);
      continue;
    }
    _paintPlayer(canvas, e, i, spot, at, g, images);
  }
}

/// _paintRun is where a player with keyframes goes: a dashed line through
/// every frame of their movement, to an arrow.
void _paintRun(
    ui.Canvas canvas, TeamGround? g, TeamElement e, PlayerSpot spot, int i) {
  var track = spot.track;
  if (track == null || track.keys.length < 2 || spot.hidden) return;
  var first = track.keys.first.frame, last = track.keys.last.frame;
  if (last <= first) return;
  var pts = <Offset>[];
  var step = math.max(1, ((last - first) / 40).ceil());
  for (var f = first; f <= last; f += step) {
    pts.add(playerPlace(g, e, spot, f).ground);
  }
  pts.add(playerPlace(g, e, spot, last).ground);
  var r = e.dotRadius * playerPlace(g, e, spot, last).size;
  var colour = _kitColour(e, i).withValues(alpha: 0.9);
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, r * 0.16)
    ..strokeCap = StrokeCap.round
    ..color = colour;
  // Dashed, by distance along the line.
  var on = r * 0.5, off = r * 0.35, carry = 0.0;
  var drawing = true;
  for (var k = 0; k + 1 < pts.length; k++) {
    var a = pts[k], b = pts[k + 1];
    var len = (b - a).distance;
    var d = 0.0;
    while (d < len) {
      var left = (drawing ? on : off) - carry;
      var step = math.min(left, len - d);
      if (drawing) {
        canvas.drawLine(Offset.lerp(a, b, d / len)!,
            Offset.lerp(a, b, (d + step) / len)!, paint);
      }
      d += step;
      carry += step;
      if (carry >= (drawing ? on : off) - 1e-6) {
        carry = 0;
        drawing = !drawing;
      }
    }
  }
  // The arrow, pointing the way the run ends.
  if (pts.length >= 2) {
    var tip = pts.last;
    var from = pts[pts.length - 2];
    for (var k = pts.length - 2; k >= 0 && (tip - from).distance < r; k--) {
      from = pts[k];
    }
    var dir = tip - from;
    if (dir.distance > 0) {
      dir = dir / dir.distance;
      var side = Offset(-dir.dy, dir.dx);
      var head = r * 0.7;
      var base = tip - dir * head;
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(
                (base + side * head * 0.55).dx, (base + side * head * 0.55).dy)
            ..lineTo(
                (base - side * head * 0.55).dx, (base - side * head * 0.55).dy)
            ..close(),
          Paint()..color = colour);
    }
  }
}

/// _kitColour is a player's main colour: the keeper's for a goalkeeper,
/// the team's for everybody else.
Color _kitColour(TeamElement e, int i) =>
    i == 0 && e.sport.hasKeeper ? e.keeperColor : e.playerColor;

void _paintPlayer(ui.Canvas canvas, TeamElement e, int i, PlayerSpot spot,
    PlayerPlace at, TeamGround? g, CanvasImageSource? images) {
  var r = e.dotRadius;
  var k = at.size;
  var keeper = i == 0 && e.sport.hasKeeper;
  var kit = _kitColour(e, i);

  // A shadow on the ground under them: always on a pitch seen at an angle,
  // where a token with none floats; where asked for, on one seen from above.
  if (g != null && !g.place.flat) {
    canvas.drawOval(
        Rect.fromCenter(
            center: at.ground,
            width: e.dotWidth * k * 1.05,
            height: r * k * 0.5),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * k * 0.12));
  } else if (e.shadow) {
    canvas.drawOval(
        Rect.fromCenter(
            center: at.centre + Offset(r * k * 0.12, r * k * 0.2),
            width: e.dotWidth * k,
            height: e.dotHeight * k),
        Paint()
          ..color = const Color(0x73000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * k * 0.18));
  }

  canvas.save();
  canvas.translate(at.centre.dx, at.centre.dy);
  canvas.scale(k);

  if (spot.highlight) {
    canvas.drawCircle(
        Offset.zero,
        r * 1.9,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, r * 1.9, [
            const Color(0xCCFFE066),
            const Color(0x00FFE066),
          ], [
            0.45,
            1
          ]));
  }

  switch (e.tokenStyle) {
    case TokenStyle.shirt:
      _paintShirt(canvas, e, kit, keeper);
    case TokenStyle.portrait:
      _paintPortrait(canvas, e, i, spot, kit, keeper, images);
    case TokenStyle.dot:
      _paintDot(canvas, e, kit, keeper);
  }

  if (spot.captain) {
    // The armband: a small badge at the token's shoulder.
    var c = Offset(-r * 0.78, -r * 0.78);
    canvas.drawCircle(c, r * 0.36, Paint()..color = const Color(0xFFF2C230));
    canvas.drawCircle(
        c,
        r * 0.36,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06
          ..color = const Color(0xFF1A1A1A));
    paintCentredGlyphs(
        canvas,
        "C",
        e.labelSpec.copyWith(
            fontSize: r * 0.42,
            color: const Color(0xFF1A1A1A),
            outlineWidth: 0),
        c);
  }

  _paintLabels(canvas, e, spot, kit, keeper);
  canvas.restore();
}

/// _kitPaint fills [shape] with the team's kit: its main colour and the
/// second laid out in its pattern -- or the keeper's colour, plain.
void _kitPaint(
    ui.Canvas canvas, Path shape, TeamElement e, Color kit, bool keeper) {
  var box = shape.getBounds();
  canvas.drawPath(shape, Paint()..color = kit);
  if (keeper || e.kitPattern == KitPattern.plain) return;
  canvas.save();
  canvas.clipPath(shape);
  var second = Paint()..color = e.secondaryColor;
  switch (e.kitPattern) {
    case KitPattern.stripes:
      var w = box.width / 5;
      for (var j = 1; j < 5; j += 2) {
        canvas.drawRect(
            Rect.fromLTWH(box.left + j * w, box.top, w, box.height), second);
      }
    case KitPattern.hoops:
      var h = box.height / 5;
      for (var j = 1; j < 5; j += 2) {
        canvas.drawRect(
            Rect.fromLTWH(box.left, box.top + j * h, box.width, h), second);
      }
    case KitPattern.halves:
      canvas.drawRect(
          Rect.fromLTRB(box.center.dx, box.top, box.right, box.bottom), second);
    case KitPattern.sash:
      var w = box.width * 0.24;
      canvas.drawPath(
          Path()
            ..moveTo(box.left, box.top + w)
            ..lineTo(box.left + w, box.top)
            ..lineTo(box.right, box.bottom - w)
            ..lineTo(box.right - w, box.bottom)
            ..close(),
          second);
    case KitPattern.quarters:
      canvas.drawRect(
          Rect.fromLTRB(box.center.dx, box.top, box.right, box.center.dy),
          second);
      canvas.drawRect(
          Rect.fromLTRB(box.left, box.center.dy, box.center.dx, box.bottom),
          second);
    case KitPattern.plain:
      break;
  }
  canvas.restore();
}

Paint _ring(TeamElement e, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeJoin = StrokeJoin.round
  ..color = e.outlineColor;

void _paintDot(ui.Canvas canvas, TeamElement e, Color kit, bool keeper) {
  var oval = Rect.fromCenter(
      center: Offset.zero, width: e.dotWidth, height: e.dotHeight);
  _kitPaint(canvas, Path()..addOval(oval), e, kit, keeper);
  if (e.ringWidth > 0 && e.outlineColor.a > 0) {
    canvas.drawOval(oval.deflate(e.ringWidth / 2), _ring(e, e.ringWidth));
  }
}

/// _shirtPath is a shirt the size of a player's token: body, sleeves and a
/// neck cut out of the top.
Path _shirtPath(double r) {
  var w = r, h = r;
  return Path()
    ..moveTo(-w * 0.32, -h * 0.92)
    ..quadraticBezierTo(0, -h * 0.62, w * 0.32, -h * 0.92)
    ..lineTo(w * 0.62, -h * 0.82)
    ..lineTo(w * 1.02, -h * 0.4)
    ..lineTo(w * 0.78, -h * 0.12)
    ..lineTo(w * 0.6, -h * 0.28)
    ..lineTo(w * 0.62, h * 0.95)
    ..lineTo(-w * 0.62, h * 0.95)
    ..lineTo(-w * 0.6, -h * 0.28)
    ..lineTo(-w * 0.78, -h * 0.12)
    ..lineTo(-w * 1.02, -h * 0.4)
    ..lineTo(-w * 0.62, -h * 0.82)
    ..close();
}

void _paintShirt(ui.Canvas canvas, TeamElement e, Color kit, bool keeper) {
  var r = e.dotRadius;
  var shirt = _shirtPath(r);
  _kitPaint(canvas, shirt, e, kit, keeper);
  // The collar and the cuffs, in the kit's second colour.
  var trim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.09
    ..strokeCap = StrokeCap.round
    ..color = keeper ? e.outlineColor : e.secondaryColor;
  canvas.drawPath(
      Path()
        ..moveTo(-r * 0.32, -r * 0.92)
        ..quadraticBezierTo(0, -r * 0.62, r * 0.32, -r * 0.92),
      trim);
  canvas.drawLine(Offset(r * 0.8, -r * 0.1), Offset(r * 1.0, -r * 0.37), trim);
  canvas.drawLine(
      Offset(-r * 0.8, -r * 0.1), Offset(-r * 1.0, -r * 0.37), trim);
  if (e.ringWidth > 0 && e.outlineColor.a > 0) {
    canvas.drawPath(shirt, _ring(e, e.ringWidth * 0.8));
  }
}

void _paintPortrait(ui.Canvas canvas, TeamElement e, int i, PlayerSpot spot,
    Color kit, bool keeper, CanvasImageSource? images) {
  var r = e.dotRadius;
  var circle = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
  var photo = spot.photo.isEmpty
      ? null
      : images?.resolve(spot.photo, const BackgroundRemoval());
  var squad = photo != null || e.teamPhoto.isEmpty
      ? null
      : images?.resolve(e.teamPhoto, const BackgroundRemoval());
  canvas.save();
  canvas.clipPath(circle);
  if (squad != null) {
    // Their part of the team photo: the circle their crop marks on it,
    // turned as it is turned, filling the token.
    var iw = squad.width.toDouble(), ih = squad.height.toDouble();
    var crop = e.cropOf(i, iw / ih);
    var radius = math.max(crop.size * iw, 1.0);
    canvas.save();
    canvas.scale(r / radius);
    canvas.rotate(-crop.turn * math.pi / 180);
    canvas.translate(-crop.x * iw, -crop.y * ih);
    canvas.drawImage(
        squad, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  } else if (photo != null) {
    // Cropped to fill the circle, the face in the upper part of it.
    var iw = photo.width.toDouble(), ih = photo.height.toDouble();
    var s = math.max(2 * r / iw, 2 * r / ih);
    var dst = Rect.fromCenter(
        center: Offset(0, (ih * s - 2 * r) * 0.25),
        width: iw * s,
        height: ih * s);
    canvas.drawImageRect(photo, Rect.fromLTWH(0, 0, iw, ih), dst,
        Paint()..filterQuality = FilterQuality.medium);
  } else if (e.faces) {
    _paintFace(canvas, r, _faceSeed(e, i, spot), kit,
        keeper ? e.outlineColor : e.secondaryColor);
  } else {
    _kitPaint(canvas, circle, e, kit, keeper);
  }
  canvas.restore();
  // A ring in the kit, so a portrait still reads as which side they are on.
  canvas.drawCircle(
      Offset.zero,
      r - math.max(e.ringWidth, r * 0.12) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(e.ringWidth, r * 0.12)
        ..color = kit);
  if (e.ringWidth > 0 && e.outlineColor.a > 0) {
    canvas.drawCircle(Offset.zero, r, _ring(e, math.max(1, e.ringWidth * 0.4)));
  }
}

int _faceSeed(TeamElement e, int i, PlayerSpot spot) {
  var h = 17;
  for (var c in "${spot.name}|${spot.number}|$i".codeUnits) {
    h = (h * 31 + c) & 0x3FFFFFFF;
  }
  return h;
}

const _skins = [
  Color(0xFFF6D3B3),
  Color(0xFFE8B98F),
  Color(0xFFD29B6C),
  Color(0xFFB07A4F),
  Color(0xFF8C5A36),
  Color(0xFF5E3A22),
];
const _hairs = [
  Color(0xFF1C1612),
  Color(0xFF3A2416),
  Color(0xFF6B4423),
  Color(0xFFC8A15A),
  Color(0xFF9C3D1C),
  Color(0xFF8E8A86),
];

/// _paintFace draws a face -- a drawn one, for a player with no photo: skin,
/// hair and its cut, the shoulders of a shirt in the kit. Each player's own,
/// from their name and number, so it stays theirs through every change.
void _paintFace(ui.Canvas canvas, double r, int seed, Color kit, Color trim) {
  double pick(int salt) => hash(seed, salt, 7);
  var skin = _skins[(pick(1) * _skins.length).floor() % _skins.length];
  var hair = _hairs[(pick(2) * _hairs.length).floor() % _hairs.length];
  var style = (pick(3) * 6).floor();
  var beard = pick(4) < 0.28;
  var shade = Color.lerp(skin, const Color(0xFF000000), 0.18)!;

  // The background behind them: the kit, paled.
  canvas.drawRect(Rect.fromCircle(center: Offset.zero, radius: r),
      Paint()..color = Color.lerp(kit, const Color(0xFFFFFFFF), 0.72)!);

  // Shoulders, in the shirt.
  canvas.drawPath(
      Path()
        ..moveTo(-r * 1.05, r * 1.1)
        ..quadraticBezierTo(-r * 0.95, r * 0.42, -r * 0.3, r * 0.38)
        ..lineTo(r * 0.3, r * 0.38)
        ..quadraticBezierTo(r * 0.95, r * 0.42, r * 1.05, r * 1.1)
        ..close(),
      Paint()..color = kit);
  // The neck, and the collar round it.
  canvas.drawRect(Rect.fromLTWH(-r * 0.17, r * 0.14, r * 0.34, r * 0.3),
      Paint()..color = shade);
  canvas.drawPath(
      Path()
        ..moveTo(-r * 0.28, r * 0.38)
        ..lineTo(0, r * 0.62)
        ..lineTo(r * 0.28, r * 0.38),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = trim);

  var head = Rect.fromCenter(
      center: Offset(0, -r * 0.14), width: r * 0.86, height: r * 1.04);
  // Long hair behind the head.
  if (style == 4) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(head.left - r * 0.08, head.top, head.right + r * 0.08,
                head.bottom + r * 0.1),
            Radius.circular(r * 0.4)),
        Paint()..color = hair);
  }
  // Ears, then the head over them.
  for (var sx in [-1.0, 1.0]) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(sx * r * 0.43, -r * 0.1),
            width: r * 0.16,
            height: r * 0.26),
        Paint()..color = shade);
  }
  canvas.drawOval(head, Paint()..color = skin);
  if (beard) {
    canvas.drawPath(
        Path()
          ..moveTo(head.left + r * 0.02, -r * 0.1)
          ..quadraticBezierTo(head.left + r * 0.05, head.bottom + r * 0.02, 0,
              head.bottom + r * 0.02)
          ..quadraticBezierTo(head.right - r * 0.05, head.bottom + r * 0.02,
              head.right - r * 0.02, -r * 0.1)
          ..quadraticBezierTo(0, r * 0.12, head.left + r * 0.02, -r * 0.1)
          ..close(),
        Paint()..color = hair.withValues(alpha: 0.85));
  }

  // The hair on top.
  var hairPaint = Paint()..color = hair;
  switch (style) {
    case 0: // short
      canvas.drawPath(
          Path()
            ..moveTo(head.left - r * 0.02, -r * 0.2)
            ..quadraticBezierTo(
                head.left, head.top - r * 0.1, 0, head.top - r * 0.06)
            ..quadraticBezierTo(
                head.right, head.top - r * 0.1, head.right + r * 0.02, -r * 0.2)
            ..quadraticBezierTo(
                r * 0.1, head.top + r * 0.18, head.left - r * 0.02, -r * 0.2)
            ..close(),
          hairPaint);
    case 1: // buzz
      canvas.drawArc(
          head.inflate(r * 0.01),
          math.pi * 1.08,
          math.pi * 0.84,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.1
            ..color = hair.withValues(alpha: 0.8));
    case 2: // curly
      for (var a = 0; a < 9; a++) {
        var t = math.pi * (1.05 + a / 8 * 0.9);
        canvas.drawCircle(
            head.center + Offset(math.cos(t) * r * 0.42, math.sin(t) * r * 0.5),
            r * 0.17,
            hairPaint);
      }
    case 3: // bald
      break;
    case 4: // long, its top
      canvas.drawPath(
          Path()
            ..moveTo(head.left - r * 0.04, -r * 0.05)
            ..quadraticBezierTo(
                head.left, head.top - r * 0.12, 0, head.top - r * 0.06)
            ..quadraticBezierTo(head.right, head.top - r * 0.12,
                head.right + r * 0.04, -r * 0.05)
            ..quadraticBezierTo(
                r * 0.2, head.top + r * 0.12, -r * 0.05, head.top + r * 0.2)
            ..quadraticBezierTo(
                head.left + r * 0.1, -r * 0.3, head.left - r * 0.04, -r * 0.05)
            ..close(),
          hairPaint);
    default: // swept
      canvas.drawPath(
          Path()
            ..moveTo(head.left - r * 0.02, -r * 0.25)
            ..quadraticBezierTo(head.left - r * 0.05, head.top - r * 0.16,
                r * 0.15, head.top - r * 0.1)
            ..quadraticBezierTo(head.right + r * 0.05, head.top,
                head.right + r * 0.02, -r * 0.28)
            ..quadraticBezierTo(
                r * 0.05, head.top + r * 0.1, head.left - r * 0.02, -r * 0.25)
            ..close(),
          hairPaint);
  }

  // Eyes, brows and a mouth.
  var ink = const Color(0xFF241A14);
  for (var sx in [-1.0, 1.0]) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(sx * r * 0.16, -r * 0.12),
            width: r * 0.09,
            height: r * 0.11),
        Paint()..color = ink);
    canvas.drawLine(
        Offset(sx * r * 0.09, -r * 0.25),
        Offset(sx * r * 0.25, -r * 0.27),
        Paint()
          ..strokeWidth = r * 0.05
          ..strokeCap = StrokeCap.round
          ..color = hair);
  }
  canvas.drawArc(
      Rect.fromCenter(
          center: Offset(0, r * 0.05), width: r * 0.26, height: r * 0.16),
      0.2,
      math.pi - 0.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(skin, ink, 0.55)!);
}

/// _paintLabels draws one player's number and name, about the token's
/// centre.
///
/// Both use the team's single [TeamElement.labelSpec] and turn together.
void _paintLabels(
    ui.Canvas canvas, TeamElement e, PlayerSpot spot, Color kit, bool keeper) {
  var r = e.dotRadius;
  var rotate = e.labelRotation * math.pi / 180;

  if (e.showNumbers && spot.number.isNotEmpty) {
    canvas.save();
    switch (e.tokenStyle) {
      case TokenStyle.portrait:
        // A badge at the token's foot, so the face is not covered.
        var c = Offset(r * 0.72, r * 0.72);
        canvas.drawCircle(c, r * 0.4, Paint()..color = e.playerColor);
        canvas.drawCircle(c, r * 0.4, _ring(e, math.max(1, r * 0.06)));
        canvas.translate(c.dx, c.dy);
        if (rotate != 0) canvas.rotate(rotate);
        paintCentredGlyphs(
            canvas,
            spot.number,
            e.labelSpec.copyWith(fontSize: e.labelSpec.fontSize * 0.62),
            Offset.zero);
      case TokenStyle.shirt:
        canvas.translate(0, r * 0.12);
        if (rotate != 0) canvas.rotate(rotate);
        paintCentredGlyphs(canvas, spot.number, e.labelSpec, Offset.zero);
      case TokenStyle.dot:
        // On a patterned dot, a disc of the kit's main colour behind the
        // number, so it is not lost in the stripes.
        if (!keeper && e.kitPattern != KitPattern.plain) {
          canvas.drawCircle(Offset.zero, r * 0.56, Paint()..color = kit);
        }
        if (rotate != 0) canvas.rotate(rotate);
        // Centred on the ink rather than on the line box -- see
        // paintCentredGlyphs.
        paintCentredGlyphs(canvas, spot.number, e.labelSpec, Offset.zero);
    }
    canvas.restore();
  }

  var name = e.labelOf(spot);
  if (!e.showNames || name.isEmpty || e.namePosition == LabelPosition.none) {
    return;
  }

  var spec = e.labelSpec;
  var text = spec.textCase.apply(name);
  var painter = layoutText(text, spec, maxWidth: math.max(40, r * 8));
  var plate = e.nameStyle == NameStyle.plate;
  var pad = plate ? Offset(r * 0.35, r * 0.12) : Offset.zero;
  // Placed from the token's edge, so a name stays the same distance from its
  // player whatever the token's size.
  var gapX = e.dotWidth / 2 + e.nameGap;
  var gapY = e.dotHeight / 2 + e.nameGap;
  var half = Offset(painter.width / 2, painter.height / 2) + pad;

  var at = switch (e.namePosition) {
    LabelPosition.above => Offset(0, -gapY - half.dy),
    LabelPosition.below => Offset(0, gapY + half.dy),
    LabelPosition.left => Offset(-gapX - half.dx, 0),
    LabelPosition.right => Offset(gapX + half.dx, 0),
    LabelPosition.none => Offset.zero,
  };

  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (rotate != 0) canvas.rotate(rotate);
  if (plate) {
    // A plate in the kit behind the name, as a broadcast caption has.
    var box = Rect.fromCenter(
        center: Offset.zero, width: half.dx * 2, height: half.dy * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(half.dy)),
        Paint()..color = e.playerColor.withValues(alpha: 0.92));
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(half.dy)),
        _ring(e, math.max(1, r * 0.05)));
  }
  var inner = Offset(painter.width / 2, painter.height / 2);
  // The type's shadow and glow, under the letters -- as the number has them.
  softFor(text, spec, maxWidth: math.max(40, r * 8), fillWidth: false)
      ?.paint(canvas, -inner);
  if (spec.outlineWidth > 0 && !plate) {
    layoutText(text, spec, maxWidth: math.max(40, r * 8), outline: true)
        .paint(canvas, -inner);
  }
  painter.paint(canvas, -inner);
  canvas.restore();
}

/// _paintBall draws the ball the sport is played with, rolling as it moves.
void _paintBall(ui.Canvas canvas, TeamElement e, PlayerSpot spot,
    PlayerPlace at, TeamGround? g, int frame) {
  var r = e.radiusOf(spot);
  var k = at.size;
  if (r <= 0) return;
  // On the ground under it: a shadow, which is most of what says where a
  // ball is when it is lifted off a pitch seen at an angle.
  var look = e.ballLook;
  var lifted = g != null && !g.place.flat;
  if (look.trail) _paintBallTrail(canvas, e, spot, at, g, frame, r);
  if (look.shadow) {
    canvas.drawOval(
        Rect.fromCenter(
            center: lifted
                ? at.ground
                : at.centre + Offset(r * k * 0.18, r * k * 0.28),
            width: r * k * 2,
            height: r * k * (lifted ? 0.7 : 1.6)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * k * 0.25));
  }

  // Rolled as far as it has travelled.
  var spin = 0.0;
  var track = spot.track;
  if (track != null && !track.isEmpty) {
    var pose = track.at(frame);
    spin = (pose.dx + pose.dy * 0.4) / r;
  }

  canvas.save();
  canvas.translate(at.centre.dx, at.centre.dy);
  canvas.scale(k);
  if (spot.highlight) {
    canvas.drawCircle(
        Offset.zero,
        r * 2.4,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, r * 2.4, [
            const Color(0xCCFFE066),
            const Color(0x00FFE066),
          ], [
            0.35,
            1
          ]));
  }
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.09
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF1A1A1A);
  var rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.07
    ..color = look.outline ? const Color(0xCC1A1A1A) : const Color(0x00000000);
  // A little light on it, from the top left like everything else.
  Paint lit(Color c) => Paint()
    ..shader = ui.Gradient.radial(Offset(-r * 0.35, -r * 0.4), r * 1.5, [
      Color.lerp(c, const Color(0xFFFFFFFF), 0.35)!,
      c,
      Color.lerp(c, const Color(0xFF000000), 0.35)!,
    ], [
      0,
      0.55,
      1
    ]);

  if (look.style != BallStyle.auto) {
    _paintDesignedBall(canvas, look, r, spin, lit, rim);
    canvas.restore();
    return;
  }
  switch (e.sport) {
    case TeamSport.basketball:
      canvas.drawCircle(Offset.zero, r, lit(const Color(0xFFE2702A)));
      canvas.save();
      canvas.rotate(spin);
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
      canvas.drawLine(Offset(0, -r), Offset(0, r), line);
      canvas.drawLine(Offset(-r, 0), Offset(r, 0), line);
      for (var sx in [-1.0, 1.0]) {
        canvas.drawArc(
            Rect.fromCircle(center: Offset(sx * r * 1.25, 0), radius: r * 0.95),
            sx < 0 ? -0.95 : math.pi - 0.95,
            1.9,
            false,
            line);
      }
      canvas.restore();
      canvas.drawCircle(Offset.zero, r, rim);
    case TeamSport.tennis:
      canvas.drawCircle(Offset.zero, r, lit(const Color(0xFFD7EC3A)));
      canvas.save();
      canvas.rotate(spin);
      var seam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = const Color(0xF2FFFFFF);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(-r * 1.15, 0), radius: r * 0.85),
          -0.9,
          1.8,
          false,
          seam);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(r * 1.15, 0), radius: r * 0.85),
          math.pi - 0.9,
          1.8,
          false,
          seam);
      canvas.restore();
      canvas.drawCircle(Offset.zero, r, rim..color = const Color(0x661A1A1A));
    case TeamSport.hockey:
      canvas.drawCircle(Offset.zero, r, lit(const Color(0xFFF4F4F2)));
      for (var a = 0; a < 7; a++) {
        var t = spin + a * math.pi * 2 / 7;
        canvas.drawCircle(Offset(math.cos(t), math.sin(t)) * r * 0.55, r * 0.1,
            Paint()..color = const Color(0x33000000));
      }
      canvas.drawCircle(
          Offset.zero, r * 0.1, Paint()..color = const Color(0x33000000));
      canvas.drawCircle(Offset.zero, r, rim);
    case TeamSport.iceHockey:
      // A puck: a black disc, a little light on its rim.
      canvas.drawCircle(
          Offset.zero, r, Paint()..color = const Color(0xFF111111));
      canvas.drawCircle(
          Offset.zero,
          r * 0.82,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.12
            ..color = const Color(0xFF3A3A3A));
      canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: r * 0.94),
          math.pi * 1.1,
          math.pi * 0.5,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.08
            ..color = const Color(0x88FFFFFF));
    case TeamSport.rugbyUnion:
    case TeamSport.rugbyLeague:
    case TeamSport.americanFootball:
      var gridiron = e.sport == TeamSport.americanFootball;
      var oval =
          Rect.fromCenter(center: Offset.zero, width: r * 2.2, height: r * 1.4);
      canvas.save();
      // Turned end over end as it travels, the way a kicked one goes.
      canvas.rotate(spin * 0.25);
      canvas.drawOval(oval,
          lit(gridiron ? const Color(0xFF7A3B1A) : const Color(0xFFF1EFEA)));
      canvas.save();
      canvas.clipPath(Path()..addOval(oval));
      if (gridiron) {
        // The white stripes near each end, and the laces.
        var stripe = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.14
          ..color = const Color(0xFFF2F2F2);
        for (var sx in [-1.0, 1.0]) {
          canvas.drawLine(
              Offset(sx * r * 0.72, -r), Offset(sx * r * 0.72, r), stripe);
        }
        var lace = Paint()
          ..strokeWidth = r * 0.08
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF7F7F7);
        canvas.drawLine(
            Offset(-r * 0.42, -r * 0.18), Offset(r * 0.42, -r * 0.18), lace);
        for (var j = -2; j <= 2; j++) {
          canvas.drawLine(Offset(j * r * 0.17, -r * 0.3),
              Offset(j * r * 0.17, -r * 0.06), lace);
        }
      } else {
        // A rugby ball's band of colour round its middle, and a seam.
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: r * 0.5, height: r * 2),
            Paint()..color = e.playerColor.withValues(alpha: 0.85));
        canvas.drawArc(
            Rect.fromCenter(
                center: Offset(0, r * 0.9), width: r * 2.4, height: r * 1.8),
            math.pi * 1.15,
            math.pi * 0.7,
            false,
            line..strokeWidth = r * 0.05);
      }
      canvas.restore();
      canvas.drawOval(oval, rim);
      canvas.restore();
    default:
      // A football: white, with a black panel in the middle and the edges of
      // the five round it, turned as it rolls.
      canvas.drawCircle(Offset.zero, r, lit(const Color(0xFFF7F7F7)));
      canvas.save();
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
      canvas.rotate(spin);
      var black = Paint()..color = const Color(0xFF161616);
      Path pentagon(Offset c, double size, double turn) => Path()
        ..addPolygon([
          for (var j = 0; j < 5; j++)
            c +
                Offset(math.cos(turn + j * math.pi * 2 / 5),
                        math.sin(turn + j * math.pi * 2 / 5)) *
                    size,
        ], true);
      canvas.drawPath(pentagon(Offset.zero, r * 0.36, -math.pi / 2), black);
      for (var j = 0; j < 5; j++) {
        var t = -math.pi / 2 + math.pi / 5 + j * math.pi * 2 / 5;
        canvas.drawPath(
            pentagon(Offset(math.cos(t), math.sin(t)) * r * 1.02, r * 0.36, t),
            black);
        canvas.drawLine(
            Offset(math.cos(t - math.pi / 5), math.sin(t - math.pi / 5)) *
                r *
                0.36,
            Offset(math.cos(t), math.sin(t)) * r * 0.7,
            Paint()
              ..strokeWidth = r * 0.05
              ..color = const Color(0xFF555555));
      }
      canvas.restore();
      canvas.drawCircle(Offset.zero, r, rim);
  }
  canvas.restore();
}

/// _paintBallTrail is where the ball has just been: fading, shrinking
/// copies of it along its path, behind it.
void _paintBallTrail(ui.Canvas canvas, TeamElement e, PlayerSpot spot,
    PlayerPlace at, TeamGround? g, int frame, double r) {
  var track = spot.track;
  if (track == null || track.keys.length < 2) return;
  const steps = 8;
  for (var k = steps; k >= 1; k--) {
    var then = playerPlace(g, e, spot, frame - k * 2);
    if ((then.centre - at.centre).distance < r * at.size * 0.3) continue;
    var fade = 1 - k / (steps + 1);
    canvas.drawCircle(
        then.centre,
        r * then.size * (0.45 + 0.5 * fade),
        Paint()
          ..color = e.ballLook.color.withValues(alpha: 0.35 * fade)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, r * then.size * 0.2));
  }
}

/// _paintDesignedBall is a ball in one of BallStyle's designs, in the ball's
/// own two colours, at the origin.
void _paintDesignedBall(ui.Canvas canvas, BallLook look, double r, double spin,
    Paint Function(Color) lit, Paint rim) {
  var ball = Rect.fromCircle(center: Offset.zero, radius: r);
  var main = look.color, second = look.second;
  canvas.drawCircle(Offset.zero, r, lit(main));
  canvas.save();
  canvas.clipPath(Path()..addOval(ball));
  canvas.rotate(spin);
  var ink = Paint()..color = second;
  switch (look.style) {
    case BallStyle.classic:
      // The 1970 ball: a black pentagon in the middle and the edges of the
      // five round it.
      Path pentagon(Offset c, double size, double turn) => Path()
        ..addPolygon([
          for (var j = 0; j < 5; j++)
            c +
                Offset(math.cos(turn + j * math.pi * 2 / 5),
                        math.sin(turn + j * math.pi * 2 / 5)) *
                    size,
        ], true);
      canvas.drawPath(pentagon(Offset.zero, r * 0.36, -math.pi / 2), ink);
      for (var j = 0; j < 5; j++) {
        var t = -math.pi / 2 + math.pi / 5 + j * math.pi * 2 / 5;
        canvas.drawPath(
            pentagon(Offset(math.cos(t), math.sin(t)) * r * 1.02, r * 0.36, t),
            ink);
      }
    case BallStyle.modern:
      // A modern match ball: a few long curved panels sweeping round it,
      // edged in the second colour.
      var edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round
        ..color = second;
      for (var j = 0; j < 3; j++) {
        canvas.save();
        canvas.rotate(j * math.pi * 2 / 3);
        var panel = Path()
          ..moveTo(0, 0)
          ..cubicTo(r * 0.5, -r * 0.2, r * 0.6, -r * 0.8, r * 0.15, -r * 1.1)
          ..cubicTo(-r * 0.2, -r * 0.7, -r * 0.1, -r * 0.3, 0, 0);
        canvas.drawPath(panel, Paint()..color = second.withValues(alpha: 0.85));
        canvas.drawPath(panel, edge);
        canvas.restore();
      }
      canvas.drawCircle(Offset.zero, r * 0.12, ink);
    case BallStyle.twoTone:
      canvas.drawRect(Rect.fromLTRB(-r, 0, r, r), ink);
      canvas.drawLine(
          Offset(-r, 0),
          Offset(r, 0),
          Paint()
            ..strokeWidth = r * 0.06
            ..color = Color.lerp(main, second, 0.5)!);
    case BallStyle.striped:
      for (var y = -r; y < r; y += r * 0.5) {
        canvas.drawRect(Rect.fromLTWH(-r, y, 2 * r, r * 0.22), ink);
      }
    case BallStyle.ring:
      canvas.drawCircle(
          Offset.zero,
          r * 0.62,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.22
            ..color = second);
    case BallStyle.plain:
    case BallStyle.auto:
      break;
  }
  canvas.restore();
  // The light again over the design, so the panels sit on a sphere.
  canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = ui.Gradient.radial(Offset(-r * 0.35, -r * 0.4), r * 1.5, [
          const Color(0x55FFFFFF),
          const Color(0x00FFFFFF),
          const Color(0x55000000),
        ], [
          0,
          0.5,
          1
        ]));
  canvas.drawCircle(Offset.zero, r, rim);
}
