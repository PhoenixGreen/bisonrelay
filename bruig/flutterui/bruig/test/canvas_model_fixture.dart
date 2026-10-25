import 'dart:convert';
import 'dart:typed_data';

// canvas_model_fixture.dart builds a little 3D character as a GLB file, for
// the tests to read: a skeleton named as Mixamo names one -- or as VRM 1
// marks one -- standing in a T, a box hung on each bone, and two face
// shapes on the head.

/// _Bone is a bone of the fixture: its name, its parent, where it is from
/// its parent, and where the box hung on it reaches to.
typedef _Bone = (String, int, List<double>, List<double>);

const List<_Bone> _bones = [
  ("mixamorig:Hips", -1, [0, 1.0, 0], [0, 0.12, 0]), // 0
  ("mixamorig:Spine", 0, [0, 0.1, 0], [0, 0.45, 0]), // 1
  ("mixamorig:Neck", 1, [0, 0.45, 0], [0, 0.1, 0]), // 2
  ("mixamorig:Head", 2, [0, 0.1, 0], [0, 0.25, 0]), // 3
  ("mixamorig:LeftArm", 1, [0.2, 0.38, 0], [0.28, 0, 0]), // 4
  ("mixamorig:LeftForeArm", 4, [0.28, 0, 0], [0.25, 0, 0]), // 5
  ("mixamorig:LeftHand", 5, [0.25, 0, 0], [0.1, 0, 0]), // 6
  ("mixamorig:RightArm", 1, [-0.2, 0.38, 0], [-0.28, 0, 0]), // 7
  ("mixamorig:RightForeArm", 7, [-0.28, 0, 0], [-0.25, 0, 0]), // 8
  ("mixamorig:RightHand", 8, [-0.25, 0, 0], [-0.1, 0, 0]), // 9
  ("mixamorig:LeftUpLeg", 0, [0.1, -0.05, 0], [0, -0.45, 0]), // 10
  ("mixamorig:LeftLeg", 10, [0, -0.45, 0], [0, -0.45, 0]), // 11
  ("mixamorig:LeftFoot", 11, [0, -0.45, 0], [0, -0.05, 0.15]), // 12
  ("mixamorig:RightUpLeg", 0, [-0.1, -0.05, 0], [0, -0.45, 0]), // 13
  ("mixamorig:RightLeg", 13, [0, -0.45, 0], [0, -0.45, 0]), // 14
  ("mixamorig:RightFoot", 14, [0, -0.45, 0], [0, -0.05, 0.15]), // 15
];

/// fixtureBoneCount is how many bones the fixture has.
int get fixtureBoneCount => _bones.length;

/// humanoidGlb is the fixture as a .glb. [vrm] marks its bones as VRM 1
/// does, under names that say nothing; [facesBack] turns it round to face
/// -z, as VRM 0 characters do; [color] is its one material's colour.
Uint8List humanoidGlb(
    {bool vrm = false,
    bool facesBack = false,
    List<double> color = const [0.8, 0.5, 0.3, 1]}) {
  // Where each bone is as it stands.
  var at = <List<double>>[];
  for (var b in _bones) {
    var t = b.$3;
    var p = b.$2 < 0 ? [0.0, 0.0, 0.0] : at[b.$2];
    at.add([p[0] + t[0], p[1] + t[1], p[2] + t[2]]);
  }
  var flip = facesBack ? -1.0 : 1.0;

  var positions = <double>[], joints = <int>[], weights = <double>[];
  var indices = <int>[];
  var smile = <double>[], jaw = <double>[];
  for (var (i, b) in _bones.indexed) {
    var a = at[i], r = b.$4;
    var e = [a[0] + r[0], a[1] + r[1], a[2] + r[2]];
    var half = i == 3 ? 0.11 : 0.05;
    var lo = [for (var k = 0; k < 3; k++) (a[k] < e[k] ? a[k] : e[k]) - half];
    var hi = [for (var k = 0; k < 3; k++) (a[k] > e[k] ? a[k] : e[k]) + half];
    var first = positions.length ~/ 3;
    for (var c = 0; c < 8; c++) {
      var x = c & 1 == 0 ? lo[0] : hi[0];
      var y = c & 2 == 0 ? lo[1] : hi[1];
      var z = c & 4 == 0 ? lo[2] : hi[2];
      positions.addAll([x * flip, y, z * flip]);
      joints.addAll([i, 0, 0, 0]);
      weights.addAll([1, 0, 0, 0]);
      // The head's front corners move: up and out for a smile, down for a
      // jaw open.
      var front = i == 3 && z > a[2];
      smile.addAll(front ? [0, 0.03, 0] : [0, 0, 0]);
      jaw.addAll(front && y < a[1] + 0.1 ? [0, -0.06, 0] : [0, 0, 0]);
    }
    // Twelve triangles, each going round anticlockwise seen from outside.
    const faces = [
      [0, 2, 3, 1], // -z
      [4, 5, 7, 6], // +z
      [0, 1, 5, 4], // -y
      [2, 6, 7, 3], // +y
      [0, 4, 6, 2], // -x
      [1, 3, 7, 5], // +x
    ];
    for (var f in faces) {
      indices.addAll([
        first + f[0], first + f[1], first + f[2], //
        first + f[0], first + f[2], first + f[3],
      ]);
    }
  }

  var bin = BytesBuilder();
  var views = <Map<String, dynamic>>[];
  var accessors = <Map<String, dynamic>>[];
  int put(Uint8List bytes, int componentType, int count, String type,
      {bool target = false}) {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
    views.add({"buffer": 0, "byteOffset": bin.length, "byteLength": bytes.length});
    bin.add(bytes);
    accessors.add({
      "bufferView": views.length - 1,
      "componentType": componentType,
      "count": count,
      "type": type,
    });
    return accessors.length - 1;
  }

  Uint8List floats(List<double> v) =>
      Float32List.fromList(v).buffer.asUint8List();
  var count = positions.length ~/ 3;
  var pos = put(floats(positions), 5126, count, "VEC3");
  var jo = put(Uint8List.fromList(joints), 5121, count, "VEC4");
  var we = put(floats(weights), 5126, count, "VEC4");
  var ix = put(Uint16List.fromList(indices).buffer.asUint8List(), 5123,
      indices.length, "SCALAR");
  var sm = put(floats(smile), 5126, count, "VEC3");
  var jw = put(floats(jaw), 5126, count, "VEC3");
  var inverse = <double>[];
  for (var p in at) {
    inverse.addAll([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]);
    inverse.addAll([-p[0] * flip, -p[1], -p[2] * flip, 1]);
  }
  var ib = put(floats(inverse), 5126, _bones.length, "MAT4");

  var nodes = <Map<String, dynamic>>[
    for (var (i, b) in _bones.indexed)
      {
        "name": vrm ? "bone$i" : b.$1,
        "translation": [b.$3[0] * flip, b.$3[1], b.$3[2] * flip],
        "children": [
          for (var (k, c) in _bones.indexed)
            if (c.$2 == i) k
        ],
      },
    {"name": "Body", "mesh": 0, "skin": 0},
  ];
  var json = {
    "asset": {"version": "2.0"},
    "scene": 0,
    "scenes": [
      {
        "nodes": [0, _bones.length]
      }
    ],
    "nodes": nodes,
    "meshes": [
      {
        "name": "Body",
        "primitives": [
          {
            "attributes": {"POSITION": pos, "JOINTS_0": jo, "WEIGHTS_0": we},
            "indices": ix,
            "material": 0,
            "targets": [
              {"POSITION": sm},
              {"POSITION": jw},
            ],
          }
        ],
        "extras": {
          "targetNames": ["mouthSmile", "jawOpen"]
        },
      }
    ],
    "skins": [
      {
        "joints": [for (var i = 0; i < _bones.length; i++) i],
        "inverseBindMatrices": ib,
      }
    ],
    "materials": [
      {
        "pbrMetallicRoughness": {"baseColorFactor": color},
      }
    ],
    "buffers": [
      {"byteLength": bin.length}
    ],
    "bufferViews": views,
    "accessors": accessors,
    if (vrm)
      "extensions": {
        "VRMC_vrm": {
          "specVersion": "1.0",
          "meta": {"name": "Fixture"},
          "humanoid": {
            "humanBones": {
              for (var (i, name) in const [
                "hips", "spine", "neck", "head", //
                "leftUpperArm", "leftLowerArm", "leftHand",
                "rightUpperArm", "rightLowerArm", "rightHand",
                "leftUpperLeg", "leftLowerLeg", "leftFoot",
                "rightUpperLeg", "rightLowerLeg", "rightFoot",
              ].indexed)
                name: {"node": i}
            }
          },
          "expressions": {
            "preset": {
              "happy": {
                "morphTargetBinds": [
                  {"node": _bones.length, "index": 0, "weight": 1}
                ]
              },
              "aa": {
                "morphTargetBinds": [
                  {"node": _bones.length, "index": 1, "weight": 1}
                ]
              },
            }
          },
        }
      },
  };
  var text = utf8.encode(jsonEncode(json));
  var jsonChunk = BytesBuilder()..add(text);
  while (jsonChunk.length % 4 != 0) {
    jsonChunk.addByte(0x20);
  }
  var binBytes = bin.takeBytes();
  var binChunk = BytesBuilder()..add(binBytes);
  while (binChunk.length % 4 != 0) {
    binChunk.addByte(0);
  }
  var j = jsonChunk.takeBytes(), b = binChunk.takeBytes();
  var out = ByteData(12 + 8 + j.length + 8 + b.length);
  var o = out.buffer.asUint8List();
  out.setUint32(0, 0x46546C67, Endian.little);
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, o.length, Endian.little);
  out.setUint32(12, j.length, Endian.little);
  out.setUint32(16, 0x4E4F534A, Endian.little);
  o.setRange(20, 20 + j.length, j);
  var at2 = 20 + j.length;
  out.setUint32(at2, b.length, Endian.little);
  out.setUint32(at2 + 4, 0x004E4942, Endian.little);
  o.setRange(at2 + 8, at2 + 8 + b.length, b);
  return o;
}
