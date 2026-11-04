import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_shape.dart shapes a VRoid body by its CharacterShape: smooth changes
// to the mesh where a part of it is -- the eyes, the jaw, the bum -- and the
// skeleton itself longer, wider or bigger. Every change is worked out from
// the mesh as made, so each setting is a setting and not a step: the same
// shape always gives the same body.
//
// Where things are is found from the mesh itself: the eyes from the eye
// meshes, the nose tip as the face's most forward point between the eyes
// and the mouth, the bum as the body's most rearward point between the hips
// and the thighs. Plain Dart, so it is tested without a GPU; vrm_scene.dart
// puts the result on the screen.

vm.Vector3 _v3(double x, double y, double z) => vm.Vector3(x, y, z);

/// FaceSide is one side of the face: the ear's outermost point, the
/// cheek's most forward one, the jaw's lowest, and the brow's middle.
class FaceSide {
  final vm.Vector3 ear, cheek, jaw, brow;
  const FaceSide(this.ear, this.cheek, this.jaw, this.brow);
}

/// FaceLandmarks are where the face's features are, in the mesh's space.
class FaceLandmarks {
  /// fwd is which way along z the face looks: 1 or -1.
  final double fwd;

  /// es is the distance between the eyes: what every face change is
  /// measured in, so it fits a face of any size.
  final double es;
  final double eyeY;
  final vm.Vector3 eyeR, eyeL, mouth, noseTip, chin, skinC, headTop;

  /// right is the side with x below nought.
  final FaceSide right, left;
  const FaceLandmarks(
      this.fwd,
      this.es,
      this.eyeY,
      this.eyeR,
      this.eyeL,
      this.mouth,
      this.noseTip,
      this.chin,
      this.skinC,
      this.headTop,
      this.right,
      this.left);
}

/// BodyPoints are places on the body to shape it where the bones are, in
/// the mesh's space.
class BodyPoints {
  /// u is the body's size against a grown woman's, for the body changes
  /// measured in metres.
  final double u;

  /// bustC and bustTip are the middle and the tip of the bust where the
  /// model has one (VRoid's J_Sec_R_Bust bones), and bustR its size.
  final vm.Vector3? bustC, bustTip;
  final double bustR;
  final vm.Vector3 bum, pec, abs, navel, chestR, waist, hips, belly;
  const BodyPoints(
      this.u,
      this.bustC,
      this.bustTip,
      this.bustR,
      this.bum,
      this.pec,
      this.abs,
      this.navel,
      this.chestR,
      this.waist,
      this.hips,
      this.belly);
}

/// Deformer is one change to the mesh.
sealed class Deformer {
  const Deformer();

  /// key says what the change is exactly, so a mesh whose changes are the
  /// same as last time is left alone.
  String get key;
}

String _k(vm.Vector3? v) => v == null
    ? '-'
    : '${v.x.toStringAsFixed(6)},${v.y.toStringAsFixed(6)},${v.z.toStringAsFixed(6)}';

/// Blob moves, sizes and turns what is inside an ellipsoid round [c] of
/// radii [r], most at the middle and fading to nothing at its edge.
class Blob extends Deformer {
  final vm.Vector3 c, r;
  final vm.Vector3? scale, t;

  /// rz turns it about the z axis, in radians.
  final double rz;

  /// mirror is the left-hand twin of a pair: its x movement and turn are
  /// reversed.
  final bool mirror;

  /// irisOnly keeps it to the iris and its highlight.
  final bool irisOnly;
  const Blob(this.c, this.r,
      {this.scale,
      this.t,
      this.rz = 0,
      this.mirror = false,
      this.irisOnly = false});

  Blob mirrored() => Blob(_v3(-c.x, c.y, c.z), r,
      scale: scale, t: t, rz: rz, mirror: true, irisOnly: irisOnly);

  @override
  String get key =>
      'b${_k(c)}|${_k(r)}|${_k(scale)}|${_k(t)}|$rz|$mirror|$irisOnly';
}

/// StrokeDeformer is one stroke of the sculpting brush (character_sculpt.dart):
/// the surface near the stroke raised or lowered along the way it faced
/// there, or pressed flat. Each spot is moved once, by the stroke's point
/// nearest it, so a stroke drawn slowly is no deeper than one drawn fast.
class StrokeDeformer extends Deformer {
  final SculptStroke stroke;

  /// side is -1 for the mirror image of a mirrored stroke.
  final double side;
  const StrokeDeformer(this.stroke, {this.side = 1});

  /// of are the deformers [strokes] make: each, and its mirror image.
  static List<StrokeDeformer> of(List<SculptStroke> strokes) => [
        for (final s in strokes)
          if (s.points.isNotEmpty) ...[
            StrokeDeformer(s),
            if (s.mirror) StrokeDeformer(s, side: -1),
          ]
      ];

  @override
  String get key => 's${stroke.key}|$side';
}

/// StretchBelow stretches everything below [y] down from it by [k].
class StretchBelow extends Deformer {
  final double y, k;
  const StretchBelow(this.y, this.k);
  @override
  String get key => 's$y|$k';
}

/// Radial makes a limb thicker or thinner round the line from [a] to [b],
/// for the vertices that follow [bones] most.
class Radial extends Deformer {
  final vm.Vector3 a, b;
  final Set<String> bones;
  final double k;
  const Radial(this.a, this.b, this.bones, this.k);
  @override
  String get key => 'r${_k(a)}|${_k(b)}|${bones.join(",")}|$k';
}

/// FootGrow grows a foot by [k] about the floor under its ankle [ankle], so
/// it stays on the floor and its toes reach further. Longer and wider by all
/// of [k] up to the ankle, fading over a band just above it, so a boot's
/// shaft is not stretched; and taller by a curve that is nought at the sole
/// and at the ankle, so nothing is pushed up past the ankle into the shaft.
/// Each depends on height alone, the same for the skin and a boot over it,
/// so the boot still covers the skin.
class FootGrow extends Deformer {
  final vm.Vector3 ankle;
  final double k, u;
  const FootGrow(this.ankle, this.k, this.u);
  @override
  String get key => 'f${_k(ankle)}|$k|$u';

  /// across is how much of the growth in length and width a point at
  /// height [y] takes.
  double across(double y) {
    // Whole up to the ankle -- the instep is below it -- and gone a little
    // above, where skin and boot both run upright, at the same heights.
    final t = ((ankle.y + 0.03 * u - y) / (0.03 * u)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// up is where a point at height [y] goes.
  double up(double y) =>
      y <= 0 || y >= ankle.y ? y : y + k * y * (1 - y / ankle.y);
}

/// Bum pushes the bum back along the line of the body seen from the side:
/// fuller above or below, rounder, lifted -- and only where the body faces
/// back.
class Bum extends Deformer {
  final vm.Vector3 c;
  final double h, w, back, u, size, round, upper, lower, lift, width;
  const Bum(this.c, this.h, this.w, this.back, this.u,
      {required this.size,
      required this.round,
      required this.upper,
      required this.lower,
      required this.lift,
      required this.width});
  @override
  String get key =>
      'u${_k(c)}|$h|$w|$back|$u|$size|$round|$upper|$lower|$lift|$width';
}

/// BoneChange is a bone moved from its place at rest, and drawn bigger or
/// smaller by [scale] (the same every way, so it turns as it did).
class BoneChange {
  final vm.Vector3 translation;
  final double scale;
  const BoneChange(this.translation, this.scale);
}

/// Proportions are the skeleton's changes: each bone changed, by name, and
/// how much bigger the whole character is.
class Proportions {
  final Map<String, BoneChange> bones;
  final double height;
  const Proportions(this.bones, this.height);
}

/// ShapeGroup is the primitives of one mesh that share their vertices and
/// are shaped alike, so are shaped once and drawn from one buffer.
class ShapeGroup {
  final VrmMeshNode node;
  final VrmVertices vertices;
  final bool iris;
  final List<int> primitives;

  /// used are the vertices any of them draws, and triangles their
  /// triangles, together.
  final Int32List used;
  final Uint32List triangles;
  ShapeGroup(this.node, this.vertices, this.iris, this.primitives, this.used,
      this.triangles);
}

/// Shaped is a group's vertices as shaped.
class Shaped {
  final Float32List positions, normals;
  const Shaped(this.positions, this.normals);
}

/// VroidBone names the VRoid bones the shaping moves.
abstract final class VroidBone {
  static const head = 'J_Bip_C_Head',
      neck = 'J_Bip_C_Neck',
      spine = 'J_Bip_C_Spine',
      chest = 'J_Bip_C_Chest';
  static const upperChest = 'J_Bip_C_UpperChest', hips = 'J_Bip_C_Hips';
  static String upperArm(String s) => 'J_Bip_${s}_UpperArm';
  static String lowerArm(String s) => 'J_Bip_${s}_LowerArm';
  static String hand(String s) => 'J_Bip_${s}_Hand';
  static String upperLeg(String s) => 'J_Bip_${s}_UpperLeg';
  static String lowerLeg(String s) => 'J_Bip_${s}_LowerLeg';
  static String foot(String s) => 'J_Bip_${s}_Foot';
}

/// VrmShapeRig is one body ready to shape: its mesh, where its features
/// are, and its primitives grouped.
class VrmShapeRig {
  final VrmMeshData data;
  final FaceLandmarks? face;
  final BodyPoints? body;
  final List<ShapeGroup> groups;

  VrmShapeRig._(this.data, this.face, this.body, this.groups);

  factory VrmShapeRig(VrmMeshData data) {
    final face = findFaceLandmarks(data);
    return VrmShapeRig._(
        data, face, findBodyPoints(data, face?.fwd ?? 1), _groupsOf(data));
  }

  static List<ShapeGroup> _groupsOf(VrmMeshData data) {
    final out = <ShapeGroup>[];
    for (final node in data.meshes) {
      final byKey = <(VrmVertices, bool), List<int>>{};
      for (var i = 0; i < node.primitives.length; i++) {
        final p = node.primitives[i];
        byKey.putIfAbsent((p.vertices, p.iris), () => []).add(i);
      }
      for (final e in byKey.entries) {
        final seen = Uint8List(e.key.$1.count);
        final tris = <int>[];
        for (final i in e.value) {
          final p = node.primitives[i];
          tris.addAll(p.indices);
          for (final v in p.used) {
            seen[v] = 1;
          }
        }
        out.add(ShapeGroup(
            node,
            e.key.$1,
            e.key.$2,
            e.value,
            Int32List.fromList([
              for (var i = 0; i < seen.length; i++)
                if (seen[i] == 1) i
            ]),
            Uint32List.fromList(tris)));
      }
    }
    return out;
  }

  /// deformers are the changes [s] makes to [region].
  List<Deformer> deformers(VrmRegion region, CharacterShape s) {
    final out = <Deformer>[];
    final L = face;
    double V(String p) => s.effective(p);
    void pair(Blob b) => out
      ..add(b)
      ..add(b.mirrored());
    final isFace = region == VrmRegion.face,
        isHair = region == VrmRegion.hair,
        isBody = region == VrmRegion.body;
    if (L != null && L.es > 0 && (isFace || isHair)) {
      final es = L.es, F = L.fwd;
      if (V('head.width') != 0) {
        out.add(Blob(_v3(0, L.eyeY, L.skinC.z), _v3(3 * es, 3.4 * es, 3 * es),
            scale: _v3(
                1 + 0.18 * V('head.width'), 1, 1 + 0.06 * V('head.width'))));
      }
      if (isHair) {
        final vol = V('hairShape.volume');
        if (vol != 0) {
          out.add(Blob(_v3(0, L.eyeY + 0.3 * es, L.skinC.z), _v3(9, 9, 9),
              scale: _v3(1 + 0.12 * vol, 1 + 0.06 * vol, 1 + 0.12 * vol)));
        }
        if (V('hairShape.length') != 0) {
          out.add(StretchBelow(L.eyeY, 1 + 0.55 * V('hairShape.length')));
        }
      }
      if (isFace) {
        if (V('face.length') != 0) {
          out.add(StretchBelow(L.eyeY, 1 + 0.14 * V('face.length')));
        }
        final fh = V('face.forehead');
        if (fh != 0) {
          out.add(Blob(_v3(0, L.eyeY + 0.75 * es, L.noseTip.z - F * 0.35 * es),
              _v3(1.1 * es, 0.5 * es, 0.8 * es),
              t: _v3(0, 0.05 * es * fh, F * 0.05 * es * fh)));
        }
        final cb = V('face.cheekbones');
        if (cb != 0) {
          pair(Blob(L.right.cheek + _v3(-0.12 * es, 0.15 * es, 0),
              _v3(0.35 * es, 0.3 * es, 0.4 * es),
              t: _v3(-0.05 * es * cb, 0.02 * es * cb, F * 0.03 * es * cb)));
        }
        final size = V('eyes.size') + 0.9 * V('figure.eyes'),
            round = V('eyes.round');
        if (size != 0 ||
            V('eyes.spacing') != 0 ||
            V('eyes.height') != 0 ||
            V('eyes.tilt') != 0 ||
            round != 0 ||
            V('eyes.depth') != 0) {
          final k = 1 + 0.32 * size;
          pair(Blob(L.eyeR, _v3(0.42 * es, 0.36 * es, 0.4 * es),
              scale: _v3(k * (1 - 0.08 * round), k * (1 + 0.25 * round),
                  math.sqrt(math.max(0.01, k))),
              t: _v3(
                  -0.09 * es * V('eyes.spacing'),
                  0.1 * es * V('eyes.height'),
                  -F * 0.05 * es * V('eyes.depth')),
              rz: -0.28 * V('eyes.tilt')));
        }
        if (V('eyes.iris') != 0) {
          final k = 1 + 0.3 * V('eyes.iris');
          pair(Blob(L.eyeR, _v3(0.5 * es, 0.5 * es, 0.5 * es),
              scale: _v3(k, k, 1), irisOnly: true));
        }
        if (V('brows.height') != 0 ||
            V('brows.angle') != 0 ||
            V('brows.thickness') != 0 ||
            V('brows.length') != 0) {
          pair(Blob(L.right.brow, _v3(0.5 * es, 0.2 * es, 0.4 * es),
              scale: _v3(1 + 0.3 * V('brows.length'),
                  1 + 0.5 * V('brows.thickness'), 1),
              t: _v3(0, 0.12 * es * V('brows.height'), 0),
              rz: -0.3 * V('brows.angle')));
        }
        if (V('nose.size') != 0 ||
            V('nose.length') != 0 ||
            V('nose.height') != 0 ||
            V('nose.width') != 0) {
          final k = 1 + 0.35 * V('nose.size');
          out.add(Blob(L.noseTip + _v3(0, 0.05 * es, -F * 0.12 * es),
              _v3(0.3 * es, 0.4 * es, 0.36 * es),
              scale: _v3(k * (1 + 0.35 * V('nose.width')), k, k),
              t: _v3(0, 0.08 * es * V('nose.height'),
                  F * 0.09 * es * V('nose.length'))));
        }
        if (V('nose.bridge') != 0) {
          out.add(Blob(_v3(0, L.eyeY - 0.18 * es, L.noseTip.z - F * 0.2 * es),
              _v3(0.2 * es, 0.32 * es, 0.3 * es),
              t: _v3(0, 0, F * 0.05 * es * V('nose.bridge'))));
        }
        if (V('nose.tip') != 0) {
          out.add(Blob(L.noseTip, _v3(0.16 * es, 0.16 * es, 0.2 * es),
              t: _v3(0, 0.06 * es * V('nose.tip'), 0)));
        }
        if (V('nose.nostrils') != 0) {
          out.add(Blob(L.noseTip + _v3(0, -0.05 * es, -F * 0.05 * es),
              _v3(0.26 * es, 0.12 * es, 0.22 * es),
              scale: _v3(1 + 0.4 * V('nose.nostrils'), 1, 1)));
        }
        if (V('mouth.width') != 0 ||
            V('mouth.height') != 0 ||
            V('mouth.size') != 0 ||
            V('mouth.lips') != 0) {
          final k = 1 + 0.3 * V('mouth.size');
          out.add(Blob(L.mouth, _v3(0.62 * es, 0.3 * es, 0.4 * es),
              scale: _v3(
                  k * (1 + 0.3 * V('mouth.width')),
                  k * (1 + 0.25 * V('mouth.lips')),
                  k * (1 + 0.4 * V('mouth.lips'))),
              t: _v3(0, 0.1 * es * V('mouth.height'), 0)));
        }
        if (V('mouth.upper') != 0) {
          out.add(Blob(L.mouth + _v3(0, 0.06 * es, 0),
              _v3(0.45 * es, 0.12 * es, 0.3 * es),
              scale: _v3(1, 1 + 0.35 * V('mouth.upper'), 1),
              t: _v3(0, 0, F * 0.03 * es * V('mouth.upper'))));
        }
        if (V('mouth.lower') != 0) {
          out.add(Blob(L.mouth + _v3(0, -0.07 * es, 0),
              _v3(0.45 * es, 0.13 * es, 0.3 * es),
              scale: _v3(1, 1 + 0.35 * V('mouth.lower'), 1),
              t: _v3(0, 0, F * 0.03 * es * V('mouth.lower'))));
        }
        if (V('mouth.corners') != 0) {
          pair(Blob(L.mouth + _v3(-0.27 * es, 0, -F * 0.03 * es),
              _v3(0.15 * es, 0.14 * es, 0.2 * es),
              t: _v3(0, 0.05 * es * V('mouth.corners'), 0)));
        }
        if (V('ears.size') != 0 || V('ears.out') != 0 || V('ears.point') != 0) {
          final k = 1 + 0.4 * V('ears.size');
          pair(Blob(L.right.ear, _v3(0.3 * es, 0.42 * es, 0.36 * es),
              scale: _v3(k, k, k), t: _v3(-0.08 * es * V('ears.out'), 0, 0)));
          final pt = V('ears.point');
          if (pt != 0) {
            pair(Blob(L.right.ear + _v3(0, 0.22 * es, -F * 0.05 * es),
                _v3(0.14 * es, 0.16 * es, 0.16 * es),
                t: _v3(-0.1 * es * pt, 0.22 * es * pt, -F * 0.06 * es * pt)));
          }
        }
        if (V('cheeks.fullness') != 0 || V('cheeks.height') != 0) {
          pair(Blob(L.right.cheek, _v3(0.45 * es, 0.42 * es, 0.42 * es),
              t: _v3(
                  -0.05 * es * V('cheeks.fullness'),
                  0.07 * es * V('cheeks.height'),
                  F * 0.05 * es * V('cheeks.fullness'))));
        }
        if (V('jaw.width') != 0) {
          pair(Blob(L.right.jaw, _v3(0.6 * es, 0.6 * es, 0.6 * es),
              t: _v3(-0.1 * es * V('jaw.width'), 0, 0)));
        }
        if (V('jaw.chin') != 0 ||
            V('jaw.forward') != 0 ||
            V('jaw.chinWidth') != 0) {
          out.add(Blob(L.chin, _v3(0.5 * es, 0.45 * es, 0.5 * es),
              scale: _v3(1 + 0.3 * V('jaw.chinWidth'), 1, 1),
              t: _v3(0, -0.12 * es * V('jaw.chin'),
                  F * 0.08 * es * V('jaw.forward'))));
        }
      }
    }
    final B = body;
    if (isBody && B != null) _bodyDeformers(out, B, s, pair);
    return out;
  }

  void _bodyDeformers(List<Deformer> out, BodyPoints B, CharacterShape s,
      void Function(Blob) pair) {
    double V(String p) => s.effective(p);
    final F = face?.fwd ?? 1, u = B.u, P = data.bindPos;
    final mus = V('body.muscle'), fat = V('muscle.fat');
    // The chest: the bust where the model has one, the pecs where not.
    final rb = B.bustC != null ? B.bustR : 0.1 * u, cc = B.chestR;
    final chest = V('body.chest') + 0.15 * fat;
    if (chest != 0) {
      pair(Blob(cc, _v3(rb, rb, rb),
          scale: _v3(1 + 0.25 * chest, 1 + 0.25 * chest, 1 + 0.45 * chest),
          t: _v3(0, 0, F * 0.02 * u * chest)));
    }
    if (V('chest.width') != 0) {
      pair(Blob(cc, _v3(rb * 1.1, rb, rb),
          scale: _v3(1 + 0.25 * V('chest.width'), 1, 1)));
    }
    if (V('chest.close') != 0) {
      pair(Blob(cc, _v3(rb * 1.15, rb * 1.1, rb * 1.1),
          t: _v3(-0.032 * u * V('chest.close'), 0, 0)));
    }
    final hang = V('chest.hang');
    if (hang != 0) {
      pair(Blob(cc + _v3(0, -0.25 * rb, F * 0.35 * rb),
          _v3(rb * 0.95, rb * 0.95, rb * 0.95),
          t: _v3(0, -0.045 * u * hang, -F * 0.008 * u * hang)));
      pair(Blob(cc + _v3(0, 0.45 * rb, F * 0.2 * rb),
          _v3(rb * 0.7, rb * 0.6, rb * 0.7),
          t: _v3(0, -0.01 * u * hang, -F * 0.016 * u * hang)));
    }
    final tip = B.bustTip ?? cc + _v3(0, 0, F * 0.4 * rb);
    final perk = V('chest.perk');
    if (perk != 0) {
      pair(Blob(tip, _v3(rb * 0.6, rb * 0.6, rb * 0.7),
          t: _v3(0, 0.012 * u * perk, F * 0.02 * u * perk),
          scale: _v3(1 - 0.1 * perk, 1 - 0.1 * perk, 1)));
    }
    if (V('chest.out') != 0) {
      pair(Blob(tip, _v3(rb * 0.75, rb * 0.75, rb * 0.8),
          t: _v3(0.028 * u * V('chest.out'), 0, 0)));
    }
    if (V('chest.upper') != 0) {
      pair(Blob(cc + _v3(0, 0.5 * rb, F * 0.3 * rb),
          _v3(rb * 0.75, rb * 0.6, rb * 0.7),
          t: _v3(0, 0.004 * u * V('chest.upper'),
              F * 0.02 * u * V('chest.upper'))));
    }
    // The bum, firmer and fuller with the glutes.
    final glutes = V('muscle.glutes');
    final firm = V('bum.firm') + 0.4 * glutes;
    final bum = (
      size: V('bum.size') + 0.25 * fat + 0.4 * glutes,
      round: V('bum.round') + 0.4 * firm,
      upper: V('bum.upper'),
      lower: V('bum.lower'),
      lift: V('bum.lift') + 0.5 * firm,
      width: V('bum.width') + 0.15 * fat,
    );
    if ([bum.size, bum.round, bum.upper, bum.lower, bum.lift, bum.width]
        .any((x) => x.abs() > 1e-4)) {
      out.add(Bum(B.bum, 0.085 * u, 0.06 * u, -F, u,
          size: bum.size,
          round: bum.round,
          upper: bum.upper,
          lower: bum.lower,
          lift: bum.lift,
          width: bum.width));
    }
    // Muscles, each a swelling where it lies; their shape stretches or
    // gathers them along the limb.
    final (along, amt) = switch (s.choice('muscle.shape')) {
      'long' => (1.35, 0.85),
      'round' => (0.95, 1.2),
      'peaked' => (0.7, 1.35),
      _ => (1.0, 1.0),
    };
    double M(String k) => (V('muscle.$k') + 0.6 * mus) * amt;
    vm.Vector3 lerp(vm.Vector3 a, vm.Vector3 b, double t) => a + (b - a) * t;
    final ua = P[VroidBone.upperArm('R')],
        la = P[VroidBone.lowerArm('R')],
        hd = P[VroidBone.hand('R')];
    final ul = P[VroidBone.upperLeg('R')],
        ll = P[VroidBone.lowerLeg('R')],
        ft = P[VroidBone.foot('R')],
        nk = P[VroidBone.neck];
    // VRM 1 puts the right side at -x; the pairs below are written for the
    // side at +x, as the shapes are measured outward from the middle.
    final sx = (ua?.x ?? -1) < 0 ? -1.0 : 1.0;
    vm.Vector3 out_(vm.Vector3 v) => _v3(v.x * sx, v.y, v.z);
    if (ua != null && la != null && hd != null) {
      final a = out_(ua), l = out_(la), h = out_(hd);
      if (M('shoulders') != 0) {
        pair(Blob(a + _v3(0.02 * u, 0.008 * u, 0),
            _v3(0.06 * u * along, 0.06 * u, 0.06 * u),
            scale: _v3(1 + 0.15 * M('shoulders'), 1 + 0.35 * M('shoulders'),
                1 + 0.35 * M('shoulders')),
            t: _v3(0.008 * u * M('shoulders'), 0.01 * u * M('shoulders'), 0)));
      }
      if (M('biceps') != 0) {
        pair(Blob(lerp(a, l, 0.55) + _v3(0, 0, F * 0.01 * u),
            _v3(0.07 * u * along, 0.04 * u, 0.04 * u),
            scale: _v3(1, 1 + 0.18 * M('biceps'), 1 + 0.25 * M('biceps')),
            t: _v3(0, 0.003 * u * M('biceps'), F * 0.02 * u * M('biceps'))));
      }
      if (M('triceps') != 0) {
        pair(Blob(lerp(a, l, 0.42) + _v3(0, 0, -F * 0.01 * u),
            _v3(0.08 * u * along, 0.036 * u, 0.036 * u),
            t: _v3(
                0, -0.003 * u * M('triceps'), -F * 0.016 * u * M('triceps'))));
      }
      if (M('forearms') != 0) {
        pair(Blob(lerp(l, h, 0.3), _v3(0.07 * u * along, 0.036 * u, 0.036 * u),
            scale: _v3(1, 1 + 0.25 * M('forearms'), 1 + 0.25 * M('forearms'))));
      }
    }
    if (M('pecs') != 0) {
      pair(Blob(B.pec, _v3(0.07 * u, 0.05 * u, 0.05 * u),
          scale: _v3(1 + 0.12 * M('pecs'), 1 + 0.05 * M('pecs'), 1),
          t: _v3(0, 0.003 * u * M('pecs'),
              F * 0.02 * u * M('pecs') * (B.bustC != null ? 0.4 : 1))));
    }
    if (M('back') != 0) {
      pair(Blob(_v3(0.09 * u, B.pec.y - 0.045 * u, B.pec.z - F * 0.05 * u),
          _v3(0.05 * u, 0.1 * u, 0.07 * u),
          t: _v3(0.03 * u * M('back'), 0, -F * 0.006 * u * M('back'))));
    }
    if (M('traps') != 0 && nk != null) {
      pair(Blob(nk + _v3(0.045 * u, -0.03 * u, -F * 0.01 * u),
          _v3(0.055 * u, 0.045 * u, 0.055 * u),
          t: _v3(0, 0.02 * u * M('traps'), 0)));
    }
    if (M('abs') != 0) {
      out.add(Blob(B.abs, _v3(0.08 * u, 0.1 * u, 0.05 * u),
          t: _v3(0, 0, F * 0.006 * u * M('abs'))));
    }
    if (ul != null && ll != null && M('quads') != 0) {
      pair(Blob(lerp(out_(ul), out_(ll), 0.45) + _v3(0, 0, F * 0.02 * u),
          _v3(0.05 * u, 0.12 * u * along, 0.05 * u),
          scale: _v3(1 + 0.18 * M('quads'), 1, 1 + 0.2 * M('quads')),
          t: _v3(0, 0, F * 0.02 * u * M('quads'))));
    }
    if (ll != null && ft != null && M('calves') != 0) {
      pair(Blob(lerp(out_(ll), out_(ft), 0.28) + _v3(0, 0, -F * 0.02 * u),
          _v3(0.04 * u, 0.08 * u * along, 0.045 * u),
          scale: _v3(1 + 0.25 * M('calves'), 1, 1 + 0.15 * M('calves')),
          t: _v3(0, 0, -F * 0.018 * u * M('calves'))));
    }
    // The belly button: a small dip, or a small rise for an outie.
    final navel = s.choice('navel.shape');
    if (navel != 'As made') {
      final sz = (0.5 + V('navel.size')) * u, rise = navel == 'outie' ? 1 : -1;
      final (rx, ry) = switch (navel) {
        'vertical' => (0.005, 0.012),
        'wide' => (0.011, 0.006),
        'outie' => (0.007, 0.007),
        _ => (0.007, 0.008)
      };
      out.add(Blob(B.navel, _v3(rx * sz * 1.6, ry * sz * 1.6, 0.012 * u),
          t: _v3(0, 0, F * rise * 0.006 * u * (0.4 + V('navel.depth')))));
    }
    // Body fat: a softer, fuller middle.
    if (fat != 0) {
      out.add(Blob(B.belly, _v3(0.15 * u, 0.12 * u, 0.14 * u),
          t: _v3(0, -0.006 * u * math.max(0, fat), F * 0.03 * u * fat)));
      out.add(Blob(B.waist, _v3(0.22 * u, 0.1 * u, 0.2 * u),
          scale: _v3(1 + 0.12 * fat, 1, 1 + 0.12 * fat)));
    }
    if (V('body.waist') != 0) {
      out.add(Blob(B.waist, _v3(0.22, 0.09, 0.2),
          scale:
              _v3(1 + 0.18 * V('body.waist'), 1, 1 + 0.18 * V('body.waist'))));
    }
    if (V('body.hips') != 0) {
      out.add(Blob(B.hips, _v3(0.3, 0.13, 0.25),
          scale: _v3(1 + 0.16 * V('body.hips'), 1, 1 + 0.12 * V('body.hips'))));
    }
    if (V('body.belly') != 0) {
      out.add(Blob(B.belly, _v3(0.15, 0.12, 0.14),
          t: _v3(0, 0, F * 0.035 * V('body.belly'))));
    }
    // Limbs thicker or thinner round their bones; muscle is all of them.
    void limb(String a, String b, double k) {
      final pa = P[a], pb = P[b];
      if (k != 0 && pa != null && pb != null) {
        out.add(Radial(pa, pb, {a}, 1 + k));
      }
    }

    for (final sd in const ['L', 'R']) {
      limb(
          VroidBone.upperArm(sd),
          VroidBone.lowerArm(sd),
          0.22 * V('arms.upper') +
              0.12 * mus +
              0.08 * fat +
              0.06 * (V('muscle.biceps') + V('muscle.triceps')));
      limb(
          VroidBone.lowerArm(sd),
          VroidBone.hand(sd),
          0.22 * V('arms.fore') +
              0.1 * mus +
              0.04 * fat +
              0.08 * V('muscle.forearms'));
      limb(
          VroidBone.upperLeg(sd),
          VroidBone.lowerLeg(sd),
          0.2 * V('legs.thigh') +
              0.08 * mus +
              0.08 * fat +
              0.1 * V('muscle.quads'));
      limb(
          VroidBone.lowerLeg(sd),
          VroidBone.foot(sd),
          0.22 * V('legs.calf') +
              0.1 * mus +
              0.04 * fat +
              0.08 * V('muscle.calves'));
    }
    limb(
        VroidBone.neck,
        VroidBone.head,
        0.25 * V('body.neckWidth') +
            0.06 * mus +
            0.08 * V('muscle.traps') +
            0.06 * fat);
    // Bigger or smaller feet, grown from the floor under the ankle.
    final feet = (1 + 0.25 * V('feet.size')) * (1 + 0.35 * V('figure.feet'));
    if ((feet - 1).abs() > 1e-4) {
      for (final sd in const ['L', 'R']) {
        final ft = P[VroidBone.foot(sd)];
        if (ft != null) out.add(FootGrow(ft, feet - 1, u));
      }
    }
  }

  /// shape is [g]'s vertices changed by [ds] (its region's deformers), or
  /// null when none of them touches it: it is as made.
  Shaped? shape(ShapeGroup g, List<Deformer> ds) {
    final vs = g.vertices, o = vs.positions, on = vs.normals;
    final a = Float32List.fromList(o);
    final moved = Uint8List(vs.count);
    var any = false;
    for (final d in ds) {
      if (d is Blob && d.irisOnly && !g.iris) continue;
      if (d is Radial) {
        if (!vs.skinned) continue;
        final ab = d.b - d.a, ab2 = ab.length2 == 0 ? 1.0 : ab.length2;
        final follows = Uint8List(g.node.jointNames.length);
        for (var j = 0; j < follows.length; j++) {
          if (d.bones.contains(g.node.jointNames[j])) follows[j] = 1;
        }
        for (final i in g.used) {
          final b = vs.domBone[i];
          if (b >= follows.length || follows[b] == 0) continue;
          final x = a[i * 3] - d.a.x,
              y = a[i * 3 + 1] - d.a.y,
              z = a[i * 3 + 2] - d.a.z;
          final t = ((x * ab.x + y * ab.y + z * ab.z) / ab2).clamp(0.0, 1.0);
          final cx = d.a.x + ab.x * t,
              cy = d.a.y + ab.y * t,
              cz = d.a.z + ab.z * t;
          a[i * 3] = cx + (a[i * 3] - cx) * d.k;
          a[i * 3 + 1] = cy + (a[i * 3 + 1] - cy) * d.k;
          a[i * 3 + 2] = cz + (a[i * 3 + 2] - cz) * d.k;
          moved[i] = 1;
          any = true;
        }
        continue;
      }
      if (d is StrokeDeformer) {
        if (_stroke(d, g, a, on, moved)) any = true;
        continue;
      }
      for (final i in g.used) {
        final x = a[i * 3], y = a[i * 3 + 1], z = a[i * 3 + 2];
        switch (d) {
          case StretchBelow():
            if (y < d.y) {
              a[i * 3 + 1] = d.y - (d.y - y) * d.k;
              moved[i] = 1;
              any = true;
            }
          case Bum():
            final h = (y - d.c.y) / d.h, wv = (x.abs() - d.c.x.abs()) / d.w;
            if (h < -1.8 || h > 1.6 || wv.abs() > 1.6) continue;
            final nb = d.back * on[i * 3 + 2], ns = on[i * 3].abs();
            if (nb < -0.1 && ns < 0.4) continue;
            double bell(double t, double w) => t.abs() >= w
                ? 0
                : math.pow(1 - (t / w) * (t / w), 2).toDouble();
            final across = bell(wv, 1.5),
                facing = ((nb + 0.1) / 0.6).clamp(0.0, 1.0);
            // A full curve over the middle, more above or below, a rounder
            // peak; lifting carries the curve up and tucks the fold under.
            // Above its fullest point it fades into the small of the back,
            // so there is no shelf.
            final hl = h - 0.2 * d.lift;
            final above = h > 0 ? bell(h, 1.15) : 1.0;
            var prof = 0.7 * d.size * bell(hl, 1.2) +
                d.upper * bell(hl - 0.35, 0.6) +
                d.lower * bell(hl + 0.45, 0.7) +
                d.round * bell(hl, 0.65) -
                0.3 * d.lift * bell(h + 1.05, 0.45);
            prof = prof.clamp(-1.1, 1.3) * above;
            final dz = d.back * d.u * 0.024 * prof * across * facing;
            final dy =
                d.u * 0.01 * d.lift * bell(h + 0.5, 0.8) * across * facing;
            final dx = x.sign *
                d.u *
                0.028 *
                d.width *
                bell(h, 1.3) *
                bell(wv - 0.7, 1.0) *
                math.max(ns, 0.3);
            if (dz == 0 && dy == 0 && dx == 0) continue;
            a[i * 3] = x + dx;
            a[i * 3 + 1] = y + dy;
            a[i * 3 + 2] = z + dz;
            moved[i] = 1;
            any = true;
          case Blob():
            final dx = (x - d.c.x) / d.r.x,
                dy = (y - d.c.y) / d.r.y,
                dz = (z - d.c.z) / d.r.z;
            final q = dx * dx + dy * dy + dz * dz;
            if (q >= 1) continue;
            final w = (1 - q) * (1 - q);
            var px = x - d.c.x, py = y - d.c.y, pz = z - d.c.z;
            final sc = d.scale;
            if (sc != null) {
              px *= sc.x;
              py *= sc.y;
              pz *= sc.z;
            }
            if (d.rz != 0) {
              final rz = d.mirror ? -d.rz : d.rz;
              final cs = math.cos(rz), sn = math.sin(rz);
              final qx = px * cs - py * sn;
              py = px * sn + py * cs;
              px = qx;
            }
            final t = d.t;
            final tx = t == null ? 0.0 : (d.mirror ? -t.x : t.x),
                ty = t?.y ?? 0.0,
                tz = t?.z ?? 0.0;
            a[i * 3] = x + w * (d.c.x + px + tx - x);
            a[i * 3 + 1] = y + w * (d.c.y + py + ty - y);
            a[i * 3 + 2] = z + w * (d.c.z + pz + tz - z);
            moved[i] = 1;
            any = true;
          case FootGrow():
            if ((x - d.ankle.x).abs() > 0.12 * d.u ||
                (z - d.ankle.z).abs() > 0.25 * d.u) {
              continue;
            }
            final w = d.across(y) * d.k, y2 = d.up(y);
            if (w == 0 && y2 == y) continue;
            a[i * 3] = x + (x - d.ankle.x) * w;
            a[i * 3 + 1] = y2;
            a[i * 3 + 2] = z + (z - d.ankle.z) * w;
            moved[i] = 1;
            any = true;
          case Radial():
          case StrokeDeformer():
            break;
        }
      }
    }
    if (!any) return null;
    return Shaped(a, _normals(g, a, moved));
  }

  /// _stroke moves what of [g] is near stroke [d], in [a]: the shape so far.
  /// True if it moved anything.
  static bool _stroke(StrokeDeformer d, ShapeGroup g, Float32List a,
      Float32List on, Uint8List moved) {
    final st = d.stroke, r = st.radius, r2 = r * r, sd = d.side;
    final pts = st.points;
    final n = pts.length;
    final px = Float64List(n), py = Float64List(n), pz = Float64List(n);
    final nx = Float64List(n), ny = Float64List(n), nz = Float64List(n);
    var lox = double.infinity, loy = double.infinity, loz = double.infinity;
    var hix = -double.infinity, hiy = -double.infinity, hiz = -double.infinity;
    for (var k = 0; k < n; k++) {
      final p = pts[k];
      px[k] = p.x * sd;
      py[k] = p.y;
      pz[k] = p.z;
      nx[k] = p.nx * sd;
      ny[k] = p.ny;
      nz[k] = p.nz;
      lox = math.min(lox, px[k]);
      loy = math.min(loy, py[k]);
      loz = math.min(loz, pz[k]);
      hix = math.max(hix, px[k]);
      hiy = math.max(hiy, py[k]);
      hiz = math.max(hiz, pz[k]);
    }
    lox -= r;
    loy -= r;
    loz -= r;
    hix += r;
    hiy += r;
    hiz += r;
    final depth = r * st.strength / 3;
    var any = false;
    for (final i in g.used) {
      final x = a[i * 3], y = a[i * 3 + 1], z = a[i * 3 + 2];
      if (x < lox || x > hix || y < loy || y > hiy || z < loz || z > hiz) {
        continue;
      }
      // The stroke's nearest point.
      var best = r2, k0 = -1;
      for (var k = 0; k < n; k++) {
        final dx = x - px[k], dy = y - py[k], dz = z - pz[k];
        final q = dx * dx + dy * dy + dz * dz;
        if (q < best) {
          best = q;
          k0 = k;
        }
      }
      if (k0 < 0) continue;
      // Only the side of the surface the brush was on: not the back of a
      // thin arm, or the far side of a finger.
      final facing =
          on[i * 3] * nx[k0] + on[i * 3 + 1] * ny[k0] + on[i * 3 + 2] * nz[k0];
      if (facing < 0) continue;
      final f0 = 1 - best / r2;
      final f = f0 * f0 * math.min(1.0, facing * 2);
      final double move;
      switch (st.tool) {
        case SculptTool.raise:
          move = depth * f;
        case SculptTool.lower:
          move = -depth * f;
        case SculptTool.flatten:
          // Toward the plane the surface was in where the stroke passed.
          final h = (x - px[k0]) * nx[k0] +
              (y - py[k0]) * ny[k0] +
              (z - pz[k0]) * nz[k0];
          move = -h * f * st.strength;
      }
      if (move == 0) continue;
      a[i * 3] = x + nx[k0] * move;
      a[i * 3 + 1] = y + ny[k0] * move;
      a[i * 3 + 2] = z + nz[k0] * move;
      moved[i] = 1;
      any = true;
    }
    return any;
  }

  /// _normals are the normals again where the shape moved, shared across
  /// texture seams, and the file's own everywhere else.
  static Float32List _normals(ShapeGroup g, Float32List a, Uint8List moved) {
    final vs = g.vertices, on = vs.normals;
    final na = Float32List.fromList(on);
    final acc = Float64List(vs.weldCount * 3),
        touched = Uint8List(vs.weldCount);
    for (final i in g.used) {
      if (moved[i] == 1) touched[vs.weld[i]] = 1;
    }
    final idx = g.triangles;
    for (var t = 0; t + 2 < idx.length; t += 3) {
      final i0 = idx[t], i1 = idx[t + 1], i2 = idx[t + 2];
      final w0 = vs.weld[i0], w1 = vs.weld[i1], w2 = vs.weld[i2];
      if (touched[w0] == 0 && touched[w1] == 0 && touched[w2] == 0) continue;
      final ax = a[i1 * 3] - a[i0 * 3],
          ay = a[i1 * 3 + 1] - a[i0 * 3 + 1],
          az = a[i1 * 3 + 2] - a[i0 * 3 + 2];
      final bx = a[i2 * 3] - a[i0 * 3],
          by = a[i2 * 3 + 1] - a[i0 * 3 + 1],
          bz = a[i2 * 3 + 2] - a[i0 * 3 + 2];
      final cx = ay * bz - az * by,
          cy = az * bx - ax * bz,
          cz = ax * by - ay * bx;
      for (final w in [w0, w1, w2]) {
        acc[w * 3] += cx;
        acc[w * 3 + 1] += cy;
        acc[w * 3 + 2] += cz;
      }
    }
    for (final i in g.used) {
      final w = vs.weld[i];
      if (touched[w] == 0) continue;
      var x = acc[w * 3], y = acc[w * 3 + 1], z = acc[w * 3 + 2];
      final l = math.sqrt(x * x + y * y + z * z);
      if (l < 1e-12) continue;
      x /= l;
      y /= l;
      z /= l;
      // Keep the made normal's side: a flipped winding must not turn it
      // inside out.
      if (x * on[i * 3] + y * on[i * 3 + 1] + z * on[i * 3 + 2] < 0) {
        x = -x;
        y = -y;
        z = -z;
      }
      na[i * 3] = x;
      na[i * 3 + 1] = y;
      na[i * 3 + 2] = z;
    }
    return na;
  }

  /// proportions are [s]'s changes to the skeleton: longer, wider, bigger,
  /// with the feet put back on the floor however the legs changed.
  Proportions proportions(CharacterShape s) {
    double V(String p) => s.effective(p);
    final bones = <String, BoneChange>{};
    void change(String name,
        {double pos = 1, double scale = 1, vm.Vector3? axes, double dy = 0}) {
      final b = data.bones[name];
      if (b == null) return;
      final t = axes != null
          ? _v3(b.translation.x * axes.x, b.translation.y * axes.y,
              b.translation.z * axes.z)
          : b.translation * pos;
      t.y += dy;
      if ((t - b.translation).length2 < 1e-14 && (scale - 1).abs() < 1e-9) {
        return;
      }
      bones[name] = BoneChange(t, scale);
    }

    final torso = 1 + 0.25 * V('body.torso') + 0.4 * V('figure.torso');
    change(VroidBone.head,
        pos: 1 + 0.6 * V('body.neck'),
        scale:
            (1 + 0.18 * V('head.size')) * math.pow(2, 0.9 * V('figure.head')));
    change(VroidBone.chest, pos: torso);
    change(VroidBone.upperChest, pos: torso);
    change(VroidBone.neck, pos: torso);
    change(VroidBone.spine, pos: 1 + 0.3 * V('figure.torso'));
    final arm = 1 + 0.18 * V('arms.length') + 0.35 * V('figure.arms');
    final leg = 1 + 0.18 * V('legs.length') + 0.4 * V('figure.legs');
    for (final sd in const ['L', 'R']) {
      // A sloping shoulder: the arm hangs lower from it.
      change(VroidBone.upperArm(sd),
          axes: _v3(
              1 +
                  0.35 * V('body.shoulders') +
                  0.07 * (V('muscle.shoulders') + V('muscle.back')),
              1,
              1),
          dy: -0.025 * V('body.slope'));
      change(VroidBone.lowerArm(sd), pos: arm);
      change(VroidBone.hand(sd),
          pos: arm,
          scale: (1 + 0.25 * V('hands.size')) * (1 + 0.35 * V('figure.hands')));
      for (final f in const ['Thumb', 'Index', 'Middle', 'Ring', 'Little']) {
        for (final j in const [2, 3]) {
          change('J_Bip_${sd}_$f$j', pos: 1 + 0.3 * V('hands.fingers'));
        }
      }
      change(VroidBone.upperLeg(sd),
          axes: _v3(1 + 0.25 * V('body.hips'), 1, 1));
      change(VroidBone.lowerLeg(sd), pos: leg);
      // The foot is grown in the mesh (FootGrow), not by its bone: a bone
      // drawn bigger would stretch a boot between the leg and the foot.
      change(VroidBone.foot(sd), pos: leg);
    }
    // Then the feet back on the floor exactly: the hips go up or down by
    // however far the foot now is from where it was made.
    final hips = data.bones[VroidBone.hips],
        restY = data.bindPos[VroidBone.foot('L')]?.y;
    if (hips != null && restY != null) {
      final fy = _modelY(VroidBone.foot('L'), bones);
      if (fy != null && (fy - restY).abs() > 1e-7) {
        final t = (bones[VroidBone.hips]?.translation ?? hips.translation)
            .clone()
          ..y += (restY - fy) / _scaleAbove(VroidBone.hips, bones);
        bones[VroidBone.hips] =
            BoneChange(t, bones[VroidBone.hips]?.scale ?? 1);
      }
    }
    return Proportions(bones, 1 + 0.12 * V('body.height'));
  }

  /// _transform is [name]'s transform at rest with [bones]' changes, in the
  /// space above the skeleton.
  vm.Matrix4? _transform(String name, Map<String, BoneChange> bones) {
    final b = data.bones[name];
    if (b == null) return null;
    final c = bones[name];
    final local = vm.Matrix4.compose(
        c?.translation ?? b.translation, b.rotation, b.scale * (c?.scale ?? 1));
    final up = b.parent == null ? null : _transform(b.parent!, bones);
    return up == null ? local : up * local as vm.Matrix4;
  }

  double? _modelY(String name, Map<String, BoneChange> bones) =>
      _transform(name, bones)?.getTranslation().y;

  /// _scaleAbove is how much bigger than made the bones above [name] draw
  /// it.
  double _scaleAbove(String name, Map<String, BoneChange> bones) {
    final p = data.bones[name]?.parent;
    if (p == null) return 1;
    final m = _transform(p, bones);
    return m == null ? 1 : m.getMaxScaleOnAxis();
  }
}

/// findFaceLandmarks finds where the face's features are, from the face's
/// own parts; null for a body with no face mesh.
FaceLandmarks? findFaceLandmarks(VrmMeshData data) {
  List<vm.Vector3> pts(VrmPart part) {
    final seen = <VrmVertices, Set<int>>{};
    final out = <vm.Vector3>[];
    for (final p in data.primitivesOf(VrmRegion.face, part)) {
      final done = seen.putIfAbsent(p.vertices, () => {});
      final pos = p.vertices.positions;
      for (final i in p.used) {
        if (done.add(i)) {
          out.add(_v3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]));
        }
      }
    }
    return out;
  }

  final eyes = pts(VrmPart.eyes),
      skin = pts(VrmPart.face),
      mouth = pts(VrmPart.mouth),
      brows = pts(VrmPart.brows);
  if (eyes.isEmpty || skin.isEmpty) return null;
  vm.Vector3 centroid(Iterable<vm.Vector3> l) {
    final s = vm.Vector3.zero();
    var n = 0;
    for (final v in l) {
      s.add(v);
      n++;
    }
    return s / math.max(1, n).toDouble();
  }

  final eyeR = centroid(eyes.where((v) => v.x < 0)),
      eyeL = centroid(eyes.where((v) => v.x > 0));
  final skinC = centroid(skin);
  final fwd = ((eyeR.z + eyeL.z) / 2 - skinC.z).sign == 0
      ? 1.0
      : ((eyeR.z + eyeL.z) / 2 - skinC.z).sign;
  final es = (eyeL.x - eyeR.x).abs();
  final eyeY = (eyeR.y + eyeL.y) / 2;
  vm.Vector3 front(List<vm.Vector3> l) =>
      l.reduce((b, v) => fwd * v.z > fwd * b.z ? v : b);
  vm.Vector3 lowest(List<vm.Vector3> l) =>
      l.reduce((b, v) => v.y < b.y ? v : b);
  final mouthC =
      mouth.isNotEmpty ? centroid(mouth) : _v3(0, eyeY - 0.9 * es, skinC.z);
  final mouthPt =
      _v3(mouthC.x, mouthC.y, (mouth.isNotEmpty ? front(mouth) : mouthC).z);
  final noseCands = skin
      .where((v) =>
          v.x.abs() < 0.12 * es &&
          v.y < eyeY - 0.1 * es &&
          v.y > mouthC.y + 0.1 * es)
      .toList();
  final noseTip = front(noseCands.isNotEmpty ? noseCands : skin).clone();
  // The chin's tip: the lowest point of the face that still faces forward,
  // not the underside of the jaw.
  final mid =
      skin.where((v) => v.x.abs() < 0.15 * es && v.y < mouthC.y).toList();
  final midOr = mid.isNotEmpty ? mid : skin;
  final deepest =
      midOr.fold<double>(0, (b, v) => math.max(b, fwd * (v.z - skinC.z)));
  final frontLow =
      midOr.where((v) => fwd * (v.z - skinC.z) > 0.6 * deepest).toList();
  final chin = lowest(frontLow.isNotEmpty ? frontLow : midOr).clone();
  FaceSide side(double s) {
    final ear = skin
        .where((v) => s * v.x > 0 && v.y < eyeY + 0.2 * es && v.y > mouthC.y)
        .toList();
    final earV = (ear.isNotEmpty ? ear : skin)
        .reduce((b, v) => s * v.x > s * b.x ? v : b)
        .clone();
    final cheekC = skin
        .where((v) =>
            s * v.x > 0.45 * es &&
            s * v.x < 0.9 * es &&
            v.y < eyeY - 0.15 * es &&
            v.y > mouthC.y)
        .toList();
    final cheek = front(cheekC.isNotEmpty ? cheekC : skin).clone();
    final jawC = skin
        .where((v) =>
            s * v.x > 0.45 * es &&
            s * v.x < 1.1 * es &&
            v.y < mouthC.y &&
            fwd * (v.z - skinC.z) > -0.2 * es)
        .toList();
    final jaw = lowest(jawC.isNotEmpty ? jawC : skin).clone();
    final bl = brows.where((v) => s * v.x > 0).toList();
    return FaceSide(
        earV,
        cheek,
        jaw,
        bl.isNotEmpty
            ? centroid(bl)
            : _v3(s * es / 2, eyeY + 0.35 * es, skinC.z));
  }

  final headTop = skin.reduce((b, v) => v.y > b.y ? v : b).clone();
  return FaceLandmarks(fwd, es, eyeY, eyeR, eyeL, mouthPt, noseTip, chin, skinC,
      headTop, side(-1), side(1));
}

/// findBodyPoints finds places on the body from its skin and its bones;
/// null for a body without the bones to find them by.
BodyPoints? findBodyPoints(VrmMeshData data, double F) {
  final P = data.bindPos;
  final up = P[VroidBone.upperChest] ?? P[VroidBone.chest],
      sp = P[VroidBone.spine],
      hp = P[VroidBone.hips];
  if (up == null || sp == null || hp == null) return null;
  final u = (P[VroidBone.upperLeg('L')]?.y ?? 0.95).abs() / 0.95;
  final skin = <double>[];
  final seen = <VrmVertices, Set<int>>{};
  for (final p in data.primitivesOf(VrmRegion.body, VrmPart.skin)) {
    final done = seen.putIfAbsent(p.vertices, () => {});
    for (final i in p.used) {
      if (done.add(i)) {
        skin.addAll([
          p.vertices.positions[i * 3],
          p.vertices.positions[i * 3 + 1],
          p.vertices.positions[i * 3 + 2]
        ]);
      }
    }
  }
  // The body's own surface: the front or back of it at a place, for putting
  // shapes where the body actually is.
  double? surf(double x, double y, double dir, [double? r]) {
    final rr = r ?? 0.022 * u;
    double? best;
    for (var i = 0; i < skin.length; i += 3) {
      if ((skin[i] - x).abs() > rr || (skin[i + 1] - y).abs() > rr) continue;
      final z = skin[i + 2];
      if (best == null || dir * F * z > dir * F * best) best = z;
    }
    return best;
  }

  final b1 = P['J_Sec_R_Bust1'], b2 = P['J_Sec_R_Bust2'];
  vm.Vector3? bustC, bustTip;
  var bustR = 0.0;
  if (b1 != null && b2 != null) {
    // On the side at +x, as every pair of shapes is measured outward from
    // the middle there.
    bustC = (b1 + b2) * 0.5
      ..x = ((b1.x + b2.x) / 2).abs();
    bustTip = b2.clone()..x = b2.x.abs();
    bustR = 0.05 * u + 0.6 * b1.distanceTo(b2);
  }
  // The bum's fullest point: the most rearward skin between the hips and
  // the tops of the thighs, off the middle.
  final ulR = P[VroidBone.upperLeg('R')] ?? _v3(0.08 * u, hp.y - 0.04, hp.z);
  List<double>? peak;
  for (var i = 0; i < skin.length; i += 3) {
    final x = skin[i].abs(), y = skin[i + 1], z = skin[i + 2];
    if (x < 0.02 * u ||
        x > 0.11 * u ||
        y < ulR.y - 0.14 * u ||
        y > hp.y + 0.04 * u) {
      continue;
    }
    if (peak == null || -F * z > -F * peak[2]) peak = [x, y, z];
  }
  final bum = peak != null
      ? _v3(peak[0], peak[1], peak[2])
      : _v3(ulR.x.abs() * 0.85, ulR.y - 0.035 * u, hp.z - F * 0.08 * u);
  final pecY = up.y - 0.03 * u,
      pecZ = surf(0.06 * u, pecY, 1) ?? up.z + F * 0.08 * u;
  final absZ = surf(0, sp.y, 1) ?? sp.z + F * 0.08 * u;
  final navelY = (sp.y + hp.y) / 2 + 0.008 * u;
  return BodyPoints(
    u,
    bustC,
    bustTip,
    bustR,
    bum,
    _v3(0.055 * u, pecY, pecZ - F * 0.025 * u),
    _v3(0, sp.y + 0.02 * u, absZ - F * 0.02 * u),
    _v3(0, navelY, surf(0, navelY, 1, 0.01 * u) ?? absZ),
    bustC?.clone() ?? up + _v3(0.055, -0.01, F * 0.08),
    sp + _v3(0, 0.02, 0),
    hp + _v3(0, -0.04, 0),
    sp + _v3(0, -0.02, F * 0.09),
  );
}

/// HairRole is what a piece of hair is: the fringe in front of the face, the
/// tails hanging well out to the sides, or the rest -- the back and sides.
enum HairRole { front, back, tails }

/// hairRoleOf says what [p], a primitive of hair, is, from where its strands
/// lie against the face [L]: tails reach out past the face and well below
/// the chin; the fringe stands in front of the face and does not reach far
/// below it.
HairRole hairRoleOf(VrmPrimitive p, FaceLandmarks L) {
  final es = L.es, F = L.fwd, pos = p.vertices.positions;
  if (p.used.isEmpty || es <= 0) return HairRole.back;
  var x = 0.0, y = 0.0, z = 0.0, fz = double.negativeInfinity;
  var y0 = double.infinity, y1 = double.negativeInfinity;
  for (final i in p.used) {
    final px = pos[i * 3], py = pos[i * 3 + 1], pz = pos[i * 3 + 2];
    x += px.abs();
    y += py;
    z += pz;
    y0 = math.min(y0, py);
    y1 = math.max(y1, py);
    fz = math.max(fz, F * (pz - L.skinC.z));
  }
  final n = p.used.length;
  x /= n;
  y /= n;
  z /= n;
  final cz = F * (z - L.skinC.z);
  if (x > 1.3 * es && y0 < L.chin.y - 0.3 * es && y1 - y0 > 2 * es) {
    return HairRole.tails;
  }
  if (fz > 0.15 * es &&
      cz > -0.3 * es &&
      y > L.eyeY - 1.1 * es &&
      y0 > L.chin.y - 0.6 * es) {
    return HairRole.front;
  }
  return HairRole.back;
}
