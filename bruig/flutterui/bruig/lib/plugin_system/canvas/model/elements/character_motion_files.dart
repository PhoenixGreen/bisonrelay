import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_fbx.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';

// character_motion_files.dart is every kind of file motion can be brought
// in from, told apart by what is in it rather than by its name.

/// motionExtensions is the files a motion can be picked from.
const List<String> motionExtensions = ["bvh", "fbx", "glb", "gltf", "vrm"];

/// readMotionFile reads [bytes], the file at [path], as a skeleton moving
/// at [frameRate], with how to speak of where it came from -- or throws a
/// MotionError or GltfError saying why it could not.
(JointMotion, String) readMotionFile(Uint8List bytes, String path,
    {double frameRate = 30, int animation = 0}) {
  var head = bytes.length < 20
      ? ""
      : latin1.decode(Uint8List.sublistView(bytes, 0, 20), allowInvalid: true);
  if (head.startsWith("Kaydara FBX Binary")) {
    return (parseFbxMotion(bytes, frameRate: frameRate), "the FBX");
  }
  if (head.startsWith("glTF")) {
    return _gltf(parseGltf(bytes), frameRate, animation);
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  var start = text.trimLeft();
  if (start.startsWith("HIERARCHY")) {
    var bvh = parseBvh(text);
    return (
      JointMotion([for (var j in bvh.joints) j.name], bvh.frames.length,
          bvh.frameTime, (f) => bvhPositions(bvh, f)),
      "the BVH"
    );
  }
  if (start.startsWith("{")) {
    return _gltf(parseGltf(bytes), frameRate, animation);
  }
  if (text.contains("FBXHeaderExtension")) {
    throw const MotionError("This is a text FBX file. Save it as binary FBX "
        "-- what Mixamo downloads are -- and bring that in.");
  }
  throw const MotionError("It is not a BVH, FBX, glTF or VRM file.");
}

(JointMotion, String) _gltf(Gltf g, double frameRate, int animation) {
  var i = g.animations.isEmpty ? 0 : animation.clamp(0, g.animations.length - 1);
  var name = g.animations.isEmpty ? "" : g.animations[i].name;
  return (
    gltfMotion(g, index: i, frameRate: frameRate),
    name.isEmpty ? "the file" : "\"$name\""
  );
}

/// motionsIn is the names of the motions in [bytes] when it is a file
/// that can hold more than one -- a glTF -- and empty otherwise, or when
/// it cannot be read.
List<String> motionsIn(Uint8List bytes) {
  try {
    var head = bytes.length < 4
        ? ""
        : latin1.decode(Uint8List.sublistView(bytes, 0, 4), allowInvalid: true);
    var text = head == "glTF" ? "" : utf8.decode(bytes, allowMalformed: true);
    if (head != "glTF" && !text.trimLeft().startsWith("{")) return const [];
    return [for (var a in parseGltf(bytes).animations) a.name];
  } catch (_) {
    return const [];
  }
}
