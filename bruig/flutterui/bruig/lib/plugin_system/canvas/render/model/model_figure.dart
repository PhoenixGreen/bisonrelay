import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
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

  /// outlineWidth is the widest outline its materials ask for, in the
  /// file's units, and outlineColour its colour -- what a VRM drawn in
  /// toon shading is outlined with.
  double get outlineWidth => gltf.materials.fold(
      0.0, (w, m) => math.max(w, m.mtoon?.outlineWidth ?? 0));

  ui.Color get outlineColour {
    for (var m in gltf.materials) {
      if (m.mtoon case var t? when t.outlineWidth > 0) {
        return ui.Color.from(
            alpha: 1, red: t.outlineColor[0], green: t.outlineColor[1], blue: t.outlineColor[2]);
      }
    }
    return const ui.Color(0xFF1A1A1A);
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
    // Kept by the size it is drawn at, not where: a figure dragged across
    // the page is the same pieces, stood somewhere else.
    var key = _keyOf(rig, face, box, lift);
    if (_drawn.remove(key) case var kept?) {
      _drawn[key] = kept;
      return (box.bottomCenter, kept.$2);
    }
    var made = CanvasPerf.time("character3dPose", () => _pieces(rig, face, box, lift));
    _drawn[key] = made;
    if (_drawn.length > 12) _drawn.remove(_drawn.keys.first);
    return made;
  }

  static String _keyOf(
      CharacterRig rig, CharacterFace face, ui.Rect box, double lift) {
    var b = StringBuffer()
      ..write(box.size)
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
          cutOut: mat?.cutOut ?? false,
          toon: switch (mat?.mtoon) {
            MToon t => MeshToon(
                shade: ui.Color.from(
                    alpha: 1, red: t.shade[0], green: t.shade[1], blue: t.shade[2]),
                toony: t.toony,
                shift: t.shift,
                rim: ui.Color.from(
                    alpha: t.rim.any((c) => c > 0) ? 1 : 0.2,
                    red: t.rim.any((c) => c > 0) ? t.rim[0] : 1,
                    green: t.rim.any((c) => c > 0) ? t.rim[1] : 1,
                    blue: t.rim.any((c) => c > 0) ? t.rim[2] : 1),
                rimPower: t.rimPower),
            _ => null,
          },
        ));
      }
    }
    return (box.bottomCenter, out);
  }

  /// boneAt is where [bone] is when posed as [rig] and [face] say, in the
  /// model's own units, facing the reader, before the body's turn -- or
  /// null when the model has no such bone.
  /// faceFrame is where the head is on the page, posed: its eyes, the
  /// bottom of the skull, the middle of the head and the mouth if it marks
  /// one, each x and y on the
  /// page and how near the reader, in pixels -- for a face drawn on it.
  /// Null for a model without eyes to find.
  ({
    List<double> eyeL,
    List<double> eyeR,
    List<double> base,
    List<double> top,
    List<double>? mouth
  })?
      faceFrame(CharacterRig rig, CharacterFace face, ui.Rect box, {double lift = 0}) {
    var h = gltf.humanoid;
    var l = h[HumanBone.leftEye], r = h[HumanBone.rightEye];
    var head = h[HumanBone.head], neck = h[HumanBone.neck];
    if (l == null || r == null || head == null || neck == null) return null;
    var world = _worldWith(_pose(rig, face));
    var b = world[head].translation, n = world[neck].translation;
    // The middle of the head is as far above the skull's base as the neck
    // is long -- as joints has it.
    var t = [for (var k = 0; k < 3; k++) b[k] + (b[k] - n[k])];
    List<double> page(List<double> p) => _onPage(p, rig, box, lift);
    var m = gltf.nodes.indexWhere((n) => n.name == mouthLandmark);
    return (
      eyeL: page(world[l].translation),
      eyeR: page(world[r].translation),
      base: page(b),
      top: page(t),
      mouth: m < 0 ? null : page(world[m].translation),
    );
  }

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
      // An arm raised past level takes its shoulder up with it, a share
      // of the way: turned at the arm alone, the shoulder folds in.
      if (_shoulderOf(seg.bone) case var sb? when h[sb] != null) {
        var up = want[1] / length(want);
        var share = 0.38 * ((up + 0.15) / 1.15).clamp(0.0, 1.0);
        if (share > 0) {
          var sn = h[sb]!;
          var q = Quat.slerp(Quat.identity, Quat.between(now, want), share);
          turns[sn] = (parentTurn(world, sn).conjugate * (q * world[sn].rotation)).normalized;
          world = _worldWith(turns);
          now = _minus(world[tip].translation, world[n].translation);
        }
      }
      var turned = Quat.between(now, want) * world[n].rotation;
      turns[n] = (parentTurn(world, n).conjugate * turned).normalized;
    }
    // Nothing of an arm inside the body: one that would be is turned out
    // of it, as little as will do.
    _clear(turns, parentTurn);

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

  /// _shoulderOf is the shoulder an upper arm [bone] hangs from.
  static HumanBone? _shoulderOf(HumanBone bone) => switch (bone) {
        HumanBone.leftUpperArm => HumanBone.leftShoulder,
        HumanBone.rightUpperArm => HumanBone.rightShoulder,
        _ => null,
      };

  /// _volumes is how much room the body takes up, measured once from it
  /// as made -- see _BodyVolumes -- or null for a model without the bones
  /// to measure by.
  late final _BodyVolumes? _volumes = _BodyVolumes.measure(gltf, _rest);

  /// _clear turns each arm of [turns] -- the forearm first, then the
  /// whole arm -- out of the body and the thighs, where any of it from
  /// the elbow down would be inside them: as little, and in as few small
  /// steps, as will do.
  void _clear(Map<int, Quat> turns, Quat Function(List<Mat4>, int) parentTurn) {
    var v = _volumes;
    if (v == null) return;
    var h = gltf.humanoid;
    for (var (upper, lower, hand) in const [
      (HumanBone.leftUpperArm, HumanBone.leftLowerArm, HumanBone.leftHand),
      (HumanBone.rightUpperArm, HumanBone.rightLowerArm, HumanBone.rightHand),
    ]) {
      var u = h[upper], l = h[lower], w = h[hand];
      if (u == null || l == null || w == null) continue;
      for (var step = 0; step < 36; step++) {
        var world = _worldWith(turns);
        var s = world[u].translation, e = world[l].translation, wr = world[w].translation;
        var fore = _minus(wr, e);
        var tip = [for (var k = 0; k < 3; k++) wr[k] + fore[k] * 0.45];
        List<double> at(List<double> a, List<double> b, double t) =>
            [for (var k = 0; k < 3; k++) a[k] + (b[k] - a[k]) * t];
        var samples = [at(s, e, 0.75), e, at(e, wr, 0.35), at(e, wr, 0.7), wr, tip];
        var worst = 0.0;
        List<double>? push;
        var which = -1;
        for (var (k, p) in samples.indexed) {
          if (v.inside(p, world, _rest) case (var depth, var away) when depth > worst) {
            worst = depth;
            push = away;
            which = k;
          }
        }
        if (push == null || worst <= 0) break;
        // The forearm turned at the elbow for a hand or forearm in the
        // body -- until it has been tried a while -- else the whole arm at
        // the shoulder.
        var pivot = which >= 2 && step < 18 ? l : u;
        var from = world[pivot].translation;
        var arm = _minus(samples[which], from);
        var axis = cross(arm, push);
        var len = length(axis);
        if (len < 1e-9 || length(arm) < 1e-9) break;
        var angle = math.min(worst / length(arm) * 1.3 + 0.01, 0.16);
        var half = angle / 2, sn = math.sin(half) / len;
        var q = Quat(axis[0] * sn, axis[1] * sn, axis[2] * sn, math.cos(half));
        turns[pivot] =
            (parentTurn(world, pivot).conjugate * (q * world[pivot].rotation)).normalized;
      }
    }
  }

  /// _guides is where the lines a figure is drawn by lie on the body as
  /// made, primitive by primitive in the order _pieces draws them -- see
  /// _GuideLines -- worked out once.
  late final List<List<_GuideSeg>> _guides = _GuideLines.measure(gltf, _rest);

  /// guidePieces is the lines a figure is drawn by, on the model posed as
  /// [pieces] has it: the middle of the body front and back and over the
  /// head, down the front of each limb, and rings round the trunk, the
  /// head and each limb -- [width] pixels wide, in [centre] and [ring],
  /// each hidden where the body over it is. For a model with a human
  /// skeleton; none for one without.
  List<MeshPiece> guidePieces(CharacterRig rig, CharacterFace face, ui.Rect box,
      {double lift = 0,
      double width = 1.6,
      ui.Color centre = const ui.Color(0xFFE8742A),
      ui.Color ring = const ui.Color(0xFF8C8F98)}) {
    if (!humanoid) return const [];
    var (_, body) = pieces(rig, face, box, lift: lift);
    var guides = _guides;
    var pts = [<double>[], <double>[]], idx = [<int>[], <int>[]];
    for (var i = 0; i < body.length && i < guides.length; i++) {
      var v = body[i].points, ix = body[i].indices;
      for (var g in guides[i]) {
        var t = g.tri * 3;
        if (t + 2 >= ix.length) continue;
        var a = ix[t] * 3, b = ix[t + 1] * 3, c = ix[t + 2] * 3;
        // Only where the body faces the reader: a line round the back of
        // an arm is not seen through it.
        var nz = (v[b] - v[a]) * (v[c + 1] - v[a + 1]) - (v[b + 1] - v[a + 1]) * (v[c] - v[a]);
        if (nz <= 0) continue;
        List<double> at((int, int, double) e) {
          var (p, q, f) = e;
          return [for (var k = 0; k < 3; k++) v[p * 3 + k] + (v[q * 3 + k] - v[p * 3 + k]) * f];
        }

        var p0 = at(g.from), p1 = at(g.to);
        var dx = p1[0] - p0[0], dy = p1[1] - p0[1];
        var len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        var nx = -dy / len * width / 2, ny = dx / len * width / 2;
        // A hair nearer than the face it lies on, so it is drawn just after.
        var z = math.max(v[a + 2], math.max(v[b + 2], v[c + 2])) + 0.05;
        var k = g.centre ? 0 : 1;
        var base = pts[k].length ~/ 3;
        pts[k].addAll([p0[0] + nx, p0[1] + ny, z, p0[0] - nx, p0[1] - ny, z,
          p1[0] + nx, p1[1] + ny, z, p1[0] - nx, p1[1] - ny, z]);
        // Corners anticlockwise as seen, so the drawing takes it as facing.
        idx[k].addAll([base, base + 2, base + 1, base + 1, base + 2, base + 3]);
      }
    }
    return [
      for (var k = 0; k < 2; k++)
        if (pts[k].isNotEmpty)
          MeshPiece(
            points: Float32List.fromList(pts[k]),
            indices: _facing(Float32List.fromList(pts[k]), Uint32List.fromList(idx[k])),
            color: k == 0 ? centre : ring,
            doubleSided: true,
          ),
    ];
  }

  /// _facing is [ix] with each triangle turned to face the reader.
  static Uint32List _facing(Float32List v, Uint32List ix) {
    for (var t = 0; t + 2 < ix.length; t += 3) {
      var a = ix[t] * 3, b = ix[t + 1] * 3, c = ix[t + 2] * 3;
      var nz = (v[b] - v[a]) * (v[c + 1] - v[a + 1]) - (v[b + 1] - v[a + 1]) * (v[c] - v[a]);
      if (nz < 0) {
        var keep = ix[t + 1];
        ix[t + 1] = ix[t + 2];
        ix[t + 2] = keep;
      }
    }
    return ix;
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

/// _BodyVolumes is the room a humanoid's body takes up, measured from it as
/// made: the trunk as a stack of slices up it -- how wide each is and how
/// far forward and back it goes -- each thigh as a rod as thick as it is,
/// and how thick an arm is. What an arm is kept out of.
class _BodyVolumes {
  final double lo, step;
  final List<(double, double, double, double, double)?> slices;
  final double arm;
  final Map<int, (int, double)> thighs;
  final int hips, chest;
  final double middle;
  const _BodyVolumes(this.lo, this.step, this.slices, this.arm, this.thighs, this.hips,
      this.chest, this.middle);

  static _BodyVolumes? measure(Gltf gltf, List<Mat4> rest) {
    var h = gltf.humanoid;
    var hipsN = h[HumanBone.hips], chestN = h[HumanBone.chest] ?? h[HumanBone.spine];
    var neckN = h[HumanBone.neck];
    if (hipsN == null || chestN == null || neckN == null) return null;
    bool under(int node, int? top) {
      if (top == null) return false;
      for (var n = node; n >= 0; n = gltf.nodes[n].parent) {
        if (n == top) return true;
      }
      return false;
    }

    var arms = [h[HumanBone.leftUpperArm], h[HumanBone.rightUpperArm]];
    var legs = [h[HumanBone.leftUpperLeg], h[HumanBone.rightUpperLeg]];
    var shins = [h[HumanBone.leftLowerLeg], h[HumanBone.rightLowerLeg]];
    var head = h[HumanBone.head];
    // What part each bone moves: 0 trunk, 1 arm, 2 and 3 a thigh, 4 the
    // rest -- head, shins, feet.
    int partOf(int node) {
      if (arms.any((a) => under(node, a))) return 1;
      for (var k = 0; k < 2; k++) {
        if (under(node, shins[k])) return 4;
        if (under(node, legs[k])) return 2 + k;
      }
      if (under(node, head)) return 4;
      return 0;
    }

    var parts = [for (var n = 0; n < gltf.nodes.length; n++) partOf(n)];
    var trunk = <List<double>>[], thigh = [<List<double>>[], <List<double>>[]];
    var armPts = <List<double>>[];
    for (var (n, node) in gltf.nodes.indexed) {
      var mi = node.mesh;
      if (mi == null || mi >= gltf.meshes.length) continue;
      var skin = node.skin != null && node.skin! < gltf.skins.length ? gltf.skins[node.skin!] : null;
      for (var prim in gltf.meshes[mi].primitives) {
        var joints = prim.joints, jw = prim.weights;
        if (skin == null || joints == null || jw == null) continue;
        var (p, _) = _skinPrimitive(gltf, rest, n, node, prim, null);
        for (var i = 0; i < prim.vertexCount; i++) {
          var best = 0, bw = -1.0;
          for (var k = 0; k < 4; k++) {
            if (jw[i * 4 + k] > bw) {
              bw = jw[i * 4 + k];
              best = joints[i * 4 + k];
            }
          }
          if (best >= skin.joints.length) continue;
          var part = parts[skin.joints[best]];
          var pt = [p[i * 3], p[i * 3 + 1], p[i * 3 + 2]];
          switch (part) {
            case 0:
              trunk.add(pt);
            case 1:
              armPts.add(pt);
            case 2 || 3:
              thigh[part - 2].add(pt);
          }
        }
      }
    }
    if (trunk.isEmpty) return null;
    var hipsAt = rest[hipsN].translation, neckAt = rest[neckN].translation;
    var lo = trunk.map((p) => p[1]).reduce(math.min);
    var hi = neckAt[1];
    const count = 40;
    var step = math.max(1e-6, (hi - lo) / count);
    var slices = List<(double, double, double, double, double)?>.filled(count, null);
    for (var k = 0; k < count; k++) {
      var y0 = lo + k * step, y1 = y0 + step;
      var inSlice = [for (var p in trunk) if (p[1] >= y0 && p[1] < y1) p];
      if (inSlice.isEmpty) continue;
      var cx = hipsAt[0];
      var zs = inSlice.map((p) => p[2]);
      var zMin = zs.reduce(math.min), zMax = zs.reduce(math.max);
      var cz = (zMin + zMax) / 2;
      var half = inSlice.map((p) => (p[0] - cx).abs()).reduce(math.max);
      slices[k] = (cx, cz, half, zMax - cz, cz - zMin);
    }
    // A slice with no point of the body in it -- a coarse mesh, its points
    // far apart -- is as the slices either side of it are, between them.
    var known = [for (var k = 0; k < count; k++) if (slices[k] != null) k];
    for (var i = 0; i + 1 < known.length; i++) {
      var a = known[i], b = known[i + 1];
      var (ax, az, ah, af, ab) = slices[a]!;
      var (bx, bz, bh, bf, bb) = slices[b]!;
      for (var k = a + 1; k < b; k++) {
        var t = (k - a) / (b - a);
        double mix(double x, double y) => x + (y - x) * t;
        slices[k] = (mix(ax, bx), mix(az, bz), mix(ah, bh), mix(af, bf), mix(ab, bb));
      }
    }
    // How far a run of points is from the line from [a] to [b]: the most
    // of most of them -- a few strays aside.
    double thickness(List<List<double>> pts, List<double> a, List<double> b, double share) {
      if (pts.isEmpty) return 0;
      var d = [for (var p in pts) _toSegment(p, a, b).$1]..sort();
      return d[((d.length - 1) * share).round()];
    }

    var lowerL = h[HumanBone.leftLowerArm], handL = h[HumanBone.leftHand];
    var arm = lowerL != null && handL != null
        ? thickness(
            [for (var p in armPts) if (_toSegment(p, rest[lowerL].translation, rest[handL].translation).$2 > 0.05) p],
            rest[lowerL].translation,
            rest[handL].translation,
            0.6)
        : 0.0;
    var thighs = <int, (int, double)>{};
    for (var k = 0; k < 2; k++) {
      var top = legs[k], knee = shins[k];
      if (top == null || knee == null) continue;
      thighs[top] = (knee, thickness(thigh[k], rest[top].translation, rest[knee].translation, 0.85));
    }
    // Room for most of an arm's thickness, not all: an arm at rest lies
    // against the side, touching it, as an arm does.
    return _BodyVolumes(lo, step, slices, arm * 0.65, thighs, hipsN, chestN,
        (hipsAt[1] + neckAt[1]) / 2);
  }

  /// inside is how far point [p] -- of the model posed as [world] -- is
  /// inside the trunk or a thigh, an arm's thickness about it, and which
  /// way is out; or null when it is clear.
  (double, List<double>)? inside(List<double> p, List<Mat4> world, List<Mat4> rest) {
    (double, List<double>)? best;
    void found(double depth, List<double> out) {
      if (depth > 0 && (best == null || depth > best!.$1)) best = (depth, out);
    }

    // The trunk, as the hips or the chest have it now -- whichever the
    // point is beside -- measured against it as made.
    for (var bone in [hips, chest]) {
      var back = rest[bone] * world[bone].inverted();
      var q = back.point(p[0], p[1], p[2]);
      var lowHalf = q[1] < middle;
      if (lowHalf != (bone == hips)) continue;
      var k = ((q[1] - lo) / step).floor();
      if (k < 0 || k >= slices.length) continue;
      var slice = slices[k];
      if (slice == null) continue;
      var (cx, cz, half, front, behind) = slice;
      var rx = half + arm, rz = (q[2] > cz ? front : behind) + arm;
      var ex = (q[0] - cx) / rx, ez = (q[2] - cz) / rz;
      var d = math.sqrt(ex * ex + ez * ez);
      if (d >= 1) continue;
      // Out across the slice, from its middle, as the body is turned now.
      var outRest = [ex / rx, 0.0, ez / rz];
      if (length(outRest) < 1e-9) outRest = [0.0, 0.0, 1.0];
      var turned = world[bone] * rest[bone].inverted();
      var out = turned.direction(outRest[0], outRest[1], outRest[2]);
      found((1 - d) * math.min(rx, rz), _unit3(out));
    }
    for (var e in thighs.entries) {
      var a = world[e.key].translation, b = world[e.value.$1].translation;
      var (d, t, c) = _toSegmentAt(p, a, b);
      var r = e.value.$2 + arm;
      if (d >= r || t <= 0.02) continue;
      found(r - d, d < 1e-9 ? const [1.0, 0.0, 0.0] : _unit3(_minus(p, c)));
    }
    return best;
  }
}

List<double> _unit3(List<double> v) {
  var l = length(v);
  return l < 1e-12 ? const [0.0, 0.0, 1.0] : [v[0] / l, v[1] / l, v[2] / l];
}

/// _toSegment is how far [p] is from the line [a] to [b], and how far
/// along it, nought to one, the nearest point is.
(double, double) _toSegment(List<double> p, List<double> a, List<double> b) {
  var (d, t, _) = _toSegmentAt(p, a, b);
  return (d, t);
}

(double, double, List<double>) _toSegmentAt(List<double> p, List<double> a, List<double> b) {
  var ab = _minus(b, a), ap = _minus(p, a);
  var l2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
  var t = l2 < 1e-12 ? 0.0 : ((ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / l2).clamp(0.0, 1.0);
  var c = [for (var k = 0; k < 3; k++) a[k] + ab[k] * t];
  return (length(_minus(p, c)), t, c);
}

/// _GuideSeg is a piece of a guide line on a mesh: across triangle [tri],
/// from a point on one of its edges to a point on another -- each as two
/// vertices and how far from the first to the second -- the middle line
/// or a ring.
typedef _GuideSeg = ({int tri, (int, int, double) from, (int, int, double) to, bool centre});

/// _GuideLines works out where the lines a figure is drawn by lie on a
/// humanoid model as made: slices of it by planes, each through only the
/// part of the body it belongs to.
class _GuideLines {
  static List<List<_GuideSeg>> measure(Gltf gltf, List<Mat4> rest) {
    var h = gltf.humanoid;
    var out = <List<_GuideSeg>>[];
    bool under(int node, int? top) {
      if (top == null) return false;
      for (var n = node; n >= 0; n = gltf.nodes[n].parent) {
        if (n == top) return true;
      }
      return false;
    }

    // Which part each bone moves: a limb's bone, the head, or the trunk.
    var limbBones = [
      for (var b in const [
        HumanBone.leftUpperArm, HumanBone.leftLowerArm, HumanBone.rightUpperArm,
        HumanBone.rightLowerArm, HumanBone.leftUpperLeg, HumanBone.leftLowerLeg,
        HumanBone.rightUpperLeg, HumanBone.rightLowerLeg,
      ])
        if (h[b] != null) b,
    ];
    var childOf = const {
      HumanBone.leftUpperArm: HumanBone.leftLowerArm,
      HumanBone.leftLowerArm: HumanBone.leftHand,
      HumanBone.rightUpperArm: HumanBone.rightLowerArm,
      HumanBone.rightLowerArm: HumanBone.rightHand,
      HumanBone.leftUpperLeg: HumanBone.leftLowerLeg,
      HumanBone.leftLowerLeg: HumanBone.leftFoot,
      HumanBone.rightUpperLeg: HumanBone.rightLowerLeg,
      HumanBone.rightLowerLeg: HumanBone.rightFoot,
    };
    // 0 the trunk, 1 the head, 2 a hand or a foot, 10 and on a limb bone.
    int partOf(int node) {
      for (var (i, b) in limbBones.indexed) {
        var child = h[childOf[b]];
        if (under(node, h[b]) && (child == null || !under(node, child))) return 10 + i;
      }
      for (var b in const [HumanBone.leftHand, HumanBone.rightHand, HumanBone.leftFoot, HumanBone.rightFoot]) {
        if (under(node, h[b])) return 2;
      }
      if (under(node, h[HumanBone.head])) return 1;
      return 0;
    }

    var parts = [for (var n = 0; n < gltf.nodes.length; n++) partOf(n)];
    var hips = h[HumanBone.hips], neck = h[HumanBone.neck], head = h[HumanBone.head];
    for (var (n, node) in gltf.nodes.indexed) {
      var mi = node.mesh;
      if (mi == null || mi >= gltf.meshes.length) continue;
      var skin = node.skin != null && node.skin! < gltf.skins.length ? gltf.skins[node.skin!] : null;
      for (var prim in gltf.meshes[mi].primitives) {
        var segs = <_GuideSeg>[];
        out.add(segs);
        var joints = prim.joints, jw = prim.weights;
        if (skin == null || joints == null || jw == null || hips == null || neck == null) continue;
        var (p, _) = _skinPrimitive(gltf, rest, n, node, prim, null);
        var count = prim.vertexCount;
        var vpart = Int32List(count);
        for (var i = 0; i < count; i++) {
          var best = 0, bw = -1.0;
          for (var k = 0; k < 4; k++) {
            if (jw[i * 4 + k] > bw) {
              bw = jw[i * 4 + k];
              best = joints[i * 4 + k];
            }
          }
          vpart[i] = best < skin.joints.length ? parts[skin.joints[best]] : -1;
        }
        List<double> pt(int i) => [p[i * 3], p[i * 3 + 1], p[i * 3 + 2]];
        var ix = prim.indices;
        // Each triangle of [part] cut by the plane through [o] square to
        // [normal] -- in front of [o] only, along [front], when given.
        void slice(Set<int> part, List<double> o, List<double> normal, bool centre,
            {List<double>? front}) {
          for (var t = 0; t + 2 < ix.length; t += 3) {
            var c = [ix[t], ix[t + 1], ix[t + 2]];
            if (!c.every((i) => part.contains(vpart[i]))) continue;
            var d = [
              for (var i in c)
                (p[i * 3] - o[0]) * normal[0] + (p[i * 3 + 1] - o[1]) * normal[1] + (p[i * 3 + 2] - o[2]) * normal[2]
            ];
            var cross = <(int, int, double)>[];
            for (var (a, b) in const [(0, 1), (1, 2), (2, 0)]) {
              if ((d[a] < 0) != (d[b] < 0)) {
                cross.add((c[a], c[b], d[a] / (d[a] - d[b])));
              }
            }
            if (cross.length != 2) continue;
            if (front != null) {
              var mid = pt(c[0]);
              var f = (mid[0] - o[0]) * front[0] + (mid[1] - o[1]) * front[1] + (mid[2] - o[2]) * front[2];
              if (f < 0) continue;
            }
            segs.add((tri: t ~/ 3, from: cross[0], to: cross[1], centre: centre));
          }
        }

        var hp = rest[hips].translation, np = rest[neck].translation;
        // Down the middle, front and back, and over the head.
        slice({0, 1}, hp, const [1, 0, 0], true);
        // Round the trunk: the chest, the waist, the hips.
        for (var f in const [0.15, 0.45, 0.75]) {
          slice({0}, [hp[0], hp[1] + (np[1] - hp[1]) * f, hp[2]], const [0, 1, 0], false);
        }
        // Round the head at the eyes.
        if (head != null) {
          var eye = h[HumanBone.leftEye];
          var y = eye != null ? rest[eye].translation[1] : rest[head].translation[1] + (np[1] - hp[1]) * 0.25;
          slice({1}, [hp[0], y, hp[2]], const [0, 1, 0], false);
        }
        // Each limb bone: round it half way and near its end, and down its
        // front.
        for (var (i, b) in limbBones.indexed) {
          var child = h[childOf[b]];
          if (child == null) continue;
          var a = rest[h[b]!].translation, z = rest[child].translation;
          var axis = [z[0] - a[0], z[1] - a[1], z[2] - a[2]];
          var l = length(axis);
          if (l < 1e-9) continue;
          axis = [axis[0] / l, axis[1] / l, axis[2] / l];
          for (var f in const [0.5, 0.92]) {
            slice({10 + i}, [for (var k = 0; k < 3; k++) a[k] + (z[k] - a[k]) * f], axis, false);
          }
          // The plane through the bone and the way the body faces -- its
          // front half.
          var across = cross(axis, const [0, 0, 1]);
          if (length(across) < 1e-6) continue;
          var ac = _unit3(across);
          slice({10 + i}, a, ac, true, front: const [0, 0, 1]);
        }
      }
    }
    return out;
  }
}
