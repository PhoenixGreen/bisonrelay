import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/human_targets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:path/path.dart' as path;

// human_assets.dart fetches the MakeHuman body -- its mesh, its skeleton,
// how the skin hangs from the skeleton, and the shapes it can be sculpted
// into -- the first time a character is made of it, and keeps it as one
// compact pack.
//
// Fetched only when asked, from GitHub, at a pinned version; and not at
// all through a proxy, which a direct download cannot honour -- the same
// rule as the stock libraries.

/// humanDownloadBytes is about how much is downloaded, for saying so.
const int humanDownloadBytes = 26 << 20;

/// inTestsUnaimed is whether this is a test that has not said where its
/// library is: the real one is not looked in -- what is downloaded on this
/// machine is no test's business.
bool get inTestsUnaimed =>
    Platform.environment.containsKey("FLUTTER_TEST") &&
    !CanvasStorage.overridden;

class HumanAssets {
  static const String _base =
      "https://raw.githubusercontent.com/makehumancommunity/makehuman/"
      "$makeHumanCommit/makehuman/data";

  /// _version is the pack's own format: a pack of another is fetched
  /// again.
  static const int _version = 1;

  static Future<String> dir({bool create = false}) async {
    var d = path.join(await CanvasStorage.libraryDir(), "Human");
    if (create) await Directory(d).create(recursive: true);
    return d;
  }

  static Future<String> packPath() async => path.join(await dir(), "human.pack");

  /// installed is whether the body is here to be used.
  static Future<bool> installed() async {
    if (inTestsUnaimed) return false;
    try {
      var f = File(await packPath());
      if (!await f.exists()) return false;
      var head = await f.openRead(0, 8).fold<List<int>>([], (a, b) => a..addAll(b));
      return head.length == 8 &&
          ascii.decode(head.sublist(0, 4)) == "MHPK" &&
          ByteData.sublistView(Uint8List.fromList(head)).getUint32(4, Endian.little) ==
              _version;
    } catch (_) {
      return false;
    }
  }

  /// install fetches the body and packs it, saying how far along it is to
  /// [progress] as a share from nought to one. Throws a message fit to show
  /// when it cannot.
  static Future<void> install({void Function(double)? progress}) async {
    if (await networkIsProxied()) {
      throw "This app reaches the network through a proxy, which this "
          "download cannot use. The detailed body needs a direct "
          "connection to GitHub.";
    }
    var root = await dir(create: true);
    var scratch = await Directory(root).createTemp("download");
    try {
      var files = <String>[
        "3dobjs/base.obj",
        "rigs/default.mhskel",
        "rigs/default_weights.mhw",
        for (var t in humanTargetFiles()) "targets/$t.target",
      ];
      for (var (i, f) in files.indexed) {
        var to = File(path.join(scratch.path, f));
        await to.parent.create(recursive: true);
        var got = false;
        for (var attempt = 0; attempt < 3 && !got; attempt++) {
          got = await StockClient.instance.download("$_base/$f", to,
              maxBytes: 8 << 20, allowFetching: true, proxied: false);
        }
        if (!got) throw "Part of the body could not be fetched ($f).";
        progress?.call((i + 1) / (files.length + 1));
      }
      var pack = await Isolate.run(() => _pack(scratch.path));
      var out = File(await packPath());
      await File("${out.path}.part").writeAsBytes(pack, flush: true);
      await File("${out.path}.part").rename(out.path);
      for (var keep in ["rigs/default.mhskel", "rigs/default_weights.mhw"]) {
        await File(path.join(scratch.path, keep))
            .copy(path.join(root, path.basename(keep)));
      }
      progress?.call(1);
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// remove deletes the body, for when it is no longer wanted.
  static Future<void> remove() async {
    try {
      await Directory(await dir()).delete(recursive: true);
    } catch (_) {}
  }
}

/// packHumanFiles is [_pack], for a test with the files already fetched.
Uint8List packHumanFiles(String root) => _pack(root);

/// _pack reads the downloaded files under [root] into one pack:
///
///   "MHPK", version
///   vertex count, then x y z for each, as floats
///   uv count, then u v for each
///   group count; each a name, then its triangles as vertex and uv indices
///   target count; each a name, how many vertices it moves, their indices
///   (16 bits) and how far, as 16-bit numbers of 1/2000 of a unit.
///
/// The three peoples' targets of each sex and age are blended evenly into
/// one, which is how MakeHuman makes a person of no one people.
Uint8List _pack(String root) {
  var b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  // A name: its length in two bytes, then the name, padded out to four.
  void name(String s) {
    var bytes = utf8.encode(s);
    b.add((ByteData(2)..setUint16(0, bytes.length, Endian.little)).buffer.asUint8List());
    b.add(bytes);
    var pad = (4 - (2 + bytes.length) % 4) % 4;
    b.add(Uint8List(pad));
  }

  b.add(ascii.encode("MHPK"));
  u32(1);

  // The mesh.
  var verts = <double>[], uvs = <double>[];
  var groups = <String, List<int>>{};
  var group = "body";
  for (var line in File(path.join(root, "3dobjs/base.obj")).readAsLinesSync()) {
    if (line.startsWith("v ")) {
      var p = line.split(RegExp(r"\s+"));
      verts.addAll([double.parse(p[1]), double.parse(p[2]), double.parse(p[3])]);
    } else if (line.startsWith("vt ")) {
      var p = line.split(RegExp(r"\s+"));
      uvs.addAll([double.parse(p[1]), double.parse(p[2])]);
    } else if (line.startsWith("g ")) {
      group = line.substring(2).trim();
    } else if (line.startsWith("f ")) {
      var corners = [
        for (var c in line.substring(2).trim().split(RegExp(r"\s+")))
          [for (var n in c.split("/")) n.isEmpty ? 0 : int.parse(n) - 1],
      ];
      var tris = groups.putIfAbsent(group, () => []);
      for (var k = 1; k + 1 < corners.length; k++) {
        for (var c in [corners[0], corners[k], corners[k + 1]]) {
          tris.add(c[0]);
          tris.add(c.length > 1 ? c[1] : 0);
        }
      }
    }
  }
  u32(verts.length ~/ 3);
  b.add(Float32List.fromList(verts).buffer.asUint8List());
  u32(uvs.length ~/ 2);
  b.add(Float32List.fromList(uvs).buffer.asUint8List());
  // Only what is drawn: the body, the hair and eyes and lashes it carries.
  // Joints, clothes helpers and the rest are not.
  var kept = {
    for (var e in groups.entries)
      if (e.key == "body" ||
          e.key == "helper-hair" ||
          e.key.startsWith("helper-l-eye") ||
          e.key.startsWith("helper-r-eye") ||
          e.key.contains("eyelashes"))
        e.key: e.value,
  };
  u32(kept.length);
  for (var e in kept.entries) {
    name(e.key);
    u32(e.value.length ~/ 2);
    b.add(Uint32List.fromList(e.value).buffer.asUint8List());
  }

  // The targets.
  Map<int, List<double>> read(String rel) {
    var out = <int, List<double>>{};
    for (var line in File(path.join(root, "targets/$rel.target")).readAsLinesSync()) {
      if (line.isEmpty || line.startsWith("#")) continue;
      var p = line.trim().split(RegExp(r"\s+"));
      if (p.length < 4) continue;
      out[int.parse(p[0])] = [double.parse(p[1]), double.parse(p[2]), double.parse(p[3])];
    }
    return out;
  }

  var targets = <String, Map<int, List<double>>>{};
  var raced = <String>{};
  for (var g in ["female", "male"]) {
    for (var a in ["baby", "child", "young", "old"]) {
      var sum = <int, List<double>>{};
      for (var rel in macroRaceTargets(g, a)) {
        raced.add(rel);
        for (var e in read(rel).entries) {
          var s = sum.putIfAbsent(e.key, () => [0, 0, 0]);
          for (var k = 0; k < 3; k++) {
            s[k] += e.value[k] / 3;
          }
        }
      }
      targets["macro/$g-$a"] = sum;
    }
  }
  for (var rel in humanTargetFiles()) {
    if (raced.contains(rel)) continue;
    targets[rel] = read(rel);
  }
  u32(targets.length);
  for (var e in targets.entries) {
    name(e.key);
    var n = e.value.length;
    u32(n);
    var idx = Uint16List(n + (n.isOdd ? 1 : 0));
    var d = Int16List(n * 3 + (n.isOdd ? 1 : 0));
    var k = 0;
    for (var v in e.value.entries) {
      idx[k] = v.key;
      for (var c = 0; c < 3; c++) {
        d[k * 3 + c] = (v.value[c] * 2000).round().clamp(-32768, 32767);
      }
      k++;
    }
    // Padded to four bytes, so each block can be read as it lies.
    b.add(idx.buffer.asUint8List());
    b.add(d.buffer.asUint8List());
  }
  return b.takeBytes();
}
