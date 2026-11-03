import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

// A new 3D character shaped from its VRoid body: the settings and presets,
// the file read as flutter_scene holds it, the face and body found from the
// mesh, the mesh and skeleton changed, and the page's two side panels.

ShapePart _part(String id) => characterShapeParts.firstWhere((p) => p.id == id);
ShapePresets _presets(String key) => characterShapeParts
    .expand((p) => p.controls)
    .whereType<ShapePresets>()
    .firstWhere((c) => c.key == key);

/// _glb is a .glb of [json] over [bin].
Uint8List _glb(Map<String, dynamic> json, Uint8List bin) {
  final js = utf8.encode(jsonEncode(json));
  final jl = (js.length + 3) & ~3, bl = (bin.length + 3) & ~3;
  return (BytesBuilder()
        ..add((ByteData(20)
              ..setUint32(0, 0x46546C67, Endian.little)
              ..setUint32(4, 2, Endian.little)
              ..setUint32(8, 12 + 8 + jl + 8 + bl, Endian.little)
              ..setUint32(12, jl, Endian.little)
              ..setUint32(16, 0x4E4F534A, Endian.little))
            .buffer
            .asUint8List())
        ..add(js)
        ..add(List.filled(jl - js.length, 0x20))
        ..add((ByteData(8)
              ..setUint32(0, bl, Endian.little)
              ..setUint32(4, 0x004E4942, Endian.little))
            .buffer
            .asUint8List())
        ..add(bin)
        ..add(List.filled(bl - bin.length, 0)))
      .takeBytes();
}

/// _prim is a primitive of its own [points], drawn as [triangles] or else
/// as a fan from the first, following [bone] (an index into its node's
/// joints) when given.
VrmPrimitive _prim(String material, List<vm.Vector3> points,
    {int? bone, List<int>? triangles}) {
  final n = points.length;
  final pos = Float32List(n * 3), nrm = Float32List(n * 3);
  for (var i = 0; i < n; i++) {
    pos.setAll(i * 3, [points[i].x, points[i].y, points[i].z]);
    nrm.setAll(i * 3, [0, 0, 1]);
  }
  final skinned = bone != null;
  final joints = Float32List(skinned ? n * 4 : 0),
      weights = Float32List(skinned ? n * 4 : 0);
  for (var i = 0; skinned && i < n; i++) {
    joints[i * 4] = bone.toDouble();
    weights[i * 4] = 1;
  }
  return VrmPrimitive(
    material: material,
    vertices: VrmVertices(
        positions: pos,
        normals: nrm,
        uv0: Float32List(n * 2),
        uv1: Float32List(n * 2),
        colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
        tangents: Float32List(n * 4),
        joints: joints,
        weights: weights,
        skinned: skinned),
    indices: Uint32List.fromList(triangles ??
        [
          for (var i = 1; i + 1 < n; i++) ...[0, i, i + 1]
        ]),
    indices32: false,
  );
}

/// _ring is a centre and [n] points round it, facing +z.
List<vm.Vector3> _ring(vm.Vector3 c, double r, [int n = 8]) => [
      c,
      for (var i = 0; i < n; i++)
        c +
            vm.Vector3(r * math.cos(2 * math.pi * i / n),
                r * math.sin(2 * math.pi * i / n), 0),
    ];

/// _face is a face looking along +z: eyes 6 cm apart at 1.5 m, a nose
/// standing out at 1.47, a mouth at 1.43, over a curved grid of skin.
VrmMeshNode _face() {
  const cols = 17, rows = 23;
  final skin = <vm.Vector3>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = -0.08 + 0.01 * c, y = 1.38 + 0.01 * r;
      final nose = c == 8 && r == 9;
      skin.add(vm.Vector3(
          x,
          y,
          nose
              ? 0.09
              : 0.02 +
                  0.05 *
                      math.sqrt(math.max(0, 1 - (x / 0.085) * (x / 0.085)))));
    }
  }
  final grid = [
    for (var r = 0; r + 1 < rows; r++)
      for (var c = 0; c + 1 < cols; c++) ...[
        r * cols + c, r * cols + c + 1, (r + 1) * cols + c, //
        r * cols + c + 1, (r + 1) * cols + c + 1, (r + 1) * cols + c,
      ],
  ];
  return VrmMeshNode('Face', [
    _prim('F00_EyeWhite_00_EYE', [
      ..._ring(vm.Vector3(-0.03, 1.5, 0.07), 0.012),
      ..._ring(vm.Vector3(0.03, 1.5, 0.07), 0.012)
    ], triangles: [
      for (final o in const [0, 9])
        for (var i = 1; i <= 8; i++) ...[o, o + i, o + i % 8 + 1]
    ]),
    _prim('F00_EyeIris_00_EYE', _ring(vm.Vector3(-0.03, 1.5, 0.072), 0.006)),
    _prim('F00_FaceMouth_00_FACE', _ring(vm.Vector3(0, 1.43, 0.065), 0.01)),
    _prim('F00_Face_00_SKIN', skin, triangles: grid),
  ], const []);
}

/// _bones is a skeleton: hips at 0.9 m over a leg of two 0.4 m bones, a
/// spine, an upper chest, and an arm out to the side.
Map<String, VrmRestBone> _bones() {
  VrmRestBone b(String n, String? p, double x, double y, double z) =>
      VrmRestBone(n, p, vm.Vector3(x, y, z), vm.Quaternion.identity(),
          vm.Vector3.all(1));
  return {
    for (final x in [
      b('Root', null, 0, 0, 0),
      b(VroidBone.hips, 'Root', 0, 0.9, 0),
      b(VroidBone.spine, VroidBone.hips, 0, 0.1, 0),
      b(VroidBone.chest, VroidBone.spine, 0, 0.1, 0),
      b(VroidBone.upperChest, VroidBone.chest, 0, 0.1, 0),
      b(VroidBone.neck, VroidBone.upperChest, 0, 0.15, 0),
      b(VroidBone.head, VroidBone.neck, 0, 0.08, 0),
      b(VroidBone.upperArm('R'), VroidBone.upperChest, -0.1, 0.1, 0),
      b(VroidBone.lowerArm('R'), VroidBone.upperArm('R'), -0.25, 0, 0),
      b(VroidBone.hand('R'), VroidBone.lowerArm('R'), -0.22, 0, 0),
      b(VroidBone.upperLeg('L'), VroidBone.hips, 0.08, -0.05, 0),
      b(VroidBone.lowerLeg('L'), VroidBone.upperLeg('L'), 0, -0.4, 0),
      b(VroidBone.foot('L'), VroidBone.lowerLeg('L'), 0, -0.4, 0),
    ])
      x.name: x,
  };
}

/// _bindPos is where [bones] are at rest, from the hips down.
Map<String, vm.Vector3> _bindPos(Map<String, VrmRestBone> bones) {
  vm.Vector3 at(String n) {
    final b = bones[n]!;
    return b.parent == null
        ? b.translation.clone()
        : at(b.parent!) + b.translation;
  }

  return {for (final n in bones.keys) n: at(n)};
}

/// _body is a body: an upper arm as a tube of skin round its bone, and a
/// patch of skin across the hips.
VrmMeshData _body() {
  final bones = _bones();
  final bind = _bindPos(bones);
  final ua = bind[VroidBone.upperArm('R')]!;
  final arm = <vm.Vector3>[];
  for (var t = 0.0; t <= 1.0001; t += 0.25) {
    for (var k = 0; k < 6; k++) {
      final a = 2 * math.pi * k / 6;
      arm.add(
          ua + vm.Vector3(-0.25 * t, 0.04 * math.cos(a), 0.04 * math.sin(a)));
    }
  }
  final hips = [
    for (var x = -0.1; x <= 0.1001; x += 0.05)
      for (var y = 0.8; y <= 1.0001; y += 0.05) vm.Vector3(x, y, -0.1)
  ];
  return VrmMeshData([
    VrmMeshNode('Body', [
      _prim('F00_Body_00_SKIN', arm, bone: 0),
      _prim('F00_Body_00_SKIN', hips, bone: 1)
    ], [
      VroidBone.upperArm('R'),
      VroidBone.hips
    ]),
  ], bones, bind);
}

double _spread(Float32List pos, Iterable<int> verts, vm.Vector3 c) {
  var r = 0.0;
  for (final i in verts) {
    r = math.max(
        r, (vm.Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]) - c).length);
  }
  return r;
}

void main() {
  group('the shape', () {
    test('a setting back at its default is not kept', () {
      final s = const CharacterShape().withValue('eyes.size', 0.5);
      expect(s.values, {'eyes.size': 0.5});
      expect(s.withValue('eyes.size', 0).values, isEmpty);
      expect(const CharacterShape().get('age'), 25);
      expect(const CharacterShape().withValue('age', 25).values, isEmpty);
    });

    test('a preset puts back what the presets set, then sets its own', () {
      final face = _presets('shapes.face');
      var s = const CharacterShape()
          .withPreset(face, 'Round')
          .withValue('nose.size', 0.3);
      expect(s.get('cheeks.fullness'), 0.6);
      s = s.withPreset(face, 'Long');
      expect(s.get('cheeks.fullness'), -0.3, reason: 'Long sets it too');
      expect(s.get('jaw.width'), 0, reason: 'Round set it; Long does not');
      expect(s.get('nose.size'), 0.3,
          reason: 'no face shape is about the nose');
      expect(s.choice('shapes.face'), 'Long');
    });

    test('a preset that owns its group puts every setting in it back', () {
      final build = _presets('muscle.build');
      final s = const CharacterShape()
          .withValue('muscle.glutes', 0.9)
          .withChoice('muscle.shape', 'peaked')
          .withPreset(build, 'Slim');
      expect(s.get('muscle.glutes'), 0,
          reason: 'Slim does not set it, but owns it');
      expect(s.get('muscle.biceps'), -0.4);
      expect(s.choice('muscle.shape'), 'peaked',
          reason: 'the shape of the muscles is not a number in the group');
    });

    test('a part says it is changed, and goes back as made', () {
      final eyes = _part('eyes');
      final s = const CharacterShape()
          .withPreset(_presets('shapes.eyes'), 'Big')
          .withValue('mouth.size', 0.2);
      expect(s.changed(eyes), isTrue);
      expect(s.changed(_part('nose')), isFalse);
      final back = s.reset(eyes);
      expect(back.changed(eyes), isFalse);
      expect(back.values, {'mouth.size': 0.2});
      expect(
          const CharacterShape()
              .withChoice('navel.shape', 'As made')
              .changed(_part('navel')),
          isFalse);
    });

    test('the years add to what is set', () {
      final old = const CharacterShape()
          .withValue('age', 85)
          .withValue('nose.size', 0.1);
      expect(old.effective('nose.size'), closeTo(0.32, 1e-9));
      expect(old.effective('ears.size'), closeTo(0.3, 1e-9));
      final young = const CharacterShape().withValue('age', 18);
      expect(young.effective('eyes.size'), closeTo(0.12, 1e-9));
      expect(const CharacterShape().effective('eyes.size'), 0,
          reason: 'at 25 the years change nothing');
    });

    test('kept and read back the same, and junk is dropped', () {
      final s = const CharacterShape()
          .withValue('age', 60)
          .withPreset(_presets('bum.shape'), 'Heart');
      expect(
          CharacterShape.fromJson(
              jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>),
          s);
      expect(
          CharacterShape.fromJson({
            'values': {'a': 'x', 'b': 1},
            'choices': {'c': 2}
          }).values,
          {'b': 1.0});
    });
  });

  group('the file', () {
    test('primitives share their vertices, and each knows which it draws', () {
      final floats = <double>[
        // 0: positions; vertices 1 and 3 are one point on a seam
        0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0,
        // 15: normals
        for (var i = 0; i < 5; i++) ...[0, 0, 1],
        // 30: weights
        for (var i = 0; i < 5; i++) ...[1, 0, 0, 0],
        // 50: an inverse bind matrix moving by (0, -0.9, 0): a joint at 0.9 m
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -0.9, 0, 1,
      ];
      final bin = BytesBuilder()
        ..add(Float32List.fromList(floats).buffer.asUint8List());
      final joints = bin.length;
      bin.add(Uint16List.fromList([
        for (var i = 0; i < 5; i++) ...[0, 0, 0, 0]
      ]).buffer.asUint8List());
      final idx = bin.length;
      bin.add(Uint16List.fromList([0, 1, 2, 1, 4, 2]).buffer.asUint8List());
      final bytes = bin.takeBytes();
      final glb = _glb({
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': bytes.length}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 15 * 4},
          {'buffer': 0, 'byteOffset': 15 * 4, 'byteLength': 15 * 4},
          {'buffer': 0, 'byteOffset': 30 * 4, 'byteLength': 20 * 4},
          {'buffer': 0, 'byteOffset': 50 * 4, 'byteLength': 16 * 4},
          {'buffer': 0, 'byteOffset': joints, 'byteLength': 40},
          {'buffer': 0, 'byteOffset': idx, 'byteLength': 12},
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 5, 'type': 'VEC3'},
          {'bufferView': 1, 'componentType': 5126, 'count': 5, 'type': 'VEC3'},
          {'bufferView': 2, 'componentType': 5126, 'count': 5, 'type': 'VEC4'},
          {'bufferView': 3, 'componentType': 5126, 'count': 1, 'type': 'MAT4'},
          {'bufferView': 4, 'componentType': 5123, 'count': 5, 'type': 'VEC4'},
          {
            'bufferView': 5,
            'componentType': 5123,
            'count': 3,
            'type': 'SCALAR'
          },
          {
            'bufferView': 5,
            'byteOffset': 6,
            'componentType': 5123,
            'count': 3,
            'type': 'SCALAR'
          },
        ],
        'materials': [
          {'name': 'F00_000_00_Face_00_SKIN'},
          {'name': 'F00_000_00_EyeIris_00_EYE'},
        ],
        'meshes': [
          {
            'primitives': [
              for (final (i, m) in [(5, 0), (6, 1)])
                {
                  'attributes': {
                    'POSITION': 0,
                    'NORMAL': 1,
                    'JOINTS_0': 4,
                    'WEIGHTS_0': 2
                  },
                  'indices': i,
                  'material': m,
                }
            ]
          }
        ],
        'skins': [
          {
            'joints': [2],
            'inverseBindMatrices': 3
          }
        ],
        'nodes': [
          {
            'name': 'Root',
            'children': [1, 2]
          },
          {'name': 'Face', 'mesh': 0, 'skin': 0},
          {
            'name': 'J_Bip_C_Head',
            'translation': [0, 0.9, 0],
            'rotation': [0, 0, 0, 1]
          },
        ],
      }, bytes);
      final data = VrmMeshData.read(glb);
      final face = data.meshes.single;
      expect(face.region, VrmRegion.face);
      expect(face.jointNames, ['J_Bip_C_Head']);
      final [skin, iris] = face.primitives;
      expect(identical(skin.vertices, iris.vertices), isTrue,
          reason: 'one vertex buffer, as flutter_scene has it');
      expect((skin.part, skin.iris, iris.part, iris.iris),
          (VrmPart.face, false, VrmPart.eyes, true));
      expect(skin.used, [0, 1, 2]);
      expect(iris.used, [1, 2, 4]);
      expect(skin.vertices.weld[1], skin.vertices.weld[3],
          reason: 'the same point either side of a seam');
      expect(skin.vertices.weldCount, 4);
      expect(data.bindPos['J_Bip_C_Head']!.y, closeTo(0.9, 1e-6));
      expect(data.bones['J_Bip_C_Head']!.parent, 'Root');
      // Laid out as the importer lays it out: 26 floats a skinned vertex.
      final packed =
          skin.vertices.pack(skin.vertices.positions, skin.vertices.normals);
      expect(packed.length, 5 * 26);
      expect(packed.sublist(26, 26 + 6), [1, 0, 0, 0, 0, 1]);
      expect(packed.sublist(26 + 10, 26 + 14), [1, 1, 1, 1],
          reason: 'no colour is white');
      expect(packed.sublist(26 + 18, 26 + 26), [0, 0, 0, 0, 1, 0, 0, 0]);
    });

    test('the skin\'s and the face\'s pictures are kept, and nothing else', () {
      final png = [137, 80, 78, 71, 1, 2, 3, 4, 5];
      final face = [255, 216, 255, 9, 8, 7];
      final bin = Uint8List.fromList([...png, ...face, 42, 42]);
      final data = VrmMeshData.read(_glb({
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': bin.length}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': png.length},
          {'buffer': 0, 'byteOffset': png.length, 'byteLength': face.length},
          {
            'buffer': 0,
            'byteOffset': png.length + face.length,
            'byteLength': 2
          },
        ],
        'images': [
          {'bufferView': 0, 'mimeType': 'image/png'},
          {'bufferView': 1, 'mimeType': 'image/jpeg'},
          {'bufferView': 2, 'mimeType': 'image/png'},
        ],
        'textures': [
          {'source': 0},
          {'source': 1},
          {'source': 2},
        ],
        'materials': [
          for (final (name, t, shade) in [
            ('F00_000_00_Body_00_SKIN', 0, 0),
            ('F00_000_00_Face_00_SKIN', 1, 2),
            ('F00_000_Hair_00_HAIR', 2, 2),
          ])
            {
              'name': name,
              'pbrMetallicRoughness': {
                'baseColorTexture': {'index': t}
              },
              'extensions': {
                'VRMC_materials_mtoon': {
                  'shadeMultiplyTexture': {'index': shade}
                }
              },
            }
        ],
        'nodes': [
          {'name': 'Root'}
        ],
      }, bin));
      expect(data.images.keys, unorderedEquals([VrmPart.skin, VrmPart.face]));
      expect(data.images[VrmPart.skin]!.bytes, png);
      expect(data.images[VrmPart.skin]!.shadeToo, isTrue);
      expect(data.images[VrmPart.face]!.bytes, face);
      expect(data.images[VrmPart.face]!.shadeToo, isFalse);
    });

    test('materials and nodes say what is drawn, and where', () {
      expect(
          vrmPartOf('N00_000_00_FaceMouth_00_FACE (Instance)'), VrmPart.mouth);
      expect(vrmPartOf('F00_000_HairBack_00_HAIR'), VrmPart.hair);
      expect(vrmPartOf('F00_002_01_Tops_01_CLOTH'), VrmPart.top);
      expect(vrmRegionOf('Hair001'), VrmRegion.hair);
      expect(vrmRegionOf('Body'), VrmRegion.body);
    });
  });

  group('shaping', () {
    final faceData = VrmMeshData([_face()], const {}, const {});

    test('the face is found from its own parts', () {
      final L = findFaceLandmarks(faceData)!;
      expect(L.fwd, 1);
      expect(L.es, closeTo(0.06, 1e-6));
      expect(L.eyeR.x, lessThan(0));
      expect(L.noseTip.y, closeTo(1.47, 1e-6));
      expect(L.noseTip.z, closeTo(0.09, 1e-6));
      expect(L.mouth.y, closeTo(1.43, 1e-6));
      expect(L.right.ear.x, lessThan(L.right.cheek.x));
    });

    test('nothing changed is left as it is', () {
      final rig = VrmShapeRig(faceData);
      expect(rig.deformers(VrmRegion.face, const CharacterShape()), isEmpty);
      expect(
          rig.groups.map((g) => rig.shape(g, const [])), everyElement(isNull));
    });

    test('bigger eyes grow round each eye, and the chin does not move', () {
      final rig = VrmShapeRig(faceData);
      final ds = rig.deformers(
          VrmRegion.face, const CharacterShape().withValue('eyes.size', 1));
      final eyes = rig.groups.firstWhere((g) =>
          g.node.primitives[g.primitives.first].material.contains('EyeWhite'));
      final out = rig.shape(eyes, ds)!;
      final right = [
        for (final i in eyes.used)
          if (eyes.vertices.positions[i * 3] < 0) i
      ];
      final c = vm.Vector3(-0.03, 1.5, 0.07);
      expect(_spread(out.positions, right, c),
          greaterThan(_spread(eyes.vertices.positions, right, c) * 1.05));
      final skin = rig.groups.firstWhere(
          (g) => g.node.primitives[g.primitives.first].part == VrmPart.face);
      final shaped = rig.shape(skin, ds);
      final low = [
        for (final i in skin.used)
          if (skin.vertices.positions[i * 3 + 1] < 1.4) i
      ];
      for (final i in low) {
        expect((shaped?.positions ?? skin.vertices.positions)[i * 3 + 1],
            skin.vertices.positions[i * 3 + 1]);
      }
    });

    test('the iris is sized on its own', () {
      final rig = VrmShapeRig(faceData);
      final ds = rig.deformers(
          VrmRegion.face, const CharacterShape().withValue('eyes.iris', 1));
      final iris = rig.groups.singleWhere((g) => g.iris);
      expect(rig.shape(iris, ds), isNotNull);
      expect(rig.groups.where((g) => !g.iris).map((g) => rig.shape(g, ds)),
          everyElement(isNull));
    });

    test('a longer face stretches down from the eyes, its normals made again',
        () {
      final rig = VrmShapeRig(faceData);
      final skin = rig.groups.firstWhere(
          (g) => g.node.primitives[g.primitives.first].part == VrmPart.face);
      final out = rig.shape(
          skin,
          rig.deformers(VrmRegion.face,
              const CharacterShape().withValue('face.length', 1)))!;
      final pos = skin.vertices.positions;
      final i = skin.used.firstWhere((i) => pos[i * 3 + 1] < 1.4);
      final eyeY = findFaceLandmarks(faceData)!.eyeY;
      expect(eyeY - out.positions[i * 3 + 1],
          closeTo((eyeY - pos[i * 3 + 1]) * 1.14, 1e-5));
      for (var k = 0; k < out.normals.length; k += 3) {
        expect(
            math.sqrt(out.normals[k] * out.normals[k] +
                out.normals[k + 1] * out.normals[k + 1] +
                out.normals[k + 2] * out.normals[k + 2]),
            closeTo(1, 1e-4));
        expect(out.normals[k + 2], greaterThan(0), reason: 'still facing out');
      }
    });

    test('thicker upper arms grow round the bone, only where they follow it',
        () {
      final data = _body();
      final rig = VrmShapeRig(data);
      final ds = rig.deformers(
          VrmRegion.body, const CharacterShape().withValue('arms.upper', 1));
      expect(ds.whereType<Radial>(), isNotEmpty);
      final arm = rig.groups.firstWhere((g) =>
          g.node.primitives[g.primitives.first].vertices.domBone.first == 0);
      final out = rig.shape(arm, ds)!;
      final ua = data.bindPos[VroidBone.upperArm('R')]!;
      for (final i in arm.used) {
        final p = arm.vertices.positions;
        final before = math.sqrt(math.pow(p[i * 3 + 1] - ua.y, 2) +
            math.pow(p[i * 3 + 2] - ua.z, 2));
        final after = math.sqrt(math.pow(out.positions[i * 3 + 1] - ua.y, 2) +
            math.pow(out.positions[i * 3 + 2] - ua.z, 2));
        expect(after, closeTo(before * 1.22, 1e-5));
      }
      final hips = rig.groups.firstWhere((g) => g != arm);
      expect(rig.shape(hips, ds.whereType<Radial>().toList()), isNull,
          reason: 'the hips follow another bone');
    });

    test('longer legs lift the hips just enough to keep the feet on the floor',
        () {
      final data = _body();
      final rig = VrmShapeRig(data);
      final p =
          rig.proportions(const CharacterShape().withValue('legs.length', 1));
      expect(p.bones[VroidBone.lowerLeg('L')]!.translation.y,
          closeTo(-0.4 * 1.18, 1e-6));
      // Each leg bone is 0.072 m longer; the hips go up by both.
      expect(p.bones[VroidBone.hips]!.translation.y,
          closeTo(0.9 + 2 * 0.4 * 0.18, 1e-6));
      expect(rig.proportions(const CharacterShape()).bones, isEmpty);
    });

    test('a chibi has a head nearly twice the size, and is no taller', () {
      final rig = VrmShapeRig(_body());
      final chibi =
          const CharacterShape().withPreset(_presets('figure.style'), 'Chibi');
      final p = rig.proportions(chibi);
      expect(p.bones[VroidBone.head]!.scale, closeTo(math.pow(2, 0.9), 1e-9));
      expect(p.height, 1);
      expect(
          rig
              .proportions(const CharacterShape().withValue('body.height', 1))
              .height,
          closeTo(1.12, 1e-9));
    });
  });

  group('feet', () {
    test('bigger feet grow in the mesh, from the floor, not by the bone', () {
      final rig = VrmShapeRig(_body());
      final s = const CharacterShape().withValue('feet.size', 1);
      expect(rig.proportions(s).bones[VroidBone.foot('L')]?.scale ?? 1, 1,
          reason: 'a bone drawn bigger stretched the boot at the ankle');
      final grow =
          rig.deformers(VrmRegion.body, s).whereType<FootGrow>().single;
      expect(grow.k, closeTo(0.25, 1e-9));
      final a = grow.ankle.y;
      // Up: still on the floor, still at the ankle, and never folded over.
      expect(grow.up(0), 0);
      expect(grow.up(a), a);
      var last = -1.0;
      for (var y = 0.0; y <= a; y += a / 20) {
        expect(grow.up(y), greaterThan(last));
        last = grow.up(y);
      }
      // Across: all of it up to the ankle, none of it well above.
      expect(grow.across(a * 0.5), 1);
      expect(grow.across(a), 1);
      expect(grow.across(a + 0.05), 0);
    });
  });

  group('hair', () {
    HairStyle style(String id) => hairStyles.firstWhere((h) => h.id == id);

    test('a body wears its own hair until another is picked', () {
      expect(const CharacterShape().hair('Vivi'),
          (back: 'Vivi', fringe: 'Vivi', tails: 'Vivi'));
      final mixed = const CharacterShape().withHairStyle(style('bobtails'));
      expect(mixed.hair('Vivi'), (
        back: 'Sendagaya_Shibu',
        fringe: 'Sendagaya_Shibu',
        tails: 'HairSample_Female'
      ));
      final swept = const CharacterShape().withHairStyle(style('tousledlong'));
      expect(swept.hair('Vita').fringe, 'Sakurada_Fumiriya');
      expect(swept.get('hairShape.length'), -0.4);
      expect(
          const CharacterShape()
              .withChoice('hair.tails', 'none')
              .hair('Vivi')
              .tails,
          isNull);
    });

    test(
        'a hairstyle sets its length afresh, and a source picked by hand '
        'is no longer that hairstyle', () {
      final full = const CharacterShape()
          .withValue('hairShape.length', 0.9)
          .withHairStyle(style('full'));
      expect((full.get('hairShape.length'), full.get('hairShape.volume')),
          (0.2, 1.0));
      expect(
          const CharacterShape().withHairStyle(style('long')).values, isEmpty);
      final picked = full.withChoice('hair.fringe', 'Vita');
      expect(picked.choice('hair.style'), 'As made');
      expect(picked.hair('Vivi').back, 'Sendagaya_Shino');
      final hair = _part('hair');
      expect(picked.changed(hair), isTrue);
      expect(picked.reset(hair), const CharacterShape());
    });

    test('the fringe, the tails and the back are told apart by where they lie',
        () {
      final L = findFaceLandmarks(VrmMeshData([_face()], const {}, const {}))!;
      VrmPrimitive strip(List<vm.Vector3> pts) =>
          _prim('F00_000_Hair_00_HAIR', pts);
      // Over the forehead, in front of the face, down to the eyes.
      final fringe = strip([
        for (var x = -0.04; x <= 0.04; x += 0.02)
          for (var y = 1.49; y <= 1.6; y += 0.03) vm.Vector3(x, y, 0.08)
      ]);
      // Hanging from the side of the head to well below the chin.
      final tail = strip(
          [for (var y = 1.1; y <= 1.55; y += 0.05) vm.Vector3(0.12, y, 0.0)]);
      // Behind the head.
      final back = strip([
        for (var x = -0.06; x <= 0.06; x += 0.03)
          for (var y = 1.3; y <= 1.62; y += 0.04) vm.Vector3(x, y, -0.04)
      ]);
      expect([hairRoleOf(fringe, L), hairRoleOf(tail, L), hairRoleOf(back, L)],
          [HairRole.front, HairRole.tails, HairRole.back]);
    });
  });

  group('the side panels', () {
    Future<void> show(WidgetTester tester, Widget child,
        {double scale = 1}) async {
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(1000, 800),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: Row(children: [SizedBox(width: 180, child: child)])),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('every part is listed, and the changed ones marked',
        (tester) async {
      String? picked;
      final s = const CharacterShape().withValue('nose.tip', 0.4);
      await show(
          tester,
          CharacterShapeList(
              shape: s, selected: 'age', onSelect: (id) => picked = id));
      for (final p in characterShapeParts) {
        await tester.scrollUntilVisible(
            find.byKey(ValueKey('shapePart-${p.id}')), 40);
        expect(find.byKey(ValueKey('shapeChanged-${p.id}')),
            p.id == 'nose' ? findsOneWidget : findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('shapePart-feet')));
      expect(picked, 'feet');
    });

    testWidgets('a part\'s numbers, presets and way back each change the shape',
        (tester) async {
      var s = const CharacterShape();
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: StatefulBuilder(
                  builder: (context, set) => CharacterShapeControls(
                      part: _part('nose'),
                      shape: s,
                      onChanged: (n) => set(() => s = n))),
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('studioPartReset')), findsNothing);
      // Dragged to the right of the middle is wider.
      await tester.drag(
          find.descendant(
              of: find.byKey(const ValueKey('shape-nose.width')),
              matching: find.byType(Slider)),
          const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(s.get('nose.width'), greaterThan(0.1));
      // Clicking its name puts it back.
      await tester.tap(find.text('Width'));
      await tester.pumpAndSettle();
      expect(s.get('nose.width'), 0);
      await tester
          .tap(find.byKey(const ValueKey('studioPill-shapes.nose-Roman')));
      await tester.pumpAndSettle();
      expect(
          (s.choice('shapes.nose'), s.get('nose.bridge'), s.get('nose.width')),
          ('Roman', 0.9, 0.0));
      await tester.tap(find.byKey(const ValueKey('studioPartReset')));
      await tester.pumpAndSettle();
      expect(s, const CharacterShape());
    });

    testWidgets('the hairstyles are there to start from', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var s = const CharacterShape();
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
                width: 330,
                child: StatefulBuilder(
                    builder: (context, set) => CharacterShapeControls(
                        part: _part('hair'),
                        shape: s,
                        onChanged: (n) => set(() => s = n)))),
          ),
        ),
      ));
      Future<void> tap(String key) async {
        final f = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(f, 80);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap('studioPill-hair.style-longtails');
      expect(s.hair('Vivi').tails, 'HairSample_Female');
      await tap('studioPill-hair.source-Vita');
      expect(
          (s.hair('Vivi').back, s.choice('hair.style')), ('Vita', 'As made'));
    });

    testWidgets('the dot beside a changed setting puts it back',
        (tester) async {
      var s = const CharacterShape().withValue('nose.width', 0.5);
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
                width: 330,
                child: StatefulBuilder(
                    builder: (context, set) => CharacterShapeControls(
                        part: _part('nose'),
                        shape: s,
                        onChanged: (n) => set(() => s = n)))),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('studioSliderReset')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studioSliderReset')));
      await tester.pumpAndSettle();
      expect(s.get('nose.width'), 0);
      expect(find.byKey(const ValueKey('studioSliderReset')), findsNothing);
    });

    testWidgets('age is counted in whole years', (tester) async {
      var s = const CharacterShape();
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
                width: 300,
                child: CharacterShapeControls(
                    part: _part('age'), shape: s, onChanged: (n) => s = n)),
          ),
        ),
      ));
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('shape-age')))
          .onChanged(61.6);
      expect(s.age, 62);
    });

    testWidgets('at every text size, nothing overflows', (tester) async {
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        await show(
            tester,
            CharacterShapeList(
                shape: const CharacterShape(),
                selected: 'muscles',
                onSelect: (_) {}),
            scale: scale);
        expect(tester.takeException(), isNull, reason: 'the list at ${scale}x');
        for (final id in const ['muscles', 'age', 'navel']) {
          await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(doLoad: false),
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                    size: const Size(1000, 800),
                    textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Row(children: [
                    SizedBox(
                        width: 300,
                        child: CharacterShapeControls(
                            part: _part(id),
                            shape: const CharacterShape()
                                .withValue('muscle.fat', 0.2),
                            onChanged: (_) {})),
                  ]),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$id at ${scale}x');
        }
      }
    });
  });
}
