import 'dart:convert';
import 'dart:typed_data';

// glb_info.dart reads what a 3D model offers from its file, without drawing
// it: the animations in a .glb -- each one's name and how long it runs --
// so its clips can be made, and its slots filled, where nothing can draw in
// 3D (a test, a machine without the GPU) and before the model is loaded.

/// ModelAnimation is one of a model's own animations: its name, and how
/// long it runs, in seconds.
typedef ModelAnimation = (String name, double length);

/// glbAnimations is the animations in the .glb [bytes], in the file's
/// order -- one with no name named for its place -- or null where [bytes]
/// are not a .glb this can read.
List<ModelAnimation>? glbAnimations(Uint8List bytes) {
  var json = _glbJson(bytes);
  if (json == null) return null;
  var accessors = json["accessors"] is List ? json["accessors"] as List : [];
  double endOf(Object? accessor) {
    if (accessor is! int || accessor < 0 || accessor >= accessors.length) {
      return 0;
    }
    var a = accessors[accessor];
    if (a is Map) {
      if (a["max"] case [num max, ...]) return max.toDouble();
    }
    return 0;
  }

  var out = <ModelAnimation>[];
  if (json["animations"] case List animations) {
    for (var (i, a) in animations.indexed) {
      if (a is! Map) continue;
      var length = 0.0;
      if (a["samplers"] case List samplers) {
        for (var s in samplers) {
          if (s is Map) {
            var end = endOf(s["input"]);
            if (end > length) length = end;
          }
        }
      }
      var name = a["name"] is String && (a["name"] as String).isNotEmpty
          ? a["name"] as String
          : "Animation ${i + 1}";
      out.add((name, length));
    }
  }
  return out;
}

/// _glbJson is the JSON chunk of a .glb: a 12-byte header -- "glTF", the
/// version, the length -- and then the first chunk, its length, "JSON" and
/// the text.
Map<String, dynamic>? _glbJson(Uint8List bytes) {
  if (bytes.length < 20) return null;
  var data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46546C67) return null; // glTF
  var length = data.getUint32(12, Endian.little);
  var type = data.getUint32(16, Endian.little);
  if (type != 0x4E4F534A || 20 + length > bytes.length) return null; // JSON
  try {
    var json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)));
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}
