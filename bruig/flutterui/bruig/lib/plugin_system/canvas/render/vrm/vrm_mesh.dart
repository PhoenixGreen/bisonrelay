import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

// vrm_mesh.dart reads from a VRM file what shaping it needs: each mesh's
// vertices as flutter_scene holds them, which part of the character each
// primitive draws, which bone each vertex follows, and the skeleton at rest.
// Plain Dart, so it can be read off the main isolate and tested without a
// GPU.
//
// flutter_scene gives every primitive of a mesh the mesh's whole vertex
// buffer, in the file's order, and draws only what its own indices use: a
// VRoid face is ten primitives over one set of 2,300 vertices. So a vertex
// here is the file's vertex, and [VrmPrimitive.used] says which of them a
// primitive draws.

/// VrmPart is what a primitive draws, from its material's name.
enum VrmPart { eyes, brows, mouth, face, skin, hair, top, bottom, shoes, other }

/// vrmPartOf names what a VRoid material draws.
VrmPart vrmPartOf(String material) {
  if (RegExp(r'EyeWhite|EyeIris|EyeHighlight|FaceEyeline|FaceEyelash|EyeExtra')
      .hasMatch(material)) {
    return VrmPart.eyes;
  }
  if (material.contains('FaceBrow')) return VrmPart.brows;
  if (material.contains('FaceMouth')) return VrmPart.mouth;
  if (material.contains('Face_00_SKIN')) return VrmPart.face;
  if (material.contains('Body_00_SKIN')) return VrmPart.skin;
  if (material.contains('HAIR')) return VrmPart.hair;
  if (material.contains('Tops')) return VrmPart.top;
  if (material.contains('Bottoms')) return VrmPart.bottom;
  if (material.contains('Shoes')) return VrmPart.shoes;
  return VrmPart.other;
}

/// VrmRegion is which of the character's meshes a primitive is in: they are
/// shaped by different rules.
enum VrmRegion { face, hair, body }

VrmRegion vrmRegionOf(String nodeName) => nodeName.contains('Face')
    ? VrmRegion.face
    : nodeName.contains('Hair')
        ? VrmRegion.hair
        : VrmRegion.body;

/// VrmVertices are a set of vertices several primitives share, with what
/// is worked out from them once.
class VrmVertices {
  final Float32List positions,
      normals,
      uv0,
      uv1,
      colors,
      tangents,
      joints,
      weights;
  final bool skinned;

  /// weld numbers each vertex by where it is, so the copies of one point
  /// along a texture seam are one point when normals are worked out.
  final Int32List weld;
  final int weldCount;

  /// domBone is, for each vertex, the joint it follows most (an index into
  /// the skin's joints); empty when not skinned.
  final Int16List domBone;

  VrmVertices._(
      this.positions,
      this.normals,
      this.uv0,
      this.uv1,
      this.colors,
      this.tangents,
      this.joints,
      this.weights,
      this.skinned,
      this.weld,
      this.weldCount,
      this.domBone);

  factory VrmVertices({
    required Float32List positions,
    required Float32List normals,
    required Float32List uv0,
    required Float32List uv1,
    required Float32List colors,
    required Float32List tangents,
    required Float32List joints,
    required Float32List weights,
    required bool skinned,
  }) {
    final weld = Int32List(positions.length ~/ 3);
    final places = _weld(positions, weld);
    return VrmVertices._(
        positions,
        normals,
        uv0,
        uv1,
        colors,
        tangents,
        joints,
        weights,
        skinned,
        weld,
        places,
        skinned ? _dominant(joints, weights) : Int16List(0));
  }

  int get count => positions.length ~/ 3;

  /// _weld fills [out] with each vertex's place, and says how many places
  /// there are.
  static int _weld(Float32List p, Int32List out) {
    final keyOf = <int, int>{};
    final n = p.length ~/ 3;
    for (var i = 0; i < n; i++) {
      // A tenth of a millimetre: VRoid's seams are exact, and nothing else
      // on a body is that close.
      final x = (p[i * 3] * 1e4).round(),
          y = (p[i * 3 + 1] * 1e4).round(),
          z = (p[i * 3 + 2] * 1e4).round();
      final k =
          ((x & 0x1fffff) << 42) | ((y & 0x1fffff) << 21) | (z & 0x1fffff);
      out[i] = keyOf.putIfAbsent(k, () => keyOf.length);
    }
    return keyOf.length;
  }

  static Int16List _dominant(Float32List joints, Float32List weights) {
    final n = joints.length ~/ 4;
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      var best = 0, bw = -1.0;
      for (var k = 0; k < 4; k++) {
        if (weights[i * 4 + k] > bw) {
          bw = weights[i * 4 + k];
          best = joints[i * 4 + k].toInt();
        }
      }
      out[i] = best;
    }
    return out;
  }

  /// pack is these vertices laid out as flutter_scene's importer lays them
  /// out: position, normal, two texture coordinates, colour and tangent,
  /// then joints and weights when skinned -- 26 floats a vertex skinned, 18
  /// not -- with [positions] and [normals] in place of the file's.
  Float32List pack(Float32List positions, Float32List normals) {
    final stride = skinned ? 26 : 18;
    final out = Float32List(count * stride);
    for (var k = 0; k < count; k++) {
      final o = k * stride;
      for (var c = 0; c < 3; c++) {
        out[o + c] = positions[k * 3 + c];
        out[o + 3 + c] = normals[k * 3 + c];
      }
      out[o + 6] = uv0[k * 2];
      out[o + 7] = uv0[k * 2 + 1];
      out[o + 8] = uv1[k * 2];
      out[o + 9] = uv1[k * 2 + 1];
      for (var c = 0; c < 4; c++) {
        out[o + 10 + c] = colors[k * 4 + c];
        out[o + 14 + c] = tangents[k * 4 + c];
      }
      if (skinned) {
        for (var c = 0; c < 4; c++) {
          out[o + 18 + c] = joints[k * 4 + c];
          out[o + 22 + c] = weights[k * 4 + c];
        }
      }
    }
    return out;
  }
}

/// VrmPrimitive is one primitive: its material, the vertices it shares,
/// its triangles, and which of the vertices those use.
class VrmPrimitive {
  final String material;
  final VrmPart part;

  /// iris is the iris and its highlight, which can be sized on their own.
  final bool iris;
  final VrmVertices vertices;
  final Uint32List indices;

  /// indices32 is whether the file stores the indices in 32 bits.
  final bool indices32;

  /// used lists the vertices the triangles use, each once.
  final Int32List used;

  VrmPrimitive(
      {required this.material,
      required this.vertices,
      required this.indices,
      required this.indices32})
      : part = vrmPartOf(material),
        iris = RegExp(r'EyeIris|EyeHighlight').hasMatch(material),
        used = _used(indices, vertices.count);

  static Int32List _used(Uint32List indices, int count) {
    final seen = Uint8List(count);
    for (final i in indices) {
      seen[i] = 1;
    }
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      if (seen[i] == 1) out.add(i);
    }
    return Int32List.fromList(out);
  }
}

/// VrmMeshNode is a node with a mesh: its name, its region, its
/// primitives, and its skin's joints by name.
class VrmMeshNode {
  final String name;
  final VrmRegion region;
  final List<VrmPrimitive> primitives;
  final List<String> jointNames;
  VrmMeshNode(this.name, this.primitives, this.jointNames)
      : region = vrmRegionOf(name);
}

/// VrmRestBone is a node of the skeleton at rest.
class VrmRestBone {
  final String name;
  final String? parent;
  final vm.Vector3 translation;
  final vm.Quaternion rotation;
  final vm.Vector3 scale;
  VrmRestBone(
      this.name, this.parent, this.translation, this.rotation, this.scale);
}

/// VrmImage is a material's picture as the file holds it.
class VrmImage {
  final Uint8List bytes;

  /// shadeToo is whether the material's shade is drawn from the same
  /// picture, so a picture put in its place goes in both.
  final bool shadeToo;
  const VrmImage(this.bytes, this.shadeToo);
}

/// VrmMeshData is everything shaping reads from one file.
class VrmMeshData {
  final List<VrmMeshNode> meshes;

  /// bones are every named node at rest, by name.
  final Map<String, VrmRestBone> bones;

  /// bindPos is where each joint was when the meshes were bound to it, in
  /// the meshes' space, from the skins' inverse bind matrices.
  final Map<String, vm.Vector3> bindPos;

  /// images are the pictures painted on the skin and the face, as the file
  /// holds them (PNG or JPEG), for the skin to be painted again where
  /// clothes come off.
  final Map<VrmPart, VrmImage> images;

  /// pictures are every material's own picture, by the material's name, as
  /// the file holds them: for drawing a material in another colour or in
  /// fewer tones. Materials sharing a picture share its bytes.
  final Map<String, Uint8List> pictures;

  VrmMeshData(this.meshes, this.bones, this.bindPos,
      {this.images = const {}, this.pictures = const {}});

  Iterable<VrmPrimitive> primitivesOf(VrmRegion region, [VrmPart? part]) => [
        for (final m in meshes)
          if (m.region == region)
            for (final p in m.primitives)
              if (part == null || p.part == part) p,
      ];

  /// read reads [glb], a binary glTF (a .vrm).
  static VrmMeshData read(Uint8List glb) {
    final d = ByteData.sublistView(glb);
    if (glb.length < 20 || d.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException("not a binary glTF file");
    }
    final jl = d.getUint32(12, Endian.little);
    final j = jsonDecode(utf8.decode(glb.sublist(20, 20 + jl)))
        as Map<String, dynamic>;
    final binStart = 20 + jl + 8;
    final accessors = ((j['accessors'] as List?) ?? const []).cast<Map>();
    final views = ((j['bufferViews'] as List?) ?? const []).cast<Map>();
    final cache = <int, Float32List>{};

    Float32List floats(int ai) => cache.putIfAbsent(ai, () {
          final a = accessors[ai];
          final v = views[a['bufferView'] as int];
          final n = const {
            'SCALAR': 1,
            'VEC2': 2,
            'VEC3': 3,
            'VEC4': 4,
            'MAT4': 16
          }[a['type']]!;
          final ct = a['componentType'] as int;
          final size =
              const {5126: 4, 5125: 4, 5123: 2, 5122: 2, 5121: 1, 5120: 1}[ct]!;
          final start = binStart +
              ((v['byteOffset'] ?? 0) as int) +
              ((a['byteOffset'] ?? 0) as int);
          final stride = (v['byteStride'] ?? n * size) as int;
          final count = a['count'] as int;
          final norm = a['normalized'] == true;
          final out = Float32List(count * n);
          for (var i = 0; i < count; i++) {
            for (var c = 0; c < n; c++) {
              final at = start + i * stride + c * size;
              out[i * n + c] = switch (ct) {
                5126 => d.getFloat32(at, Endian.little),
                5125 => d.getUint32(at, Endian.little).toDouble(),
                5123 => norm
                    ? d.getUint16(at, Endian.little) / 65535
                    : d.getUint16(at, Endian.little).toDouble(),
                5122 => norm
                    ? d.getInt16(at, Endian.little) / 32767
                    : d.getInt16(at, Endian.little).toDouble(),
                5121 => norm ? d.getUint8(at) / 255 : d.getUint8(at).toDouble(),
                _ => norm ? d.getInt8(at) / 127 : d.getInt8(at).toDouble(),
              };
            }
          }
          return out;
        });

    Float32List filled(int count, double v) =>
        Float32List(count)..fillRange(0, count, v);

    final nodes = (j['nodes'] as List).cast<Map>();
    final skins = ((j['skins'] as List?) ?? const []).cast<Map>();
    final meshes = ((j['meshes'] as List?) ?? const []).cast<Map>();
    final materials = ((j['materials'] as List?) ?? const []).cast<Map>();
    String nameOf(int i) => (nodes[i]['name'] ?? 'node$i') as String;

    // Vertices shared by primitives are read once, by the accessors they
    // are read from.
    final shared = <String, VrmVertices>{};
    final out = <VrmMeshNode>[];
    for (final n in nodes) {
      if (n['mesh'] is! int) continue;
      final skin = n['skin'] is int ? skins[n['skin'] as int] : null;
      final joints = skin == null
          ? const <String>[]
          : [for (final x in (skin['joints'] as List).cast<int>()) nameOf(x)];
      final prims = <VrmPrimitive>[];
      for (final p
          in (meshes[n['mesh'] as int]['primitives'] as List).cast<Map>()) {
        final at = (p['attributes'] as Map).cast<String, int>();
        final skinned =
            skin != null && at['JOINTS_0'] != null && at['WEIGHTS_0'] != null;
        final key = [
          for (final k in const [
            'POSITION',
            'NORMAL',
            'TEXCOORD_0',
            'TEXCOORD_1',
            'COLOR_0',
            'TANGENT',
            'JOINTS_0',
            'WEIGHTS_0'
          ])
            at[k],
          skinned
        ].join(',');
        final vs = shared.putIfAbsent(key, () {
          final pos = floats(at['POSITION']!);
          final count = pos.length ~/ 3;
          Float32List colour() {
            final c = floats(at['COLOR_0']!);
            if (c.length == count * 4) return c;
            final rgba = filled(count * 4, 1);
            for (var i = 0; i < count; i++) {
              for (var k = 0; k < 3; k++) {
                rgba[i * 4 + k] = c[i * 3 + k];
              }
            }
            return rgba;
          }

          return VrmVertices(
            positions: pos,
            normals: floats(at['NORMAL']!),
            uv0: at['TEXCOORD_0'] != null
                ? floats(at['TEXCOORD_0']!)
                : Float32List(count * 2),
            uv1: at['TEXCOORD_1'] != null
                ? floats(at['TEXCOORD_1']!)
                : Float32List(count * 2),
            colors: at['COLOR_0'] != null ? colour() : filled(count * 4, 1),
            tangents: at['TANGENT'] != null
                ? floats(at['TANGENT']!)
                : Float32List(count * 4),
            joints: skinned ? floats(at['JOINTS_0']!) : Float32List(0),
            weights: skinned ? floats(at['WEIGHTS_0']!) : Float32List(0),
            skinned: skinned,
          );
        });
        final ia = p['indices'] as int;
        prims.add(VrmPrimitive(
          material: p['material'] is int
              ? (materials[p['material'] as int]['name'] ?? '') as String
              : '',
          vertices: vs,
          indices: Uint32List.fromList([for (final x in floats(ia)) x.toInt()]),
          indices32: accessors[ia]['componentType'] == 5125,
        ));
      }
      out.add(VrmMeshNode((n['name'] ?? '') as String, prims, joints));
    }

    final parentOf = <int, int>{};
    for (var i = 0; i < nodes.length; i++) {
      for (final c
          in ((nodes[i]['children'] as List?) ?? const []).cast<int>()) {
        parentOf[c] = i;
      }
    }
    vm.Vector3 v3(Object? l, double d) => l is List
        ? vm.Vector3((l[0] as num).toDouble(), (l[1] as num).toDouble(),
            (l[2] as num).toDouble())
        : vm.Vector3.all(d);
    final bones = <String, VrmRestBone>{};
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final r = n['rotation'] is List
          ? (n['rotation'] as List).map((x) => (x as num).toDouble()).toList()
          : const [0.0, 0.0, 0.0, 1.0];
      bones.putIfAbsent(
          nameOf(i),
          () => VrmRestBone(
              nameOf(i),
              parentOf[i] == null ? null : nameOf(parentOf[i]!),
              v3(n['translation'], 0),
              vm.Quaternion(r[0], r[1], r[2], r[3]),
              v3(n['scale'], 1)));
    }

    final bindPos = <String, vm.Vector3>{};
    for (final s in skins) {
      final ibm = s['inverseBindMatrices'] is int
          ? floats(s['inverseBindMatrices'] as int)
          : null;
      final js = (s['joints'] as List).cast<int>();
      for (var k = 0; k < js.length; k++) {
        if (ibm == null) continue;
        final m = vm.Matrix4.fromFloat32List(
            Float32List.sublistView(ibm, k * 16, k * 16 + 16));
        bindPos.putIfAbsent(nameOf(js[k]),
            () => (vm.Matrix4.copy(m)..invert()).getTranslation());
      }
    }
    final images = <VrmPart, VrmImage>{};
    final pictures = <String, Uint8List>{};
    final byView = <int, Uint8List>{};
    final textures = ((j['textures'] as List?) ?? const []).cast<Map>();
    final imageList = ((j['images'] as List?) ?? const []).cast<Map>();
    for (final m in materials) {
      final base = (m['pbrMetallicRoughness'] as Map?)?['baseColorTexture'];
      final ti = base is Map ? base['index'] : null;
      final source =
          ti is int && ti < textures.length ? textures[ti]['source'] : null;
      final view = source is int && source < imageList.length
          ? imageList[source]['bufferView']
          : null;
      if (view is int) {
        pictures[(m['name'] ?? '') as String] = byView.putIfAbsent(view, () {
          final v = views[view];
          final start = binStart + ((v['byteOffset'] ?? 0) as int);
          return Uint8List.fromList(
              glb.sublist(start, start + (v['byteLength'] as int)));
        });
      }
    }
    for (final m in materials) {
      final part = vrmPartOf((m['name'] ?? '') as String);
      if ((part != VrmPart.skin && part != VrmPart.face) ||
          images.containsKey(part)) {
        continue;
      }
      final base = (m['pbrMetallicRoughness'] as Map?)?['baseColorTexture'];
      final ti = base is Map ? base['index'] : null;
      final source =
          ti is int && ti < textures.length ? textures[ti]['source'] : null;
      final view = source is int && source < imageList.length
          ? imageList[source]['bufferView']
          : null;
      if (view is! int) continue;
      final v = views[view];
      final start = binStart + ((v['byteOffset'] ?? 0) as int);
      final shade = (((m['extensions'] as Map?)?['VRMC_materials_mtoon']
          as Map?)?['shadeMultiplyTexture'] as Map?)?['index'];
      images[part] = VrmImage(
          Uint8List.fromList(
              glb.sublist(start, start + (v['byteLength'] as int))),
          shade == ti);
    }
    return VrmMeshData(out, bones, bindPos, images: images, pictures: pictures);
  }
}
