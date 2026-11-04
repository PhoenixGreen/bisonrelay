import 'dart:convert';
import 'dart:typed_data';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// gltf_pack.dart packs a multi-file glTF (the .gltf, its buffers and its
// pictures, as Poly Haven serves them) into one .glb, which the library keeps
// and a sent canvas carries. Buffers are joined into the one binary chunk,
// each picture a buffer view of its own; nothing is decoded.

/// packGltf is the .gltf [gltf] -- its text -- as a .glb, its files found
/// by [files]: each by the address the .gltf names it by. Null where a
/// file it needs is missing or it cannot be read.
Uint8List? packGltf(String gltf, Map<String, Uint8List> files) {
  Map<String, dynamic> json;
  try {
    var read = jsonDecode(gltf);
    if (read is! Map<String, dynamic>) return null;
    json = read;
  } catch (_) {
    return null;
  }
  Uint8List? fileOf(String uri) {
    if (uri.startsWith("data:")) {
      var comma = uri.indexOf(",");
      if (comma < 0 || !uri.substring(0, comma).endsWith(";base64")) {
        return null;
      }
      return base64Decode(uri.substring(comma + 1));
    }
    return files[Uri.decodeComponent(uri)] ?? files[uri];
  }

  var bin = BytesBuilder();
  void align() {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
  }

  // Each buffer where it now starts in the one.
  var starts = <int>[];
  var buffers = json["buffers"] is List ? json["buffers"] as List : const [];
  for (var b in buffers) {
    if (b is! Map || b["uri"] is! String) return null;
    var bytes = fileOf(b["uri"] as String);
    if (bytes == null) return null;
    align();
    starts.add(bin.length);
    bin.add(bytes);
  }
  var views = [
    for (var v
        in json["bufferViews"] is List ? json["bufferViews"] as List : [])
      if (v is Map)
        {
          ...v,
          "buffer": 0,
          "byteOffset": ((jsonNum(v["byteOffset"])) ?? 0).toInt() +
              (v["buffer"] is int && (v["buffer"] as int) < starts.length
                  ? starts[v["buffer"] as int]
                  : 0),
        }
  ];
  // The pictures, each a view of its own.
  var images = <Object?>[];
  for (var image in json["images"] is List ? json["images"] as List : []) {
    if (image is Map && image["uri"] is String) {
      var uri = image["uri"] as String;
      var bytes = fileOf(uri);
      if (bytes == null) return null;
      align();
      views.add(
          {"buffer": 0, "byteOffset": bin.length, "byteLength": bytes.length});
      bin.add(bytes);
      images.add({
        for (var e in image.entries)
          if (e.key != "uri") e.key: e.value,
        "bufferView": views.length - 1,
        "mimeType": image["mimeType"] ?? _mimeOf(uri),
      });
    } else {
      images.add(image);
    }
  }
  align();
  var body = bin.toBytes();
  json = {
    ...json,
    "buffers": [
      if (body.isNotEmpty) {"byteLength": body.length}
    ],
    if (views.isNotEmpty) "bufferViews": views,
    if (images.isNotEmpty) "images": images,
  };
  var text = utf8.encode(jsonEncode(json));
  var padded = [...text, ...List.filled((4 - text.length % 4) % 4, 0x20)];
  var total = 12 + 8 + padded.length + (body.isEmpty ? 0 : 8 + body.length);
  var out = BytesBuilder()
    ..add(_u32(0x46546C67)) // glTF
    ..add(_u32(2))
    ..add(_u32(total))
    ..add(_u32(padded.length))
    ..add(_u32(0x4E4F534A)) // JSON
    ..add(padded);
  if (body.isNotEmpty) {
    out
      ..add(_u32(body.length))
      ..add(_u32(0x004E4942)) // BIN
      ..add(body);
  }
  return out.toBytes();
}

String _mimeOf(String uri) {
  var u = uri.toLowerCase();
  if (u.endsWith(".png")) return "image/png";
  if (u.endsWith(".webp")) return "image/webp";
  if (u.endsWith(".ktx2")) return "image/ktx2";
  return "image/jpeg";
}

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
