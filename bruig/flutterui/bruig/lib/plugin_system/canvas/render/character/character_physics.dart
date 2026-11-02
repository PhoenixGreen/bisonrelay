import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';

// character_physics.dart works out how far a character's hair has swung on
// a frame: a spring, pulled by the head's movement over the frames before
// and settling as it goes. No state is kept from one frame to the next --
// the frames before are worked out again -- so a frame is the same whether
// it is played to, jumped to, or exported. See model/elements/
// character_physics.dart.

/// _lookBack is how many frames of movement the hair remembers.
const int _lookBack = 14;

/// HairSway is how [e]'s hair hangs on a frame, about its brow -- see
/// hairPivot -- so what frames the face stays by it:
/// [across] how far it moves across for each unit down -- positive to the
/// page's right -- and [stretch] how much longer it hangs, or shorter, as
/// the head drops and rises under it.
class HairSway {
  final double across;
  final double stretch;
  const HairSway(this.across, this.stretch);
  static const HairSway none = HairSway(0, 0);
  bool get isNone => across == 0 && stretch == 0;

  /// share is this much of it: for hair nearer the face, which moves less.
  HairSway share(double of) => HairSway(across * of, stretch * of);

  /// at is where a point [p] of the hair is drawn, swayed, about [pivot]:
  /// nothing above it moves.
  Offset at(Offset p, double pivot) {
    var down = math.max(0.0, p.dy - pivot);
    return Offset(p.dx + across * down, p.dy + stretch * down);
  }
}

/// hairPivot is how far down the head, from its top, the hair sways
/// about, in the head's heights: its brow.
const double hairPivot = 0.3;

/// hairSwayAt is how [e]'s hair hangs on [frame], drawn in [box]. None
/// where its physics is off.
HairSway hairSwayAt(CharacterElement e, int frame, int frameRate, Rect box) {
  var p = e.physics;
  if (!p.on || e.dna.hairStyle == HairStyle.bald || frameRate <= 0) {
    return HairSway.none;
  }
  var dt = 1 / frameRate;
  // Where the head is on the page, in heads, frame by frame: as the body
  // moves it and as the element is moved across the page.
  Offset headAt(int f) {
    f = math.max(0, f);
    var (pose, _) = e.performanceAt(f, frameRate);
    if (!e.body.inThreeD) pose = e.inView(pose);
    var rig = CharacterRig.of(e.dna, pose, box);
    var head = rig.headRadii.height * 2;
    if (head <= 0) return Offset.zero;
    var moved = e.track?.at(f);
    return (rig.headCentre + Offset(moved?.dx ?? 0, moved?.dy ?? 0)) / head;
  }

  // Nothing moving it -- no motions, nothing keyed -- it hangs still but
  // for the air.
  var still = e.motions.isEmpty && (e.track?.isEmpty ?? true);
  var heads = still
      ? const <Offset>[]
      : [for (var f = frame - _lookBack - 2; f <= frame; f++) headAt(f)];
  // A pendulum each way, hung from the top of the head: pulled back by its
  // weight -- harder the stiffer the hair -- damped the less it bounces,
  // thrown the other way as the head speeds up, as far as it is heavy, and
  // blown back by the air as it moves.
  var k = 25 + 150 * p.stiffness;
  // Damped for its stiffness, so stiff hair rings no longer than soft: a
  // third of what stops it swinging back at all, bouncy, to more than all.
  var c = (0.3 + 0.9 * (1 - p.bounce)) * 2 * math.sqrt(k);
  var throw_ = 0.06 + 0.3 * p.weight;
  var drag = 0.3 + 0.6 * (1 - p.weight);
  var s = Offset.zero, v = Offset.zero;
  for (var i = 2; i < heads.length; i++) {
    var speed = (heads[i] - heads[i - 1]) / dt;
    var accel = (heads[i] - heads[i - 1] * 2 + heads[i - 2]) / (dt * dt);
    var a = -s * k - v * c - accel * throw_ - speed * drag;
    v += a * dt;
    s += v * dt;
  }
  // And a breath of air, so hair standing still is not cut from card.
  var t = frame / frameRate;
  var seed = e.id.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xffff);
  var air = 0.012 *
      (1 - 0.5 * p.stiffness) *
      math.sin(2 * math.pi * t / 3.1 + seed % 7);
  // Dropping, it is left behind above the head -- shorter -- and rising
  // pulled out long: half as far as across, hair being longer than wide.
  return HairSway(
      (s.dx + air).clamp(-0.5, 0.5), (s.dy * 0.5).clamp(-0.15, 0.15));
}
