import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_extremities.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';

// character_puppet.dart is what the stage needs to pose a character by
// hand: where its pins are on the page, and the pose a pin dragged to a
// point asks for.
//
// A pin is a joint a person would take hold of to move a figure: a hand, a
// foot, the head, the chest. Dragging one bends whatever it is on the end of
// -- a hand bends the arm, a foot the leg -- and leaves the rest of the body
// where it was, which is how a puppet pinned to a board behaves.

/// CharacterPin is one place a character can be taken hold of.
enum CharacterPin {
  head,
  chest,
  handL,
  handR,
  footL,
  footR,

  /// toeL and toeR are on the tips of the toes, which point the foot --
  /// on a drawn body, which has a foot to point.
  toeL,
  toeR;

  /// limb is the arm or leg this pin is on the end of, or null for the head
  /// and chest.
  CharacterLimb? get limb => switch (this) {
        handL => CharacterLimb.armL,
        handR => CharacterLimb.armR,
        footL || toeL => CharacterLimb.legL,
        footR || toeR => CharacterLimb.legR,
        _ => null,
      };

  bool get isToe => this == toeL || this == toeR;
}

/// CharacterPlacement is how a character's own drawing space lies on the
/// page at one frame: its keyframe's shift, its turn and slant about its
/// middle, and its keyframe's turn and size about its anchor -- in the order
/// paintElement applies them.
class CharacterPlacement {
  final CharacterElement element;
  final int frame;
  final CharacterRig rig;
  final BoxFrame _box;
  final Offset _centre;
  final Offset _shift;
  final Offset _anchor;
  final double _turn;
  final double _scale;

  /// turn is what the stage's camera adds to the character's own turn,
  /// which a pin's pose has to have taken back off.
  final double turn;

  /// model is where a modelled body's joints are, in the drawing's own
  /// space, when it is drawn from a model -- whose arms and legs are its
  /// own length, not the rig's. Empty otherwise.
  final Map<RigJoint, ModelJoint> model;

  /// bounds is the box the rig fills, in the drawing's own space.
  final Rect bounds;

  CharacterPlacement._(this.element, this.frame, this.rig, this._box,
      this._centre, this._shift, this._anchor, this._turn, this._scale,
      {this.turn = 0, this.model = const {}, this.bounds = Rect.zero});

  /// of places [e] on [frame], breathing as it does at [frameRate] -- the
  /// pins are on the joints as they are drawn, chest risen or not, and on
  /// the model's joints when it is drawn from one [models] has.
  factory CharacterPlacement.of(CharacterElement e, int frame,
      {int frameRate = 12,
      CanvasDocument? document,
      CanvasModelSource? models}) {
    var shown = e.style.frameOf(frame);
    var (performed, face) = e.performanceAt(shown, frameRate);
    var breath = lifeAt(e, shown, frameRate).breath;
    var loaded = e.body.kind == BodyKind.model && e.body.modelId.isNotEmpty
        ? models?.resolveModel(e.body.modelId)
        : null;
    Map<RigJoint, ModelJoint> modelOf(CharacterRig rig, Rect box) =>
        loaded?.joints(rig, face, box, lift: performed.lift * rig.unit) ??
        const {};
    // On a stage, where its camera puts it and turned as it sees it -- and
    // nothing of its own box: see paintElement.
    if (document != null && e.onStage != null) {
      if (staging(e, document.elements, frame) case var at?) {
        var seen = performed
            .withTurn(performed.turn + at.turn)
            .withTilt((performed.tilt + at.tilt).clamp(-85.0, 85.0));
        // A sketch from the panel it is drawn from -- see paintCharacterFigure.
        var rig = CharacterRig.of(
            e.style.dnaOf(e.dna), e.body.inThreeD ? seen : e.inView(seen), at.box,
            breath: breath);
        return CharacterPlacement._(
          e,
          frame,
          rig,
          BoxFrame(0, 0, 0),
          at.box.center,
          Offset.zero,
          at.box.center,
          0,
          1,
          turn: at.turn,
          model: modelOf(rig, at.box),
          bounds: at.box,
        );
      }
    }
    var pose = e.poseAt(frame);
    var bounds = characterBox(e, frame, e.bounds);
    // As it is drawn: in its style's proportions, and on the frame its
    // style shows -- see paintCharacter.
    var rig = CharacterRig.of(e.style.dnaOf(e.dna),
        e.body.inThreeD ? performed : e.inView(performed), bounds,
        breath: breath);
    return CharacterPlacement._(
      e,
      frame,
      rig,
      BoxFrame(e.rotation, e.base.skewX, e.base.skewY),
      bounds.center,
      Offset(pose.dx, pose.dy),
      e.anchorIn(bounds),
      pose.rotate * math.pi / 180,
      pose.scale,
      model: modelOf(rig, bounds),
      bounds: bounds,
    );
  }

  /// _at is where [j] is drawn: on the model when there is one, and on
  /// the rig otherwise.
  Offset _at(RigJoint j) => model[j]?.page ?? _rigAt(j);

  /// _rigAt is where the rig's [j] is.
  Offset _rigAt(RigJoint j) {
    var r = rig;
    return switch (j) {
      RigJoint.hips => r.hips,
      RigJoint.chest => r.chest,
      RigJoint.neck => r.neck,
      RigJoint.head => r.headCentre,
      RigJoint.shoulderL => r.shoulderL,
      RigJoint.elbowL => r.elbowL,
      RigJoint.wristL => r.wristL,
      RigJoint.shoulderR => r.shoulderR,
      RigJoint.elbowR => r.elbowR,
      RigJoint.wristR => r.wristR,
      RigJoint.hipL => r.hipL,
      RigJoint.kneeL => r.kneeL,
      RigJoint.ankleL => r.ankleL,
      RigJoint.hipR => r.hipR,
      RigJoint.kneeR => r.kneeR,
      RigJoint.ankleR => r.ankleR,
    };
  }

  /// _forRig is [target], a point the model's [joint] is dragged to, as
  /// the point the rig's has to reach for the model's to land on it: the
  /// same way from [from] -- the joint it swings about -- and as far, as
  /// a share of the reach. On a drawn body, the target itself.
  Offset _forRig(
      Offset target, RigJoint from, List<RigJoint> chain, double rigReach) {
    var m = model[from];
    if (m == null) return target;
    var reach = 0.0;
    var prev = from;
    for (var j in chain) {
      var a = model[prev], b = model[j];
      if (a == null || b == null) return target;
      // Its length in 3D: a limb pointing at the reader is short on the
      // page, but not long.
      var d = a.page - b.page, z = a.depth - b.depth;
      reach += math.sqrt(d.dx * d.dx + d.dy * d.dy + z * z);
      prev = j;
    }
    if (reach <= 0) return target;
    return _rigAt(from) + (target - m.page) * (rigReach / reach);
  }



  /// toPage is a point of the drawing where it is on the page.
  Offset toPage(Offset local) {
    var p = local;
    if (_turn != 0 || _scale != 1) {
      var d = (p - _anchor) * _scale;
      var c = math.cos(_turn), s = math.sin(_turn);
      p = _anchor + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    }
    p = _centre + _box.apply(p - _centre);
    return p + _shift;
  }

  /// toLocal is the inverse of [toPage].
  Offset toLocal(Offset page) {
    var p = page - _shift;
    p = _centre + _box.invert(p - _centre);
    if (_turn != 0 || _scale != 1) {
      var d = p - _anchor;
      var c = math.cos(-_turn), s = math.sin(-_turn);
      d = Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
      p = _anchor + d / (_scale == 0 ? 1 : _scale);
    }
    return p;
  }

  /// pinAt is where [pin] is drawn, in the drawing's own space.
  Offset localPin(CharacterPin pin) => pin.isToe
      ? _toe(rig, pin.limb!)
      : _at(switch (pin) {
        CharacterPin.head => RigJoint.head,
        CharacterPin.chest => RigJoint.chest,
        CharacterPin.handL => RigJoint.wristL,
        CharacterPin.handR => RigJoint.wristR,
        CharacterPin.footL => RigJoint.ankleL,
        CharacterPin.footR || CharacterPin.toeR => RigJoint.ankleR,
        CharacterPin.toeL => RigJoint.ankleL,
      });

  /// _toe is where the tip of [leg]'s toes is in [r].
  static Offset _toe(CharacterRig r, CharacterLimb leg) =>
      r.end(leg) + footShape(r, leg, r.footSize()).tip;

  /// _pointed is [seen] with [leg]'s foot pointed and turned so the tips
  /// of its toes are where [target] is, as the ankle sees them: up and down
  /// is how far it points, across how far it turns -- whichever way it is
  /// seen, each measured on the rig as it stands, the body lifted on to its
  /// toes as far as they go into the floor (see CharacterRig.of). Solved a
  /// few damped steps at a time, so a foot seen toes on -- where pointing
  /// it hardly moves the tip -- turns rather than sticks.
  CharacterPose _pointed(CharacterPose seen, CharacterLimb leg, Offset target) {
    var bone = ankleBone(leg.onLeft);
    var dna = element.style.dnaOf(element.dna);
    Offset tipOf(double point, double turn) {
      var q = seen.withSwing(bone, point).withAngle(bone, turn);
      var r = CharacterRig.of(dna, element.inView(q), bounds);
      return _toe(r, leg) - r.end(leg);
    }

    var want = target - rig.end(leg);
    (double, double, double) solve(double point, double turn) {
      for (var k = 0; k < 8; k++) {
        var now = tipOf(point, turn);
        var miss = want - now;
        if (miss.distance < 0.05) break;
        var a = tipOf(point + 1, turn) - now, b = tipOf(point, turn + 1) - now;
        // Damped least squares: (JᵀJ + λI) d = Jᵀ miss.
        var aa = a.dx * a.dx + a.dy * a.dy, bb = b.dx * b.dx + b.dy * b.dy;
        var ab = a.dx * b.dx + a.dy * b.dy;
        var lambda = 0.02 * (aa + bb) + 1e-9;
        var ra = a.dx * miss.dx + a.dy * miss.dy, rb = b.dx * miss.dx + b.dy * miss.dy;
        var m11 = aa + lambda, m22 = bb + lambda, det = m11 * m22 - ab * ab;
        if (det.abs() < 1e-12) break;
        point = (point + ((m22 * ra - ab * rb) / det).clamp(-20.0, 20.0))
            .clamp(-40.0, 85.0);
        turn = (turn + ((m11 * rb - ab * ra) / det).clamp(-20.0, 20.0))
            .clamp(-60.0, 60.0);
      }
      return (point, turn, (want - tipOf(point, turn)).distance);
    }

    // From where it is, and -- in case pointing further is what carried
    // the toes away, past where they start to come back -- from flat and
    // from half way: whichever lands nearest, where it is if all do.
    var best = solve(seen.swing(bone), seen[bone]);
    for (var start in const [0.0, 45.0]) {
      var tried = solve(start, seen[bone]);
      if (tried.$3 < best.$3 - 0.05) best = tried;
    }
    var (point, turn, _) = best;
    return seen.withSwing(bone, point).withAngle(bone, turn);
  }

  Offset pin(CharacterPin pin) => toPage(localPin(pin));

  /// bones is the skeleton as page lines, for drawing over the character
  /// while it is being posed.
  List<(Offset, Offset)> get bones => [
        for (var (a, b) in const [
          (RigJoint.hips, RigJoint.chest),
          (RigJoint.chest, RigJoint.neck),
          (RigJoint.neck, RigJoint.head),
          (RigJoint.shoulderL, RigJoint.shoulderR),
          (RigJoint.shoulderL, RigJoint.elbowL),
          (RigJoint.elbowL, RigJoint.wristL),
          (RigJoint.shoulderR, RigJoint.elbowR),
          (RigJoint.elbowR, RigJoint.wristR),
          (RigJoint.hipL, RigJoint.hipR),
          (RigJoint.hipL, RigJoint.kneeL),
          (RigJoint.kneeL, RigJoint.ankleL),
          (RigJoint.hipR, RigJoint.kneeR),
          (RigJoint.kneeR, RigJoint.ankleR),
        ])
          (toPage(_at(a)), toPage(_at(b))),
        for (var p in pins)
          if (p.isToe) (pin(p.limb == CharacterLimb.legL ? CharacterPin.footL : CharacterPin.footR), pin(p)),
      ];

  /// posedBy is the pose that [pin] dragged to [page] asks for.
  CharacterPose posedBy(CharacterPin pin, Offset page) {
    var target = toLocal(page);
    // Solved as it is seen -- with the camera's turn -- and given back as
    // the character's own.
    var pose = element.poseAtFrame(frame);
    var seen = pose.withTurn(pose.turn + turn);
    var r = rig;
    var trunk = r.torsoLength + r.neckLength;
    var solved = switch (pin) {
      CharacterPin.handL => r.solveLimb(
          seen,
          CharacterLimb.armL,
          _forRig(
              target,
              RigJoint.shoulderL,
              const [RigJoint.elbowL, RigJoint.wristL],
              r.upperArm + r.foreArm)),
      CharacterPin.handR => r.solveLimb(
          seen,
          CharacterLimb.armR,
          _forRig(
              target,
              RigJoint.shoulderR,
              const [RigJoint.elbowR, RigJoint.wristR],
              r.upperArm + r.foreArm)),
      CharacterPin.footL => r.solveLimb(
          seen,
          CharacterLimb.legL,
          _forRig(target, RigJoint.hipL,
              const [RigJoint.kneeL, RigJoint.ankleL], r.thigh + r.shin)),
      CharacterPin.footR => r.solveLimb(
          seen,
          CharacterLimb.legR,
          _forRig(target, RigJoint.hipR,
              const [RigJoint.kneeR, RigJoint.ankleR], r.thigh + r.shin)),
      CharacterPin.head => r.solveHead(
          seen,
          _forRig(target, RigJoint.chest, const [RigJoint.head],
              r.neckLength + r.unit * 0.5 * r.headScale)),
      CharacterPin.chest => r.solveLean(
          seen, _forRig(target, RigJoint.hips, const [RigJoint.chest], trunk)),
      CharacterPin.toeL || CharacterPin.toeR =>
        _pointed(seen, pin.limb!, target),
    };
    return solved.withTurn(pose.turn).withTilt(pose.tilt);
  }

  /// pins is the pins this character has: no feet on a fish.
  List<CharacterPin> get pins => [
        for (var p in CharacterPin.values)
          if (!(element.dna.species.legless &&
                  (p == CharacterPin.footL || p == CharacterPin.footR)) &&
              !(p.isToe && !_pointable))
            p,
      ];

  /// _pointable is whether its feet point: drawn, and standing on two.
  bool get _pointable {
    var dna = element.dna;
    return !element.body.inThreeD &&
        !dna.species.legless &&
        !dna.fourLegs &&
        dna.species != Species.bird;
  }

  /// pinUnder is the pin within [reach] of [page], nearest first, or null.
  CharacterPin? pinUnder(Offset page, double reach) {
    CharacterPin? best;
    var nearest = reach;
    for (var p in pins) {
      var d = (pin(p) - page).distance;
      if (d <= nearest) {
        nearest = d;
        best = p;
      }
    }
    return best;
  }
}
