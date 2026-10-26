import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';

// character_fbx.dart reads the motion out of an FBX file -- the form
// Mixamo gives its animations out in -- as a skeleton moving, for
// motionPoses to lay on a character.
//
// FBX is a tree of named records. What a motion needs from it is three
// kinds of object and how they are joined: the skeleton's joints (Model
// records, each placed against its parent), the curves that move them
// (AnimationCurve, a value at each key time) and the nodes that gather a
// joint's three curves for one property (AnimationCurveNode, "Lcl
// Rotation" say). Meshes, materials and skins are passed over: a modelled
// character is brought in as glTF, which keeps them far more simply.
//
// Only binary FBX, which is what Mixamo and every current exporter write.

/// _ticks is FBX's unit of time: this many to the second.
const double _ticks = 46186158000;

/// _Node is one record of an FBX file: its name, its values and the
/// records inside it.
class _Node {
  final String name;
  final List<Object?> props;
  final List<_Node> children;
  const _Node(this.name, this.props, this.children);

  _Node? child(String n) {
    for (var c in children) {
      if (c.name == n) return c;
    }
    return null;
  }

  /// properties is this record's "Properties70": each P's name and its
  /// values.
  Map<String, List<Object?>> get properties => {
        for (var p in child("Properties70")?.children ?? const <_Node>[])
          if (p.name == "P" && p.props.isNotEmpty) "${p.props[0]}": p.props.sublist(4),
      };
}

class _Reader {
  final Uint8List bytes;
  final ByteData data;
  final bool wide;
  int at = 27;

  _Reader(this.bytes, int version)
      : data = ByteData.sublistView(bytes),
        wide = version >= 7500;

  int _uint() {
    if (wide) {
      var v = data.getUint64(at, Endian.little);
      at += 8;
      return v;
    }
    var v = data.getUint32(at, Endian.little);
    at += 4;
    return v;
  }

  /// node reads the record at [at], or null at the empty record that ends
  /// a list.
  _Node? node() {
    var end = _uint();
    var count = _uint();
    _uint(); // The properties' length in bytes, which reading them gives.
    var nameLength = bytes[at++];
    if (end == 0) return null;
    var name = latin1.decode(Uint8List.sublistView(bytes, at, at + nameLength));
    at += nameLength;
    var props = [for (var i = 0; i < count; i++) _prop()];
    var children = <_Node>[];
    while (at < end) {
      var c = node();
      if (c == null) break;
      children.add(c);
    }
    at = end;
    return _Node(name, props, children);
  }

  Object? _prop() {
    var type = String.fromCharCode(bytes[at++]);
    switch (type) {
      case "Y":
        var v = data.getInt16(at, Endian.little);
        at += 2;
        return v;
      case "C":
        return bytes[at++] != 0;
      case "I":
        var v = data.getInt32(at, Endian.little);
        at += 4;
        return v;
      case "F":
        var v = data.getFloat32(at, Endian.little);
        at += 4;
        return v;
      case "D":
        var v = data.getFloat64(at, Endian.little);
        at += 8;
        return v;
      case "L":
        var v = data.getInt64(at, Endian.little);
        at += 8;
        return v;
      case "S":
      case "R":
        var n = data.getUint32(at, Endian.little);
        at += 4;
        var raw = Uint8List.sublistView(bytes, at, at + n);
        at += n;
        return type == "S" ? latin1.decode(raw) : raw;
      case "f":
      case "d":
      case "l":
      case "i":
      case "b":
        var count = data.getUint32(at, Endian.little);
        var encoding = data.getUint32(at + 4, Endian.little);
        var length = data.getUint32(at + 8, Endian.little);
        at += 12;
        var raw = Uint8List.sublistView(bytes, at, at + length);
        at += length;
        if (encoding == 1) {
          raw = Uint8List.fromList(ZLibDecoder().convert(raw));
        }
        var d = ByteData.sublistView(raw);
        return switch (type) {
          "f" => [for (var i = 0; i < count; i++) d.getFloat32(i * 4, Endian.little).toDouble()],
          "d" => [for (var i = 0; i < count; i++) d.getFloat64(i * 8, Endian.little)],
          "l" => [for (var i = 0; i < count; i++) d.getInt64(i * 8, Endian.little)],
          "i" => [for (var i = 0; i < count; i++) d.getInt32(i * 4, Endian.little)],
          _ => [for (var i = 0; i < count; i++) raw[i] != 0],
        };
      default:
        throw MotionError("The FBX file is damaged (a value of type '$type').");
    }
  }
}

/// _Joint is a joint of the skeleton, standing as it was made.
class _Joint {
  final int id;
  final String name;
  int parent = -1;
  List<double> translation, rotation, preRotation, postRotation, scaling;
  final int order;

  /// curves is what moves it: for "T", "R" and "S", a curve for each of
  /// x, y and z, or null where that one is not moved.
  final Map<String, List<_Curve?>> curves = {};

  _Joint(this.id, this.name, this.translation, this.rotation,
      this.preRotation, this.postRotation, this.scaling, this.order);
}

/// _Curve is one value's keys: times in seconds, and the values.
class _Curve {
  final List<double> times;
  final List<double> values;
  const _Curve(this.times, this.values);

  double at(double t) {
    if (times.isEmpty) return 0;
    if (t <= times.first) return values.first;
    if (t >= times.last) return values.last;
    var lo = 0, hi = times.length - 1;
    while (hi - lo > 1) {
      var mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    var f = (t - times[lo]) / math.max(1e-12, times[hi] - times[lo]);
    return values[lo] + (values[hi] - values[lo]) * f;
  }
}

/// parseFbxMotion reads the skeleton and its motion out of [bytes], a
/// binary FBX file, at [frameRate] frames a second. Throws a MotionError
/// for what is not binary FBX, or has no motion in it.
JointMotion parseFbxMotion(Uint8List bytes, {double frameRate = 30}) {
  const magic = "Kaydara FBX Binary  ";
  if (bytes.length < 27 ||
      latin1.decode(Uint8List.sublistView(bytes, 0, 20)) != magic) {
    if (bytes.length > 5 && utf8.decode(bytes.sublist(0, math.min(200, bytes.length)),
            allowMalformed: true).contains("FBX")) {
      throw const MotionError("This is a text FBX file. Save it as binary "
          "FBX -- what Mixamo downloads are -- and bring that in.");
    }
    throw const MotionError("This is not an FBX file.");
  }
  var version = ByteData.sublistView(bytes).getUint32(23, Endian.little);
  var reader = _Reader(bytes, version);
  var top = <_Node>[];
  try {
    while (reader.at < bytes.length - 13) {
      var n = reader.node();
      if (n == null) break;
      top.add(n);
    }
  } on RangeError {
    throw const MotionError("The FBX file is damaged: it ends too soon.");
  }
  _Node? find(String name) {
    for (var n in top) {
      if (n.name == name) return n;
    }
    return null;
  }

  var objects = find("Objects");
  var connections = find("Connections");
  if (objects == null || connections == null) {
    throw const MotionError("The FBX file has nothing in it.");
  }

  List<double> vec(Map<String, List<Object?>> p, String key, List<double> or) {
    var v = p[key];
    if (v == null || v.length < 3) return or;
    return [for (var i = 0; i < 3; i++) (v[i] as num).toDouble()];
  }

  var joints = <int, _Joint>{};
  var curveNodes = <int, String>{};
  var curves = <int, _Curve>{};
  for (var o in objects.children) {
    if (o.props.isEmpty || o.props[0] is! int) continue;
    var id = o.props[0] as int;
    var name = o.props.length > 1 ? "${o.props[1]}".split("\u0000").first : "";
    switch (o.name) {
      case "Model":
        var kind = o.props.length > 2 ? "${o.props[2]}" : "";
        if (kind != "LimbNode" && kind != "Root" && kind != "Null") break;
        var p = o.properties;
        joints[id] = _Joint(
          id,
          name,
          vec(p, "Lcl Translation", const [0, 0, 0]),
          vec(p, "Lcl Rotation", const [0, 0, 0]),
          vec(p, "PreRotation", const [0, 0, 0]),
          vec(p, "PostRotation", const [0, 0, 0]),
          vec(p, "Lcl Scaling", const [1, 1, 1]),
          (p["RotationOrder"]?.firstOrNull as num?)?.toInt() ?? 0,
        );
      case "AnimationCurveNode":
        curveNodes[id] = name;
      case "AnimationCurve":
        var t = o.child("KeyTime")?.props.firstOrNull;
        var v = o.child("KeyValueFloat")?.props.firstOrNull;
        if (t is List && v is List && t.isNotEmpty) {
          curves[id] = _Curve([for (var x in t) (x as int) / _ticks],
              [for (var x in v) (x as num).toDouble()]);
        }
    }
  }
  if (joints.isEmpty) {
    throw const MotionError("The FBX file has no skeleton in it.");
  }

  // How the pieces are joined: a joint to its parent; a curve to the
  // curve node for one axis of a property; a curve node to the joint whose
  // property it moves.
  var curveOf = <int, Map<String, _Curve>>{};
  var nodeOf = <int, (int, String)>{};
  for (var c in connections.children) {
    if (c.name != "C" || c.props.length < 3) continue;
    var kind = c.props[0], child = c.props[1], parent = c.props[2];
    if (child is! int || parent is! int) continue;
    if (kind == "OO" && joints.containsKey(child) && joints.containsKey(parent)) {
      joints[child]!.parent = parent;
    } else if (kind == "OP" && c.props.length > 3) {
      var prop = "${c.props[3]}";
      if (curves.containsKey(child) && curveNodes.containsKey(parent)) {
        (curveOf[parent] ??= {})[prop] = curves[child]!;
      } else if (curveNodes.containsKey(child) && joints.containsKey(parent)) {
        nodeOf[child] = (parent, prop);
      }
    }
  }
  var end = 0.0;
  for (var e in nodeOf.entries) {
    var (joint, prop) = e.value;
    var key = switch (prop) {
      "Lcl Translation" => "T",
      "Lcl Rotation" => "R",
      "Lcl Scaling" => "S",
      _ => null,
    };
    if (key == null) continue;
    var axes = curveOf[e.key] ?? const {};
    var three = [axes["d|X"], axes["d|Y"], axes["d|Z"]];
    joints[joint]!.curves[key] = three;
    for (var c in three) {
      if (c != null && c.times.isNotEmpty) end = math.max(end, c.times.last);
    }
  }
  if (nodeOf.isEmpty) {
    throw const MotionError("The FBX file has a skeleton but no motion. "
        "On Mixamo, download it with Skin off or on -- either works -- "
        "but as an animation, not a T-pose.");
  }

  // Parents before children.
  var order = <_Joint>[];
  var placed = <int>{};
  void place(_Joint j) {
    if (placed.contains(j.id)) return;
    if (joints[j.parent] case var p?) place(p);
    placed.add(j.id);
    order.add(j);
  }

  for (var j in joints.values) {
    place(j);
  }
  var index = {for (var (i, j) in order.indexed) j.id: i};
  var frames = math.max(1, (end * frameRate).round() + 1);

  List<List<double>> positionsAt(int f) {
    var t = f / frameRate;
    var world = <_M4>[];
    var out = <List<double>>[];
    for (var j in order) {
      List<double> value(String key, List<double> rest) {
        var c = j.curves[key];
        if (c == null) return rest;
        return [for (var k = 0; k < 3; k++) c[k]?.at(t) ?? rest[k]];
      }

      var local = _M4.translate(value("T", j.translation)) *
          _M4.euler(j.preRotation, 0) *
          _M4.euler(value("R", j.rotation), j.order) *
          _M4.euler(j.postRotation, 0).transposed *
          _M4.scale(value("S", j.scaling));
      var p = index[j.parent];
      var w = p == null ? local : world[p] * local;
      world.add(w);
      out.add([w.m[3], w.m[7], w.m[11]]);
    }
    return out;
  }

  return JointMotion([for (var j in order) j.name], frames, 1 / frameRate,
      positionsAt);
}

/// _M4 is a 4x4 matrix, row by row.
class _M4 {
  final List<double> m;
  const _M4(this.m);

  factory _M4.translate(List<double> t) =>
      _M4([1, 0, 0, t[0], 0, 1, 0, t[1], 0, 0, 1, t[2], 0, 0, 0, 1]);

  factory _M4.scale(List<double> s) =>
      _M4([s[0], 0, 0, 0, 0, s[1], 0, 0, 0, 0, s[2], 0, 0, 0, 0, 1]);

  /// euler is turns of [d] degrees round x, y and z in FBX's [order] --
  /// 0 is XYZ, x turned first -- as one matrix.
  factory _M4.euler(List<double> d, int order) {
    _M4 axis(int a) {
      var r = d[a] * math.pi / 180, c = math.cos(r), s = math.sin(r);
      return switch (a) {
        0 => _M4([1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1]),
        1 => _M4([c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1]),
        _ => _M4([c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      };
    }

    // The axes in the order they are turned; the matrix applies the first
    // last.
    var axes = const [
      [0, 1, 2], // XYZ
      [0, 2, 1], // XZY
      [1, 2, 0], // YZX
      [1, 0, 2], // YXZ
      [2, 0, 1], // ZXY
      [2, 1, 0], // ZYX
    ][order.clamp(0, 5)];
    return axis(axes[2]) * axis(axes[1]) * axis(axes[0]);
  }

  _M4 operator *(_M4 b) => _M4([
        for (var r = 0; r < 4; r++)
          for (var c = 0; c < 4; c++)
            m[r * 4] * b.m[c] +
                m[r * 4 + 1] * b.m[4 + c] +
                m[r * 4 + 2] * b.m[8 + c] +
                m[r * 4 + 3] * b.m[12 + c],
      ]);

  /// transposed is, for a turn, the turn undone.
  _M4 get transposed => _M4([
        for (var r = 0; r < 4; r++)
          for (var c = 0; c < 4; c++) m[c * 4 + r],
      ]);
}
