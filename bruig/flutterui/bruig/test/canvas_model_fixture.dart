import 'dart:convert';
import 'dart:io' show ZLibEncoder;
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
    bool animated = false,
    bool toon = false,
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
  // A second's motion: the left arm brought down from the T to the side.
  var times = put(floats([0, 1]), 5126, 2, "SCALAR");
  var down = put(floats([0, 0, 0, 1, 0, 0, -0.70710678, 0.70710678]), 5126, 2, "VEC4");

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
        if (toon)
          "extensions": {
            "VRMC_materials_mtoon": {
              "shadeColorFactor": [0.5, 0.3, 0.6],
              "shadingToonyFactor": 0.95,
              "shadingShiftFactor": -0.1,
              "outlineWidthMode": "worldCoordinates",
              "outlineWidthFactor": 0.02,
              "outlineColorFactor": [0.2, 0.1, 0.1],
            }
          },
      }
    ],
    if (animated)
      "animations": [
        {
          "name": "Arm down",
          "samplers": [
            {"input": times, "output": down, "interpolation": "LINEAR"}
          ],
          "channels": [
            {
              "sampler": 0,
              "target": {"node": 4, "path": "rotation"}
            }
          ],
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


/// mixamoFbx is the fixture's skeleton as Mixamo's binary FBX gives one
/// out, in centimetres, with a second of motion on it: the left arm
/// brought down from the T to the side, turned round z from 0 to -90
/// degrees.
Uint8List mixamoFbx() {
  var out = BytesBuilder();
  out.add(latin1.encode("Kaydara FBX Binary  "));
  out.add([0, 0x1a, 0]);
  out.add(_u32(7400));

  // A record as bytes, its end offset counted from where it will start.
  Uint8List record(int start, String name, List<Uint8List> props,
      List<Uint8List Function(int)> children) {
    var p = BytesBuilder();
    for (var x in props) {
      p.add(x);
    }
    var propBytes = p.takeBytes();
    var headLength = 13 + name.length;
    var at = start + headLength + propBytes.length;
    var kids = BytesBuilder();
    for (var c in children) {
      var k = c(at);
      kids.add(k);
      at += k.length;
    }
    if (children.isNotEmpty) {
      kids.add(Uint8List(13));
      at += 13;
    }
    var b = BytesBuilder();
    b.add(_u32(at));
    b.add(_u32(props.length));
    b.add(_u32(propBytes.length));
    b.addByte(name.length);
    b.add(latin1.encode(name));
    b.add(propBytes);
    b.add(kids.takeBytes());
    return b.takeBytes();
  }

  Uint8List Function(int) node(String name, List<Uint8List> props,
          [List<Uint8List Function(int)> children = const []]) =>
      (start) => record(start, name, props, children);

  Uint8List Function(int) p70(Map<String, List<double>> vectors) =>
      node("Properties70", [], [
        for (var e in vectors.entries)
          node("P", [
            _s(e.key), _s(e.key), _s(""), _s("A"),
            for (var v in e.value) _d(v),
          ]),
      ]);

  var models = <Uint8List Function(int)>[];
  for (var (i, b) in _bones.indexed) {
    models.add(node("Model", [
      _l(1000 + i),
      _s("${b.$1}\u0000\u0001Model"),
      _s("LimbNode"),
    ], [
      p70({"Lcl Translation": [for (var v in b.$3) v * 100]}),
    ]));
  }
  // The curve node and its three curves.
  const second = 46186158000;
  models.add(node("AnimationCurveNode", [_l(2000), _s("R\u0000\u0001AnimCurveNode"), _s("")]));
  for (var (k, values) in [
    [0.0, 0.0],
    [0.0, 0.0],
    [0.0, -90.0],
  ].indexed) {
    models.add(node("AnimationCurve", [
      _l(3000 + k),
      _s("\u0000\u0001AnimCurve"),
      _s(""),
    ], [
      node("KeyTime", [_longs([0, second])]),
      node("KeyValueFloat", [_floats(values, compressed: k == 2)]),
    ]));
  }
  var links = <Uint8List Function(int)>[
    for (var (i, b) in _bones.indexed)
      if (b.$2 >= 0) node("C", [_s("OO"), _l(1000 + i), _l(1000 + b.$2)]),
    for (var (k, axis) in ["d|X", "d|Y", "d|Z"].indexed)
      node("C", [_s("OP"), _l(3000 + k), _l(2000), _s(axis)]),
    node("C", [_s("OP"), _l(2000), _l(1004), _s("Lcl Rotation")]),
  ];

  var at = 27;
  for (var top in [node("Objects", [], models), node("Connections", [], links)]) {
    var r = top(at);
    out.add(r);
    at += r.length;
  }
  out.add(Uint8List(13));
  return out.takeBytes();
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
Uint8List _s(String v) {
  var b = latin1.encode(v);
  return Uint8List.fromList([0x53, ..._u32(b.length), ...b]);
}

Uint8List _l(int v) => Uint8List.fromList(
    [0x4C, ...(ByteData(8)..setInt64(0, v, Endian.little)).buffer.asUint8List()]);
Uint8List _d(double v) => Uint8List.fromList(
    [0x44, ...(ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List()]);

Uint8List _longs(List<int> v) {
  var d = ByteData(v.length * 8);
  for (var (i, x) in v.indexed) {
    d.setInt64(i * 8, x, Endian.little);
  }
  var raw = d.buffer.asUint8List();
  return Uint8List.fromList(
      [0x6C, ..._u32(v.length), ..._u32(0), ..._u32(raw.length), ...raw]);
}

Uint8List _floats(List<double> v, {bool compressed = false}) {
  var raw = Float32List.fromList(v).buffer.asUint8List();
  var data = compressed ? Uint8List.fromList(ZLibEncoder().convert(raw)) : raw;
  return Uint8List.fromList([
    0x66,
    ..._u32(v.length),
    ..._u32(compressed ? 1 : 0),
    ..._u32(data.length),
    ...data,
  ]);
}
