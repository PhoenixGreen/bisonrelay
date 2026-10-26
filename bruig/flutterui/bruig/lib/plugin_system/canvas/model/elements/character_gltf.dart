import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/model_math.dart';

// character_gltf.dart reads a 3D character from a glTF file -- .glb, .gltf
// or .vrm, which is a .glb with a little more in it -- into what drawing
// one needs: its meshes, its skeleton and how the meshes hang from it, its
// colours and pictures, its face shapes, and which bone is which.
//
// Only what is in the file: a .gltf that points at other files beside it
// is not read, because a canvas carries one file per model. GLB and VRM are
// one file by nature, and are what a character is nearly always exported
// as.

/// GltfError is a file that is not glTF, or not glTF this can read.
class GltfError implements Exception {
  final String message;
  const GltfError(this.message);
  @override
  String toString() => message;
}

/// HumanBone is a bone of a human skeleton, by the name VRM gives it.
enum HumanBone {
  hips,
  spine,
  chest,
  neck,
  head,
  leftUpperArm,
  leftLowerArm,
  leftHand,
  rightUpperArm,
  rightLowerArm,
  rightHand,
  leftUpperLeg,
  leftLowerLeg,
  leftFoot,
  rightUpperLeg,
  rightLowerLeg,
  rightFoot,
  leftEye,
  rightEye,
}

/// _boneNames is what each human bone is called in the rigs a character is
/// commonly made with -- Mixamo's, Blender's, Unreal's, Character
/// Creator's -- lower case, with any "prefix:" taken off.
const Map<HumanBone, List<String>> _boneNames = {
  HumanBone.hips: ["hips", "hip", "pelvis", "cc_base_hip"],
  HumanBone.spine: ["spine", "spine_01", "spine01", "cc_base_waist"],
  HumanBone.chest: ["chest", "spine2", "spine_02", "spine1", "upperchest", "spine_03", "cc_base_spine02"],
  HumanBone.neck: ["neck", "neck_01", "cc_base_necktwist01"],
  HumanBone.head: ["head", "cc_base_head"],
  HumanBone.leftUpperArm: ["leftarm", "upperarm_l", "upperarm.l", "l_upperarm", "leftupperarm", "lshldr", "cc_base_l_upperarm"],
  HumanBone.leftLowerArm: ["leftforearm", "lowerarm_l", "forearm_l", "forearm.l", "leftlowerarm", "lforearm", "cc_base_l_forearm"],
  HumanBone.leftHand: ["lefthand", "hand_l", "hand.l", "lhand", "cc_base_l_hand"],
  HumanBone.rightUpperArm: ["rightarm", "upperarm_r", "upperarm.r", "r_upperarm", "rightupperarm", "rshldr", "cc_base_r_upperarm"],
  HumanBone.rightLowerArm: ["rightforearm", "lowerarm_r", "forearm_r", "forearm.r", "rightlowerarm", "rforearm", "cc_base_r_forearm"],
  HumanBone.rightHand: ["righthand", "hand_r", "hand.r", "rhand", "cc_base_r_hand"],
  HumanBone.leftUpperLeg: ["leftupleg", "thigh_l", "thigh.l", "upperleg_l", "leftupperleg", "lthigh", "cc_base_l_thigh"],
  HumanBone.leftLowerLeg: ["leftleg", "calf_l", "shin_l", "shin.l", "lowerleg_l", "leftlowerleg", "lshin", "cc_base_l_calf"],
  HumanBone.leftFoot: ["leftfoot", "foot_l", "foot.l", "lfoot", "cc_base_l_foot"],
  HumanBone.rightUpperLeg: ["rightupleg", "thigh_r", "thigh.r", "upperleg_r", "rightupperleg", "rthigh", "cc_base_r_thigh"],
  HumanBone.rightLowerLeg: ["rightleg", "calf_r", "shin_r", "shin.r", "lowerleg_r", "rightlowerleg", "rshin", "cc_base_r_calf"],
  HumanBone.rightFoot: ["rightfoot", "foot_r", "foot.r", "rfoot", "cc_base_r_foot"],
  HumanBone.leftEye: ["lefteye", "eye_l", "eye.l"],
  HumanBone.rightEye: ["righteye", "eye_r", "eye.r"],
};

/// GltfNode is one node of the scene: a place, maybe a mesh hung on it,
/// and its children.
/// mouthLandmark names a node marking where the mouth is -- with no skin
/// on it, riding on the head -- for a face drawn over the model. The
/// sculpted body has one; see buildHuman.
const String mouthLandmark = "face.mouth";

class GltfNode {
  final String name;
  int parent;
  final List<int> children;
  final List<double> translation;
  final Quat rotation;
  final List<double> scale;

  /// matrix, where the file gives one in place of the three above.
  final Mat4? matrix;
  final int? mesh;
  final int? skin;

  GltfNode(this.name, this.children, this.translation, this.rotation,
      this.scale, this.matrix, this.mesh, this.skin)
      : parent = -1;

  /// local is where it is against its parent, turned by [turn] in place of
  /// its own turn when given.
  Mat4 local([Quat? turn]) =>
      matrix ?? Mat4.trs(translation, turn ?? rotation, scale);
}

/// GltfPrimitive is one piece of a mesh, in one material.
class GltfPrimitive {
  final Float32List positions;
  final Float32List? normals;
  final Float32List? uvs;
  final Uint16List? joints;
  final Float32List? weights;
  final Float32List? colors;
  final Uint32List indices;
  final int? material;

  /// targets are its face shapes: how far each vertex moves for each.
  final List<Float32List> targets;

  const GltfPrimitive(this.positions, this.normals, this.uvs, this.joints,
      this.weights, this.colors, this.indices, this.material, this.targets);

  int get vertexCount => positions.length ~/ 3;
}

class GltfMesh {
  final String name;
  final List<GltfPrimitive> primitives;

  /// targetNames are its face shapes' names, where the file gives them.
  final List<String> targetNames;
  final List<double> weights;
  const GltfMesh(this.name, this.primitives, this.targetNames, this.weights);
}

class GltfSkin {
  final List<int> joints;
  final List<Mat4> inverseBind;
  const GltfSkin(this.joints, this.inverseBind);
}

class GltfMaterial {
  /// color is its base colour, red green blue alpha from 0 to 1.
  final List<double> color;

  /// image is the picture its colour comes from, or null.
  final int? image;
  final bool doubleSided;

  /// toon is whether it asks to be drawn flat-lit, cel-shaded -- an unlit
  /// material, or VRM's MToon.
  final bool toon;
  final bool transparent;

  /// mtoon is how VRM's toon shader would draw it, when it says.
  final MToon? mtoon;

  /// cutOut is a picture used only for where it is solid -- a hair card --
  /// its colour coming from the vertices.
  final bool cutOut;
  const GltfMaterial(
      this.color, this.image, this.doubleSided, this.toon, this.transparent,
      {this.mtoon, this.cutOut = false});

  GltfMaterial withImage(int? image) => GltfMaterial(
      color, image, doubleSided, toon, transparent,
      mtoon: mtoon, cutOut: cutOut);

  GltfMaterial withMToon(MToon m) => GltfMaterial(
      color, image, doubleSided, true, transparent,
      mtoon: m, cutOut: cutOut);
}

/// MToon is a material's toon settings, as VRM keeps them: the colour its
/// shadow is, how hard the line between light and shadow is (toony, from
/// soft at nought to a hard edge at one) and where it falls (shift, below
/// nought further round into the light), a rim of light round its edge,
/// and the width and colour of its outline.
class MToon {
  final List<double> shade;
  final double toony;
  final double shift;
  final List<double> rim;
  final double rimPower;
  final double outlineWidth;
  final List<double> outlineColor;
  const MToon({
    this.shade = const [0.8, 0.75, 0.85],
    this.toony = 0.9,
    this.shift = 0,
    this.rim = const [0, 0, 0],
    this.rimPower = 5,
    this.outlineWidth = 0,
    this.outlineColor = const [0, 0, 0],
  });
}

/// GltfChannel is one property of one node moving: its key times in
/// seconds, and its values at them -- three numbers a key for a move or a
/// size, four for a turn.
class GltfChannel {
  final int node;

  /// path is "translation", "rotation" or "scale".
  final String path;
  final Float32List times;
  final Float32List values;

  /// step holds each value until the next key, rather than easing.
  final bool step;
  const GltfChannel(this.node, this.path, this.times, this.values, this.step);

  int get size => path == "rotation" ? 4 : 3;

  /// at is the value at [t] seconds.
  List<double> at(double t) {
    var n = times.length, k = size;
    if (n == 0) return List.filled(k, 0);
    List<double> key(int i) => [for (var c = 0; c < k; c++) values[i * k + c]];
    if (t <= times.first) return key(0);
    if (t >= times[n - 1]) return key(n - 1);
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      var mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    if (step) return key(lo);
    var f = (t - times[lo]) / (times[hi] - times[lo]);
    if (k == 4) {
      var a = key(lo), b = key(hi);
      var q = Quat.slerp(Quat(a[0], a[1], a[2], a[3]), Quat(b[0], b[1], b[2], b[3]), f);
      return [q.x, q.y, q.z, q.w];
    }
    var a = key(lo), b = key(hi);
    return [for (var c = 0; c < k; c++) a[c] + (b[c] - a[c]) * f];
  }
}

/// GltfAnimation is one of a file's motions: a name, and what it moves.
class GltfAnimation {
  final String name;
  final List<GltfChannel> channels;
  const GltfAnimation(this.name, this.channels);

  double get seconds => channels.fold(
      0.0, (m, c) => c.times.isEmpty ? m : (c.times.last > m ? c.times.last : m));
}

/// ExpressionBind is one face shape a VRM expression turns on, and how far.
typedef ExpressionBind = ({int mesh, int target, double weight});

/// Gltf is a whole file, read.
class Gltf {
  final List<GltfNode> nodes;
  final List<GltfMesh> meshes;
  final List<GltfSkin> skins;
  final List<GltfMaterial> materials;

  /// images are the pictures, as the bytes of PNG or JPEG files.
  final List<Uint8List?> images;
  final List<int> roots;

  /// humanoid is which node each bone of a human skeleton is, as far as
  /// the file says or its names suggest.
  final Map<HumanBone, int> humanoid;

  /// expressions are VRM's named expressions -- "happy", "aa", "blink" --
  /// and what each turns on.
  final Map<String, List<ExpressionBind>> expressions;

  /// vrm is the VRM version -- 0 or 1 -- or null for plain glTF.
  final int? vrm;
  final String title;
  final List<GltfAnimation> animations;

  const Gltf(this.nodes, this.meshes, this.skins, this.materials, this.images,
      this.roots, this.humanoid, this.expressions, this.vrm, this.title,
      [this.animations = const []]);

  /// facesBack is whether the character faces away down -z, as VRM 0
  /// characters do, rather than towards +z as glTF says it should.
  bool get facesBack => vrm == 0;

  /// world is every node's place in the scene, with [turns] in place of
  /// the nodes' own turns where given, and [moves] in place of where they
  /// are against their parents.
  List<Mat4> world(
      [Map<int, Quat> turns = const {},
      Map<int, List<double>> moves = const {}]) {
    var out = List<Mat4?>.filled(nodes.length, null);
    Mat4 at(int i) {
      if (out[i] case var m?) return m;
      var n = nodes[i];
      var move = moves[i];
      var local = move == null
          ? n.local(turns[i])
          : Mat4.trs(move, turns[i] ?? n.rotation, n.scale);
      return out[i] = n.parent < 0 ? local : at(n.parent) * local;
    }

    for (var i = 0; i < nodes.length; i++) {
      at(i);
    }
    return [for (var m in out) m!];
  }
}

/// parseGltf reads [bytes], a .glb or a .gltf, or throws a GltfError.
Gltf parseGltf(Uint8List bytes) {
  Map<String, dynamic> json;
  Uint8List? bin;
  var data = ByteData.sublistView(bytes);
  if (bytes.length >= 12 && String.fromCharCodes(bytes.sublist(0, 4)) == "glTF") {
    var length = data.getUint32(8, Endian.little);
    var at = 12;
    Map<String, dynamic>? found;
    while (at + 8 <= length && at + 8 <= bytes.length) {
      var size = data.getUint32(at, Endian.little);
      var type = data.getUint32(at + 4, Endian.little);
      var chunk = Uint8List.sublistView(bytes, at + 8, at + 8 + size);
      if (type == 0x4E4F534A) {
        found = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
      } else if (type == 0x004E4942) {
        bin = chunk;
      }
      at += 8 + size;
    }
    if (found == null) throw const GltfError("The file has no scene in it.");
    json = found;
  } else {
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const GltfError("This is not a glTF, GLB or VRM file.");
    }
  }
  return _Reader(json, bin).read();
}

class _Reader {
  final Map<String, dynamic> json;
  final Uint8List? bin;
  final List<Uint8List?> _buffers = [];

  _Reader(this.json, this.bin);

  List<dynamic> list(String key) => (json[key] as List?) ?? const [];

  Gltf read() {
    for (var (i, b) in list("buffers").indexed) {
      var uri = (b as Map)["uri"] as String?;
      if (uri == null) {
        _buffers.add(i == 0 ? bin : null);
      } else if (uri.startsWith("data:")) {
        _buffers.add(base64Decode(uri.substring(uri.indexOf(",") + 1)));
      } else {
        throw const GltfError("This glTF keeps its data in other files. "
            "Export it as a single .glb file instead.");
      }
    }

    var nodes = <GltfNode>[];
    for (var n in list("nodes")) {
      var m = n as Map;
      List<double> v(String k, List<double> d) =>
          [for (var x in (m[k] as List?) ?? d) (x as num).toDouble()];
      var r = v("rotation", const [0, 0, 0, 1]);
      var t = v("translation", const [0, 0, 0]);
      var sc = v("scale", const [1, 1, 1]);
      var q = Quat(r[0], r[1], r[2], r[3]);
      // A node placed by a matrix is taken apart into where, how turned
      // and how big, so it can be turned like any other.
      if (m["matrix"] is List) {
        var mat = Mat4(Float64List.fromList(v("matrix", const [])));
        t = mat.translation;
        sc = [
          length([mat.m[0], mat.m[1], mat.m[2]]),
          length([mat.m[4], mat.m[5], mat.m[6]]),
          length([mat.m[8], mat.m[9], mat.m[10]]),
        ];
        q = mat.rotation;
      }
      nodes.add(GltfNode(
          (m["name"] as String?) ?? "",
          [for (var c in (m["children"] as List?) ?? const []) (c as num).toInt()],
          t,
          q,
          sc,
          null,
          (m["mesh"] as num?)?.toInt(),
          (m["skin"] as num?)?.toInt()));
    }
    for (var (i, n) in nodes.indexed) {
      for (var c in n.children) {
        if (c >= 0 && c < nodes.length) nodes[c].parent = i;
      }
    }

    var meshes = [
      for (var m in list("meshes")) _mesh(m as Map),
    ];
    var skins = [
      for (var s in list("skins"))
        GltfSkin(
          [for (var j in ((s as Map)["joints"] as List)) (j as num).toInt()],
          s["inverseBindMatrices"] == null
              ? [
                  for (var _ in (s["joints"] as List)) Mat4.identity(),
                ]
              : _matrices((s["inverseBindMatrices"] as num).toInt()),
        ),
    ];
    var materials = [for (var m in list("materials")) _material(m as Map)];
    var images = [for (var im in list("images")) _image(im as Map)];
    var textures = list("textures");
    // A material names a texture, which names an image: resolved here, so
    // a material carries the image it shows.
    materials = [
      for (var m in materials)
        m.withImage(m.image == null || m.image! >= textures.length
            ? null
            : ((textures[m.image!] as Map)["source"] as num?)?.toInt()),
    ];
    // VRM 0 keeps its toon settings apart from the materials, by name.
    var props = ((json["extensions"] as Map?)?["VRM"] as Map?)?["materialProperties"];
    if (props is List) {
      var names = [for (var m in list("materials")) (m as Map)["name"] as String?];
      for (var p in props) {
        if (p is! Map || p["shader"] != "VRM/MToon") continue;
        var i = names.indexOf(p["name"] as String?);
        if (i < 0 || i >= materials.length) continue;
        var vec = (p["vectorProperties"] as Map?) ?? const {};
        var fl = (p["floatProperties"] as Map?) ?? const {};
        List<double> rgb(Object? v, List<double> or) => v is List && v.length >= 3
            ? [for (var k = 0; k < 3; k++) (v[k] as num).toDouble()]
            : or;
        double f(String k, double or) => (fl[k] as num?)?.toDouble() ?? or;
        materials[i] = materials[i].withMToon(MToon(
          shade: rgb(vec["_ShadeColor"], const [0.8, 0.75, 0.85]),
          toony: f("_ShadeToony", 0.9),
          shift: f("_ShadeShift", 0),
          rim: rgb(vec["_RimColor"], const [0, 0, 0]),
          rimPower: f("_RimFresnelPower", 5),
          // VRM 0's outline width is in centimetres.
          outlineWidth: f("_OutlineWidth", 0) / 100,
          outlineColor: rgb(vec["_OutlineColor"], const [0, 0, 0]),
        ));
      }
    }

    var scene = list("scenes").isEmpty
        ? null
        : list("scenes")[(json["scene"] as num?)?.toInt() ?? 0] as Map;
    var roots = scene == null
        ? [
            for (var (i, n) in nodes.indexed)
              if (n.parent < 0) i
          ]
        : [for (var r in (scene["nodes"] as List?) ?? const []) (r as num).toInt()];

    var (vrm, humanoid, expressions) = _vrm(nodes, meshes);
    var title = ((json["asset"] as Map?)?["extras"] as Map?)?["title"] as String? ??
        (((json["extensions"] as Map?)?["VRMC_vrm"] as Map?)?["meta"] as Map?)?["name"] as String? ??
        "";
    var animations = <GltfAnimation>[];
    for (var (i, a) in list("animations").indexed) {
      var am = a as Map;
      var samplers = (am["samplers"] as List?) ?? const [];
      var channels = <GltfChannel>[];
      for (var c in (am["channels"] as List?) ?? const []) {
        var cm = c as Map;
        var target = cm["target"] as Map?;
        var node = (target?["node"] as num?)?.toInt();
        var path = target?["path"] as String?;
        var si = (cm["sampler"] as num?)?.toInt();
        if (node == null || si == null || si >= samplers.length) continue;
        if (path != "translation" && path != "rotation" && path != "scale") {
          continue;
        }
        var sm = samplers[si] as Map;
        var times = _floats((sm["input"] as num).toInt());
        var values = _floats((sm["output"] as num).toInt());
        var size = path == "rotation" ? 4 : 3;
        // A cubic spline keeps an in-tangent, the value and an out-tangent
        // for each key: the value is all a motion needs.
        if (sm["interpolation"] == "CUBICSPLINE") {
          values = Float32List.fromList([
            for (var k = 0; k < times.length; k++)
              for (var c = 0; c < size; c++) values[(k * 3 + 1) * size + c],
          ]);
        }
        channels.add(GltfChannel(
            node, path!, times, values, sm["interpolation"] == "STEP"));
      }
      if (channels.isNotEmpty) {
        animations.add(GltfAnimation(
            (am["name"] as String?) ?? "Motion ${i + 1}", channels));
      }
    }
    return Gltf(nodes, meshes, skins, materials, images, roots, humanoid,
        expressions, vrm, title, animations);
  }

  GltfMesh _mesh(Map m) {
    var prims = <GltfPrimitive>[];
    for (var p in (m["primitives"] as List)) {
      var pm = p as Map;
      var mode = (pm["mode"] as num?)?.toInt() ?? 4;
      if (mode != 4) continue; // Only triangles: lines and points are not skin.
      var attrs = pm["attributes"] as Map;
      int? a(String k) => (attrs[k] as num?)?.toInt();
      var positions = _floats(a("POSITION")!);
      var count = positions.length ~/ 3;
      var indices = pm["indices"] == null
          ? Uint32List.fromList([for (var i = 0; i < count; i++) i])
          : _ints((pm["indices"] as num).toInt());
      Float32List? colors;
      if (a("COLOR_0") case var c?) {
        var raw = _floats(c);
        var size = raw.length ~/ count;
        colors = Float32List(count * 4);
        for (var i = 0; i < count; i++) {
          for (var k = 0; k < 4; k++) {
            colors[i * 4 + k] = k < size ? raw[i * size + k] : 1;
          }
        }
      }
      prims.add(GltfPrimitive(
        positions,
        a("NORMAL") == null ? null : _floats(a("NORMAL")!),
        a("TEXCOORD_0") == null ? null : _floats(a("TEXCOORD_0")!),
        a("JOINTS_0") == null
            ? null
            : Uint16List.fromList(_ints(a("JOINTS_0")!)),
        a("WEIGHTS_0") == null ? null : _floats(a("WEIGHTS_0")!),
        colors,
        indices,
        (pm["material"] as num?)?.toInt(),
        [
          for (var t in (pm["targets"] as List?) ?? const [])
            if ((t as Map)["POSITION"] != null)
              _floats((t["POSITION"] as num).toInt())
            else
              Float32List(positions.length),
        ],
      ));
    }
    var extras = m["extras"] as Map?;
    return GltfMesh(
      (m["name"] as String?) ?? "",
      prims,
      [for (var n in (extras?["targetNames"] as List?) ?? const []) "$n"],
      [for (var w in (m["weights"] as List?) ?? const []) (w as num).toDouble()],
    );
  }

  GltfMaterial _material(Map m) {
    var pbr = m["pbrMetallicRoughness"] as Map?;
    var color = [
      for (var c in (pbr?["baseColorFactor"] as List?) ?? const [1, 1, 1, 1])
        (c as num).toDouble()
    ];
    var ext = m["extensions"] as Map?;
    MToon? mtoon;
    if (ext?["VRMC_materials_mtoon"] case Map t) {
      List<double> rgb(Object? v, List<double> or) => v is List && v.length >= 3
          ? [for (var k = 0; k < 3; k++) (v[k] as num).toDouble()]
          : or;
      double f(String k, double or) => (t[k] as num?)?.toDouble() ?? or;
      mtoon = MToon(
        shade: rgb(t["shadeColorFactor"], const [0.8, 0.75, 0.85]),
        toony: f("shadingToonyFactor", 0.9),
        shift: f("shadingShiftFactor", 0),
        rim: rgb(t["parametricRimColorFactor"], const [0, 0, 0]),
        rimPower: f("parametricRimFresnelPowerFactor", 5),
        outlineWidth: t["outlineWidthMode"] == "none" ? 0 : f("outlineWidthFactor", 0),
        outlineColor: rgb(t["outlineColorFactor"], const [0, 0, 0]),
      );
    }
    return GltfMaterial(
      color,
      ((pbr?["baseColorTexture"] as Map?)?["index"] as num?)?.toInt(),
      (m["doubleSided"] as bool?) ?? false,
      ext?.containsKey("KHR_materials_unlit") == true || mtoon != null,
      m["alphaMode"] == "BLEND",
      mtoon: mtoon,
    );
  }

  Uint8List? _image(Map im) {
    if (im["bufferView"] is num) {
      return _view((im["bufferView"] as num).toInt());
    }
    var uri = im["uri"] as String?;
    if (uri != null && uri.startsWith("data:")) {
      return base64Decode(uri.substring(uri.indexOf(",") + 1));
    }
    return null;
  }

  Uint8List _view(int i) {
    var v = list("bufferViews")[i] as Map;
    var buffer = _buffers[(v["buffer"] as num).toInt()];
    if (buffer == null) throw const GltfError("The file is missing its data.");
    var offset = (v["byteOffset"] as num?)?.toInt() ?? 0;
    var length = (v["byteLength"] as num).toInt();
    return Uint8List.sublistView(buffer, offset, offset + length);
  }

  /// _values is accessor [i] read as numbers, one list per element.
  (List<double>, int) _values(int i) {
    var a = list("accessors")[i] as Map;
    var count = (a["count"] as num).toInt();
    var size = switch (a["type"]) {
      "SCALAR" => 1,
      "VEC2" => 2,
      "VEC3" => 3,
      "VEC4" => 4,
      "MAT4" => 16,
      _ => 1,
    };
    var type = (a["componentType"] as num).toInt();
    var normalized = (a["normalized"] as bool?) ?? false;
    var out = List<double>.filled(count * size, 0);
    if (a["bufferView"] is num) {
      var v = list("bufferViews")[(a["bufferView"] as num).toInt()] as Map;
      var bytes = _view((a["bufferView"] as num).toInt());
      var data = ByteData.sublistView(bytes);
      var start = (a["byteOffset"] as num?)?.toInt() ?? 0;
      var comp = _componentSize(type);
      var stride = (v["byteStride"] as num?)?.toInt() ?? comp * size;
      for (var e = 0; e < count; e++) {
        for (var k = 0; k < size; k++) {
          out[e * size + k] =
              _read(data, start + e * stride + k * comp, type, normalized);
        }
      }
    }
    // A sparse accessor is mostly its base -- or zeros -- with a few
    // elements given: how morph targets are usually stored.
    if (a["sparse"] case Map sparse) {
      var n = (sparse["count"] as num).toInt();
      var idx = sparse["indices"] as Map, val = sparse["values"] as Map;
      var iData = ByteData.sublistView(_view((idx["bufferView"] as num).toInt()));
      var vData = ByteData.sublistView(_view((val["bufferView"] as num).toInt()));
      var iType = (idx["componentType"] as num).toInt();
      var iStart = (idx["byteOffset"] as num?)?.toInt() ?? 0;
      var vStart = (val["byteOffset"] as num?)?.toInt() ?? 0;
      var comp = _componentSize(type);
      for (var s = 0; s < n; s++) {
        var e = _read(iData, iStart + s * _componentSize(iType), iType, false).toInt();
        for (var k = 0; k < size; k++) {
          out[e * size + k] =
              _read(vData, vStart + (s * size + k) * comp, type, normalized);
        }
      }
    }
    return (out, size);
  }

  Float32List _floats(int i) => Float32List.fromList(_values(i).$1);
  Uint32List _ints(int i) =>
      Uint32List.fromList([for (var v in _values(i).$1) v.round()]);

  List<Mat4> _matrices(int i) {
    var (v, _) = _values(i);
    return [
      for (var k = 0; k + 16 <= v.length; k += 16)
        Mat4(Float64List.fromList(v.sublist(k, k + 16))),
    ];
  }

  static int _componentSize(int type) => switch (type) {
        5120 || 5121 => 1,
        5122 || 5123 => 2,
        _ => 4,
      };

  static double _read(ByteData d, int at, int type, bool normalized) {
    switch (type) {
      case 5120:
        var v = d.getInt8(at).toDouble();
        return normalized ? (v / 127).clamp(-1.0, 1.0) : v;
      case 5121:
        var v = d.getUint8(at).toDouble();
        return normalized ? v / 255 : v;
      case 5122:
        var v = d.getInt16(at, Endian.little).toDouble();
        return normalized ? (v / 32767).clamp(-1.0, 1.0) : v;
      case 5123:
        var v = d.getUint16(at, Endian.little).toDouble();
        return normalized ? v / 65535 : v;
      case 5125:
        return d.getUint32(at, Endian.little).toDouble();
      default:
        return d.getFloat32(at, Endian.little);
    }
  }

  /// _vrm is the file's VRM version, its human skeleton and its
  /// expressions -- from VRM where it is VRM, and from the bones' names
  /// otherwise.
  (int?, Map<HumanBone, int>, Map<String, List<ExpressionBind>>) _vrm(
      List<GltfNode> nodes, List<GltfMesh> meshes) {
    var ext = json["extensions"] as Map?;
    var humanoid = <HumanBone, int>{};
    var expressions = <String, List<ExpressionBind>>{};
    int? version;
    // Which mesh a node shows: VRM 1 names expression shapes by node.
    int? meshOf(int node) =>
        node >= 0 && node < nodes.length ? nodes[node].mesh : null;

    if (ext?["VRMC_vrm"] case Map vrm1) {
      version = 1;
      var bones = (vrm1["humanoid"] as Map?)?["humanBones"] as Map?;
      for (var e in (bones ?? const {}).entries) {
        var bone = HumanBone.values.where((b) => b.name == e.key).firstOrNull;
        var node = ((e.value as Map)["node"] as num?)?.toInt();
        if (bone != null && node != null) humanoid[bone] = node;
      }
      var ex = vrm1["expressions"] as Map?;
      for (var group in [ex?["preset"], ex?["custom"]]) {
        if (group is! Map) continue;
        for (var e in group.entries) {
          var binds = <ExpressionBind>[];
          for (var b in ((e.value as Map)["morphTargetBinds"] as List?) ?? const []) {
            var bm = b as Map;
            var mesh = meshOf((bm["node"] as num).toInt());
            if (mesh == null) continue;
            binds.add((
              mesh: mesh,
              target: (bm["index"] as num).toInt(),
              weight: (bm["weight"] as num?)?.toDouble() ?? 1,
            ));
          }
          expressions["${e.key}".toLowerCase()] = binds;
        }
      }
    } else if (ext?["VRM"] case Map vrm0) {
      version = 0;
      for (var b in ((vrm0["humanoid"] as Map?)?["humanBones"] as List?) ?? const []) {
        var bm = b as Map;
        var bone = HumanBone.values.where((x) => x.name == bm["bone"]).firstOrNull;
        var node = (bm["node"] as num?)?.toInt();
        if (bone != null && node != null) humanoid[bone] = node;
      }
      // VRM 0's names for the expressions, in VRM 1's words.
      const renamed = {
        "joy": "happy",
        "sorrow": "sad",
        "fun": "relaxed",
        "a": "aa",
        "i": "ih",
        "u": "ou",
        "e": "ee",
        "o": "oh",
        "blink_l": "blinkleft",
        "blink_r": "blinkright",
      };
      for (var g in ((vrm0["blendShapeMaster"] as Map?)?["blendShapeGroups"] as List?) ?? const []) {
        var gm = g as Map;
        var name = "${gm["presetName"] ?? gm["name"] ?? ""}".toLowerCase();
        if (name.isEmpty || name == "unknown") name = "${gm["name"]}".toLowerCase();
        expressions[renamed[name] ?? name] = [
          for (var b in (gm["binds"] as List?) ?? const [])
            (
              mesh: ((b as Map)["mesh"] as num).toInt(),
              target: (b["index"] as num).toInt(),
              // VRM 0 counts weights to a hundred.
              weight: ((b["weight"] as num?)?.toDouble() ?? 100) / 100,
            ),
        ];
      }
    }
    // Whatever the file did not say, by the bones' names.
    for (var e in _boneNames.entries) {
      if (humanoid.containsKey(e.key)) continue;
      for (var name in e.value) {
        var at = nodes.indexWhere(
            (n) => n.name.split(":").last.toLowerCase() == name);
        if (at >= 0) {
          humanoid[e.key] = at;
          break;
        }
      }
    }
    if (expressions.isEmpty) expressions.addAll(_guessExpressions(meshes));
    return (version, humanoid, expressions);
  }
}

/// _shapeNames is what a face shape doing each expression is called in the
/// rigs that are not VRM -- Apple's ARKit names, Ready Player Me's visemes,
/// Character Creator's -- lower case. Every shape that matches is turned
/// on, so a smile made of a left and a right half turns on both.
const Map<String, List<String>> _shapeNames = {
  "happy": ["mouthsmileleft", "mouthsmileright", "mouthsmile", "smile", "mouth_smile", "happy", "joy"],
  "sad": ["mouthfrownleft", "mouthfrownright", "mouthfrown", "frown", "sad", "sorrow"],
  "angry": ["browdownleft", "browdownright", "browdown", "angry", "brow_drop"],
  "surprised": ["browouterupleft", "browouterupright", "browinnerup", "eyewideleft", "eyewideright", "surprised", "surprise"],
  "blink": ["eyeblinkleft", "eyeblinkright", "eyeblink", "blink", "eyesclosed", "eye_blink", "eyes_closed"],
  "blinkleft": ["eyeblinkleft", "eye_blink_l", "blink_l"],
  "blinkright": ["eyeblinkright", "eye_blink_r", "blink_r"],
  "aa": ["viseme_aa", "jawopen", "mouthopen", "mouth_open", "aa", "a"],
  "ih": ["viseme_i", "ih", "i", "mouthstretchleft", "mouthstretchright"],
  "ou": ["viseme_u", "mouthpucker", "ou", "u"],
  "ee": ["viseme_e", "ee", "e"],
  "oh": ["viseme_o", "mouthfunnel", "oh", "o"],
};

Map<String, List<ExpressionBind>> _guessExpressions(List<GltfMesh> meshes) {
  var out = <String, List<ExpressionBind>>{};
  for (var e in _shapeNames.entries) {
    var binds = <ExpressionBind>[];
    for (var (m, mesh) in meshes.indexed) {
      for (var (t, name) in mesh.targetNames.indexed) {
        var n = name.split(".").last.toLowerCase();
        if (e.value.contains(n)) binds.add((mesh: m, target: t, weight: 1));
      }
    }
    if (binds.isNotEmpty) out[e.key] = binds;
  }
  return out;
}


/// _motionNames is the name each human bone goes by when a glTF motion is
/// handed to motionPoses -- Mixamo's, which it knows.
const Map<HumanBone, String> _motionNames = {
  HumanBone.hips: "hips",
  HumanBone.spine: "spine",
  HumanBone.chest: "spine2",
  HumanBone.neck: "neck",
  HumanBone.head: "head",
  HumanBone.leftUpperArm: "leftarm",
  HumanBone.leftLowerArm: "leftforearm",
  HumanBone.leftHand: "lefthand",
  HumanBone.rightUpperArm: "rightarm",
  HumanBone.rightLowerArm: "rightforearm",
  HumanBone.rightHand: "righthand",
  HumanBone.leftUpperLeg: "leftupleg",
  HumanBone.leftLowerLeg: "leftleg",
  HumanBone.leftFoot: "leftfoot",
  HumanBone.rightUpperLeg: "rightupleg",
  HumanBone.rightLowerLeg: "rightleg",
  HumanBone.rightFoot: "rightfoot",
};

/// gltfMotion is [gltf]'s animation [index] as a skeleton moving, sampled
/// at [frameRate] -- its human bones named so motionPoses finds them,
/// whatever the file called them.
JointMotion gltfMotion(Gltf gltf, {int index = 0, double frameRate = 30}) {
  if (gltf.animations.isEmpty) {
    throw const MotionError("The file has no motion in it.");
  }
  var anim = gltf.animations[index.clamp(0, gltf.animations.length - 1)];
  var byNode = {for (var e in gltf.humanoid.entries) e.value: e.key};
  var names = [
    for (var (i, n) in gltf.nodes.indexed)
      _motionNames[byNode[i]] ?? (n.name.isEmpty ? "node$i" : n.name),
  ];
  // VRM 0 faces away; turned round, so its left is on the same side as
  // every other skeleton's.
  var turnRound = gltf.facesBack;
  var frames = (anim.seconds * frameRate).round() + 1;
  return JointMotion(names, frames, 1 / frameRate, (f) {
    var t = f / frameRate;
    var turns = <int, Quat>{};
    var moves = <int, List<double>>{};
    for (var c in anim.channels) {
      if (c.node >= gltf.nodes.length) continue;
      var v = c.at(t);
      if (c.path == "rotation") {
        turns[c.node] = Quat(v[0], v[1], v[2], v[3]);
      } else if (c.path == "translation") {
        moves[c.node] = v;
      }
    }
    return [
      for (var m in gltf.world(turns, moves))
        turnRound
            ? [-m.translation[0], m.translation[1], -m.translation[2]]
            : m.translation,
    ];
  });
}
