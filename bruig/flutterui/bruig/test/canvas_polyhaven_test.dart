import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/gltf_pack.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:flutter_test/flutter_test.dart';

// Poly Haven's 3D models: found by its search, shown from its catalogue,
// open to all with no key, and fetched as the several files they are --
// packed into the one .glb the library keeps.

/// chunks is a .glb's JSON and its binary.
(Map<String, dynamic>, Uint8List) chunks(Uint8List glb) {
  var d = ByteData.sublistView(glb);
  expect(d.getUint32(0, Endian.little), 0x46546C67, reason: "glTF");
  expect(d.getUint32(8, Endian.little), glb.length, reason: "its length");
  var jsonLength = d.getUint32(12, Endian.little);
  var json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)));
  var at = 20 + jsonLength;
  var binLength = d.getUint32(at, Endian.little);
  expect(d.getUint32(at + 4, Endian.little), 0x004E4942, reason: "BIN");
  return (
    json as Map<String, dynamic>,
    glb.sublist(at + 8, at + 8 + binLength)
  );
}

void main() {
  test("a glTF and its files are packed into one .glb", () {
    var mesh = Uint8List.fromList(List.generate(10, (i) => i + 1));
    var picture = Uint8List.fromList([0xFF, 0xD8, 0xFF, 7, 7]);
    var gltf = jsonEncode({
      "asset": {"version": "2.0"},
      "buffers": [
        {"uri": "Chair.bin", "byteLength": 10}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 4, "byteLength": 6}
      ],
      "images": [
        {"uri": "textures/Chair%20wood.jpg", "name": "wood"}
      ],
    });
    var glb = packGltf(gltf, {
      "Chair.bin": mesh,
      "textures/Chair wood.jpg": picture,
    })!;
    var (json, bin) = chunks(glb);
    expect(json["buffers"], [
      {"byteLength": bin.length}
    ]);
    var views = json["bufferViews"] as List;
    expect(views[0]["byteOffset"], 4, reason: "the mesh first, where it was");
    expect(bin.sublist(views[0]["byteOffset"], views[0]["byteOffset"] + 6),
        mesh.sublist(4));
    var image = (json["images"] as List).single as Map;
    expect(image.containsKey("uri"), isFalse);
    expect((image["mimeType"], image["name"]), ("image/jpeg", "wood"));
    var view = views[image["bufferView"] as int] as Map;
    expect(view["byteOffset"] % 4, 0, reason: "aligned");
    expect(bin.sublist(view["byteOffset"], view["byteOffset"] + 5), picture);
    expect(packGltf(gltf, {"Chair.bin": mesh}), isNull,
        reason: "a picture missing is not packed without it");
  });

  test("its models: searched, or the most downloaded, a page at a time", () {
    var catalogue = {
      for (var i = 0; i < 40; i++)
        "model_$i": {
          "name": "Model $i",
          "authors": {"Jake Mobley": "All"},
          "download_count": i,
          "thumbnail_url": "https://cdn.polyhaven.com/asset_img/thumbs/m$i.png",
        }
    };
    var first = polyHavenPage(catalogue, null);
    expect(first.items.first.title, "Model 39", reason: "most downloaded");
    expect(first.items, hasLength(stockPageSize));
    expect(first.more, isTrue);
    expect(polyHavenPage(catalogue, null, page: 2).items, hasLength(10));
    var found = polyHavenPage(catalogue, ["model_3", "gone", "model_1"]);
    expect([for (var i in found.items) i.id], ["model_3", "model_1"]);
    var item = found.items.first;
    expect((item.license, item.author, item.kind),
        ("CC0", "Jake Mobley", AssetKind.model));
    expect(item.page, "https://polyhaven.com/a/model_3");
    expect(StockSource.polyHaven.terms, contains("Powered by Poly Haven"),
        reason: "the credit its API asks for");
  });

  test("no key is needed", () async {
    expect(StockSource.polyHaven.needsKey, isFalse);
    expect(await StockKeys.has(StockSource.polyHaven), isTrue);
  });
}
