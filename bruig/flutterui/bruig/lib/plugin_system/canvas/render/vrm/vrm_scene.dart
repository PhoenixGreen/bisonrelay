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
// drawn by flutter_scene.
//
// The mesh: each shaped group's vertices are packed as the importer packed
// them and uploaded over the old, so skinning and the face's expressions
// carry on as before (an expression is a change on top of the vertices).
//
// The skeleton: flutter_vrm writes every humanoid bone from its rest place
// each frame, so a bone moved directly would be put back. Instead each bone
// that can change sits under a node of its own, put between it and its
// parent when the avatar loads. That node holds T(t')·S(s)·T(-t), where t is
// the bone's rest place and t' its new one: whatever turn the rig gives the
// bone, it lands at t' and draws s times as big, because a scale the same
// every way does not care which way it is turned. Skinning, the spring
// bones and the eyes all follow, as they read where the bones are.
//
// The clothes: each one made to fit is a node of its own beside the body,
// bound to the body's bones, drawn in flutter_vrm's MToon with the skin's
// settings and an outline like the skin's, and shaped with the body. The
// body's own clothes are shown, hidden, or cut shorter; and the skin's
// picture is painted again where they come off.

/// CharacterHit is where a ray met the character: see ShapedAvatar.pick.
typedef CharacterHit = ({
  vm.Vector3 at,
  vm.Vector3 made,
  vm.Vector3 normal,
  double distance,
  String? surface,
});

/// ShapedAvatar is an avatar that can be shaped and dressed.
class ShapedAvatar {
  final VrmAvatar avatar;
  final VrmShapeRig rig;

  /// wardrobe makes its clothes; null for a body they cannot be made for.
  final VrmWardrobe? wardrobe;

  /// holder is what goes in the scene: the avatar inside it, sized by the
  /// character's height.
  final Node holder;

  final Map<String, (Node, vm.Vector3)> _wrappers;
  final Map<ShapeGroup, List<Geometry>> _geometry;
  final Map<VrmPrimitive, TypedData> _indices = {};
  final Map<ShapeGroup, String> _uploaded = {};
  final Map<ShapeGroup, Float32List> _packed = {};
  final Map<VrmRegion, String> _regionKeys = {};
  CharacterShape? _shape;

  /// _body is the body's mesh node; its primitives as drawn are the file's,
  /// then the outlines flutter_vrm adds after them.
  final Node? _body;

  /// _byName is every node of the avatar, by name.
  final Map<String, Node> _byName;

  ShapedAvatar._(this.avatar, this.rig, this.wardrobe, this.holder,
      this._wrappers, this._geometry, this._body, this._byName);

  /// load reads [bytes], a VRM 1.0 file, ready to shape and dress. The file
  /// is read for shaping off the main isolate while the avatar loads.
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
    // Every bone the proportions can move, wrapped before the avatar is in
    // a scene, so nothing has to be mounted again.
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

  /// apply shapes the character as [s] says. Only what [s] changes is
  /// worked out again: a region whose changes are the same is left alone.
  /// Without [bones], the skeleton is left as made: for a character worn
  /// only for its hair, which is placed on another's head, at its size.
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

  // ---------------------------------------------------------------------
  // Shaped by hand.

  List<SculptStroke> _sculpt = const [];
  String _sculptKey = '';
  bool _reshape = false;

  /// sculpt shapes the body by hand as well, with [strokes]
  /// (character_sculpt.dart), on the next [apply].
  void sculpt(List<SculptStroke> strokes) {
    // Asked at every frame: the same list is the same strokes, without
    // hashing every point of every one.
    if (identical(strokes, _sculpt)) return;
    final key = strokes.map((s) => s.key).join(';');
    if (key == _sculptKey) return;
    _sculpt = strokes;
    _sculptKey = key;
    _reshape = true;
  }

  /// _deformers are [region]'s changes: the shaping's, then the strokes'.
  /// Not the hair's, which keeps its own shape over a head shaped by hand.
  List<Deformer> _deformers(VrmRegion region, CharacterShape s) => [
        ...rig.deformers(region, s),
        if (region != VrmRegion.hair) ...StrokeDeformer.of(_sculpt),
      ];

  // ---------------------------------------------------------------------
  // Physics: how the hair and clothes swing.

  /// _springs swings the hair and clothes in place of the avatar's own, with
  /// their settings changed; null for them as made.
  VrmSpringBoneSystem? _springs;
  String _physicsKey = "1.0|1.0|1.0|0.0";

  /// physics swings the hair [hair] times as loose as made and the clothes
  /// [clothes] times, as heavy as [weight] times, in a wind of [wind]
  /// (nought to one) blowing across. flutter_vrm reads the swing settings
  /// once, so a change makes the swing again: from rest, its chains put
  /// back first.
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

  // ---------------------------------------------------------------------
  // The body at rest, for posing (vrm_pose.dart).

  /// bodyAtRest is points on the body at rest, as it is shaped: the skin
  /// of its torso, neck and thighs, and the clothes over them -- its own and
  /// made ones -- every [step]th of each. [cloth] marks the clothes, and
  /// [loose] those that hang away from the body, as a skirt does.
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
    // The body's own clothes, where they are worn: they are in its mesh, and
    // without them arms go through them.
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

  // ---------------------------------------------------------------------
  // The face's expression (character_face.dart).

  /// _faceUnits are the nodes with the face's shapes, each with where its
  /// shapes are by their names after "Fcl_" ("EYE_Joy").
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

  /// _wore is each shape [wear] last set: what it was before, and what it
  /// was set to. flutter_vrm sets again, each frame, only the shapes its own
  /// expressions use; the rest keep what they were given, and would gather
  /// more each frame if this were added to them again.
  final Map<(Node, int), (double, double)> _wore = {};

  /// wear puts [units] on the face, over what the avatar's own expressions
  /// set -- a blink among them, which gives way as far as the eyes are
  /// already closing.
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
        // Unchanged since it was set: flutter_vrm left it alone, so it is
        // still what was set, over what it was before.
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
    // Shapes set before and not now go back to what they were.
    for (final k in _wore.keys.toList()) {
      if (touched.contains(k)) continue;
      final (base, v) = _wore.remove(k)!;
      final live = k.$1.morphWeights;
      if (live != null && (live[k.$2] - v).abs() < 1e-6) {
        k.$1.setMorphWeight(k.$2, base);
      }
    }
  }

  /// blushAt is where a blush goes on each cheek, on the face as made: a
  /// point on the skin under each eye, toward the outside, with the way
  /// it faces; and how big. Empty for a face without its landmarks.
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

  /// creaseKey is what [creases] are drawn from in [shape], so they are
  /// drawn again only when it changes.
  static String creaseKey(CharacterShape shape) => [
        shape.age,
        shape.get("muscle.definition"),
        shape.get("muscle.abs"),
        shape.get("muscle.pecs"),
        shape.get("muscle.fat"),
        shape.get("body.muscle"),
      ].map((v) => v.toStringAsFixed(2)).join(";");

  /// creases are the lines the years and the muscles draw on the skin, as
  /// paint: on the forehead, at the corners of the eyes, under them and
  /// from the nose to the mouth as it ages -- from 35, deepest at 80 -- and
  /// with muscles defined, the line down the middle of the stomach, the
  /// bands across it, the pecs' lower edge on a flat chest and the lines of
  /// the obliques. Laid on the body as made, so they follow its shaping.
  List<PaintStroke> creases(CharacterShape shape) {
    final out = <PaintStroke>[];
    final L = rig.face, B = rig.body;
    const ink = 0x5a3328;
    double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

    // A line through [xy] on the front of the face or the body, followed
    // along the skin, as a stroke -- mirrored onto the other side where it
    // is one of a pair.
    void line(List<(double, double)> xy,
        {required bool face,
        required double radius,
        required double opacity,
        bool mirror = false}) {
      if (opacity < 0.02 || xy.length < 2) return;
      final fwd = L?.fwd ?? 1;
      // Points close enough together for the brush to run unbroken.
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
      // On the skin itself under each point, not on the nearest corner of
      // it: corners are further apart than the brush is wide, and a line
      // laid on them is a row of dots.
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

    // The years, on the face.
    final age = clamp01((shape.age - 35) / 45);
    if (L != null && age > 0) {
      final es = L.es, ey = L.eyeY, r = es * 0.036;
      final cx = (L.eyeL.x + L.eyeR.x) / 2;
      // Across the forehead, more of them the older.
      for (var k = 0; k < 3 && k < (age * 3.2).ceil(); k++) {
        final y = ey + es * (0.95 + 0.22 * k);
        line([
          for (var i = -6; i <= 6; i++)
            (cx + es * 0.85 * i / 6, y + es * 0.05 * (1 - math.pow(i / 6, 2)))
        ], face: true, radius: r, opacity: age * 0.32 * (1 - 0.2 * k));
      }
      // Crow's feet, fanning out from the outer corner of each eye.
      final corner = L.eyeL.x + es * 0.44;
      for (final a in const [-0.4, 0.05, 0.45]) {
        final long = es * 0.16 * (0.6 + 0.4 * age);
        line([
          (corner, ey + a * es * 0.08),
          (corner + math.cos(a) * long, ey + math.sin(a) * long)
        ], face: true, radius: r * 0.8, opacity: age * 0.22, mirror: true);
      }
      // Under each eye.
      line([
        for (var i = 0; i <= 6; i++)
          (
            L.eyeL.x - es * 0.22 + es * 0.55 * i / 6,
            ey - es * 0.42 - es * 0.05 * math.sin(math.pi * i / 6)
          )
      ], face: true, radius: r, opacity: age * 0.28, mirror: true);
      // Bracketing the mouth: from a little over its corners, curving
      // out and down past them -- where the cheeks fold as it ages. Kept
      // close to the mouth: run from the nose on a face drawn with a small
      // high nose, they cross the cheek like whiskers.
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

    // The muscles, on the body: as defined as the body is lean.
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
      // Down the middle, from under the chest to the navel.
      line([(0, top), (0, bottom)],
          face: false, radius: r, opacity: abs * 0.55);
      // The bands across.
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
      // The obliques, down towards the hips.
      line([
        (0.1 * u, B.waist.y - 0.02 * u),
        (0.075 * u, (B.waist.y + B.hips.y) / 2 - 0.02 * u),
        (0.045 * u, B.hips.y - 0.03 * u)
      ], face: false, radius: r, opacity: defined * 0.45, mirror: true);
    }
    return out;
  }

  /// _skinTriangles are the triangles of the front of the face's or the
  /// body's skin, as made -- the side [fwd] along z faces -- whose outline
  /// across x and y reaches into [lo]..[hi]: each as its three corners'
  /// vertex numbers and the positions and normals they index.
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
          // Facing forward, near enough.
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

  /// _onSkin is the point on the front of [triangles] seen straight on at
  /// [x], [y] -- the one nearest the viewer, the side [fwd] along z -- and
  /// which way the skin faces there; null where none is under it.
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

  /// _shapedAt are each group's vertices at rest as last shaped, where
  /// shaping moved them.
  final Map<ShapeGroup, Float32List> _shapedAt = {};

  /// pick is where a ray from [from] going [dir], in the scene, first
  /// meets the body, its face or the clothes it wears: that place on the
  /// body as it is shaped at rest, and as it was made; which way the
  /// surface faces there; how far along the ray it is; and what it is --
  /// "skin", or a piece of clothing by its slot's name, or null for
  /// anything else. Null if it meets none of them.
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

  /// _posed is [g]'s vertices, at rest as [rest], posed as [node] is now:
  /// skinned as the GPU skins them.
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

  /// _rayTriangle is how far along [d] from [o] the ray meets triangle
  /// [i0], [i1], [i2] of [p], and where on it (two barycentric weights);
  /// null where it misses, from either side.
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

  /// restVersion counts the changes to the body's shape and what it
  /// wears: a pose measured at rest is measured again when it moves on.
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

  /// update moves the avatar on by [dt], and lights the clothes as the
  /// avatar is lit.
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

  // ---------------------------------------------------------------------
  // Hair.

  /// _drawn are [node]'s [i]th primitive as drawn: the primitive, and the
  /// outline flutter_vrm draws over the same geometry.
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
  /// look is applied, whose finish draws the lines.
  bool _outlines = true;

  /// _show shows or hides a primitive as [drawn] lists it -- the primitive
  /// first, then its outlines.
  void _show(List<MeshPrimitive> drawn, bool on) {
    for (var k = 0; k < drawn.length; k++) {
      drawn[k].visible = on && (k == 0 || _outlines);
    }
  }

  // ---------------------------------------------------------------------
  // Painting: each material's colour, shading and picture, for the look,
  // the colours picked, and the clothes taken off.

  /// look is the look applied, if any.
  CharacterLook? get look => _look;
  CharacterLook? _look;

  /// _colours are the colours picked, by what they colour (hair, skin, eyes,
  /// brows), as 0xRRGGBB; _hairAs the colour other characters' hair worn
  /// here takes; and how grey the years have turned the hair.
  Map<VrmPart, int> _colours = const {};
  int? _hairAs;
  double _grey = 0;

  /// _bare is whether the skin's painted clothes are taken off above the
  /// knees and below them.
  (bool, bool) _bare = (false, false);

  /// applyLook draws the character in [l]: every MToon material shaded as
  /// [l] shades, and the lines left to the finish (vrm_look.dart).
  /// Without [finished] -- no finish to draw the lines, where its shader
  /// could not be loaded -- flutter_vrm's own outlines stay.
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
        // An outline flutter_vrm added: shown again only where its own
        // primitive is.
        if (!_outlines) mesh.primitives[i].visible = false;
      }
    }
    _recolour();
    if (retexture) _retexture();
  }

  /// colour colours the hair, skin, eyes and brows as [colours] say,
  /// 0xRRGGBB by what they colour, the rest as made. Hair worn from this
  /// character on another's head takes [hairAs] where no colour is picked;
  /// [grey] greys the hair.
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

  /// _materials are the character's own MToon materials, each once, with
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

  /// _maskCutouts makes each cut-out material (cloth and hair whose
  /// picture's clear parts are cut away) cut out in the depth it writes too.
  /// flutter_vrm leaves that off, and the finish, which finds its lines in
  /// depth and normals, would line edges of cloth that is not there.
  void _maskCutouts() {
    for (final (_, m, _) in _materials) {
      final a = m.parameters.assignedValues;
      final tex = a['base_color_texture'];
      if (a['alpha_mode'] != 1 || tex is! gpu.Texture) continue;
      final cutoff = a['alpha_cutoff'];
      // Protected for subclasses that set up their own mask; flutter_vrm's
      // MToon is not one, and there is no other way to give it a mask.
      // ignore: invalid_use_of_protected_member
      m.configureDepthAlphaMask(
        texture: GpuTextureSource(tex),
        cutoff: cutoff is double ? cutoff : 0.5,
      );
    }
  }

  /// _originals are each material's colour and pictures as made, kept the
  /// first time they are changed, to go back to.
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

  /// hairAverage is the colour this character's hair is mostly, once its
  /// picture has been read.
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

  /// _recolour sets every material's colour and shading for the look.
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

  /// _read are the pictures as read, by their bytes, and _pictures as
  /// changed, by what was changed: kept once made.
  final Map<Uint8List, Future<(Uint8List, int, int)>> _read = {};
  final Map<String, Texture2D> _pictures = {};
  Future<List<int>?>? _faceColour;
  int _painting = 0;

  /// _retexture gives each material the picture it is now drawn with: its
  /// own, or its own with the skin's painted clothes taken off, in grey to
  /// be coloured, or in flat tones.
  Future<void> _retexture() async {
    _retexturing++;
    try {
      await _retextureNow();
    } finally {
      _retexturing--;
    }
  }

  int _retexturing = 0;

  /// busy is whether clothes, decals or pictures are still being made.
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

  /// _decode is a picture's RGBA, its width and its height.
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

  /// _readFaceColour is the face's skin colour, from its picture.
  Future<List<int>?> _readFaceColour() async {
    final fb = rig.data.images[VrmPart.face]?.bytes;
    if (fb == null) return null;
    final (px, fw, fh) = await _decode(fb, size: 128);
    return faceSkinColour(px, fw, fh, rig.data);
  }

  /// hairRoles are what each piece of the character's hair is: the fringe,
  /// the back and sides, or the tails.
  late final Map<VrmPrimitive, HairRole> hairRoles = {
    for (final node in rig.data.meshes)
      for (final p in node.primitives)
        if (p.part == VrmPart.hair)
          p: rig.face == null ? HairRole.back : hairRoleOf(p, rig.face!),
  };

  /// showHair shows the pieces of hair [show] says to. As a [donor] -- a
  /// character worn only for its hair -- everything else of it is hidden.
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

  /// headNode is the head's bone.
  Node? get headNode => avatar.humanoid.node(VrmHumanBone.head);

  /// wearOn places this character, worn for its hair, so its head is on
  /// [base]'s head, grown by [grow] to fit it. It is posed as [base] is
  /// first, so its springs and colliders -- its hair's swing, and the
  /// shoulders the hair lies on -- are where [base]'s are, not standing in
  /// the T it was made in.
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
    // Where the head is now, from the holder: put there on [base]'s head.
    final here = (holder.localTransform.clone()..invert()) *
        mine.globalTransform as vm.Matrix4;
    holder.localTransform = head.clone()
      ..scaleByDouble(grow, grow, grow, 1)
      ..multiply(vm.Matrix4.inverted(here));
  }

  // ---------------------------------------------------------------------
  // Dressing.

  final Map<WearSlot, _Worn> _worn = {};
  CharacterOutfit? _want, _dressed;
  bool _dressing = false;

  /// dressError is why the last dressing failed, or null.
  String? dressError;

  /// dress puts [o] on. Clothes take a moment to make, so changes made
  /// while one is being put on wait for it, and only the last is put on.
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
      // show through what is over them.
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
    // Decals on clothes go with the clothes.
    final load = _decalLoad;
    // Through their guards, so two runs never lay the same one twice.
    if (load != null) await decorate(_decalWant, load);
    // And paint on clothes.
    if (_paintWant.isNotEmpty || _paints.isNotEmpty) await paint(_paintWant);
  }

  // ---------------------------------------------------------------------
  // Paint: strokes on the skin and clothes, each surface's drawn into a
  // picture of its own (vrm_paint.dart) on a copy of the triangles painted,
  // a hair off the surface, as decals are.

  final Map<String, _Worn> _paints = {};
  List<PaintStroke> _paintWant = const [];
  bool _paintingLayers = false, _paintAgain = false;

  /// paint paints [strokes] on the character, in place of what was.
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

  /// _paintTargets are the surfaces that can be painted now: an id, what a
  /// stroke on it is said to be on, the node it is drawn beside, its
  /// skin's joints, its vertices and triangles, how far over it paint lies,
  /// and a key that changes when it does.
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
        // A made garment's pattern repeats over it, front and back alike:
        // no place to paint one spot and not another.
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
      // The surface's vertices, or each painted triangle's own.
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

  /// _overlayMaterial is a material that lays [tex] over the skin, as the
  /// skin is drawn, where it is not clear, at depth layer [layer]: drawn over
  /// the surface it lies on at any distance and round any curve, which
  /// lifting it off the surface alone does not hold.
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
    // Both faces: VRoid's clothes wind their triangles either way, so a decal
    // or paint cut from them, drawn from one side, would lose those facing in.
    material.doubleSided = true;
    return material;
  }

  // ---------------------------------------------------------------------
  // Decals: pictures and vectors laid on the skin and clothes.

  final Map<String, _Worn> _decals = {};
  List<CharacterDecal> _decalWant = const [];
  Future<(Uint8List, int, int)?> Function(String source)? _decalLoad;
  final Map<String, Texture2D> _decalPictures = {};
  bool _decorating = false, _decorateAgain = false;

  /// decorate lays [decals] on the character, reading each one's picture
  /// with [load] (RGBA, its width and height). Changes made while some are
  /// being laid on wait for them, and only the last are laid on.
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

  /// _surface is what [on] is now -- the skin, or the piece of clothing
  /// worn -- with a key that changes when it does; null for nothing worn.
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

  /// _clothLift is how far over the body's own clothes (VRoid's, in its
  /// mesh) a decal or paint lies: a little more than over clothes made to
  /// fit. Much more (8 mm) and a decal floats visibly over the buttons and
  /// frills it should lie among; checked across bodies, looks and angles,
  /// nothing hides it at this lift.
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
      // One laid meanwhile is taken off: never two of it, one lost.
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

  /// _skinMaterials are the skin's materials, each with the outline
  /// drawn over the same geometry, if any.
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
        // Cloth has no rim of light, shine, glow or bumps of its own: the
        // skin's warm rim round dark trousers is a glow, and its bumps laid
        // out over a repeated pattern are specks.
        ..setFloat('normal_scale', 0)
        ..setVec3('parametric_rim_color_factor', vm.Vector3.zero())
        ..setVec3('matcap_factor', vm.Vector3.zero())
        ..setVec3('emissive_factor', vm.Vector3.zero());
    }
    // The outline in a dark shade of the cloth, not the skin's: a light
    // line round dark trousers is a glow.
    double linear(int shift) =>
        0.3 * math.pow(((g.colour >> shift) & 0xff) / 255, 2.2);
    outline?.parameters.setVec3(
        'outline_color_factor', vm.Vector3(linear(16), linear(8), linear(0)));
    return _meshNode('wear-${slot.name}', key, mesh, material, outline, body);
  }

  /// _meshNode is [mesh] drawn in [material] (and [outline]), bound to the
  /// body's bones beside it, as a node to add next to it.
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

  /// _setIndices draws [p] with [cut] of its triangles, and says whether
  /// that is a change.
  bool _setIndices(VrmPrimitive p, Uint32List cut) {
    final now = _indices[p];
    if (now != null &&
        now.lengthInBytes ~/ (p.indices32 ? 4 : 2) == cut.length) {
      return false;
    }
    _indices[p] = p.indices32 ? cut : Uint16List.fromList(cut);
    return true;
  }

  /// _showOwn shows the body's own top, bottom and shoes where they are
  /// worn, with their sleeves and trouser legs cut as asked, and hides them
  /// where they are not.
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

/// _Worn is a garment on the character: what it was made from, its node,
/// its shape to be shaped with the body, and its materials to be lit.
class _Worn {
  final String key;
  final Node node;
  final ShapeGroup group;
  final List<PreprocessedMaterial> materials;
  const _Worn(this.key, this.node, this.group, this.materials);
}
