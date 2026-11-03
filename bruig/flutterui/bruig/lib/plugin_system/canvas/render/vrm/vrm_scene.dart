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

  /// The body's mesh node, and its primitives as drawn: the file's, then
  /// the outlines flutter_vrm adds after them.
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
    if (s == _shape && !_resculpt) return;
    _shape = s;
    _resculpt = false;
    for (final region in VrmRegion.values) {
      final ds = _deformers(region, s);
      final key = ds.map((d) => d.key).join(';');
      if (_regionKeys[region] == key) continue;
      _regionKeys[region] = key;
      for (final g in [
        ...rig.groups,
        if (region == VrmRegion.body) ..._worn.values.map((w) => w.group),
        if (region == VrmRegion.body) ..._decals.values.map((w) => w.group)
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
  bool _resculpt = false;

  /// sculpt shapes the body by hand as well, with [strokes]
  /// (character_sculpt.dart), on the next [apply].
  void sculpt(List<SculptStroke> strokes) {
    final key = strokes.map((s) => s.key).join(';');
    if (key == _sculptKey) return;
    _sculpt = strokes;
    _sculptKey = key;
    _resculpt = true;
  }

  /// _deformers are [region]'s changes: the shaping's, then the strokes'.
  /// Not the hair's, which keeps its own shape over a head shaped by hand.
  List<Deformer> _deformers(VrmRegion region, CharacterShape s) => [
        ...rig.deformers(region, s),
        if (region != VrmRegion.hair) ...StrokeDeformer.of(_sculpt),
      ];

  /// _shapedAt are each group's vertices at rest as last shaped, where
  /// shaping moved them.
  final Map<ShapeGroup, Float32List> _shapedAt = {};

  /// pick is where a ray from [from] going [dir], in the scene, first
  /// meets the body, its face or the clothes it wears: that place on the
  /// body as it is shaped at rest, which way the surface faces there, and
  /// how far along the ray it is. Null if it meets none of them.
  ({vm.Vector3 at, vm.Vector3 normal, double distance})? pick(
      vm.Vector3 from, vm.Vector3 dir) {
    final d = dir.normalized();
    var best = double.infinity;
    ({vm.Vector3 at, vm.Vector3 normal, double distance})? hit;
    final groups = <(ShapeGroup, Node?)>[
      for (final g in rig.groups)
        if (g.node.region != VrmRegion.hair && !g.iris)
          (g, _byName[g.node.name]),
      for (final w in _worn.values) (w.group, w.node),
    ];
    for (final (g, node) in groups) {
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
            normal: n.length2 < 1e-12 ? vm.Vector3(0, 0, 1) : n.normalized(),
            distance: r.$1,
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

  void _upload(ShapeGroup g, Float32List packed) {
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
    final l = avatar.mtoonLighting;
    for (final w in _worn.values) {
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

  /// The colours picked, by what they colour (hair, skin, eyes, brows), as
  /// 0xRRGGBB; the colour other characters' hair worn here takes; and how
  /// grey the years have turned the hair.
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

  /// _maskCutouts makes each cut-out material -- cloth and hair whose
  /// picture's clear parts are cut away -- cut out in the depth it writes
  /// too. flutter_vrm leaves that off, so the finish, which finds its lines
  /// in the depth and normals, lined the edges of cloth that is not there:
  /// below a hem, past a sleeve.
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

  /// _hairAverage is the colour this character's hair is mostly, once its
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
    for (final w in [..._worn.values, ..._decals.values]) {
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

  /// The pictures as read, by their bytes, and as changed, by what was
  /// changed: kept once made.
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
  bool get busy => _dressing || _decorating || _retexturing > 0;

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
    if (load != null) await _decorate(_decalWant, load);
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
        DecalSurface(w.skin, Uint32List.fromList(tris), lift: 0.0009),
        "own"
      );
    }
    return null;
  }

  Uint32List? _skinTris;

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
      final material = await loadFmatMaterial(
          'assets/materials/mtoon_blend.fmat',
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
      final worn = _meshNode('decal-${d.id}', key, mesh, material, null, body);
      parent.add(worn.node);
      _decals[d.id] = worn;
      _styleWorn(worn);
      final ds = _deformers(VrmRegion.body, shape);
      _shapeGroup(worn.group, ds, ds.map((x) => x.key).join(';'));
    }
  }

  void _unwear(_Worn w) {
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
      PreprocessedMaterial material, PreprocessedMaterial? outline, Node body) {
    final prim = VrmPrimitive(
        material: name,
        vertices: mesh.vertices,
        indices: mesh.indices,
        indices32: true);
    final node = VrmMeshNode(name, [prim], wardrobe!.body.jointNames);
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

  /// _showOwn shows the body's own top, bottom and shoes where they are
  /// worn, with their sleeves and trouser legs cut as asked, and hides them
  /// where they are not.
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
