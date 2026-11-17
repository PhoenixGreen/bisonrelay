import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_colour.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_decal.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_look.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_paint.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_wear.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_scene.dart puts a CharacterShape and a CharacterOutfit on a VrmAvatar
// drawn by flutter_scene. Shaped vertices are uploaded over the old, so
// skinning and expressions carry on. flutter_vrm resets every humanoid bone
// from rest each frame, so a bone that can change sits under its own node
// holding T(t')·S(s)·T(-t): a uniform scale ignores turning, so whatever turn
// the rig gives it, it lands at t' at s times the size.

/// CharacterHit is where a ray met the character: see ShapedAvatar.pick.
typedef CharacterHit = ({
  vm.Vector3 at,
  vm.Vector3 made,
  vm.Vector3 normal,
  double distance,
  String? surface,
});

class ShapedAvatar {
  final VrmAvatar avatar;
  final VrmShapeRig rig;

  /// wardrobe makes its clothes; null for a body they cannot be made for.
  final VrmWardrobe? wardrobe;

  /// holder is what goes in the scene, sized by the character's height.
  final Node holder;

  final Map<String, (Node, vm.Vector3)> _wrappers;
  final Map<ShapeGroup, List<Geometry>> _geometry;
  final Map<VrmPrimitive, TypedData> _indices = {};
  final Map<ShapeGroup, String> _uploaded = {};
  final Map<ShapeGroup, Float32List> _packed = {};
  final Map<VrmRegion, String> _regionKeys = {};
  CharacterShape? _shape;

  /// _body is the body's mesh node: the file's primitives, then the outlines
  /// flutter_vrm adds.
  final Node? _body;

  final Map<String, Node> _byName;

  ShapedAvatar._(this.avatar, this.rig, this.wardrobe, this.holder,
      this._wrappers, this._geometry, this._body, this._byName);

  /// load reads [bytes], a VRM 1.0 file, ready to shape and dress; the
  /// shaping data is read off the main isolate while the avatar loads.
  static Future<ShapedAvatar> load(Uint8List bytes) async {
    final rigFuture = Isolate.run(() {
      final rig = VrmShapeRig(VrmMeshData.read(bytes));
      return (rig, VrmWardrobe.of(rig));
    });
    final avatar = await VrmAvatar.fromBytes(bytes);
    final (rig, wardrobe) = await rigFuture;
    final byName = <String, Node>{};
    void walk(Node n) {
      byName.putIfAbsent(n.name, () => n);
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(avatar.root);
    // Every bone the proportions can move, wrapped before the avatar is in a
    // scene, so nothing has to be mounted again.
    final wrappers = <String, (Node, vm.Vector3)>{};
    for (final name in _shapedBones) {
      final bone = byName[name],
          rest = rig.data.bones[name],
          parent = bone?.parent;
      if (bone == null || rest == null || parent == null) continue;
      final w = Node(name: '$name#shape');
      parent.remove(bone);
      parent.add(w);
      w.add(bone);
      wrappers[name] = (w, rest.translation.clone());
    }
    final geometry = <ShapeGroup, List<Geometry>>{};
    for (final g in rig.groups) {
      final mesh = byName[g.node.name]?.mesh;
      if (mesh == null) continue;
      geometry[g] = [
        for (final i in g.primitives)
          if (i < mesh.primitives.length) mesh.primitives[i].geometry,
      ];
    }
    final holder = Node(name: 'character')..add(avatar.root);
    final body = wardrobe == null ? null : byName[wardrobe.body.name];
    return ShapedAvatar._(
        avatar, rig, wardrobe, holder, wrappers, geometry, body, byName);
  }

  static final List<String> _shapedBones = [
    VroidBone.hips, VroidBone.spine, VroidBone.chest, VroidBone.upperChest,
    VroidBone.neck, VroidBone.head, //
    for (final s in const ['L', 'R']) ...[
      VroidBone.upperArm(s), VroidBone.lowerArm(s), VroidBone.hand(s), //
      VroidBone.upperLeg(s), VroidBone.lowerLeg(s), VroidBone.foot(s),
      for (final f in const ['Thumb', 'Index', 'Middle', 'Ring', 'Little'])
        for (final j in const [2, 3]) 'J_Bip_${s}_$f$j',
    ],
  ];

  CharacterShape get shape => _shape ?? const CharacterShape();

  /// apply shapes the character as [s] says, redoing only regions whose
  /// changes differ. Without [bones] the skeleton stays as made: for a
  /// character worn only for its hair, placed on another's head.
  void apply(CharacterShape s, {bool bones = true}) {
    if (s == _shape && !_reshape) return;
    _shape = s;
    _reshape = false;
    for (final region in VrmRegion.values) {
      final ds = _deformers(region, s);
      final key = ds.map((d) => d.key).join(';');
      if (_regionKeys[region] == key) continue;
      _regionKeys[region] = key;
      for (final g in [
        ...rig.groups,
        if (region == VrmRegion.body) ..._worn.values.map((w) => w.group),
        if (region == VrmRegion.body) ..._decals.values.map((w) => w.group),
        ..._paints.values.map((w) => w.group),
      ]) {
        if (g.node.region == region) _shapeGroup(g, ds, key);
      }
    }
    if (!bones) return;
    final p = rig.proportions(s);
    for (final e in _wrappers.entries) {
      final (w, rest) = e.value;
      final c = p.bones[e.key];
      w.localTransform = c == null
          ? vm.Matrix4.identity()
          : (vm.Matrix4.translation(c.translation)
            ..scaleByDouble(c.scale, c.scale, c.scale, 1)
            ..translateByVector3(-rest));
    }
    holder.localTransform =
        vm.Matrix4.diagonal3Values(p.height, p.height, p.height);
  }

  // Shaped by hand.

  List<SculptStroke> _sculpt = const [];
  String _sculptKey = '';
  bool _reshape = false;

  /// sculpt adds hand-shaping [strokes] (character_sculpt.dart) on the next
  /// [apply].
  void sculpt(List<SculptStroke> strokes) {
    // Asked every frame: the same list is the same strokes, unhashed.
    if (identical(strokes, _sculpt)) return;
    final key = strokes.map((s) => s.key).join(';');
    if (key == _sculptKey) return;
    _sculpt = strokes;
    _sculptKey = key;
    _reshape = true;
  }

  /// _deformers are [region]'s changes: the shaping's, then the strokes'.
  /// Not the hair's, which keeps its shape over a hand-shaped head.
  List<Deformer> _deformers(VrmRegion region, CharacterShape s) => [
        ...rig.deformers(region, s),
        if (region != VrmRegion.hair) ...StrokeDeformer.of(_sculpt),
      ];

  // Physics: how the hair and clothes swing.

  /// _springs swings hair and clothes in place of the avatar's own, with
  /// changed settings; null for as made.
  VrmSpringBoneSystem? _springs;
  String _physicsKey = "1.0|1.0|1.0|0.0";

  /// physics swings the hair [hair] times as loose as made and the clothes
  /// [clothes] times, [weight] times as heavy, in a cross wind of [wind]
  /// (0 to 1). flutter_vrm reads the settings once, so a change rebuilds the
  /// swing from rest, its chains put back first.
  void physics(
      {double hair = 1,
      double clothes = 1,
      double weight = 1,
      double wind = 0}) {
    final key = "$hair|$clothes|$weight|$wind";
    if (key == _physicsKey) return;
    _physicsKey = key;
    (_springs ?? avatar.springBones).reset();
    final def = avatar.document.springBone;
    if (def == null ||
        (hair == 1 && clothes == 1 && weight == 1 && wind == 0)) {
      _springs = null;
      avatar.springBones
        ..enabled = true
        ..reset();
      return;
    }
    VrmSpringJoint scaled(VrmSpringJoint j) {
      final name = j.node < avatar.gltfNodes.length
          ? avatar.gltfNodes[j.node]?.name ?? ""
          : "";
      if (name.contains("Bust")) return j;
      final swing = name.contains("Hair") ? hair : clothes;
      final g = j.gravityDir * (j.gravityPower * weight) +
          vm.Vector3(0, -1, 0) * (0.45 * math.max(0, weight - 1)) +
          // A steady breeze: the settings are read once, so it cannot gust.
          vm.Vector3(wind * 0.22, 0.02 * wind, wind * 0.06);
      return VrmSpringJoint(
        node: j.node,
        hitRadius: j.hitRadius,
        stiffness: j.stiffness / math.max(0.25, swing),
        gravityPower: g.length,
        gravityDir: g.length2 > 1e-8 ? g.normalized() : j.gravityDir,
        dragForce: math.min(
            0.95,
            j.dragForce * (0.4 + 0.6 * weight) +
                0.08 * math.max(0, weight - 1)),
      );
    }

    avatar.springBones.enabled = false;
    _springs = VrmSpringBoneSystem(
      VrmSpringBoneDefinition(
        colliders: def.colliders,
        colliderGroups: def.colliderGroups,
        springs: [
          for (final sp in def.springs)
            VrmSpring(
              name: sp.name,
              joints: [for (final j in sp.joints) scaled(j)],
              colliderGroups: sp.colliderGroups,
              center: sp.center,
            ),
        ],
      ),
      avatar.gltfNodes,
      avatar.modelRoot,
    );
  }

  // The body at rest, for posing (vrm_pose.dart).

  /// bodyAtRest is every [step]th point of the shaped body at rest: torso,
  /// neck and thigh skin and the clothes over them. [cloth] marks clothes,
  /// [loose] those that hang away, as a skirt does.
  Iterable<({double x, double y, double z, bool cloth, bool loose})> bodyAtRest(
      {int step = 3}) sync* {
    final w = wardrobe;
    if (w == null) return;
    final skinGroup = rig.groups.where((g) => g.vertices == w.skin).firstOrNull;
    final pos =
        (skinGroup == null ? null : _shapedAt[skinGroup]) ?? w.skin.positions;
    final keep = {
      for (final p in w.body.primitives)
        if (p.vertices == w.skin && p.part == VrmPart.skin) ...p.used
    };
    var k = 0;
    for (final i in keep) {
      if (k++ % step != 0 || i >= w.group.length) continue;
      final g = w.groupAt(i);
      if (g != BodyGroup.torso && g != BodyGroup.neck && g != BodyGroup.legU) {
        continue;
      }
      yield (
        x: pos[i * 3],
        y: pos[i * 3 + 1],
        z: pos[i * 3 + 2],
        cloth: false,
        loose: false
      );
    }
    // The body's own clothes where worn: they are in its mesh, and without
    // them arms go through them.
    final o = _dressed ?? CharacterOutfit.asDesigned;
    for (final p in w.body.primitives) {
      if (p.vertices != w.skin) continue;
      final slot = switch (p.part) {
        VrmPart.top => WearSlot.top,
        VrmPart.bottom => WearSlot.bottom,
        _ => null,
      };
      if (slot == null || o[slot].source != WearSource.own) continue;
      for (var j = 0; j < p.used.length; j += step) {
        final i = p.used[j];
        yield (
          x: pos[i * 3],
          y: pos[i * 3 + 1],
          z: pos[i * 3 + 2],
          cloth: true,
          loose: slot == WearSlot.bottom
        );
      }
    }
    for (final MapEntry(key: slot, value: worn) in _worn.entries) {
      if (slot != WearSlot.top &&
          slot != WearSlot.bottom &&
          slot != WearSlot.underwear) {
        continue;
      }
      final p = _shapedAt[worn.group] ?? worn.group.vertices.positions;
      for (var j = 0; j < worn.group.used.length; j += step) {
        final i = worn.group.used[j];
        yield (
          x: p[i * 3],
          y: p[i * 3 + 1],
          z: p[i * 3 + 2],
          cloth: true,
          loose: slot == WearSlot.bottom
        );
      }
    }
  }

  // The face's expression (character_face.dart).

  /// _faceUnits are the face-shape nodes, each with shape indices by the name
  /// after "Fcl_" ("EYE_Joy").
  late final List<(Node, Map<String, int>)> _faceUnits = [
    for (final m in rig.data.meshes)
      if (_byName[m.name] case final n? when n.morphTargetCount > 0)
        (
          n,
          {
            for (final (i, name) in m.targetNames.indexed)
              if (name.indexOf('Fcl_') case final k
                  when k >= 0 && i < n.morphTargetCount)
                name.substring(k + 4): i
          }
        )
  ]..removeWhere((e) => e.$2.isEmpty);

  /// _wore is each shape [wear] last set: its value before, and what it was
  /// set to. flutter_vrm resets each frame only the shapes its expressions
  /// use; the rest keep what they were given and would accumulate if added
  /// to again.
  final Map<(Node, int), (double, double)> _wore = {};

  /// wear puts [units] on the face over the avatar's own expressions,
  /// including a blink, which gives way as far as the eyes already close.
  void wear(Map<String, double> units) {
    double u(String k) => units[k] ?? 0;
    final closing = math.max(
        math.max(u('EYE_Close'), u('EYE_Joy')),
        0.5 *
            math.max(math.max(u('EYE_Close_L'), u('EYE_Close_R')),
                math.max(u('EYE_Joy_L'), u('EYE_Joy_R'))));
    final touched = <(Node, int)>{};
    for (final (node, idx) in _faceUnits) {
      final live = node.morphWeights;
      if (live == null) continue;
      void put(int i, double Function(double base) value) {
        final k = (node, i), now = live[i], was = _wore[k];
        // Unchanged since set: flutter_vrm left it, so it is still ours over
        // what it was before.
        final base = was != null && (now - was.$2).abs() < 1e-6 ? was.$1 : now;
        final v = value(base).clamp(0.0, 1.0);
        node.setMorphWeight(i, v);
        _wore[k] = (base, v);
        touched.add(k);
      }

      final shut = idx['EYE_Close'];
      for (final e in units.entries) {
        final i = idx[e.key];
        if (i == null || i == shut) continue;
        put(i, (b) => b + e.value);
      }
      if (shut != null) {
        put(shut, (b) => b * (1 - closing.clamp(0.0, 1.0)) + u('EYE_Close'));
      }
    }
    // Shapes set before and not now go back.
    for (final k in _wore.keys.toList()) {
      if (touched.contains(k)) continue;
      final (base, v) = _wore.remove(k)!;
      final live = k.$1.morphWeights;
      if (live != null && (live[k.$2] - v).abs() < 1e-6) {
        k.$1.setMorphWeight(k.$2, base);
      }
    }
  }

  /// blushAt is where a blush goes on each cheek of the face as made: a skin
  /// point under each eye, toward the outside, its facing, and its size.
  /// Empty for a face without landmarks.
  late final List<(vm.Vector3, vm.Vector3, double)> blushAt = () {
    final L = rig.face;
    if (L == null) return const <(vm.Vector3, vm.Vector3, double)>[];
    final out = <(vm.Vector3, vm.Vector3, double)>[];
    for (final eye in [L.eyeL, L.eyeR]) {
      final want = vm.Vector2(eye.x * 1.08, eye.y - L.es * 0.5);
      vm.Vector3? best;
      vm.Vector3? normal;
      var dist = double.infinity;
      for (final m in rig.data.meshes) {
        if (m.region != VrmRegion.face) continue;
        for (final p in m.primitives) {
          if (p.part != VrmPart.face) continue;
          final pos = p.vertices.positions, nrm = p.vertices.normals;
          for (final i in p.used) {
            if (nrm[i * 3 + 2] * L.fwd < 0.3) continue;
            final dx = pos[i * 3] - want.x, dy = pos[i * 3 + 1] - want.y;
            final d = dx * dx + dy * dy;
            if (d < dist) {
              dist = d;
              best = vm.Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]);
              normal = vm.Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
            }
          }
        }
      }
      if (best != null) out.add((best, normal!, L.es * 0.42));
    }
    return out;
  }();

  /// creaseKey is what [creases] depend on in [shape], so they are redrawn
  /// only when it changes.
  static String creaseKey(CharacterShape shape) => [
        shape.age,
        shape.get("muscle.definition"),
        shape.get("muscle.abs"),
        shape.get("muscle.pecs"),
        shape.get("muscle.fat"),
        shape.get("body.muscle"),
      ].map((v) => v.toStringAsFixed(2)).join(";");

  /// creases are the lines of age and muscle drawn as paint: forehead, eye
  /// corners, under the eyes and beside the mouth from age 35 (deepest at
  /// 80); and with muscle defined, the stomach's midline and bands, the pecs'
  /// lower edge on a flat chest, and the obliques. Laid on the body as made,
  /// so they follow its shaping.
  List<PaintStroke> creases(CharacterShape shape) {
    final out = <PaintStroke>[];
    final L = rig.face, B = rig.body;
    const ink = 0x5a3328;
    double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

    // A line through [xy] on the front of the face or body, followed along
    // the skin, mirrored onto the other side when one of a pair.
    void line(List<(double, double)> xy,
        {required bool face,
        required double radius,
        required double opacity,
        bool mirror = false}) {
      if (opacity < 0.02 || xy.length < 2) return;
      final fwd = L?.fwd ?? 1;
      final dense = <(double, double)>[xy.first];
      for (var i = 1; i < xy.length; i++) {
        final (ax, ay) = xy[i - 1];
        final (bx, by) = xy[i];
        final n = math.max(
            1,
            (math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2)) /
                    (radius * 0.6))
                .ceil());
        for (var k = 1; k <= n; k++) {
          dense.add((ax + (bx - ax) * k / n, ay + (by - ay) * k / n));
        }
      }
      // On the skin under each point, not its nearest corner: corners are
      // further apart than the brush is wide, making a row of dots.
      var lo = vm.Vector2(double.infinity, double.infinity),
          hi = vm.Vector2(-double.infinity, -double.infinity);
      for (final (x, y) in dense) {
        lo = vm.Vector2(math.min(lo.x, x), math.min(lo.y, y));
        hi = vm.Vector2(math.max(hi.x, x), math.max(hi.y, y));
      }
      final near = _skinTriangles(lo, hi, face: face, fwd: fwd);
      final points = <SculptPoint>[];
      for (final (x, y) in dense) {
        final at = _onSkin(x, y, near, fwd);
        if (at == null) continue;
        final (p, n) = at;
        points.add(SculptPoint(p.x, p.y, p.z, n.x, n.y, n.z));
      }
      if (points.length < 2) return;
      out.add(PaintStroke(
          on: "skin",
          colour: ink,
          radius: radius,
          opacity: clamp01(opacity),
          softness: 0.85,
          mirror: mirror,
          points: points));
    }

    final age = clamp01((shape.age - 35) / 45);
    if (L != null && age > 0) {
      final es = L.es, ey = L.eyeY, r = es * 0.036;
      final cx = (L.eyeL.x + L.eyeR.x) / 2;
      for (var k = 0; k < 3 && k < (age * 3.2).ceil(); k++) {
        final y = ey + es * (0.95 + 0.22 * k);
        line([
          for (var i = -6; i <= 6; i++)
            (cx + es * 0.85 * i / 6, y + es * 0.05 * (1 - math.pow(i / 6, 2)))
        ], face: true, radius: r, opacity: age * 0.32 * (1 - 0.2 * k));
      }
      // Crow's feet, fanning from each eye's outer corner.
      final corner = L.eyeL.x + es * 0.44;
      for (final a in const [-0.4, 0.05, 0.45]) {
        final long = es * 0.16 * (0.6 + 0.4 * age);
        line([
          (corner, ey + a * es * 0.08),
          (corner + math.cos(a) * long, ey + math.sin(a) * long)
        ], face: true, radius: r * 0.8, opacity: age * 0.22, mirror: true);
      }
      line([
        for (var i = 0; i <= 6; i++)
          (
            L.eyeL.x - es * 0.22 + es * 0.55 * i / 6,
            ey - es * 0.42 - es * 0.05 * math.sin(math.pi * i / 6)
          )
      ], face: true, radius: r, opacity: age * 0.28, mirror: true);
      // Bracketing the mouth: from a little over its corners, curving out
      // and down. Kept close to the mouth: run from a small high nose, they
      // cross the cheek like whiskers.
      final top = L.mouth.y + (L.noseTip.y - L.mouth.y) * 0.45;
      line([
        for (var i = 0; i <= 6; i++)
          (
            L.mouth.x +
                es * (0.3 + 0.12 * i / 6) +
                es * 0.05 * math.sin(math.pi * i / 6),
            top + (L.mouth.y - es * 0.1 - top) * i / 6
          )
      ], face: true, radius: r, opacity: age * 0.3, mirror: true);
      // And down from the corners of the mouth, later on.
      if (age > 0.5) {
        line([
          (L.mouth.x + es * 0.42, L.mouth.y - es * 0.05),
          (L.mouth.x + es * 0.48, L.chin.y + es * 0.2)
        ], face: true, radius: r, opacity: (age - 0.5) * 0.6, mirror: true);
      }
    }

    // Muscles, as defined as the body is lean.
    if (B != null) {
      final u = B.u, r = 0.008 * u;
      final fat = clamp01(shape.get("muscle.fat"));
      final defined = clamp01(shape.get("muscle.definition") +
              0.4 * shape.get("body.muscle") -
              0.7 * fat) *
          (1 - fat);
      final abs =
          clamp01(defined * 0.7 + 0.5 * shape.get("muscle.abs")) * (1 - fat);
      final pecs = clamp01(defined * 0.6 + 0.6 * shape.get("muscle.pecs"));
      final top = B.pec.y - 0.06 * u, bottom = B.navel.y + 0.025 * u;
      line([(0, top), (0, bottom)],
          face: false, radius: r, opacity: abs * 0.55);
      for (final t in const [0.28, 0.55, 0.8]) {
        final y = top + (bottom - top) * t;
        line([
          (0.012 * u, y),
          (0.04 * u, y - 0.004 * u),
          (0.066 * u, y + 0.002 * u)
        ], face: false, radius: r, opacity: abs * 0.45, mirror: true);
      }
      // The pecs' lower edge, where there is no bust over it.
      if (B.bustC == null) {
        line([
          for (var i = 0; i <= 6; i++)
            (
              0.02 * u + 0.11 * u * i / 6,
              B.pec.y - 0.055 * u + 0.035 * u * math.pow(i / 6, 1.6)
            )
        ], face: false, radius: r * 1.2, opacity: pecs * 0.5, mirror: true);
      }
      line([
        (0.1 * u, B.waist.y - 0.02 * u),
        (0.075 * u, (B.waist.y + B.hips.y) / 2 - 0.02 * u),
        (0.045 * u, B.hips.y - 0.03 * u)
      ], face: false, radius: r, opacity: defined * 0.45, mirror: true);
    }
    return out;
  }

  /// _skinTriangles are the front-facing (along [fwd]) skin triangles of the
  /// face or body as made, whose x-y outline reaches into [lo]..[hi]: each
  /// as three vertex numbers and the positions and normals they index.
  List<(int, int, int, Float32List, Float32List)> _skinTriangles(
      vm.Vector2 lo, vm.Vector2 hi,
      {required bool face, required double fwd}) {
    final out = <(int, int, int, Float32List, Float32List)>[];
    for (final m in rig.data.meshes) {
      if (m.region != (face ? VrmRegion.face : VrmRegion.body)) continue;
      for (final p in m.primitives) {
        if (p.part != (face ? VrmPart.face : VrmPart.skin)) continue;
        final pos = p.vertices.positions, nrm = p.vertices.normals;
        final ix = p.indices;
        for (var t = 0; t + 2 < ix.length; t += 3) {
          final a = ix[t], b = ix[t + 1], c = ix[t + 2];
          final nz =
              (nrm[a * 3 + 2] + nrm[b * 3 + 2] + nrm[c * 3 + 2]) / 3 * fwd;
          if (nz < 0.1) continue;
          final x0 = math.min(pos[a * 3], math.min(pos[b * 3], pos[c * 3])),
              x1 = math.max(pos[a * 3], math.max(pos[b * 3], pos[c * 3])),
              y0 = math.min(
                  pos[a * 3 + 1], math.min(pos[b * 3 + 1], pos[c * 3 + 1])),
              y1 = math.max(
                  pos[a * 3 + 1], math.max(pos[b * 3 + 1], pos[c * 3 + 1]));
          if (x1 < lo.x || x0 > hi.x || y1 < lo.y || y0 > hi.y) continue;
          out.add((a, b, c, pos, nrm));
        }
      }
    }
    return out;
  }

  /// _onSkin is the front-most point of [triangles] seen straight on at [x],
  /// [y], and the skin's facing there; null where none is under it.
  static (vm.Vector3, vm.Vector3)? _onSkin(double x, double y,
      List<(int, int, int, Float32List, Float32List)> triangles, double fwd) {
    (vm.Vector3, vm.Vector3)? best;
    var front = -double.infinity;
    for (final (a, b, c, pos, nrm) in triangles) {
      final ax = pos[a * 3], ay = pos[a * 3 + 1];
      final bx = pos[b * 3], by = pos[b * 3 + 1];
      final cx = pos[c * 3], cy = pos[c * 3 + 1];
      final den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
      if (den.abs() < 1e-12) continue;
      final u = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / den;
      final v = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / den;
      final w = 1 - u - v;
      if (u < -1e-6 || v < -1e-6 || w < -1e-6) continue;
      final z = u * pos[a * 3 + 2] + v * pos[b * 3 + 2] + w * pos[c * 3 + 2];
      if (z * fwd <= front) continue;
      front = z * fwd;
      final n = vm.Vector3(
          u * nrm[a * 3] + v * nrm[b * 3] + w * nrm[c * 3],
          u * nrm[a * 3 + 1] + v * nrm[b * 3 + 1] + w * nrm[c * 3 + 1],
          u * nrm[a * 3 + 2] + v * nrm[b * 3 + 2] + w * nrm[c * 3 + 2])
        ..normalize();
      best = (vm.Vector3(x, y, z), n);
    }
    return best;
  }

  /// _shapedAt are each group's vertices at rest as last shaped.
  final Map<ShapeGroup, Float32List> _shapedAt = {};

  /// pick is where a scene ray from [from] along [dir] first meets the body,
  /// face or clothes: the place on the shaped body at rest and as made, the
  /// surface's facing, the distance along the ray, and what it is ("skin", a
  /// clothing slot's name, or null). Null if it meets nothing.
  CharacterHit? pick(vm.Vector3 from, vm.Vector3 dir) {
    final d = dir.normalized();
    var best = double.infinity;
    CharacterHit? hit;
    String? partOn(VrmPrimitive p) => switch (p.part) {
          VrmPart.skin || VrmPart.face => "skin",
          VrmPart.top || VrmPart.bottom || VrmPart.shoes => p.part.name,
          _ => null,
        };
    final groups = <(ShapeGroup, Node?, String? Function(VrmPrimitive))>[
      for (final g in rig.groups)
        if (g.node.region != VrmRegion.hair && !g.iris)
          (g, _byName[g.node.name], partOn),
      for (final MapEntry(key: slot, value: w) in _worn.entries)
        (w.group, w.node, (_) => slot.name),
    ];
    for (final (g, node, surfaceOf) in groups) {
      if (node == null) continue;
      final vs = g.vertices;
      final rest = _shapedAt[g] ?? vs.positions;
      final posed = _posed(g, node, rest);
      if (posed == null) continue;
      for (final pi in g.primitives) {
        if (pi >= g.node.primitives.length) continue;
        final p = g.node.primitives[pi];
        final List<int> tris = _indices[p] as List<int>? ?? p.indices;
        for (var t = 0; t + 2 < tris.length; t += 3) {
          final i0 = tris[t], i1 = tris[t + 1], i2 = tris[t + 2];
          final r = _rayTriangle(from, d, posed, i0, i1, i2);
          if (r == null || r.$1 >= best) continue;
          best = r.$1;
          final u = r.$2, v = r.$3, w = 1 - u - v;
          vm.Vector3 at(Float32List a) => vm.Vector3(
              a[i0 * 3] * w + a[i1 * 3] * u + a[i2 * 3] * v,
              a[i0 * 3 + 1] * w + a[i1 * 3 + 1] * u + a[i2 * 3 + 1] * v,
              a[i0 * 3 + 2] * w + a[i1 * 3 + 2] * u + a[i2 * 3 + 2] * v);
          final n = at(vs.normals);
          hit = (
            at: at(rest),
            made: at(vs.positions),
            normal: n.length2 < 1e-12 ? vm.Vector3(0, 0, 1) : n.normalized(),
            distance: r.$1,
            surface: surfaceOf(p),
          );
        }
      }
    }
    return hit;
  }

  /// _posed is [g]'s [rest] vertices posed as [node] is now, skinned as the
  /// GPU skins them.
  Float32List? _posed(ShapeGroup g, Node node, Float32List rest) {
    final vs = g.vertices;
    final out = Float32List(vs.count * 3);
    final skin = node.skin;
    if (!vs.skinned || skin == null) {
      final m = node.globalTransform;
      for (final i in g.used) {
        final v = m.transformed3(
            vm.Vector3(rest[i * 3], rest[i * 3 + 1], rest[i * 3 + 2]));
        out[i * 3] = v.x;
        out[i * 3 + 1] = v.y;
        out[i * 3 + 2] = v.z;
      }
      return out;
    }
    final mats = [
      for (var j = 0; j < skin.joints.length; j++)
        skin.joints[j] == null
            ? vm.Matrix4.identity().storage
            : (skin.joints[j]!.globalTransform * skin.inverseBindMatrices[j]
                    as vm.Matrix4)
                .storage
    ];
    final jn = vs.joints, wt = vs.weights;
    for (final i in g.used) {
      final x = rest[i * 3], y = rest[i * 3 + 1], z = rest[i * 3 + 2];
      var ox = 0.0, oy = 0.0, oz = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = wt[i * 4 + k];
        if (w == 0) continue;
        final j = jn[i * 4 + k].toInt();
        if (j < 0 || j >= mats.length) continue;
        final m = mats[j];
        ox += w * (m[0] * x + m[4] * y + m[8] * z + m[12]);
        oy += w * (m[1] * x + m[5] * y + m[9] * z + m[13]);
        oz += w * (m[2] * x + m[6] * y + m[10] * z + m[14]);
      }
      out[i * 3] = ox;
      out[i * 3 + 1] = oy;
      out[i * 3 + 2] = oz;
    }
    return out;
  }

  /// _rayTriangle is how far along [d] from [o] the ray meets triangle [i0],
  /// [i1], [i2] of [p], and where (two barycentric weights); null on a miss
  /// from either side.
  static (double, double, double)? _rayTriangle(
      vm.Vector3 o, vm.Vector3 d, Float32List p, int i0, int i1, int i2) {
    final ax = p[i0 * 3], ay = p[i0 * 3 + 1], az = p[i0 * 3 + 2];
    final e1x = p[i1 * 3] - ax,
        e1y = p[i1 * 3 + 1] - ay,
        e1z = p[i1 * 3 + 2] - az;
    final e2x = p[i2 * 3] - ax,
        e2y = p[i2 * 3 + 1] - ay,
        e2z = p[i2 * 3 + 2] - az;
    final px = d.y * e2z - d.z * e2y,
        py = d.z * e2x - d.x * e2z,
        pz = d.x * e2y - d.y * e2x;
    final det = e1x * px + e1y * py + e1z * pz;
    if (det.abs() < 1e-12) return null;
    final inv = 1 / det;
    final tx = o.x - ax, ty = o.y - ay, tz = o.z - az;
    final u = (tx * px + ty * py + tz * pz) * inv;
    if (u < 0 || u > 1) return null;
    final qx = ty * e1z - tz * e1y,
        qy = tz * e1x - tx * e1z,
        qz = tx * e1y - ty * e1x;
    final v = (d.x * qx + d.y * qy + d.z * qz) * inv;
    if (v < 0 || u + v > 1) return null;
    final t = (e2x * qx + e2y * qy + e2z * qz) * inv;
    if (t <= 1e-6) return null;
    return (t, u, v);
  }

  void _shapeGroup(ShapeGroup g, List<Deformer> ds, String key) {
    final was = _uploaded[g] ?? '';
    if (was == key) return;
    final shaped = rig.shape(g, ds);
    if (shaped == null && was.isEmpty) return;
    if (shaped == null) {
      _shapedAt.remove(g);
    } else {
      _shapedAt[g] = shaped.positions;
    }
    _upload(
        g,
        g.vertices.pack(shaped?.positions ?? g.vertices.positions,
            shaped?.normals ?? g.vertices.normals));
    _uploaded[g] = shaped == null ? '' : key;
  }

  /// restVersion counts changes to the body's shape and clothes, so a pose
  /// measured at rest is remeasured.
  int restVersion = 0;

  void _upload(ShapeGroup g, Float32List packed) {
    restVersion++;
    _packed[g] = packed;
    final geos = _geometry[g] ?? const [];
    for (var k = 0; k < geos.length; k++) {
      final p = g.node.primitives[g.primitives[k]];
      final idx = _indices.putIfAbsent(
          p, () => p.indices32 ? p.indices : Uint16List.fromList(p.indices));
      geos[k].uploadVertexData(ByteData.sublistView(packed), g.vertices.count,
          ByteData.sublistView(idx),
          indexType: p.indices32 ? gpu.IndexType.int32 : gpu.IndexType.int16);
    }
  }

  /// update moves the avatar on by [dt], lighting the clothes as it is lit.
  void update(double dt, {Camera? camera}) {
    avatar.update(dt, camera: camera);
    _springs?.update(dt);
    final l = avatar.mtoonLighting;
    // Decals and paint as well, lit as the skin is.
    for (final w in [..._worn.values, ..._decals.values, ..._paints.values]) {
      for (final m in w.materials) {
        m.parameters
          ..setVec3('light_direction', l.direction)
          ..setVec3('light_color', l.color)
          ..setVec3('gi_sky_color', l.skyColor)
          ..setVec3('gi_ground_color', l.groundColor);
      }
    }
  }

  /// _drawn is [node]'s [i]th primitive as drawn, and the outline flutter_vrm
  /// draws over the same geometry.
  List<MeshPrimitive> _drawn(VrmMeshNode node, int i) {
    final mesh = _byName[node.name]?.mesh;
    if (mesh == null || i >= mesh.primitives.length) return const [];
    final g = mesh.primitives[i].geometry;
    return [
      for (final m in mesh.primitives)
        if (identical(m.geometry, g)) m
    ];
  }

  /// _outlines is whether flutter_vrm's own outlines are drawn: not once a
  /// look's finish draws the lines.
  bool _outlines = true;

  /// _show shows or hides a primitive and its outlines ([drawn]).
  void _show(List<MeshPrimitive> drawn, bool on) {
    for (var k = 0; k < drawn.length; k++) {
      drawn[k].visible = on && (k == 0 || _outlines);
    }
  }

  // Painting: each material's colour, shading and picture, for the look,
  // the colours picked, and the clothes taken off.

  CharacterLook? get look => _look;
  CharacterLook? _look;

  /// _colours are the colours picked (hair, skin, eyes, brows) as 0xRRGGBB;
  /// _hairAs the colour borrowed hair takes here; and how grey the hair is.
  Map<VrmPart, int> _colours = const {};
  int? _hairAs;
  double _grey = 0;

  /// _bare is whether the skin's painted clothes are off above, and below,
  /// the knees.
  (bool, bool) _bare = (false, false);

  /// applyLook draws the character in [l]: every MToon material shaded as
  /// [l] says, lines left to the finish (vrm_look.dart). Without [finished]
  /// (its shader failed to load) flutter_vrm's own outlines stay.
  void applyLook(CharacterLook l, {bool finished = true}) {
    if (l == _look && finished == !_outlines) return;
    final retexture = l.fill != _look?.fill || l.levels != _look?.levels;
    if (_look == null) _maskCutouts();
    _look = l;
    _outlines = !finished;
    for (final node in rig.data.meshes) {
      final mesh = _byName[node.name]?.mesh;
      if (mesh == null) continue;
      for (var i = node.primitives.length; i < mesh.primitives.length; i++) {
        // A flutter_vrm outline: shown only where its primitive is.
        if (!_outlines) mesh.primitives[i].visible = false;
      }
    }
    _recolour();
    if (retexture) _retexture();
  }

  /// colour colours hair, skin, eyes and brows as [colours] (0xRRGGBB) say,
  /// the rest as made. This character's hair worn on another's head takes
  /// [hairAs] when no colour is picked; [grey] greys the hair.
  void colour(Map<VrmPart, int> colours, {int? hairAs, double grey = 0}) {
    final same = colours.length == _colours.length &&
        colours.entries.every((e) => _colours[e.key] == e.value);
    if (same && hairAs == _hairAs && (grey - _grey).abs() < 1e-3) return;
    final regrey = (_colours.isEmpty) != (colours.isEmpty) ||
        (hairAs == null) != (_hairAs == null) ||
        (grey > 0.01) != (_grey > 0.01);
    _colours = colours;
    _hairAs = hairAs;
    _grey = grey;
    _recolour();
    if (!same || regrey) _retexture();
  }

  /// _materials are the character's own MToon materials, once each, with
  /// the primitive it draws and its outline, if any.
  late final List<(VrmPrimitive, PreprocessedMaterial, PreprocessedMaterial?)>
      _materials = () {
    final out = <(VrmPrimitive, PreprocessedMaterial, PreprocessedMaterial?)>[];
    for (final node in rig.data.meshes) {
      final mesh = _byName[node.name]?.mesh;
      if (mesh == null) continue;
      for (var i = 0;
          i < node.primitives.length && i < mesh.primitives.length;
          i++) {
        final m = mesh.primitives[i].material;
        if (m is! PreprocessedMaterial || out.any((e) => identical(e.$2, m))) {
          continue;
        }
        final outline = mesh.primitives
            .skip(node.primitives.length)
            .where((x) => identical(x.geometry, mesh.primitives[i].geometry))
            .firstOrNull
            ?.material;
        out.add((
          node.primitives[i],
          m,
          outline is PreprocessedMaterial ? outline : null
        ));
      }
    }
    return out;
  }();

  /// _maskCutouts makes cut-out materials (cloth and hair with clear parts)
  /// cut out in depth too. flutter_vrm leaves that off, and the finish,
  /// which finds lines in depth and normals, would line absent cloth.
  void _maskCutouts() {
    for (final (_, m, _) in _materials) {
      final a = m.parameters.assignedValues;
      final tex = a['base_color_texture'];
      if (a['alpha_mode'] != 1 || tex is! gpu.Texture) continue;
      final cutoff = a['alpha_cutoff'];
      // Protected for subclasses with their own mask; flutter_vrm's MToon is
      // not one, and there is no other way to give it a mask.
      // ignore: invalid_use_of_protected_member
      m.configureDepthAlphaMask(
        texture: GpuTextureSource(tex),
        cutoff: cutoff is double ? cutoff : 0.5,
      );
    }
  }

  /// _originals are each material's colour and pictures as made, kept on
  /// first change to go back to.
  final Map<PreprocessedMaterial, (vm.Vector4, gpu.Texture?, gpu.Texture?)>
      _originals = {};

  (vm.Vector4, gpu.Texture?, gpu.Texture?) _original(PreprocessedMaterial m) =>
      _originals.putIfAbsent(m, () {
        final a = m.parameters.assignedValues;
        final f = a['base_color_factor'];
        return (
          f is vm.Vector4 ? f.clone() : vm.Vector4(1, 1, 1, 1),
          a['base_color_texture'] as gpu.Texture?,
          a['shade_multiply_texture'] as gpu.Texture?,
        );
      });

  /// hairAverage is the colour this character's hair mostly is, once read.
  int? hairAverage;

  /// _chosen is the colour [p] is drawn in, or null for as made.
  int? _chosen(VrmPrimitive p) {
    switch (p.part) {
      case VrmPart.hair:
        var c = _colours[VrmPart.hair] ?? _hairAs;
        if (_grey > 0.01) {
          final from = c ?? hairAverage;
          if (from != null) c = mixColour(from, 0xd2cec8, _grey * 0.9);
        }
        return c;
      case VrmPart.face || VrmPart.skin:
        return _colours[VrmPart.skin];
      case VrmPart.eyes:
        // Only the iris: the whites and highlights stay white.
        return p.material.contains('EyeIris') ? _colours[VrmPart.eyes] : null;
      case VrmPart.brows:
        return _colours[VrmPart.brows];
      default:
        return null;
    }
  }

  void _recolour() {
    final l = _look;
    for (final (p, m, outline) in _materials) {
      final c = _chosen(p);
      final f = _original(m).$1;
      final base = c == null
          ? f.xyz
          : (() {
              final (r, g, b) = linearOf(c);
              return vm.Vector3(r, g, b);
            })();
      for (final x in [m, if (outline != null) outline]) {
        x.parameters.setVec4(
            'base_color_factor', vm.Vector4(base.x, base.y, base.z, f.w));
      }
      if (l != null) styleMaterial(m, p.part, l, base: base);
    }
    for (final w in [..._worn.values, ..._decals.values, ..._paints.values]) {
      _styleWorn(w);
    }
  }

  void _styleWorn(_Worn w) {
    final l = _look;
    if (l == null) return;
    styleMaterial(w.materials.first, null, l, cloth: true);
    final prims = w.node.mesh?.primitives ?? const [];
    for (var k = 1; k < prims.length; k++) {
      prims[k].visible = _outlines;
    }
  }

  /// _read are pictures as read, by their bytes; _pictures as changed, by
  /// the change. Both kept once made.
  final Map<Uint8List, Future<(Uint8List, int, int)>> _read = {};
  final Map<String, Texture2D> _pictures = {};
  Future<List<int>?>? _faceColour;
  int _painting = 0;

  /// _retexture gives each material its current picture: its own, or with
  /// the skin's painted clothes off, in grey to be coloured, or in flat
  /// tones.
  Future<void> _retexture() async {
    _retexturing++;
    try {
      await _retextureNow();
    } finally {
      _retexturing--;
    }
  }

  int _retexturing = 0;

  bool get busy =>
      _dressing || _decorating || _paintingLayers || _retexturing > 0;

  Future<void> _retextureNow() async {
    final run = ++_painting;
    final l = _look;
    final steps = l == null ? 0 : (2 + l.levels * 6).round();
    for (final (p, m, outline) in _materials) {
      final bytes = rig.data.pictures[p.material];
      if (bytes == null) continue;
      final part = p.part;
      final grey = _chosen(p) != null || (part == VrmPart.hair && _grey > 0.01);
      final flat = l?.fill == "flat" &&
          const [
            VrmPart.skin,
            VrmPart.hair,
            VrmPart.top,
            VrmPart.bottom,
            VrmPart.shoes
          ].contains(part);
      final bare = part == VrmPart.skin ? _bare : (false, false);
      final orig = _original(m);
      gpu.Texture? base = orig.$2, shade = orig.$3;
      if (part == VrmPart.hair && hairAverage == null) {
        final (rgba, _, _) = await (_read[bytes] ??= _decode(bytes));
        hairAverage ??=
            timesColour(averageColour(rgba), orig.$1.x, orig.$1.y, orig.$1.z);
        if (_grey > 0.01) _recolour();
      }
      if (grey || flat || bare.$1 || bare.$2) {
        final key =
            '${identityHashCode(bytes)}|$grey|${flat ? steps : 0}|${bare.$1}|${bare.$2}';
        var t = _pictures[key];
        if (t == null) {
          final (rgba, w, h) = await (_read[bytes] ??= _decode(bytes));
          final face = bare.$1 || bare.$2
              ? await (_faceColour ??= _readFaceColour())
              : null;
          final wr = wardrobe;
          final px = await Isolate.run(() {
            var out = rgba;
            if ((bare.$1 || bare.$2) && wr != null) {
              out = bareSkin(out, w, h, wr,
                  upper: bare.$1, lower: bare.$2, face: face);
            }
            if (grey) out = greyPixels(out);
            if (flat) out = flatPixels(out, steps);
            return out;
          });
          if (run != _painting) return;
          t = _pictures[key] = Texture2D.fromPixels(px, w, h);
        }
        final shared = identical(orig.$2, orig.$3);
        base = t.gpuTexture;
        if (shared) shade = t.gpuTexture;
      }
      if (run != _painting) return;
      for (final x in [m, if (outline != null) outline]) {
        if (base != null) x.parameters.setTexture('base_color_texture', base);
        if (shade != null) {
          x.parameters.setTexture('shade_multiply_texture', shade);
        }
      }
    }
  }

  static Future<(Uint8List, int, int)> _decode(Uint8List bytes,
      {int? size}) async {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: size, targetHeight: size);
    final frame = (await codec.getNextFrame()).image;
    final px =
        await frame.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final out = (Uint8List.sublistView(px!), frame.width, frame.height);
    frame.dispose();
    codec.dispose();
    return out;
  }

  Future<List<int>?> _readFaceColour() async {
    final fb = rig.data.images[VrmPart.face]?.bytes;
    if (fb == null) return null;
    final (px, fw, fh) = await _decode(fb, size: 128);
    return faceSkinColour(px, fw, fh, rig.data);
  }

  /// hairRoles are each hair piece's role: fringe, back and sides, or tails.
  late final Map<VrmPrimitive, HairRole> hairRoles = {
    for (final node in rig.data.meshes)
      for (final p in node.primitives)
        if (p.part == VrmPart.hair)
          p: rig.face == null ? HairRole.back : hairRoleOf(p, rig.face!),
  };

  /// showHair shows the hair pieces [show] picks. As a [donor] (worn only
  /// for its hair) everything else is hidden.
  void showHair(bool Function(HairRole) show, {bool donor = false}) {
    for (final node in rig.data.meshes) {
      for (var i = 0; i < node.primitives.length; i++) {
        final role = hairRoles[node.primitives[i]];
        if (role == null && !donor) continue;
        final on = role != null && show(role);
        _show(_drawn(node, i), on);
      }
    }
  }

  Node? get headNode => avatar.humanoid.node(VrmHumanBone.head);

  /// wearOn places this character, worn for its hair, with its head on
  /// [base]'s, grown by [grow]. It is posed as [base] first, so its springs
  /// and colliders (the hair's swing, the shoulders it lies on) match
  /// [base]'s rather than the T it was made in.
  void wearOn(ShapedAvatar base, double grow) {
    final head = base.headNode?.globalTransform, mine = headNode;
    if (head == null || mine == null) return;
    final rig = avatar.humanoid, from = base.avatar.humanoid;
    for (final b in rig.bones) {
      final r = from.normalizedRotation(b);
      if (r == null) {
        rig.clearNormalizedRotation(b);
      } else {
        rig.setNormalizedRotation(b, r);
      }
    }
    rig.apply();
    // Where the head is now, from the holder, put on [base]'s head.
    final here = (holder.localTransform.clone()..invert()) *
        mine.globalTransform as vm.Matrix4;
    holder.localTransform = head.clone()
      ..scaleByDouble(grow, grow, grow, 1)
      ..multiply(vm.Matrix4.inverted(here));
  }

  final Map<WearSlot, _Worn> _worn = {};
  CharacterOutfit? _want, _dressed;
  bool _dressing = false;

  String? dressError;

  /// dress puts [o] on. Clothes take a moment to make, so changes made
  /// meanwhile wait, and only the last is put on.
  Future<void> dress(CharacterOutfit o) async {
    _want = o;
    if (_dressing) return;
    _dressing = true;
    try {
      while (_dressed != _want) {
        final next = _want!;
        try {
          await _dressAs(next);
          dressError = null;
        } catch (e) {
          dressError = "$e";
        }
        _dressed = next;
      }
    } finally {
      _dressing = false;
    }
  }

  Future<void> _dressAs(CharacterOutfit o) async {
    final w = wardrobe, body = _body, parent = body?.parent;
    if (w == null || body == null || parent == null) return;
    final lines = w.lines(
        overOwnBottom:
            o[WearSlot.bottom].source == WearSource.own && w.hasOwnBottom);
    final skinMats = _skinMaterials();
    for (final slot in WearSlot.values) {
      final g = o[slot];
      // Underwear and socks under other clothes have no outline: it would
      // show through.
      final under = switch (slot) {
        WearSlot.underwear => o[WearSlot.top].source != WearSource.none ||
            o[WearSlot.bottom].source != WearSource.none,
        WearSlot.legwear => o[WearSlot.bottom].source != WearSource.none,
        _ => false,
      };
      // A skirt's waistband goes over a top made to fit, however loose.
      final top = o[WearSlot.top];
      final over = slot == WearSlot.bottom && top.made
          ? w.offset(WearSlot.top, top) + 0.002
          : 0.0;
      final shod = slot == WearSlot.legwear &&
          o[WearSlot.shoes].source != WearSource.none;
      final key = g.made ? '${g.key}|${lines.tuck}|$under|$over|$shod' : '';
      if ((_worn[slot]?.key ?? '') == key) continue;
      final old = _worn.remove(slot);
      if (old != null) _unwear(old);
      if (!g.made) continue;
      final mesh = w.make(slot, g, lines, over: over, shod: shod);
      if (mesh == null) continue;
      final worn =
          await _wear(slot, g, mesh, key, body, skinMats, outlined: !under);
      parent.add(worn.node);
      _worn[slot] = worn;
      _styleWorn(worn);
      final s = shape;
      final ds = _deformers(VrmRegion.body, s);
      _shapeGroup(worn.group, ds, ds.map((d) => d.key).join(';'));
    }
    _showOwn(o);
    // The skin's painted clothes, off where its own clothes come off.
    final upper = o[WearSlot.top].source != WearSource.own ||
        (w.hasOwnBottom && o[WearSlot.bottom].source != WearSource.own);
    final lower = o[WearSlot.shoes].source != WearSource.own;
    if (_bare != (upper, lower)) {
      _bare = (upper, lower);
      await _retexture();
    }
    final load = _decalLoad;
    // Decals on clothes go with them, through their guards so two runs
    // never lay the same one twice.
    if (load != null) await decorate(_decalWant, load);
    if (_paintWant.isNotEmpty || _paints.isNotEmpty) await paint(_paintWant);
  }

  // Paint: strokes on skin and clothes, each surface drawn into its own
  // picture (vrm_paint.dart) on a copy of the painted triangles, a hair off
  // the surface, as decals are.

  final Map<String, _Worn> _paints = {};
  List<PaintStroke> _paintWant = const [];
  bool _paintingLayers = false, _paintAgain = false;

  /// paint paints [strokes] on the character, replacing what was.
  Future<void> paint(List<PaintStroke> strokes) async {
    _paintWant = strokes;
    if (_paintingLayers) {
      _paintAgain = true;
      return;
    }
    _paintingLayers = true;
    try {
      do {
        _paintAgain = false;
        await _paint(_paintWant);
      } while (_paintAgain);
    } finally {
      _paintingLayers = false;
    }
  }

  /// _paintTargets are the surfaces paintable now: an id, what a stroke on
  /// it is said to be on, the node it is drawn beside, the skin's joints,
  /// vertices and triangles, how far over it paint lies, and a change key.
  List<
      ({
        String id,
        String on,
        Node node,
        List<String> joints,
        VrmVertices vertices,
        Uint32List triangles,
        double lift,
        bool cells,
        String key
      })> _paintTargets() {
    final w = wardrobe, body = _body;
    if (w == null || body == null) return const [];
    final o = _dressed ?? CharacterOutfit.asDesigned;
    Uint32List tris(bool Function(VrmPrimitive) keep) => Uint32List.fromList([
          for (final p in w.body.primitives)
            if (p.vertices == w.skin && keep(p)) ...p.indices
        ]);
    final out = [
      (
        id: "skin",
        on: "skin",
        node: body,
        joints: w.body.jointNames,
        vertices: w.skin,
        triangles: _skinTris ??= tris((p) => p.part == VrmPart.skin),
        lift: 0.0007,
        cells: false,
        key: "skin",
      ),
    ];
    for (final m in rig.data.meshes) {
      if (m.region != VrmRegion.face) continue;
      final node = _byName[m.name];
      if (node == null) continue;
      for (final p in m.primitives) {
        if (p.part != VrmPart.face) continue;
        out.add((
          id: "Face-${p.material}",
          on: "skin",
          node: node,
          joints: m.jointNames,
          vertices: p.vertices,
          triangles: p.indices,
          lift: 0.0005,
          cells: false,
          key: "face",
        ));
      }
    }
    for (final slot in const [WearSlot.top, WearSlot.bottom, WearSlot.shoes]) {
      final g = o[slot];
      if (g.source == WearSource.own) {
        final t = tris((p) => p.part.name == slot.name);
        if (t.isEmpty) continue;
        out.add((
          id: "own-${slot.name}",
          on: slot.name,
          node: body,
          joints: w.body.jointNames,
          vertices: w.skin,
          triangles: t,
          lift: _clothLift,
          cells: false,
          key: "own",
        ));
      }
    }
    for (final MapEntry(key: slot, value: worn) in _worn.entries) {
      out.add((
        id: "wear-${slot.name}",
        on: slot.name,
        node: worn.node,
        joints: w.body.jointNames,
        vertices: worn.group.vertices,
        triangles: worn.group.triangles,
        lift: 0.0009,
        // A made garment's pattern repeats front and back: no place to paint
        // one spot and not another.
        cells: true,
        key: worn.key,
      ));
    }
    return out;
  }

  Future<void> _paint(List<PaintStroke> strokes) async {
    final body = _body, parent = body?.parent;
    if (body == null || parent == null) return;
    final targets = _paintTargets();
    final ids = {for (final t in targets) t.id};
    for (final id in _paints.keys.toList()) {
      if (!ids.contains(id)) _unwear(_paints.remove(id)!);
    }
    for (final t in targets) {
      final on = [
        for (final s in strokes)
          if (s.on == t.on) s
      ];
      final key = "${t.key}|${on.map((s) => s.key).join(";")}";
      if (on.isEmpty) {
        final old = _paints.remove(t.id);
        if (old != null) _unwear(old);
        continue;
      }
      if (_paints[t.id]?.key == key) continue;
      // Only plain data goes to the isolate: not [t], which holds nodes.
      final vs = t.vertices, tris = t.triangles, cells = t.cells;
      final layer = await Isolate.run(() => paintLayer(
          positions: vs.positions,
          normals: vs.normals,
          uv: vs.uv0,
          triangles: tris,
          strokes: on,
          cells: cells));
      final old = _paints.remove(t.id);
      if (old != null) _unwear(old);
      if (layer == null) continue;
      final from = layer.source;
      final n = from?.length ?? vs.count;
      int src(int i) => from == null ? i : from[i];
      final lifted = Float32List(n * 3), normals = Float32List(n * 3);
      final joints = Float32List(vs.skinned ? n * 4 : 0),
          weights = Float32List(vs.skinned ? n * 4 : 0);
      for (var i = 0; i < n; i++) {
        final o = src(i);
        for (var k = 0; k < 3; k++) {
          normals[i * 3 + k] = vs.normals[o * 3 + k];
          lifted[i * 3 + k] =
              vs.positions[o * 3 + k] + vs.normals[o * 3 + k] * t.lift;
        }
        for (var k = 0; vs.skinned && k < 4; k++) {
          joints[i * 4 + k] = vs.joints[o * 4 + k];
          weights[i * 4 + k] = vs.weights[o * 4 + k];
        }
      }
      final mesh = GarmentMesh(
        VrmVertices(
          positions: lifted,
          normals: normals,
          uv0: layer.uv ?? vs.uv0,
          uv1: Float32List(n * 2),
          colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
          tangents: Float32List(n * 4),
          joints: joints,
          weights: weights,
          skinned: vs.skinned,
        ),
        layer.triangles,
      );
      final tex = Texture2D.fromPixels(layer.rgba, layer.size, layer.size,
          sampling: const TextureSampling(
              addressMode: gpu.SamplerAddressMode.clampToEdge));
      // Paint goes over decals, and both over the surface they lie on.
      final material = await _overlayMaterial(tex, layer: 2);
      final worn = _meshNode('paint-${t.id}', key, mesh, material, null, t.node,
          joints: t.joints);
      (t.node.parent ?? parent).add(worn.node);
      final was = _paints[t.id];
      if (was != null) _unwear(was);
      _paints[t.id] = worn;
      _styleWorn(worn);
      final region = worn.group.node.region;
      final ds = _deformers(region, shape);
      _shapeGroup(worn.group, ds, ds.map((x) => x.key).join(';'));
    }
  }

  /// _overlayMaterial lays [tex] over the skin, drawn as the skin is where
  /// [tex] is not clear, at depth layer [layer]: over its surface at any
  /// distance and curve, which lifting it off the surface alone cannot do.
  Future<PreprocessedMaterial> _overlayMaterial(Texture2D tex,
      {required int layer}) async {
    final material = await loadFmatMaterial('assets/materials/mtoon_blend.fmat',
        package: 'flutter_vrm');
    final skin = _skinMaterials().firstOrNull;
    if (skin != null) material.parameters.copyStateFrom(skin.$1.parameters);
    material.parameters
      ..setTexture('base_color_texture', tex.gpuTexture,
          sampler: tex.sampledSampler)
      ..setTexture('shade_multiply_texture', tex.gpuTexture,
          sampler: tex.sampledSampler)
      ..setVec4('base_color_factor', vm.Vector4(1, 1, 1, 1))
      ..setInt('alpha_mode', 2)
      ..setFloat('normal_scale', 0)
      ..setVec3('parametric_rim_color_factor', vm.Vector3.zero())
      ..setVec3('matcap_factor', vm.Vector3.zero())
      ..setVec3('emissive_factor', vm.Vector3.zero());
    material.depthLayer = layer;
    // Both faces: VRoid's clothes wind triangles either way, so a decal or
    // paint cut from them, drawn one-sided, would lose those facing in.
    material.doubleSided = true;
    return material;
  }

  final Map<String, _Worn> _decals = {};
  List<CharacterDecal> _decalWant = const [];
  Future<(Uint8List, int, int)?> Function(String source)? _decalLoad;
  final Map<String, Texture2D> _decalPictures = {};
  bool _decorating = false, _decorateAgain = false;

  /// decorate lays [decals] on the character, reading pictures with [load].
  /// Changes made meanwhile wait, and only the last are laid on.
  Future<void> decorate(List<CharacterDecal> decals,
      Future<(Uint8List, int, int)?> Function(String source) load) async {
    _decalWant = decals;
    _decalLoad = load;
    if (_decorating) {
      _decorateAgain = true;
      return;
    }
    _decorating = true;
    try {
      do {
        _decorateAgain = false;
        await _decorate(_decalWant, load);
      } while (_decorateAgain);
    } finally {
      _decorating = false;
    }
  }

  /// _surface is what [on] is now (skin or worn piece) and a change key;
  /// null for nothing worn.
  (DecalSurface, String)? _surface(String on) {
    final w = wardrobe;
    if (w == null) return null;
    Uint32List skinTris() => Uint32List.fromList([
          for (final p in w.body.primitives)
            if (p.part == VrmPart.skin && p.vertices == w.skin) ...p.indices
        ]);
    if (on == "skin") {
      return (
        DecalSurface(w.skin, _skinTris ??= skinTris(), lift: 0.0007),
        "skin"
      );
    }
    final slot = WearSlot.values.where((x) => x.name == on).firstOrNull;
    final o = _dressed ?? CharacterOutfit.asDesigned;
    if (slot == null) return null;
    final g = o[slot];
    if (g.made) {
      final worn = _worn[slot];
      if (worn == null) return null;
      final skirt = slot == WearSlot.bottom && g.kind == "skirt";
      return (
        DecalSurface(worn.group.vertices, worn.group.triangles,
            likeSkin: !skirt, lift: 0.0009),
        worn.key
      );
    }
    if (g.source == WearSource.own) {
      final tris = [
        for (final p in w.body.primitives)
          if (p.part.name == slot.name && p.vertices == w.skin) ...p.indices
      ];
      if (tris.isEmpty) return null;
      return (
        DecalSurface(w.skin, Uint32List.fromList(tris), lift: _clothLift),
        "own"
      );
    }
    return null;
  }

  Uint32List? _skinTris;

  /// _clothLift is how far over the body's own (VRoid mesh) clothes a decal
  /// or paint lies: a little more than over made clothes. Much more (8 mm)
  /// and a decal floats over the buttons and frills it should lie among; at
  /// this lift nothing hides it across bodies, looks and angles.
  static const double _clothLift = 0.0012;

  Future<void> _decorate(List<CharacterDecal> decals,
      Future<(Uint8List, int, int)?> Function(String source) load) async {
    final w = wardrobe, body = _body, parent = body?.parent;
    if (w == null || body == null || parent == null) return;
    final ids = {for (final d in decals) d.id};
    for (final id in _decals.keys.toList()) {
      if (!ids.contains(id)) _unwear(_decals.remove(id)!);
    }
    for (final d in decals) {
      final surface = _surface(d.on);
      final key = '${d.shapeKey}|${surface?.$2}|${d.pictureKey}';
      if (_decals[d.id]?.key == key) continue;
      final old = _decals.remove(d.id);
      if (old != null) _unwear(old);
      if (surface == null) continue;
      final mesh = makeDecal(w, d, surface.$1);
      if (mesh == null) continue;
      var tex = _decalPictures[d.pictureKey];
      if (tex == null) {
        final pic = await load(d.source);
        if (pic == null) continue;
        final (px, pw, ph) =
            await Isolate.run(() => decalPicture(pic.$1, pic.$2, pic.$3, d));
        tex = _decalPictures[d.pictureKey] = Texture2D.fromPixels(px, pw, ph,
            sampling: const TextureSampling(
                addressMode: gpu.SamplerAddressMode.clampToEdge));
      }
      final material = await _overlayMaterial(tex, layer: 1);
      final worn = _meshNode('decal-${d.id}', key, mesh, material, null, body);
      parent.add(worn.node);
      // One laid meanwhile is taken off: never two of it, nor one lost.
      final was = _decals[d.id];
      if (was != null) _unwear(was);
      _decals[d.id] = worn;
      _styleWorn(worn);
      final ds = _deformers(VrmRegion.body, shape);
      _shapeGroup(worn.group, ds, ds.map((x) => x.key).join(';'));
    }
  }

  void _unwear(_Worn w) {
    restVersion++;
    w.node.parent?.remove(w.node);
    _geometry.remove(w.group);
    _uploaded.remove(w.group);
    _packed.remove(w.group);
  }

  /// _skinMaterials are the skin's materials, each with its outline, if any.
  List<(PreprocessedMaterial, PreprocessedMaterial?, VrmPrimitive)>
      _skinMaterials() {
    final mesh = _body?.mesh, w = wardrobe;
    if (mesh == null || w == null) return const [];
    final n = w.body.primitives.length;
    final out = <(PreprocessedMaterial, PreprocessedMaterial?, VrmPrimitive)>[];
    for (var i = 0; i < n && i < mesh.primitives.length; i++) {
      final p = w.body.primitives[i];
      final m = mesh.primitives[i].material;
      if (p.part != VrmPart.skin ||
          m is! PreprocessedMaterial ||
          out.any((e) => identical(e.$1, m))) {
        continue;
      }
      final outline = mesh.primitives
          .skip(n)
          .where((x) => identical(x.geometry, mesh.primitives[i].geometry))
          .firstOrNull
          ?.material;
      out.add((m, outline is PreprocessedMaterial ? outline : null, p));
    }
    return out;
  }

  Future<_Worn> _wear(
      WearSlot slot,
      Garment g,
      GarmentMesh mesh,
      String key,
      Node body,
      List<(PreprocessedMaterial, PreprocessedMaterial?, VrmPrimitive)>
          skinMats,
      {required bool outlined}) async {
    final (px, pw, ph) = garmentPicture(slot, g);
    final tex = Texture2D.fromPixels(px, pw, ph,
        sampling: slot == WearSlot.shoes
            ? const TextureSampling(
                mipmaps: false,
                minFilter: gpu.MinMagFilter.nearest,
                magFilter: gpu.MinMagFilter.nearest,
                addressMode: gpu.SamplerAddressMode.clampToEdge)
            : const TextureSampling());
    final skin = skinMats.firstOrNull;
    final material = await loadFmatMaterial(
        mesh.doubleSided
            ? 'assets/materials/mtoon_opaque_double.fmat'
            : 'assets/materials/mtoon_opaque.fmat',
        package: 'flutter_vrm');
    final outline = skin?.$2 == null || !outlined
        ? null
        : await loadFmatMaterial('assets/materials/mtoon_outline.fmat',
            package: 'flutter_vrm');
    for (final (m, from) in [
      (material, skin?.$1),
      if (outline != null) (outline, skin?.$2)
    ]) {
      if (from != null) m.parameters.copyStateFrom(from.parameters);
      m.parameters
        ..setTexture('base_color_texture', tex.gpuTexture,
            sampler: tex.sampledSampler)
        ..setTexture('shade_multiply_texture', tex.gpuTexture,
            sampler: tex.sampledSampler)
        ..setVec4('base_color_factor', vm.Vector4(1, 1, 1, 1))
        // A cool grey shade, so any colour of cloth darkens as cloth does.
        ..setVec3('shade_color_factor', vm.Vector3(0.48, 0.43, 0.48))
        ..setInt('alpha_mode', 0)
        // Cloth has no rim light, shine, glow or bumps: the skin's warm rim
        // round dark trousers is a glow, and its bumps over a repeated
        // pattern are specks.
        ..setFloat('normal_scale', 0)
        ..setVec3('parametric_rim_color_factor', vm.Vector3.zero())
        ..setVec3('matcap_factor', vm.Vector3.zero())
        ..setVec3('emissive_factor', vm.Vector3.zero());
    }
    // The outline a dark shade of the cloth, not the skin's: a light line
    // round dark trousers is a glow.
    double linear(int shift) =>
        0.3 * math.pow(((g.colour >> shift) & 0xff) / 255, 2.2);
    outline?.parameters.setVec3(
        'outline_color_factor', vm.Vector3(linear(16), linear(8), linear(0)));
    return _meshNode('wear-${slot.name}', key, mesh, material, outline, body);
  }

  /// _meshNode is [mesh] in [material] (and [outline]), bound to the body's
  /// bones, as a node to add beside it.
  _Worn _meshNode(String name, String key, GarmentMesh mesh,
      PreprocessedMaterial material, PreprocessedMaterial? outline, Node body,
      {List<String>? joints}) {
    final prim = VrmPrimitive(
        material: name,
        vertices: mesh.vertices,
        indices: mesh.indices,
        indices32: true);
    final node = VrmMeshNode(name, [prim], joints ?? wardrobe!.body.jointNames);
    final group = ShapeGroup(
        node, mesh.vertices, false, const [0], prim.used, mesh.indices);
    final geometry = SkinnedGeometry()
      ..uploadVertexData(
          ByteData.sublistView(mesh.vertices
              .pack(mesh.vertices.positions, mesh.vertices.normals)),
          mesh.vertices.count,
          ByteData.sublistView(mesh.indices),
          indexType: gpu.IndexType.int32);
    final scene = Node(
      name: node.name,
      localTransform: body.localTransform.clone(),
      mesh: Mesh.primitives(primitives: [
        MeshPrimitive(geometry, material),
        if (outline != null) MeshPrimitive(geometry, outline),
      ]),
    );
    final from = body.skin;
    if (from != null) {
      scene.skin = Skin()
        ..joints.addAll(from.joints)
        ..inverseBindMatrices.addAll(from.inverseBindMatrices);
    }
    _geometry[group] = [geometry];
    return _Worn(key, scene, group, [material, if (outline != null) outline]);
  }

  /// _setIndices draws [p] with [cut] of its triangles; true if that changed.
  bool _setIndices(VrmPrimitive p, Uint32List cut) {
    final now = _indices[p];
    if (now != null &&
        now.lengthInBytes ~/ (p.indices32 ? 4 : 2) == cut.length) {
      return false;
    }
    _indices[p] = p.indices32 ? cut : Uint16List.fromList(cut);
    return true;
  }

  /// _showOwn shows the body's own top, bottom and shoes where worn, sleeves
  /// and legs cut as asked, and hides them where not.
  void _showOwn(CharacterOutfit o) {
    final mesh = _body?.mesh, w = wardrobe;
    if (mesh == null || w == null) return;
    final n = w.body.primitives.length;
    final shod = o[WearSlot.shoes].source != WearSource.none;
    var recut = false;
    for (var i = 0; i < n && i < mesh.primitives.length; i++) {
      final p = w.body.primitives[i];
      final slot = switch (p.part) {
        VrmPart.top => WearSlot.top,
        VrmPart.bottom => WearSlot.bottom,
        VrmPart.shoes => WearSlot.shoes,
        _ => null,
      };
      if (slot == null) {
        // The skin inside shoes is not drawn.
        if (p.part != VrmPart.skin || p.vertices != w.skin) continue;
        final cut = shod ? w.withoutFeet(p.indices) : p.indices;
        recut = _setIndices(p, cut) || recut;
        continue;
      }
      final g = o[slot], on = g.source == WearSource.own;
      final geometry = mesh.primitives[i].geometry;
      _show([
        for (final m in mesh.primitives)
          if (identical(m.geometry, geometry)) m
      ], on);
      if (slot == WearSlot.shoes) continue;
      recut = _setIndices(p, w.cut(p, on ? g.ownCut : 1)) || recut;
    }
    if (!recut) return;
    for (final g in rig.groups) {
      if (g.node == w.body) {
        _upload(
            g,
            _packed[g] ??
                g.vertices.pack(g.vertices.positions, g.vertices.normals));
      }
    }
  }
}

/// _Worn is a garment on the character: its source, node, shape to shape
/// with the body, and materials to light.
class _Worn {
  final String key;
  final Node node;
  final ShapeGroup group;
  final List<PreprocessedMaterial> materials;
  const _Worn(this.key, this.node, this.group, this.materials);
}
