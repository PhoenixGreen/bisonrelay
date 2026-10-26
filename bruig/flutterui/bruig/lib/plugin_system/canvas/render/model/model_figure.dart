import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/model_math.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';

// model_figure.dart poses a character from a file the way the drawn
// figure is posed: from the same rig, so pins, keyframes, motions and lip
// sync move it with nothing of their own.
//
// Posing is by pointing. Each bone the rig has -- the spine, the arms, the
// legs -- is turned, in the model's own skeleton, by the least it takes to
// point the way the rig's bone points; the head is turned as the rig's head
// is. Whatever the model was made standing in -- a T, an A, arms down -- it
// ends up where the rig says, and a bone the rig has not got (a finger, a
// ponytail) is carried along by the one it hangs from.

/// CanvasModelSource hands the renderer 3D models, as CanvasImageSource
/// hands it pictures: null while one is being read, and a notification
/// when it arrives.
abstract interface class CanvasModelSource {
  /// resolveModel is the stored model [mediaId] read and ready to pose, or
  /// null while it is being read -- or when it cannot be.
  LoadedModel? resolveModel(String mediaId);
}

/// loadModel reads [bytes] -- a .glb, .gltf or .vrm -- off the main
/// thread, and decodes its pictures. It throws a GltfError for a file it
/// cannot read.
Future<LoadedModel> loadModel(Uint8List bytes) async {
  var gltf = await Isolate.run(() => parseGltf(bytes));
  var images = <ui.Image?>[];
  for (var data in gltf.images) {
    ui.Image? image;
    if (data != null) {
      try {
        var codec = await ui.instantiateImageCodec(data);
        image = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {
        // A picture that will not decode leaves its material its colour.
      }
    }
    images.add(image);
  }
  return LoadedModel.of(gltf, images);
}

/// ModelJoint is a joint of a model as it is drawn: where on the page,
/// and how near the reader.
typedef ModelJoint = ({ui.Offset page, double depth});

/// _Segment is a bone of the rig, and the bone of the model's skeleton
/// that takes its direction: from [from] to [to] in the rig, and from the
/// model's [bone] to [tip].
typedef _Segment = ({RigJoint from, RigJoint to, HumanBone bone, HumanBone tip});

/// LoadedModel is a model file read, with its pictures decoded and what
/// posing it needs worked out once.
class LoadedModel {
  final Gltf gltf;
  final List<ui.Image?> images;

  /// _fix turns the whole model to face the reader with y up, as glTF
  /// means a model to and some are not.
  final Mat4 _fix;

  /// _rest is every node's place standing as it was made, after [_fix].
  final List<Mat4> _rest;
  final List<_Segment> _segments;

  /// height is how tall the model stands as made, and floor, hipsX and
  /// hipsZ where its feet and its middle are -- in the file's units.
  final double height, floor, hipsX, hipsZ;

  /// _joints is which of the model's bones stands for each of the rig's
  /// joints -- the rig's left being the model's right.
  final Map<RigJoint, HumanBone> _joints;

  /// _drawn is the last few posings drawn, so a frame drawn again -- the
  /// stage repainting under a pointer, a row of tiles -- is not skinned
  /// again. Newest last.
  final Map<String, (ui.Offset, List<MeshPiece>)> _drawn = {};

  LoadedModel._(this.gltf, this.images, this._fix, this._rest, this._segments,
      this.height, this.floor, this.hipsX, this.hipsZ, this._joints);

  void dispose() {
    for (var i in images) {
      i?.dispose();
    }
  }

  /// humanoid is whether a human skeleton was found in it: one that can
  /// be posed. A model without one is drawn standing as it was made.
  bool get humanoid => _segments.isNotEmpty;

  factory LoadedModel.of(Gltf gltf, List<ui.Image?> images) {
    var h = gltf.humanoid;
    var raw = gltf.world();
    // glTF says a model faces +z, its left arm towards +x. VRM 0 faces the
    // other way, and so do some exports; the arms say which it is.
    var backwards = gltf.facesBack;
    if (h[HumanBone.leftUpperArm] case var l?) {
      if (h[HumanBone.rightUpperArm] case var r?) {
        backwards = raw[l].translation[0] < raw[r].translation[0];
      }
    }
    var fix = backwards
        ? Mat4.trs(const [0, 0, 0], const Quat(0, 1, 0, 0), const [1, 1, 1])
        : Mat4.identity();
    var rest = [for (var m in raw) fix * m];

    // The rig's left is the page's left as it faces the reader, which is
    // the model's right; worked out from where the arms are rather than
    // from their names, in case a name is wrong.
    var segments = <_Segment>[];
    void add(RigJoint from, RigJoint to, HumanBone bone, HumanBone tip) {
      if (h.containsKey(bone) && h.containsKey(tip)) {
        segments.add((from: from, to: to, bone: bone, tip: tip));
      }
    }

    var spine = h.containsKey(HumanBone.spine) ? HumanBone.spine : HumanBone.chest;
    add(RigJoint.hips, RigJoint.neck, spine, HumanBone.neck);
    var leftIsRigLeft = false;
    if (h[HumanBone.leftUpperArm] case var l?) {
      leftIsRigLeft = rest[l].translation[0] < (rest[h[HumanBone.hips] ?? l].translation[0]);
    }
    var (aL, aR) = leftIsRigLeft
        ? (_left, _right)
        : (_right, _left);
    var joints = <RigJoint, HumanBone>{
      RigJoint.hips: HumanBone.hips,
      RigJoint.chest: HumanBone.neck,
      RigJoint.neck: HumanBone.neck,
      RigJoint.head: HumanBone.head,
    };
    for (var (side, rig) in [(aL, _rigLeft), (aR, _rigRight)]) {
      for (var k = 0; k < 6; k++) {
        joints[rig[k]] = side[k];
      }
      add(rig[0], rig[1], side[0], side[1]);
      add(rig[1], rig[2], side[1], side[2]);
      add(rig[3], rig[4], side[3], side[4]);
      add(rig[4], rig[5], side[4], side[5]);
    }
    // Put in skeleton order, parents before children, so a bone is turned
    // after the one it hangs from.
    int depthOf(int n) {
      var d = 0;
      for (var p = gltf.nodes[n].parent; p >= 0; p = gltf.nodes[p].parent) {
        d++;
      }
      return d;
    }

    segments.sort((a, b) => depthOf(h[a.bone]!).compareTo(depthOf(h[b.bone]!)));

    // How tall it stands, from its meshes as made.
    var lo = double.infinity, hi = -double.infinity;
    for (var (_, points) in _skinned(gltf, rest, const {})) {
      for (var i = 1; i < points.length; i += 3) {
        lo = math.min(lo, points[i]);
        hi = math.max(hi, points[i]);
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    }
    var hips = h[HumanBone.hips];
    var hp = hips == null ? const [0.0, 0.0, 0.0] : rest[hips].translation;
    joints.removeWhere((_, b) => !h.containsKey(b));
    return LoadedModel._(gltf, images, fix, rest, segments,
        math.max(1e-6, hi - lo), lo, hp[0], hp[2], joints);
  }

  /// pieces is the model posed as [rig] is, with [face]'s expression, its
  /// feet on the bottom of [box] and as tall as the box -- in pixels from
  /// the middle of the box's bottom, which is returned with them.
  /// [lift] is how far it is off the ground, in pixels: a jump.
  (ui.Offset, List<MeshPiece>) pieces(
      CharacterRig rig, CharacterFace face, ui.Rect box,
      {double lift = 0}) {
    var key = _keyOf(rig, face, box, lift);
    if (_drawn.remove(key) case var kept?) return _drawn[key] = kept;
    var made = _pieces(rig, face, box, lift);
    _drawn[key] = made;
    if (_drawn.length > 12) _drawn.remove(_drawn.keys.first);
    return made;
  }

  static String _keyOf(
      CharacterRig rig, CharacterFace face, ui.Rect box, double lift) {
    var b = StringBuffer()
      ..write(box)
      ..write(lift)
      ..write(rig.yaw)
      ..write(rig.tilt)
      ..write(rig.headBasis)
      ..write(face.toJson());
    for (var v in rig.joints3.values) {
      b.write(v);
    }
    return b.toString();
  }

  /// _onPage is where a point of the model, posed, is drawn: turned with
  /// the body, sized to [box] and stood on its bottom -- as x, y down the
  /// page, and z towards the reader, in pixels.
  List<double> _onPage(List<double> p, CharacterRig rig, ui.Rect box,
      double lift) {
    var v = _seen(rig)(p[0], p[1], p[2], box.height / height, lift);
    return [box.bottomCenter.dx + v[0], box.bottom - v[1], v[2]];
  }

  /// _seen is how a point of the model is seen as [rig] is: turned with
  /// the body and tipped about its feet, sized by s and lifted by lift --
  /// x across, y up from the ground, z towards the reader, in pixels.
  /// With s nought, a direction: turned and tipped only.
  List<double> Function(double x, double y, double z, double s, double lift)
      _seen(CharacterRig rig) {
    var yaw = rig.yaw * math.pi / 180, tilt = rig.tilt * math.pi / 180;
    var cy = math.cos(yaw), sy = math.sin(yaw);
    var ct = math.cos(tilt), st = math.sin(tilt);
    return (x, y, z, s, lift) {
      double up, near, across;
      if (s == 0) {
        across = x * cy - z * sy;
        near = x * sy + z * cy;
        up = y;
      } else {
        x -= hipsX;
        z -= hipsZ;
        across = (x * cy - z * sy) * s;
        near = (x * sy + z * cy) * s;
        up = (y - floor) * s + lift;
      }
      return [across, up * ct - near * st, up * st + near * ct];
    };
  }

  /// joints is where each of the rig's joints is on the model, posed as
  /// [rig] and [face] say, on the page -- what a pin is drawn on and
  /// taken hold of. The head is its middle, as the rig's is. Empty for a
  /// model with no human skeleton.
  Map<RigJoint, ModelJoint> joints(
      CharacterRig rig, CharacterFace face, ui.Rect box,
      {double lift = 0}) {
    if (!humanoid) return const {};
    var world = _worldWith(_pose(rig, face));
    var out = <RigJoint, ModelJoint>{};
    for (var e in _joints.entries) {
      var p = world[gltf.humanoid[e.value]!].translation;
      if (e.key == RigJoint.head) {
        // The head bone is at the bottom of the skull; its middle is as far
        // above it again as the neck is long.
        if (gltf.humanoid[HumanBone.neck] case var n?) {
          var q = world[n].translation;
          p = [for (var k = 0; k < 3; k++) p[k] + (p[k] - q[k])];
        }
      }
      var at = _onPage(p, rig, box, lift);
      out[e.key] = (page: ui.Offset(at[0], at[1]), depth: at[2]);
    }
    return out;
  }

  /// _pieces is [pieces], worked out.
  (ui.Offset, List<MeshPiece>) _pieces(
      CharacterRig rig, CharacterFace face, ui.Rect box, double lift) {
    var turns = _pose(rig, face);
    var world = _worldWith(turns);
    var weights = _expressionWeights(face);
    var s = box.height / height;
    var seen = _seen(rig);
    var out = <MeshPiece>[];
    for (var (n, node) in gltf.nodes.indexed) {
      var mi = node.mesh;
      if (mi == null || mi >= gltf.meshes.length) continue;
      var mesh = gltf.meshes[mi];
      for (var prim in mesh.primitives) {
        var (p, nrm) = _skinPrimitive(gltf, world, n, node, prim, weights[mi]);
        var count = p.length ~/ 3;
        var points = Float32List(count * 3);
        var normals = nrm == null ? null : Float32List(count * 3);
        for (var i = 0; i < count; i++) {
          var v = seen(p[i * 3], p[i * 3 + 1], p[i * 3 + 2], s, lift);
          points[i * 3] = v[0];
          points[i * 3 + 1] = v[1];
          points[i * 3 + 2] = v[2];
          if (normals != null) {
            var d = seen(nrm![i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2], 0, 0);
            normals[i * 3] = d[0];
            normals[i * 3 + 1] = d[1];
            normals[i * 3 + 2] = d[2];
          }
        }
        var mat = prim.material != null && prim.material! < gltf.materials.length
            ? gltf.materials[prim.material!]
            : null;
        var c = mat?.color ?? const [1.0, 1.0, 1.0, 1.0];
        var image = mat?.image != null && mat!.image! < images.length
            ? images[mat.image!]
            : null;
        out.add(MeshPiece(
          points: points,
          normals: normals,
          uvs: image == null ? null : prim.uvs,
          colors: prim.colors,
          indices: prim.indices,
          color: ui.Color.from(alpha: c[3], red: c[0], green: c[1], blue: c[2]),
          image: image,
          doubleSided: mat?.doubleSided ?? false,
        ));
      }
    }
    return (box.bottomCenter, out);
  }

  /// boneAt is where [bone] is when posed as [rig] and [face] say, in the
  /// model's own units, facing the reader, before the body's turn -- or
  /// null when the model has no such bone.
  List<double>? boneAt(CharacterRig rig, CharacterFace face, HumanBone bone) {
    var n = gltf.humanoid[bone];
    if (n == null) return null;
    return _worldWith(_pose(rig, face))[n].translation;
  }

  List<Mat4> _worldWith(Map<int, Quat> turns) =>
      [for (var m in gltf.world(turns)) _fix * m];

  /// _pose is the turn each of the model's bones needs, against its
  /// parent, to stand as [rig] does.
  Map<int, Quat> _pose(CharacterRig rig, CharacterFace face) {
    var turns = <int, Quat>{};
    if (!humanoid) return turns;
    var h = gltf.humanoid;
    var j = rig.joints3;
    Quat parentTurn(List<Mat4> world, int n) {
      var p = gltf.nodes[n].parent;
      return p < 0 ? _fix.rotation : world[p].rotation;
    }

    for (var seg in _segments) {
      var world = _worldWith(turns);
      var n = h[seg.bone]!, tip = h[seg.tip]!;
      var a = j[seg.from], b = j[seg.to];
      if (a == null || b == null) continue;
      // The rig's y runs down the page, the model's up.
      var want = [b[0] - a[0], -(b[1] - a[1]), b[2] - a[2]];
      if (length(want) < 1e-9) continue;
      var now = _minus(world[tip].translation, world[n].translation);
      if (length(now) < 1e-9) continue;
      var turned = Quat.between(now, want) * world[n].rotation;
      turns[n] = (parentTurn(world, n).conjugate * turned).normalized;
    }

    // The head, turned as the rig turns it and as the face turns and nods
    // it, from how it stood as made.
    if (h[HumanBone.head] case var head?) {
      var world = _worldWith(turns);
      var q = _headTurn(rig.headBasis, face);
      var turned = q * _rest[head].rotation;
      turns[head] = (parentTurn(world, head).conjugate * turned).normalized;
      // And the eyes where the face looks.
      var look = _look(face);
      for (var eye in [HumanBone.leftEye, HumanBone.rightEye]) {
        var e = h[eye];
        if (e == null) continue;
        var w = _worldWith(turns);
        var t = q * look * _rest[e].rotation;
        turns[e] = (parentTurn(w, e).conjugate * t).normalized;
      }
    }
    return turns;
  }

  /// _expressionWeights is how far each mesh's face shapes are turned on
  /// for [face], mesh by mesh.
  Map<int, Float64List> _expressionWeights(CharacterFace face) {
    var out = <int, Float64List>{};
    for (var (i, m) in gltf.meshes.indexed) {
      var count = m.primitives.isEmpty ? 0 : m.primitives.first.targets.length;
      if (count == 0) continue;
      var w = Float64List(count);
      for (var t = 0; t < count && t < m.weights.length; t++) {
        w[t] = m.weights[t];
      }
      out[i] = w;
    }
    if (out.isEmpty) return out;
    for (var e in expressionsOf(face).entries) {
      for (var bind in gltf.expressions[e.key] ?? const <ExpressionBind>[]) {
        var w = out[bind.mesh];
        if (w == null || bind.target >= w.length) continue;
        w[bind.target] = (w[bind.target] + bind.weight * e.value).clamp(0.0, 1.0);
      }
    }
    return out;
  }
}

const _left = [
  HumanBone.leftUpperArm,
  HumanBone.leftLowerArm,
  HumanBone.leftHand,
  HumanBone.leftUpperLeg,
  HumanBone.leftLowerLeg,
  HumanBone.leftFoot,
];
const _right = [
  HumanBone.rightUpperArm,
  HumanBone.rightLowerArm,
  HumanBone.rightHand,
  HumanBone.rightUpperLeg,
  HumanBone.rightLowerLeg,
  HumanBone.rightFoot,
];
const _rigLeft = [
  RigJoint.shoulderL,
  RigJoint.elbowL,
  RigJoint.wristL,
  RigJoint.hipL,
  RigJoint.kneeL,
  RigJoint.ankleL,
];
const _rigRight = [
  RigJoint.shoulderR,
  RigJoint.elbowR,
  RigJoint.wristR,
  RigJoint.hipR,
  RigJoint.kneeR,
  RigJoint.ankleR,
];

List<double> _minus(List<double> a, List<double> b) =>
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

/// _headTurn is the rig's head turn -- [basis], in its space -- with the
/// face's turn and nod on it, as a turn in the model's space.
Quat _headTurn(List<double> basis, CharacterFace face) {
  // The face's turn round the head's own up, then its nod round its own
  // across -- in the rig's space, y down.
  var t = face[FaceControl.turn] * math.pi / 180;
  var n = face[FaceControl.nod] * math.pi / 180;
  var ct = math.cos(t), st = math.sin(t), cn = math.cos(n), sn = math.sin(n);
  var yaw = [ct, 0.0, -st, 0.0, 1.0, 0.0, st, 0.0, ct];
  var nod = [1.0, 0.0, 0.0, 0.0, cn, sn, 0.0, -sn, cn];
  var m = _mul3(_mul3(basis, yaw), nod);
  // Into the model's space -- y flipped -- which is m with its y row and
  // column negated.
  var f = [
    m[0], -m[1], m[2], //
    -m[3], m[4], -m[5],
    m[6], -m[7], m[8],
  ];
  var mat = Mat4(Float64List.fromList([
    f[0], f[3], f[6], 0, //
    f[1], f[4], f[7], 0,
    f[2], f[5], f[8], 0,
    0, 0, 0, 1,
  ]));
  return mat.rotation;
}

/// _look is the eyes' turn for where [face] looks.
Quat _look(CharacterFace face) {
  var across = face[FaceControl.lookX] * 0.35;
  var up = face[FaceControl.lookY] * 0.25;
  // Round y to look across, then round x to look up.
  var qy = Quat(0, math.sin(across / 2), 0, math.cos(across / 2));
  var qx = Quat(math.sin(-up / 2), 0, 0, math.cos(-up / 2));
  return qy * qx;
}

List<double> _mul3(List<double> a, List<double> b) => [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
    ];

/// expressionsOf is the VRM expressions -- happy, blink, aa and the rest --
/// that make [face], and how far each.
Map<String, double> expressionsOf(CharacterFace face) {
  var out = <String, double>{};
  void put(String name, double w) {
    if (w <= 0.001) return;
    out[name] = ((out[name] ?? 0) + w).clamp(0.0, 1.0);
  }

  var smile = face[FaceControl.smile];
  put("happy", smile);
  put("sad", -smile + face[FaceControl.browWorry] * 0.5);
  put("angry", face[FaceControl.browSqueeze]);
  put("surprised", face[FaceControl.browRaise] * 0.7);
  put("blink", 1 - face[FaceControl.eyesOpen] + face[FaceControl.squint] * 0.4);
  // The mouth: its shape when one is keyed -- speech -- and its controls
  // otherwise.
  switch (face.mouth) {
    case MouthShape.rest:
      put("aa", face[FaceControl.jaw]);
      var wide = face[FaceControl.wide];
      put("ih", wide * 0.6);
      put("ou", -wide * 0.8);
    case MouthShape.closed:
      break;
    case MouthShape.teeth:
      put("ih", 0.7);
    case MouthShape.open:
      put("ee", 0.6);
      put("aa", 0.35);
    case MouthShape.wide:
      put("aa", 1);
    case MouthShape.round:
      put("oh", 0.9);
    case MouthShape.pucker:
      put("ou", 1);
    case MouthShape.lip:
      put("ih", 0.3);
    case MouthShape.tongue:
      put("aa", 0.45);
  }
  return out;
}

/// _skinned is every mesh of [gltf] as it stands in [world], node by node.
Iterable<(int, Float32List)> _skinned(
    Gltf gltf, List<Mat4> world, Map<int, Float64List> weights) sync* {
  for (var (n, node) in gltf.nodes.indexed) {
    var mi = node.mesh;
    if (mi == null || mi >= gltf.meshes.length) continue;
    for (var prim in gltf.meshes[mi].primitives) {
      yield (n, _skinPrimitive(gltf, world, n, node, prim, weights[mi]).$1);
    }
  }
}

/// _skinPrimitive is [prim]'s points and normals as it stands: its face
/// shapes laid on, then hung from its skeleton's bones in [world] -- or,
/// with no skeleton, placed where its node is.
(Float32List, Float32List?) _skinPrimitive(Gltf gltf, List<Mat4> world, int n,
    GltfNode node, GltfPrimitive prim, Float64List? weights) {
  var count = prim.vertexCount;
  var base = prim.positions;
  var src = base;
  if (weights != null && prim.targets.isNotEmpty) {
    src = Float32List.fromList(base);
    for (var t = 0; t < prim.targets.length && t < weights.length; t++) {
      var w = weights[t];
      if (w == 0) continue;
      var d = prim.targets[t];
      for (var i = 0; i < src.length && i < d.length; i++) {
        src[i] += d[i] * w;
      }
    }
  }
  var out = Float32List(count * 3);
  var normals = prim.normals;
  var outN = normals == null ? null : Float32List(count * 3);
  var skin = node.skin != null && node.skin! < gltf.skins.length
      ? gltf.skins[node.skin!]
      : null;
  var joints = prim.joints, jw = prim.weights;
  if (skin == null || joints == null || jw == null) {
    var m = world[n];
    for (var i = 0; i < count; i++) {
      var p = m.point(src[i * 3], src[i * 3 + 1], src[i * 3 + 2]);
      out[i * 3] = p[0];
      out[i * 3 + 1] = p[1];
      out[i * 3 + 2] = p[2];
      if (outN != null) {
        var d = m.direction(normals![i * 3], normals[i * 3 + 1], normals[i * 3 + 2]);
        _putUnit(outN, i, d[0], d[1], d[2]);
      }
    }
    return (out, outN);
  }
  // Each bone's matrix once, then each point a weighted mix of them.
  var mats = [
    for (var (k, j) in skin.joints.indexed)
      (j < world.length ? world[j] : Mat4.identity()) *
          (k < skin.inverseBind.length ? skin.inverseBind[k] : Mat4.identity()),
  ];
  for (var i = 0; i < count; i++) {
    var x = src[i * 3], y = src[i * 3 + 1], z = src[i * 3 + 2];
    double px = 0, py = 0, pz = 0, nx = 0, ny = 0, nz = 0, total = 0;
    for (var k = 0; k < 4; k++) {
      var w = jw[i * 4 + k];
      if (w <= 0) continue;
      var ji = joints[i * 4 + k];
      if (ji >= mats.length) continue;
      var m = mats[ji].m;
      px += w * (m[0] * x + m[4] * y + m[8] * z + m[12]);
      py += w * (m[1] * x + m[5] * y + m[9] * z + m[13]);
      pz += w * (m[2] * x + m[6] * y + m[10] * z + m[14]);
      if (normals != null) {
        var a = normals[i * 3], b = normals[i * 3 + 1], c = normals[i * 3 + 2];
        nx += w * (m[0] * a + m[4] * b + m[8] * c);
        ny += w * (m[1] * a + m[5] * b + m[9] * c);
        nz += w * (m[2] * a + m[6] * b + m[10] * c);
      }
      total += w;
    }
    if (total <= 0) {
      px = x;
      py = y;
      pz = z;
    } else if ((total - 1).abs() > 1e-3) {
      px /= total;
      py /= total;
      pz /= total;
    }
    out[i * 3] = px;
    out[i * 3 + 1] = py;
    out[i * 3 + 2] = pz;
    if (outN != null) _putUnit(outN, i, nx, ny, nz);
  }
  return (out, outN);
}

void _putUnit(Float32List out, int i, double x, double y, double z) {
  var l = math.sqrt(x * x + y * y + z * z);
  if (l == 0) l = 1;
  out[i * 3] = x / l;
  out[i * 3 + 1] = y / l;
  out[i * 3 + 2] = z / l;
}
