import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';

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
  footR;

  /// limb is the arm or leg this pin is on the end of, or null for the head
  /// and chest.
  CharacterLimb? get limb => switch (this) {
        handL => CharacterLimb.armL,
        handR => CharacterLimb.armR,
        footL => CharacterLimb.legL,
        footR => CharacterLimb.legR,
        _ => null,
      };
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

  CharacterPlacement._(this.element, this.frame, this.rig, this._box,
      this._centre, this._shift, this._anchor, this._turn, this._scale);

  /// of places [e] on [frame], breathing as it does at [frameRate] -- the
  /// pins are on the joints as they are drawn, chest risen or not.
  factory CharacterPlacement.of(CharacterElement e, int frame,
      {int frameRate = 12}) {
    var pose = e.poseAt(frame);
    var bounds = e.bounds;
    return CharacterPlacement._(
      e,
      frame,
      CharacterRig.of(e.dna, e.performanceAt(frame, frameRate).$1, bounds,
          breath: lifeAt(e, frame, frameRate).breath),
      BoxFrame(e.rotation, e.base.skewX, e.base.skewY),
      bounds.center,
      Offset(pose.dx, pose.dy),
      e.anchorIn(bounds),
      pose.rotate * math.pi / 180,
      pose.scale,
    );
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
  Offset localPin(CharacterPin pin) => switch (pin) {
        CharacterPin.head => rig.headCentre,
        CharacterPin.chest => rig.chest,
        CharacterPin.handL => rig.wristL,
        CharacterPin.handR => rig.wristR,
        CharacterPin.footL => rig.ankleL,
        CharacterPin.footR => rig.ankleR,
      };

  Offset pin(CharacterPin pin) => toPage(localPin(pin));

  /// bones is the skeleton as page lines, for drawing over the character
  /// while it is being posed.
  List<(Offset, Offset)> get bones {
    var r = rig;
    return [
      for (var (a, b) in [
        (r.hips, r.chest),
        (r.chest, r.neck),
        (r.neck, r.headCentre),
        (r.shoulderL, r.shoulderR),
        (r.shoulderL, r.elbowL),
        (r.elbowL, r.wristL),
        (r.shoulderR, r.elbowR),
        (r.elbowR, r.wristR),
        (r.hipL, r.hipR),
        (r.hipL, r.kneeL),
        (r.kneeL, r.ankleL),
        (r.hipR, r.kneeR),
        (r.kneeR, r.ankleR),
      ])
        (toPage(a), toPage(b)),
    ];
  }

  /// posedBy is the pose that [pin] dragged to [page] asks for.
  CharacterPose posedBy(CharacterPin pin, Offset page) {
    var target = toLocal(page);
    var pose = element.poseAtFrame(frame);
    if (pin.limb case var limb?) return rig.solveLimb(pose, limb, target);
    if (pin == CharacterPin.head) return rig.solveHead(pose, target);
    return rig.solveLean(pose, target);
  }

  /// pinUnder is the pin within [reach] of [page], nearest first, or null.
  CharacterPin? pinUnder(Offset page, double reach) {
    CharacterPin? best;
    var nearest = reach;
    for (var p in CharacterPin.values) {
      var d = (pin(p) - page).distance;
      if (d <= nearest) {
        nearest = d;
        best = p;
      }
    }
    return best;
  }
}
