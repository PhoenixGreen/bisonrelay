import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';

// character_guide.dart is the puppet laid over a sketched character to draw
// over: the construction an illustrator starts from -- the head as a ball
// with its middle line and the lines the eyes, nose and mouth sit on, the
// ribcage, the pelvis, the limbs with their joints, the hands and feet --
// drawn from the character's own rig, so it is where the character is on
// whichever panel it is seen from.
//
// Its handles change the character's proportions: the head's size, width
// and height, where the features sit, the shoulders, the hips, how long
// the arms and legs are. They are the Appearance sliders, taken hold of on
// the figure, so what is changed on one panel is changed on all of them --
// the proportions are the character's, not a panel's.
//
// A handle moves its slider by however far it moves the handle: each
// drag's step is measured from the rig, the slider nudged and the rig built
// again. Nothing here knows how a slider shapes the body, so nothing here
// goes wrong when that changes.

/// GuideHandle is one of the puppet's proportions taken hold of.
enum GuideHandle {
  headSize("Head size", null),
  headWidth("Head width", Look.headWidth),
  headHeight("Head height", Look.headHeight),
  eyeLine("Eye line", Look.eyeHeight),
  eyeSpacing("Eye spacing", Look.eyeSpacing),
  noseLine("Nose line", Look.noseHeight),
  mouthLine("Mouth line", Look.mouthHeight),
  neck("Neck length", Look.neckLength),
  shoulders("Shoulders", Look.shoulders),
  hips("Hips", Look.hips),
  armLength("Arm length", Look.armLength),
  legLength("Leg length", Look.legLength),
  hands("Hands", Look.hands);

  final String label;

  /// look is the slider the handle moves; null for the head's size, which
  /// is how many heads tall the character is.
  final Look? look;
  const GuideHandle(this.label, this.look);
}

/// _Head is the head's own space as the rig has it: its middle, turn and
/// size, and how far round it faces.
class _Head {
  final CharacterRig rig;
  _Head(this.rig);

  double get w => rig.headRadii.width;
  double get h => rig.headRadii.height;
  double get u => rig.unit;
  double get yaw => rig.yaw * math.pi / 180;

  Offset at(double x, double y) {
    var t = rig.headTurn * math.pi / 180;
    var s = rig.headScale;
    var c = math.cos(t), n = math.sin(t);
    return rig.headCentre + Offset((x * c - y * n) * s, (x * n + y * c) * s);
  }

  /// across is how far across the head a feature [phi] round it is seen.
  double across(double phi) => w * math.sin(phi - yaw);
  double toward(double phi) => math.cos(phi - yaw);

  // Where the sketch draws its features -- see character_painter.dart's
  // _face, _nose and _mouth.
  double get eyeY => u * 0.06 - rig.look[Look.eyeHeight] * u * 0.06;
  double get noseY => u * 0.12 - rig.look[Look.noseHeight] * u * 0.05;
  double get mouthY => u * 0.255 - rig.look[Look.mouthHeight] * u * 0.05;
  double get eyePhi => 0.42 * (1 + 0.22 * rig.look[Look.eyeSpacing]);

  /// nearEye is the side of the eye nearer the reader.
  double get nearEye => toward(eyePhi) >= toward(-eyePhi) ? 1 : -1;
}

/// _pageRight is whichever of [a] and [b] is further right on the page.
Offset _pageRight(Offset a, Offset b) => a.dx >= b.dx ? a : b;

/// guidePoint is where [handle] is, in the character's own drawing space.
Offset guidePoint(CharacterRig rig, GuideHandle handle) {
  var head = _Head(rig);
  return switch (handle) {
    GuideHandle.headSize => head.at(head.w * 0.72, -head.h * 0.72),
    GuideHandle.headWidth => head.at(head.w, 0),
    GuideHandle.headHeight => head.at(0, -head.h),
    GuideHandle.eyeLine => head.at(head.across(0), head.eyeY),
    GuideHandle.eyeSpacing =>
      head.at(head.across(head.nearEye * head.eyePhi), head.eyeY),
    GuideHandle.noseLine => head.at(head.across(0), head.noseY),
    GuideHandle.mouthLine => head.at(head.across(0), head.mouthY),
    // Low on the neck: the head stays on top, and a longer neck takes the
    // shoulders down. Clear of the chest's pin.
    GuideHandle.neck => Offset.lerp(rig.chest, rig.neck, 0.4)!,
    GuideHandle.shoulders => _pageRight(rig.shoulderL, rig.shoulderR),
    GuideHandle.hips => _pageRight(rig.hipL, rig.hipR),
    GuideHandle.armLength => _pageRight(rig.elbowL, rig.elbowR),
    GuideHandle.legLength => _pageRight(rig.kneeL, rig.kneeR),
    GuideHandle.hands => () {
        var right = rig.wristL.dx >= rig.wristR.dx;
        var wrist = right ? rig.wristL : rig.wristR;
        var elbow = right ? rig.elbowL : rig.elbowR;
        var d = wrist - elbow;
        var l = d.distance;
        return wrist +
            (l == 0 ? const Offset(0, 1) : d / l) * rig.handRadius * 2;
      }(),
  };
}

/// guideValue is [handle]'s setting on [e].
double guideValue(CharacterElement e, GuideHandle handle) =>
    handle.look == null ? e.dna.headsTall : e.dna.look[handle.look!];

/// withGuide is [e] with [handle]'s setting [v], kept within its range.
CharacterElement withGuide(CharacterElement e, GuideHandle handle, double v) {
  var look = handle.look;
  if (look == null) {
    return e.copyWith(
        dna: e.dna.copyWith(
            headsTall: v.clamp(CharacterDna.minHeads, CharacterDna.maxHeads)));
  }
  return e.copyWith(dna: e.dna.copyWith(look: e.dna.look.withValue(look, v)));
}

/// guided is [e] -- as it was when [handle] was taken hold of at [from], a
/// point on the page -- with the handle dragged to [to]: its setting moved
/// as far as takes the handle there, as near as it can go.
CharacterElement guided(
    CharacterElement e, GuideHandle handle, Offset from, Offset to, int frame,
    {int frameRate = 12, CanvasDocument? document}) {
  CharacterPlacement place(CharacterElement c) =>
      CharacterPlacement.of(c, frame, frameRate: frameRate, document: document);
  var start = place(e);
  var wanted =
      guidePoint(start.rig, handle) + (start.toLocal(to) - start.toLocal(from));
  var step = handle.look == null ? 0.1 : 0.05;
  var next = e;
  // Two steps of Newton's: the second takes up what bends.
  for (var i = 0; i < 2; i++) {
    var v = guideValue(next, handle);
    var p0 = guidePoint(place(next).rig, handle);
    var p1 = guidePoint(place(withGuide(next, handle, v + step)).rig, handle);
    var d = (p1 - p0) / step;
    var d2 = d.dx * d.dx + d.dy * d.dy;
    if (d2 < 1e-9) break;
    var miss = wanted - p0;
    next = withGuide(next, handle, v + (miss.dx * d.dx + miss.dy * d.dy) / d2);
  }
  return next;
}

/// guideUnder is the handle within [reach] of [page], nearest first.
GuideHandle? guideUnder(CharacterPlacement placed, Offset page, double reach) {
  GuideHandle? best;
  var nearest = reach;
  for (var h in GuideHandle.values) {
    var d = (placed.toPage(guidePoint(placed.rig, h)) - page).distance;
    if (d <= nearest) {
      nearest = d;
      best = h;
    }
  }
  return best;
}

/// guideColour is the puppet's colour: apart from the pins' blue, so the
/// two are not taken for one another.
const Color guideColour = Color(0xFFE0569B);

/// paintGuide draws the puppet of [placed] -- [at] takes a point on the
/// page to the screen -- with its handles where [handles].
void paintGuide(
    Canvas canvas, CharacterPlacement placed, Offset Function(Offset) at,
    {bool handles = true, GuideHandle? held}) {
  var rig = placed.rig;
  Offset p(Offset local) => at(placed.toPage(local));
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = guideColour.withValues(alpha: 0.75);
  var faint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = guideColour.withValues(alpha: 0.4);

  void poly(List<Offset> pts, Paint paint, {bool closed = false}) {
    if (pts.length < 2) return;
    canvas.drawPath(
        Path()..addPolygon([for (var q in pts) p(q)], closed), paint);
  }

  /// oval round [centre], [rx] across [dir] and [ry] along it.
  List<Offset> oval(Offset centre, Offset dir, double rx, double ry) {
    var l = dir.distance;
    var a = l == 0 ? const Offset(0, 1) : dir / l;
    var b = Offset(-a.dy, a.dx);
    return [
      for (var i = 0; i < 32; i++)
        centre +
            b * (rx * math.cos(i * math.pi / 16)) +
            a * (ry * math.sin(i * math.pi / 16)),
    ];
  }

  // The head: a ball, the line down the middle of the face, and the lines
  // the features sit on, as far round as can be seen.
  var head = _Head(rig);
  poly([
    for (var i = 0; i < 40; i++)
      head.at(head.w * math.cos(i * math.pi / 20),
          head.h * math.sin(i * math.pi / 20))
  ], line, closed: true);
  if (head.toward(0) > 0.05) {
    poly([
      for (var i = -10; i <= 10; i++)
        head.at(head.across(0) * math.cos(i * math.pi / 20),
            head.h * math.sin(i * math.pi / 20)),
    ], faint);
  }
  for (var y in [head.eyeY, head.noseY, head.mouthY]) {
    var half = head.w * math.sqrt(math.max(0, 1 - (y / head.h) * (y / head.h)));
    // From one side of the face to the other, round the front.
    poly([
      for (var phi = -math.pi / 2;
          phi <= math.pi / 2 + 1e-6;
          phi += math.pi / 16)
        if (head.toward(phi) > 0) head.at(half / head.w * head.across(phi), y),
    ], faint);
  }
  for (var side in [-1.0, 1.0]) {
    var phi = side * head.eyePhi;
    var t = head.toward(phi);
    if (t < 0.12) continue;
    poly(
        oval(head.at(head.across(phi), head.eyeY), const Offset(0, 1),
            rig.unit * 0.085 * t, rig.unit * 0.06),
        line,
        closed: true);
  }

  // The neck, the ribcage and the pelvis.
  poly([rig.neck, head.at(0, head.h * 0.8)], line);
  var down = rig.hips - rig.chest;
  var shoulders = (rig.shoulderL - rig.shoulderR).distance;
  poly(
      oval(rig.chest + down * 0.28, down,
          math.max(shoulders * 0.42, rig.unit * 0.25), down.distance * 0.5),
      line,
      closed: true);
  var hipWidth = (rig.hipL - rig.hipR).distance;
  poly(
      oval(rig.hips + down * 0.05, down,
          math.max(hipWidth * 0.85, rig.unit * 0.3), rig.unit * 0.32),
      line,
      closed: true);
  poly([rig.shoulderL, rig.shoulderR], faint);
  poly([rig.hipL, rig.hipR], faint);

  // The limbs, their joints, the hands and the feet.
  for (var limb in CharacterLimb.values) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    poly([a, b, c], line);
    var r = (limb.isArm ? rig.limbWidth : rig.legWidth) * 0.42;
    for (var j in [a, b, c]) {
      poly(oval(j, const Offset(0, 1), r, r), faint, closed: true);
    }
    if (limb.isArm) {
      var d = c - b;
      var l = d.distance;
      var dir = l == 0 ? const Offset(0, 1) : d / l;
      poly(
          oval(c + dir * rig.handRadius, dir, rig.handRadius * 0.8,
              rig.handRadius),
          line,
          closed: true);
    } else {
      var f = rig.legWidth;
      poly(oval(c + Offset(0, f * 0.45), const Offset(1, 0), f * 0.35, f * 0.8),
          line,
          closed: true);
    }
  }

  if (!handles) return;
  var fill = Paint()..color = guideColour;
  var knob = Paint()..color = const Color(0xFFFFFFFF);
  for (var h in GuideHandle.values) {
    var c = p(guidePoint(rig, h));
    var size = h == held ? 6.5 : 5.0;
    // Diamonds, where the pins are round.
    var d = Path()
      ..moveTo(c.dx, c.dy - size)
      ..lineTo(c.dx + size, c.dy)
      ..lineTo(c.dx, c.dy + size)
      ..lineTo(c.dx - size, c.dy)
      ..close();
    canvas.drawPath(d, h == held ? fill : knob);
    canvas.drawPath(
        d,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = guideColour);
  }
}
