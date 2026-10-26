import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';

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
/// [staged] is where it stands on a 3D stage, when it does: its box is the
/// camera's, it is turned as the camera sees it, and lit by the stage.
void paintCharacter(Canvas canvas, Rect box, CharacterElement e, int frame,
    {int frameRate = 12,
    bool editing = false,
    Staging? staged,
    CanvasImageSource? images}) {
  // A style on twos holds each drawing for two frames, as stop motion does.
  frame = e.style.frameOf(frame);
  var life = lifeAt(e, frame, frameRate);
  var (pose, face) = e.performanceAt(frame, frameRate);
  if (staged != null) {
    pose = pose
        .withTurn(pose.turn + staged.turn)
        .withTilt((pose.tilt + staged.tilt).clamp(-85.0, 85.0));
    if (staged.shadow case var shadow?) {
      canvas.drawPath(shadow, _shadowPaint(e.shadow, box.height));
    }
  } else {
    box = characterBox(e, frame, box);
    if (e.shadow != CharacterShadow.none) {
      // A contact shadow on the ground under the feet, smaller and fainter
      // the higher it jumps.
      var up = 1 / (1 + pose.lift.abs() * 0.8);
      canvas.drawOval(
          Rect.fromCenter(
              center: box.bottomCenter,
              width: box.width * 0.8 * up,
              height: box.height * 0.05 * up),
          _shadowPaint(e.shadow, box.height, strength: up));
    }
  }
  var light = staged == null ? null : lightFilter(staged.light);
  if (light != null) {
    canvas.saveLayer(box.inflate(box.height), Paint()..colorFilter = light);
  }
  paintCharacterFigure(canvas, box, e.dna, pose,
      face: face,
      life: life,
      bare: editing && e.bareView,
      style: e.style,
      body: e.body,
      images: images);
  if (light != null) canvas.restore();
}

Paint _shadowPaint(CharacterShadow kind, double size, {double strength = 1}) {
  var p = Paint()
    ..color = const Color(0xFF000000)
        .withValues(alpha: (kind == CharacterShadow.hard ? 0.32 : 0.24) * strength);
  if (kind == CharacterShadow.soft) {
    p.maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.5, size * 0.012));
  }
  return p;
}

/// characterBox is where [e] is drawn in its own [box] on [frame]: as it
/// is, or -- with depth -- nearer and bigger for having moved down the
/// page, further and smaller for having moved up it, about its feet.
Rect characterBox(CharacterElement e, int frame, Rect box) {
  if (e.depth == 0) return box;
  var dy = e.poseAt(frame).dy;
  var f = (1 + e.depth * dy / math.max(1.0, e.height)).clamp(0.25, 4.0);
  if (f == 1) return box;
  return Rect.fromLTWH(box.center.dx - box.width * f / 2,
      box.bottom - box.height * f, box.width * f, box.height * f);
}

/// paintCharacterFigure draws [dna] in [pose], filling the height of [box].
/// What the settings panel's tiles draw, with no element behind them.
void paintCharacterFigure(
    Canvas canvas, Rect box, CharacterDna dna, CharacterPose pose,
    {CharacterFace face = CharacterFace.rest,
    LifeAt life = LifeAt.none,
    bool bare = false,
    CharacterStyle style = CharacterStyle.featureCartoon,
    CharacterBody body = const CharacterBody(),
    CanvasImageSource? images}) {
  if (box.height <= 0) return;
  dna = style.dnaOf(dna);
  var rig = CharacterRig.of(dna, pose, box, breath: life.breath);
  var look = _Look.of(style);
  void draw(Canvas onto) => body.inThreeD
      ? _paintInThreeD(onto, rig, dna, pose, face, life, body, box, images)
      : _Drawing(onto, rig, dna, face, life,
              bare: bare, look: look, images: images)
          .draw();
  // The room the figure is drawn in, arms out and hat on included.
  var room = box.inflate(box.height * 0.35);
  switch (style) {
    case CharacterStyle.noir:
      // A silhouette, lit from behind on one side: the figure in light,
      // moved a little towards the light, and the figure in near-black
      // over it.
      var unit = box.height / dna.headsTall;
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0xFFF2EEE4), BlendMode.srcIn));
      canvas.translate(-unit * 0.07, -unit * 0.045);
      draw(canvas);
      canvas.restore();
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0xFF141414), BlendMode.srcIn));
      draw(canvas);
      canvas.restore();
    case CharacterStyle.paperCutout:
      // Pieces of paper laid on the page cast a shadow on it.
      var unit = box.height / dna.headsTall;
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0x55000000), BlendMode.srcIn));
      canvas.translate(unit * 0.05, unit * 0.06);
      draw(canvas);
      canvas.restore();
      draw(canvas);
    case CharacterStyle.manga:
      canvas.saveLayer(room, Paint()..colorFilter = _greyscale);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.storybook:
      canvas.saveLayer(room, Paint()..colorFilter = _wash);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.pixel:
      // Drawn at a small size and scaled up without smoothing: every pixel
      // of the small drawing a square block.
      var block = math.max(2.0, box.height / 90);
      var w = (room.width / block).ceil(), h = (room.height / block).ceil();
      var recorder = PictureRecorder();
      var small = Canvas(recorder)
        ..scale(1 / block)
        ..translate(-room.left, -room.top);
      draw(small);
      var image = recorder.endRecording().toImageSync(math.max(1, w), math.max(1, h));
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Rect.fromLTWH(room.left, room.top, w * block, h * block),
          Paint()..filterQuality = FilterQuality.none);
      image.dispose();
    default:
      draw(canvas);
  }
}

/// _paintInThreeD draws [dna] as a body in 3D: the model [body] names when
/// it is loaded, and the mannequin until it is -- or when it is the
/// mannequin that is asked for.
void _paintInThreeD(Canvas canvas, CharacterRig rig, CharacterDna dna,
    CharacterPose pose, CharacterFace face, LifeAt life, CharacterBody body,
    Rect box, CanvasImageSource? images) {
  // Blinking and glancing about, as the drawn face does.
  face = face.withControls({
    if (life.blink > 0)
      FaceControl.eyesOpen: face[FaceControl.eyesOpen] * (1 - life.blink),
    if (life.lookX != 0)
      FaceControl.lookX: face[FaceControl.lookX] + life.lookX,
    if (life.lookY != 0)
      FaceControl.lookY: face[FaceControl.lookY] + life.lookY,
  });
  var model = body.kind == BodyKind.model && body.modelId.isNotEmpty
      ? switch (images) {
          CanvasModelSource source => source.resolveModel(body.modelId),
          _ => null,
        }
      : null;
  var outline = body.outline ? math.max(1.0, box.height * 0.006) : 0.0;
  if (model != null) {
    var (origin, pieces) =
        model.pieces(rig, face, box, lift: pose.lift * rig.unit);
    paintMeshes(canvas, origin, pieces,
        shading: body.shading, outline: outline);
    return;
  }
  paintMeshes(canvas, rig.hips, mannequinPieces(rig, dna, face),
      shading: body.shading, outline: outline);
}

/// _greyscale takes the colour out, leaving how light each thing is, a
/// little harder: ink on paper.
const ColorFilter _greyscale = ColorFilter.matrix([
  0.36, 0.71, 0.12, 0, -20, //
  0.36, 0.71, 0.12, 0, -20, //
  0.36, 0.71, 0.12, 0, -20, //
  0, 0, 0, 1, 0,
]);

/// _wash is colour softened and lightened, as watercolour on paper is.
const ColorFilter _wash = ColorFilter.matrix([
  0.72, 0.18, 0.05, 0, 30, //
  0.1, 0.78, 0.07, 0, 30, //
  0.1, 0.15, 0.7, 0, 28, //
  0, 0, 0, 1, 0,
]);

/// _Shading is how a style shades a shape: not at all, with a band of
/// shadow, or with the shadow printed as dots.
enum _Shading { flat, cel, halftone, screentone }

enum _Eyes { round, anime, pie }

/// _Look is how a style draws: its line, its shading, its eyes, its limbs.
class _Look {
  /// line is how thick the outline is, against the usual; nought is none.
  final double line;

  /// ink is the outline's colour, or null for a shade of what it goes
  /// round.
  final Color? ink;
  final _Shading shading;
  final _Eyes eyes;

  /// limbs is how thick arms and legs are, against the usual.
  final double limbs;

  /// hose is limbs drawn as one bending curve each, with no elbow or knee.
  final bool hose;

  /// gloves is white cartoon gloves on the hands.
  final bool gloves;

  const _Look(
      {this.line = 1,
      this.ink,
      this.shading = _Shading.flat,
      this.eyes = _Eyes.round,
      this.limbs = 1,
      this.hose = false,
      this.gloves = false});

  static const _black = Color(0xFF151515);

  static _Look of(CharacterStyle style) => switch (style) {
        CharacterStyle.featureCartoon => const _Look(),
        CharacterStyle.anime =>
          const _Look(line: 0.8, shading: _Shading.cel, eyes: _Eyes.anime),
        CharacterStyle.manga => const _Look(
            line: 1.3,
            ink: _black,
            shading: _Shading.screentone,
            eyes: _Eyes.anime),
        CharacterStyle.chibi =>
          const _Look(shading: _Shading.cel, eyes: _Eyes.anime),
        CharacterStyle.tvFlat => const _Look(line: 2.2, ink: _black),
        CharacterStyle.rubberHose => const _Look(
            line: 2,
            ink: _black,
            eyes: _Eyes.pie,
            limbs: 0.5,
            hose: true,
            gloves: true),
        CharacterStyle.comic => const _Look(
            line: 1.8, ink: _black, shading: _Shading.halftone),
        CharacterStyle.storybook =>
          const _Look(line: 0.7, ink: Color(0xFF6B5B4B)),
        CharacterStyle.clay => const _Look(line: 0, shading: _Shading.cel),
        CharacterStyle.paperCutout => const _Look(line: 0.5),
        CharacterStyle.pixel => const _Look(line: 1.2, ink: _black),
        CharacterStyle.noir => const _Look(line: 0),
      };
}

class _Drawing {
  final Canvas canvas;
  final CharacterRig rig;
  final CharacterDna dna;
  final CharacterFace face;
  final LifeAt life;

  /// bare is the body without its clothes -- the editor's bare view.
  final bool bare;

  final _Look look;

  /// images is where a garment's picture print comes from.
  final CanvasImageSource? images;

  _Drawing(this.canvas, this.rig, this.dna, this.face, this.life,
      {this.bare = false, this.look = const _Look(), this.images});

  double get u => rig.unit;

  /// edge is how thick every outline is.
  double get edge => math.max(0.6, u * 0.022) * look.line;

  /// lined is whether outlines are drawn at all.
  bool get lined => look.line > 0;

  /// armWidth and legWidth are how thick the limbs are drawn, in this style.
  double get armWidth => rig.limbWidth * look.limbs;
  double get legWidth => rig.legWidth * look.limbs;

  /// _inkFor is the outline round [colour].
  Color _inkFor(Color colour) => look.ink ?? _shade(colour);

  /// _solid draws something in [colour] by way of [draw], shaded as the
  /// style shades: a shadow on the side away from the light, which is above
  /// and to the left -- a band of darker colour, or dots.
  void _solid(Rect bounds, Color colour, void Function(Paint) draw) {
    var base = Paint()..color = colour;
    if (look.shading == _Shading.flat) {
      draw(base);
      return;
    }
    var room = bounds.inflate(u * 0.3);
    canvas.saveLayer(room, Paint());
    draw(base);
    var shadow = Color.lerp(colour, const Color(0xFF000000), 0.24)!;
    switch (look.shading) {
      case _Shading.cel:
        canvas.drawRect(room,
            Paint()
              ..color = shadow
              ..blendMode = BlendMode.srcATop);
      case _Shading.halftone || _Shading.screentone:
        var tone = look.shading == _Shading.screentone;
        var dot = Paint()
          ..color = tone ? const Color(0x99000000) : const Color(0xCC151515)
          ..blendMode = BlendMode.srcATop;
        var step = u * (tone ? 0.045 : 0.07);
        var r = step * (tone ? 0.22 : 0.3);
        var row = 0;
        for (var y = room.top; y < room.bottom; y += step, row++) {
          for (var x = room.left + (row.isOdd ? step / 2 : 0);
              x < room.right;
              x += step) {
            canvas.drawCircle(Offset(x, y), r, dot);
          }
        }
      case _Shading.flat:
        break;
    }
    // The lit part: the same thing again, moved towards the light, in its
    // own colour -- what is left showing of the shadow is a crescent on the
    // far side.
    canvas.save();
    var d = u * 0.07;
    canvas.translate(-d, -d * 0.6);
    draw(Paint()
      ..color = colour
      ..blendMode = BlendMode.srcATop);
    canvas.restore();
    canvas.restore();
  }

  /// _outline edges [path] as the style edges things.
  void _outline(Path path, Color colour) {
    if (!lined) return;
    canvas.drawPath(path, _edgePaint(colour));
  }

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
    // A tail and wings grow from the back: behind the body, until the body
    // turns away from the reader.
    if (bodyFacing >= -0.2) {
      _wings();
      _tail();
    }
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
    if (bodyFacing < -0.2) {
      _capes();
      _wings();
      _tail();
    }
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
    if (dna.species.legless) return;
    // The far leg first, so the near one crosses in front of it.
    var legs = [CharacterLimb.legL, CharacterLimb.legR]
      ..sort((a, b) => rig.depths[a]!.compareTo(rig.depths[b]!));
    var seated = <(int, Garment)>[];
    for (var limb in legs) {
      if (dna.species == Species.bird) {
        // Thin legs and three toes, in the beak's colour.
        _stroke(_along(limb, 0.45, 1), legWidth * 0.32, dna.fur2);
        _toes(limb);
        continue;
      }
      _stroke(_along(limb, 0, 1), legWidth, dna.skin);
      _foot(limb, dna.skin, bareFoot: true);
      for (var (i, g) in _wearing((g) => g.kind.coversLegs)) {
        var from = g.kind.from, to = math.max(from + 0.02, g.lengthOr);
        _cloth(null, g, i,
            line: _along(limb, from, math.min(1, to)),
            width: legWidth * 1.12 * g.fitOr,
            part: limb.index,
            hem: true);
        if (g.kind == GarmentKind.socks) _foot(limb, g.color);
        if (from == 0 && !dna.fourLegs && !seated.any((s) => s.$1 == i)) {
          seated.add((i, g));
        }
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
    // Nothing hangs from the waist of a body carried level.
    if (dna.fourLegs || dna.species.legless) return;
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
          width: legWidth * 1.2,
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
          _outline(shoe, colour);
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
    if (dna.species.legless) {
      _fishBody();
      return;
    }
    if (dna.species == Species.bird && !dna.fourLegs) {
      // A round body, lighter down the front.
      var egg = Path()
        ..addOval(Rect.fromCenter(
            center: Offset.lerp(rig.chest, rig.hips, 0.55)!,
            width: rig.shoulderHalf * 2.3,
            height: (rig.hips - rig.chest).distance * 1.5));
      _fill(egg, dna.skin);
      canvas.save();
      canvas.clipPath(egg);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.lerp(rig.chest, rig.hips, 0.65)! +
                  Offset(-math.sin(rig.yaw * math.pi / 180) * rig.shoulderHalf * 0.4, 0),
              width: rig.shoulderHalf * 1.3 * (0.4 + 0.6 * bodyFacing.abs()),
              height: (rig.hips - rig.chest).distance * 1.1),
          Paint()..color = Color.lerp(dna.skin, const Color(0xFFFFFFFF), 0.55)!);
      canvas.restore();
      return;
    }
    if (dna.fourLegs) {
      // A body carried level: a thick band from the hips to the shoulders,
      // with the lighter fur of the belly along its underside.
      var thick = rig.hipHalf * 2.1;
      _stroke([rig.hips, rig.chest], thick, dna.skin);
      // A top on a body carried level is a coat along it, from the
      // shoulders back as far as it is long.
      for (var (i, g) in _wearing((g) =>
          g.kind.shape == GarmentShape.torso ||
          g.kind.shape == GarmentShape.dress ||
          g.kind.shape == GarmentShape.cape)) {
        var back = Offset.lerp(rig.chest, rig.hips, math.min(1, g.lengthOr))!;
        _cloth(null, g, i,
            line: [rig.chest, back], width: thick * 1.06 * g.fitOr, part: 30);
      }
      if (bodyFacing.abs() < 0.8 && garments.every((g) => g.kind.shape != GarmentShape.torso)) {
        var belly = Offset(0, thick * 0.22);
        canvas.save();
        canvas.clipPath(_capsule([rig.hips, rig.chest], thick));
        _stroke([rig.hips + belly * 1.6, rig.chest + belly * 1.6], thick * 0.5,
            dna.fur2);
        canvas.restore();
      }
    } else {
      _fill(_torsoPath(), dna.skin);
    }
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
      // A shape of the garment's own, laid on over it.
      if (g.outline.length >= 3) _cloth(_outlinePath(g.outline), g, i, part: 32);
    }
  }

  /// _outlinePath is a garment's own outline -- see Garment.outline -- on
  /// the body as it stands and turns: a smooth curve through its points.
  Path _outlinePath(List<Offset> points) {
    var (across, _, half, low) = _torsoFrame;
    Offset at(Offset p) {
      var width = half + (low - half) * p.dy.clamp(0.0, 1.0);
      return Offset.lerp(rig.chest, rig.hips, p.dy)! + across * (width * p.dx);
    }

    var pts = [for (var p in points) at(p)];
    var path = Path();
    Offset mid(int k) =>
        Offset.lerp(pts[k % pts.length], pts[(k + 1) % pts.length], 0.5)!;
    path.moveTo(mid(0).dx, mid(0).dy);
    for (var k = 1; k <= pts.length; k++) {
      var c = pts[k % pts.length], m = mid(k);
      path.quadraticBezierTo(c.dx, c.dy, m.dx, m.dy);
    }
    return path..close();
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
    var collar = dna.fourLegs
        ? Offset.lerp(rig.neck, rig.chest, 0.4)!
        : rig.chest + up * (u * 0.02);
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
      if (dna.species == Species.bird) {
        _birdWing(shoulder, elbow, wrist, limb.onLeft ? -1 : 1);
        continue;
      }
      if (dna.species.legless) {
        _fin(shoulder, elbow);
        continue;
      }
      _stroke([shoulder, elbow, wrist], armWidth, dna.skin);
      if (dna.fourLegs) {
        // Front legs: whatever is worn on the legs is worn on these too.
        for (var (i, g) in _wearing((g) => g.kind.coversLegs)) {
          var from = g.kind.from, to = math.max(from + 0.02, g.lengthOr);
          _cloth(null, g, i,
              line: _along(limb, from, math.min(1, to)),
              width: armWidth * 1.12 * g.fitOr,
              part: 70 + limb.index,
              hem: true);
        }
      }
      var forward = wrist - elbow;
      var hand = wrist +
          (forward.distance == 0
              ? Offset.zero
              : forward / forward.distance * rig.handRadius * 0.5);
      if (look.gloves) {
        // A white cartoon glove, a size up, with a cuff.
        var cuff = wrist - (forward.distance == 0
            ? Offset.zero
            : forward / forward.distance * rig.handRadius * 0.2);
        _fill(Path()..addOval(Rect.fromCircle(center: hand, radius: rig.handRadius * 1.35)),
            const Color(0xFFFAFAFA));
        _fill(Path()..addOval(Rect.fromCircle(center: cuff, radius: rig.handRadius * 0.75)),
            const Color(0xFFFAFAFA));
      } else {
        _fill(Path()..addOval(Rect.fromCircle(center: hand, radius: rig.handRadius)),
            dna.skin);
      }
      for (var (i, g) in _wearing((g) => g.kind.hasSleeves)) {
        var sleeve = g.sleeveOr;
        if (sleeve <= 0) continue;
        _cloth(null, g, i,
            line: _along(limb, 0, math.min(0.97, sleeve)),
            width: armWidth * 1.14 * g.fitOr,
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
    if (look.hose && points.length == 3) {
      // A rubber hose limb bends all the way along, with no joint in it.
      var through = points[1] * 2 - (points[0] + points[2]) / 2;
      path.quadraticBezierTo(through.dx, through.dy, points[2].dx, points[2].dy);
    } else {
      for (var p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }
    Paint stroke() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (lined) {
      canvas.drawPath(
          path,
          stroke()
            ..strokeWidth = width + edge * 2
            ..color = _inkFor(colour));
    }
    var bounds = path.getBounds().inflate(width);
    _solid(bounds, colour, (p) {
      canvas.drawPath(
          path,
          stroke()
            ..strokeWidth = width
            ..color = p.color
            ..blendMode = p.blendMode);
    });
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
      _solid(bounds, colour, (p) => canvas.drawPath(shape, p));
    } else {
      _stroke(line!, width, colour);
    }
    canvas.save();
    canvas.clipPath(area);
    _pattern(bounds, g, seed, part);
    _wear(area, bounds, g, colour, seed);
    canvas.restore();
    if (shape != null) _outline(shape, colour);
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
  void _pattern(Rect bounds, Garment g, int seed, [int part = 0]) {
    var ink = Paint()..color = g.color2.withValues(alpha: 0.85);
    var step = u * 0.1;
    switch (g.pattern) {
      case GarmentPattern.plain:
        return;
      case GarmentPattern.print:
        // On the front of the body only -- not down each sleeve -- and not
        // from behind.
        if (part != 30 && part != 31) return;
        if (bodyFacing < 0.2 || g.printId.isEmpty) return;
        var picture = images?.resolve(g.printId, const BackgroundRemoval());
        if (picture == null) return;
        var w = bounds.width * g.printSize * bodyFacing;
        var h = w * picture.height / math.max(1, picture.width);
        var centre = Offset(bounds.center.dx, bounds.top + bounds.height * 0.4);
        canvas.drawImageRect(
            picture,
            Rect.fromLTWH(
                0, 0, picture.width.toDouble(), picture.height.toDouble()),
            Rect.fromCenter(center: centre, width: w, height: h),
            Paint()..filterQuality = FilterQuality.medium);
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
    ..color = _inkFor(colour);

  /// _inHead draws [what] in the head's own space: the middle of the head
  /// at the origin, tilted with it.
  void _inHead(void Function() what) {
    canvas.save();
    canvas.translate(rig.headCentre.dx, rig.headCentre.dy);
    canvas.rotate(rig.headTurn * math.pi / 180);
    // The whole head together, face and all, so it keeps its proportions.
    if (rig.headScale != 1) canvas.scale(rig.headScale);
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
    if (dna.spikes) _spikes(w, h);
    if (dna.species.animal) {
      _animalEars(w, h);
    } else {
      for (var phi in ears) {
        if (_toward(phi) < 0.3) ear(phi);
      }
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
    if (facing > -0.2 && !dna.species.animal) _nose(w, front: false);
    if (!dna.species.animal) {
      for (var phi in ears) {
        if (_toward(phi) >= 0.3) ear(phi);
      }
    }
    _hair(r);
    _horns(w, h);
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
    var eyeSides = switch (dna.eyeCount) {
      1 => [0.0],
      3 => [-1.0, 0.0, 1.0],
      _ => [-1.0, 1.0],
    };
    for (var side in eyeSides) {
      // One eye is in the middle and big; a third sits above the other two.
      var cyclops = dna.eyeCount == 1;
      var phi = side * 0.42;
      var toward = _toward(phi);
      if (toward < 0.12) continue;
      var c = Offset(_across(phi, w), eyeY);
      if (side == 0 && !cyclops) c = c + Offset(0, -u * 0.14);
      var ew = u * 0.17 * toward, eh = u * 0.21;
      if (cyclops) {
        ew *= 1.8;
        eh *= 1.6;
      }
      if (look.eyes == _Eyes.anime) {
        ew *= 1.2;
        eh *= 1.45;
        c = c + Offset(0, u * 0.03);
      }
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
        if (look.eyes == _Eyes.pie) {
          _pieEye(box, lookX, lookY, toward);
        } else {
          var anime = look.eyes == _Eyes.anime;
          canvas.drawOval(box, white);
          canvas.save();
          canvas.clipPath(Path()..addOval(box));
          var iris = c +
              Offset(lookX * u * 0.04 * toward, -lookY * u * 0.035 + u * 0.015);
          var big = anime ? 1.45 : 1.0;
          canvas.drawOval(
              Rect.fromCenter(
                  center: iris,
                  width: u * 0.124 * big * toward,
                  height: u * 0.124 * big * (anime ? 1.25 : 1)),
              Paint()..color = dna.eyes);
          canvas.drawOval(
              Rect.fromCenter(
                  center: iris,
                  width: u * 0.068 * big * toward,
                  height: u * 0.068 * big * (anime ? 1.2 : 1)),
              Paint()..color = const Color(0xFF1B1512));
          canvas.drawCircle(iris + Offset(-u * 0.022, -u * 0.035) * big,
              u * 0.017 * big, white);
          if (anime) {
            // A second, smaller highlight low on the other side.
            canvas.drawCircle(iris + Offset(u * 0.025, u * 0.03), u * 0.012, white);
          }
          canvas.restore();
          canvas.drawOval(box, lid);
          if (anime) {
            // A heavy upper lash line.
            canvas.drawArc(box, math.pi * 1.1, math.pi * 0.8, false,
                _feature(u * 0.035, const Color(0xFF1B1512)));
          }
        }
      }
      if (side != 0) _brow(c, side, toward);
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
    if (dna.species.animal) {
      _muzzle(w);
    } else {
      _nose(w, front: true);
    }
    // A beak is a bird's mouth.
    if (dna.species != Species.bird) _mouth(w);
    if (dna.fangs) _fangs(w);
  }

  // ---- what a creature has that a person does not ----

  /// _animalEars are a species' ears, on top of the head, going round with
  /// it: pointed for a cat or a fox, floppy for a dog, round for a bear or
  /// a mouse, long for a rabbit.
  void _animalEars(double w, double h) {
    for (var side in [-1.0, 1.0]) {
      var phi = side * 0.6;
      if (_toward(phi) < -0.5) continue;
      var x = _across(phi, w * 0.9);
      var base = Offset(x, -h * 0.72);
      var ear = Path();
      var inner = Path();
      switch (dna.species) {
        case Species.cat || Species.fox || Species.monster:
          var tall = dna.species == Species.fox ? 0.75 : 0.6;
          ear.addPolygon([
            base + Offset(-w * 0.32, h * 0.15),
            base + Offset(side * w * 0.12, -h * tall),
            base + Offset(w * 0.32, h * 0.15),
          ], true);
          inner.addPolygon([
            base + Offset(-w * 0.17, h * 0.08),
            base + Offset(side * w * 0.08, -h * tall * 0.7),
            base + Offset(w * 0.17, h * 0.08),
          ], true);
        case Species.dog:
          // Hanging down the side of the head.
          var at = Offset(_across(side * 1.25, w), -h * 0.35);
          ear.addOval(Rect.fromCenter(
              center: at + Offset(0, h * 0.45), width: w * 0.42, height: h * 1.0));
        case Species.bear || Species.mouse:
          var r = dna.species == Species.mouse ? w * 0.42 : w * 0.3;
          ear.addOval(Rect.fromCircle(center: base + Offset(side * w * 0.12, 0), radius: r));
          inner.addOval(Rect.fromCircle(center: base + Offset(side * w * 0.12, 0), radius: r * 0.55));
        case Species.rabbit:
          ear.addOval(Rect.fromCenter(
              center: base + Offset(side * w * 0.08, -h * 0.75), width: w * 0.42, height: h * 1.5));
          inner.addOval(Rect.fromCenter(
              center: base + Offset(side * w * 0.08, -h * 0.7), width: w * 0.2, height: h * 1.1));
        case Species.pig:
          ear.addPolygon([
            base + Offset(-w * 0.28, h * 0.1),
            base + Offset(side * w * 0.38, -h * 0.4),
            base + Offset(w * 0.28, h * 0.1),
          ], true);
        case Species.human || Species.bird || Species.fish:
          break;
      }
      if (ear.getBounds().isEmpty) continue;
      _fill(ear, dna.skin);
      if (!inner.getBounds().isEmpty) {
        canvas.drawPath(inner, Paint()..color = dna.fur2);
      }
    }
  }

  /// _muzzle is a creature's muzzle -- lighter fur round its nose and mouth,
  /// longer on a dog or a fox -- its nose, and whiskers where it has them.
  void _muzzle(double w) {
    var sp = dna.species;
    if (sp == Species.fish) return;
    if (sp == Species.bird) {
      // A beak, pointing the way the face does.
      var side = math.sin(yaw);
      var at = Offset(_across(0, w * 0.92), u * 0.16 + _nodShift);
      var long = u * (0.14 + 0.16 * side.abs());
      var beak = Path()
        ..moveTo(at.dx - u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..lineTo(at.dx - side * long, at.dy + u * 0.06)
        ..lineTo(at.dx + u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..quadraticBezierTo(at.dx, at.dy + u * 0.12, at.dx - u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..close();
      _fill(beak, dna.fur2);
      return;
    }
    var cx = _across(0, w * 0.9);
    var y = u * 0.2 + _nodShift;
    var long = sp == Species.dog || sp == Species.fox || sp == Species.bear;
    var mw = u * (long ? 0.42 : 0.32) * (0.6 + 0.4 * facing.abs());
    var mh = u * (long ? 0.3 : 0.22);
    // Side on, a long muzzle sticks out past the face.
    var out = math.sin(yaw) * (long ? -u * 0.18 : -u * 0.08);
    var at = Offset(cx + out, y);
    if (sp == Species.pig) {
      // A snout: a disc with two nostrils.
      var disc = Rect.fromCenter(center: at, width: u * 0.26, height: u * 0.18);
      _fill(Path()..addOval(disc), Color.lerp(dna.skin, const Color(0xFFE07A8A), 0.4)!);
      for (var s in [-1.0, 1.0]) {
        canvas.drawOval(
            Rect.fromCenter(center: at + Offset(s * u * 0.05, 0), width: u * 0.04, height: u * 0.07),
            Paint()..color = const Color(0xFF5A2A2A));
      }
      return;
    }
    _fill(Path()..addOval(Rect.fromCenter(center: at, width: mw, height: mh)), dna.fur2);
    var nose = Path()
      ..moveTo(at.dx - u * 0.06, at.dy - mh * 0.32)
      ..lineTo(at.dx + u * 0.06, at.dy - mh * 0.32)
      ..quadraticBezierTo(at.dx, at.dy - mh * 0.02, at.dx - u * 0.06, at.dy - mh * 0.32)
      ..close();
    _fill(nose, const Color(0xFF2A1A16));
    if (sp == Species.cat || sp == Species.mouse || sp == Species.rabbit || sp == Species.fox) {
      var whisker = _feature(u * 0.012, const Color(0xAA2A1A16));
      for (var s in [-1.0, 1.0]) {
        for (var k = 0; k < 2; k++) {
          var from = at + Offset(s * mw * 0.3, k * u * 0.03);
          canvas.drawLine(from, from + Offset(s * u * 0.28, (k - 0.5) * u * 0.08), whisker);
        }
      }
    }
  }

  /// _fangs are two teeth hanging from the top lip at the mouth's corners.
  void _fangs(double w) {
    var at = Offset(_across(0, w * 0.88), u * 0.3 + _nodShift);
    var white = Paint()..color = const Color(0xFFFAFAF2);
    for (var s in [-1.0, 1.0]) {
      var x = at.dx + s * u * 0.06 * (0.4 + 0.6 * facing.abs());
      var fang = Path()
        ..moveTo(x - u * 0.025, at.dy - u * 0.005)
        ..lineTo(x + u * 0.025, at.dy - u * 0.005)
        ..lineTo(x, at.dy + u * 0.07)
        ..close();
      canvas.drawPath(fang, white);
      _outline(fang, const Color(0xFFFAFAF2));
    }
  }

  /// _horns are on top of the head, in the lighter colour: two short
  /// points, a ram's curls, or antlers.
  void _horns(double w, double h) {
    if (dna.horns == HornKind.none) return;
    for (var side in [-1.0, 1.0]) {
      var phi = side * 0.45;
      if (_toward(phi) < -0.4) continue;
      var base = Offset(_across(phi, w * 0.85), -h * 0.78);
      switch (dna.horns) {
        case HornKind.small:
          var horn = Path()
            ..moveTo(base.dx - w * 0.14, base.dy + h * 0.08)
            ..quadraticBezierTo(base.dx + side * w * 0.05, base.dy - h * 0.25,
                base.dx + side * w * 0.2, base.dy - h * 0.48)
            ..quadraticBezierTo(base.dx + side * w * 0.12, base.dy - h * 0.1,
                base.dx + w * 0.14, base.dy + h * 0.08)
            ..close();
          _fill(horn, dna.fur2);
        case HornKind.ram:
          // A curl round the side of the head.
          var curl = Path()..moveTo(base.dx, base.dy);
          for (var k = 1; k <= 24; k++) {
            var a = k / 24 * math.pi * 1.7;
            var r = w * (0.45 - 0.012 * k);
            curl.lineTo(base.dx + side * (r * math.sin(a)),
                base.dy + h * 0.35 - r * math.cos(a));
          }
          canvas.drawPath(
              curl,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = w * 0.2
                ..color = dna.fur2);
          canvas.drawPath(curl, _edgePaint(dna.fur2)..strokeWidth = edge);
        case HornKind.antlers:
          var stem = [base, base + Offset(side * w * 0.25, -h * 0.7)];
          _stroke(stem, w * 0.1, dna.fur2);
          _stroke([base + Offset(side * w * 0.1, -h * 0.3), base + Offset(side * w * 0.45, -h * 0.5)],
              w * 0.08, dna.fur2);
          _stroke([base + Offset(side * w * 0.2, -h * 0.55), base + Offset(-side * w * 0.05, -h * 0.85)],
              w * 0.08, dna.fur2);
        case HornKind.none:
          break;
      }
    }
  }

  /// _spikes are a row of points along the top of the head, behind it.
  void _spikes(double w, double h) {
    for (var k = 0; k < 5; k++) {
      var a = math.pi * (1.15 + k * 0.7 / 4);
      var at = Offset(math.cos(a) * w * 0.95, math.sin(a) * h * 0.95);
      var dir = Offset(math.cos(a), math.sin(a));
      var side = Offset(-dir.dy, dir.dx);
      _fill(
          Path()
            ..addPolygon([
              at + side * (w * 0.13),
              at + dir * (h * 0.38),
              at - side * (w * 0.13),
            ], true),
          dna.fur2);
    }
  }

  /// _tail grows from the back of the hips, out the way the body is not
  /// facing -- to the side, facing the reader.
  void _tail() {
    if (dna.species == Species.bird && dna.tail == TailKind.none) {
      _tailFeathers();
      return;
    }
    if (dna.tail == TailKind.none) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    var back = side.abs() < 0.3 ? 1.0 : side.sign;
    var root = rig.hips + Offset(back * rig.hipHalf * 0.6, -legWidth * 0.2);
    var t = u;
    switch (dna.tail) {
      case TailKind.long:
        _strokeCurve(root, root + Offset(back * t * 0.9, -t * 0.2),
            root + Offset(back * t * 1.3, -t * 0.9), legWidth * 0.32, dna.skin);
      case TailKind.bushy:
        var tip = root + Offset(back * t * 1.1, -t * 0.9);
        var tail = Path()
          ..moveTo(root.dx, root.dy - t * 0.1)
          ..quadraticBezierTo(root.dx + back * t * 1.4, root.dy + t * 0.1, tip.dx, tip.dy)
          ..quadraticBezierTo(root.dx + back * t * 0.4, root.dy - t * 0.5, root.dx, root.dy + t * 0.12)
          ..close();
        _fill(tail, dna.skin);
        canvas.save();
        canvas.clipPath(tail);
        canvas.drawCircle(tip, t * 0.3, Paint()..color = dna.fur2);
        canvas.restore();
      case TailKind.curly:
        var curl = Path()..moveTo(root.dx, root.dy);
        for (var k = 1; k <= 30; k++) {
          var a = k / 30 * math.pi * 3;
          var r = t * 0.1 * (1 - k / 40);
          curl.lineTo(root.dx + back * (t * 0.15 + r * math.cos(a)), root.dy - t * 0.1 - r * math.sin(a));
        }
        canvas.drawPath(
            curl,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = t * 0.05
              ..color = dna.skin);
      case TailKind.stub:
        _fill(Path()..addOval(Rect.fromCircle(center: root, radius: t * 0.16)), dna.fur2);
      case TailKind.dragon:
        var end = root + Offset(back * t * 1.6, t * 0.1);
        _strokeCurve(root, root + Offset(back * t * 0.8, t * 0.5), end, legWidth * 0.5, dna.skin);
        _fill(
            Path()
              ..addPolygon([
                end + Offset(0, -t * 0.14),
                end + Offset(back * t * 0.3, 0),
                end + Offset(0, t * 0.14),
              ], true),
            dna.fur2);
      case TailKind.none:
        break;
    }
  }

  /// _wings grow from the shoulders, behind the body: feathers in fans, or
  /// a bat's stretched between long fingers.
  void _wings() {
    if (dna.wings == WingKind.none) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    for (var s in [-1.0, 1.0]) {
      // Side on, only the far wing shows, behind.
      if (side.abs() > 0.7 && s != side.sign) continue;
      var root = rig.chest + Offset(s * rig.shoulderHalf * 0.5, 0);
      var span = rig.shoulderHalf * 2.6;
      var out = side.abs() > 0.7 ? -side.sign : s;
      // Raised as far as the flap says, about where it grows from.
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(-out * rig.wingFlap * 0.8 * math.pi / 180);
      canvas.translate(-root.dx, -root.dy);
      if (dna.wings == WingKind.feathered) {
        for (var k = 0; k < 3; k++) {
          var a = -0.9 + k * 0.45;
          var tip = root + Offset(out * span * math.cos(a) * (1 - k * 0.15), span * math.sin(a) * 0.8);
          _fill(
              Path()
                ..addOval(Rect.fromPoints(root, tip).inflate(u * 0.05)),
              Color.lerp(dna.fur2, dna.skin, k * 0.2)!);
        }
      } else {
        var top = root + Offset(out * span * 0.6, -span * 0.75);
        var tip = root + Offset(out * span, -span * 0.2);
        var membrane = Path()
          ..moveTo(root.dx, root.dy)
          ..lineTo(top.dx, top.dy)
          ..lineTo(tip.dx, tip.dy)
          ..quadraticBezierTo(root.dx + out * span * 0.75, root.dy + span * 0.05,
              root.dx + out * span * 0.55, root.dy + span * 0.25)
          ..quadraticBezierTo(root.dx + out * span * 0.35, root.dy + span * 0.05,
              root.dx + out * span * 0.2, root.dy + span * 0.3)
          ..close();
        _fill(membrane, Color.lerp(dna.skin, const Color(0xFF000000), 0.18)!);
        _stroke([root, top, tip], u * 0.05, dna.skin);
      }
      canvas.restore();
    }
  }

  /// _birdWing is a bird's arm drawn as a wing: feathers fanned along it,
  /// longest at the tip, lighter at the edge.
  void _birdWing(Offset shoulder, Offset elbow, Offset wrist, double side) {
    var along = wrist - shoulder;
    if (along.distance < 1e-6) return;
    var out = Offset(-along.dy, along.dx) / along.distance;
    // The feathers hang below the arm, whichever way it points.
    if (out.dy < 0) out = -out;
    var width = rig.shoulderHalf * 0.9;
    var wing = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(elbow.dx, elbow.dy, wrist.dx, wrist.dy);
    for (var k = 4; k >= 0; k--) {
      var at = Offset.lerp(shoulder, wrist, k / 4)!;
      var reach = width * (0.6 + 0.5 * k / 4);
      wing.lineTo(at.dx + out.dx * reach, at.dy + out.dy * reach);
    }
    wing.close();
    _fill(wing, dna.skin);
    canvas.save();
    canvas.clipPath(wing);
    var tips = Paint()..color = Color.lerp(dna.skin, dna.fur2, 0.45)!;
    for (var k = 0; k <= 4; k++) {
      var at = Offset.lerp(shoulder, wrist, k / 4)!;
      var reach = width * (0.6 + 0.5 * k / 4);
      canvas.drawCircle(at + out * reach, width * 0.28, tips);
    }
    canvas.restore();
  }

  /// _toes are a bird's three toes, spread on the ground.
  void _toes(CharacterLimb limb) {
    var ankle = rig.end(limb);
    var drop = rig.below * CharacterRig.footDrop;
    var side = math.sin(rig.yaw * math.pi / 180);
    var forward = side.abs() > 0.5 ? -side.sign : 0.0;
    var toe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = legWidth * 0.18
      ..color = dna.fur2;
    for (var k = -1; k <= 1; k++) {
      var dir = Offset(k * 0.6 + forward * 0.8, 1).scale(1, 1);
      var tip = ankle + Offset(dir.dx * legWidth * 0.9, drop * 0.9);
      if (lined) {
        canvas.drawLine(ankle, tip,
            Paint()
              ..strokeCap = StrokeCap.round
              ..strokeWidth = legWidth * 0.18 + edge * 2
              ..color = _inkFor(dna.fur2));
      }
      canvas.drawLine(ankle, tip, toe);
    }
  }

  /// _fin is a small fin from a fish's side, pointing as the arm would.
  void _fin(Offset shoulder, Offset elbow) {
    var d = elbow - shoulder;
    if (d.distance < 1e-6) return;
    var dir = d / d.distance;
    var across = Offset(-dir.dy, dir.dx);
    var len = rig.shoulderHalf * 1.1;
    _fill(
        Path()
          ..addPolygon([
            shoulder + across * (len * 0.25),
            shoulder + dir * len,
            shoulder - across * (len * 0.25),
          ], true),
        Color.lerp(dna.skin, dna.fur2, 0.5)!);
  }

  /// _fishBody is a fish: a long rounded body from its tail to its head,
  /// lighter underneath, and a forked tail fin that flicks as it sways.
  void _fishBody() {
    var thick = rig.hipHalf * 3.2;
    var tail = rig.hips, front = rig.neck;
    var along = front - tail;
    var dir = along.distance < 1e-6 ? const Offset(1, 0) : along / along.distance;
    var across = Offset(-dir.dy, dir.dx);
    // The tail fin, behind the body.
    var fin = tail - dir * (thick * 0.25);
    var flick = across * (thick * 0.2 * math.sin(rig.bodyTurn * math.pi / 30));
    _fill(
        Path()
          ..addPolygon([
            fin,
            fin - dir * thick * 0.9 + across * thick * 0.65 + flick,
            fin - dir * thick * 0.55 + flick,
            fin - dir * thick * 0.9 - across * thick * 0.65 + flick,
          ], true),
        Color.lerp(dna.skin, dna.fur2, 0.35)!);
    _stroke([tail, front], thick, dna.skin);
    var belly = Path()
      ..addOval(Rect.fromCenter(
          center: Offset.lerp(tail, front, 0.55)! + Offset(0, thick * 0.22),
          width: along.distance * 0.9,
          height: thick * 0.4));
    canvas.save();
    canvas.clipPath(_capsule([tail, front], thick));
    canvas.drawPath(belly, Paint()..color = dna.fur2);
    canvas.restore();
  }

  /// _tailFeathers are a bird's tail: a short fan from the back of the hips.
  void _tailFeathers() {
    var side = math.sin(rig.yaw * math.pi / 180);
    var back = side.abs() < 0.3 ? 0.0 : side.sign;
    var root = rig.hips + Offset(back * rig.hipHalf * 0.5, 0);
    for (var k = -1; k <= 1; k++) {
      var tip = root + Offset(back * u * 0.55 + k * u * 0.18, u * 0.35 + (back == 0 ? u * 0.15 : 0));
      _fill(
          Path()
            ..addOval(Rect.fromPoints(root, tip).inflate(u * 0.05)),
          Color.lerp(dna.skin, const Color(0xFF000000), 0.1 + 0.05 * k.abs())!);
    }
  }

  /// _strokeCurve is a band [width] wide along a curve from [a] through
  /// [mid] to [b].
  void _strokeCurve(Offset a, Offset mid, Offset b, double width, Color colour) {
    var path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    Paint stroke(double w, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w
      ..color = c;
    if (lined) canvas.drawPath(path, stroke(width + edge * 2, _inkFor(colour)));
    canvas.drawPath(path, stroke(width, colour));
  }

  /// _pieEye is a 1930s cartoon eye: a black oval with a slice cut out of
  /// it for the shine, the slice moving with where it looks.
  void _pieEye(Rect box, double lookX, double lookY, double toward) {
    var eye = Rect.fromCenter(
        center: box.center + Offset(lookX * u * 0.02, -lookY * u * 0.02),
        width: box.width * 0.75,
        height: box.height * 1.05);
    canvas.drawOval(eye, Paint()..color = const Color(0xFF151515));
    if (toward > 0.4) {
      canvas.drawArc(eye.deflate(eye.width * 0.08), -math.pi * 0.45,
          math.pi * 0.28, true, Paint()..color = const Color(0xFFFAFAFA));
    }
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
    _solid(path.getBounds(), colour, (p) => canvas.drawPath(path, p));
    _outline(path, colour);
  }

}

/// _shade is [c] darkened by [by], for the edge drawn round it.
Color _shade(Color c, [double by = 0.32]) =>
    Color.lerp(c, const Color(0xFF000000), by)!;
