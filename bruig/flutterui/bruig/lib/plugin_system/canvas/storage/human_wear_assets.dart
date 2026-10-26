import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/human_targets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/remote_zip.dart';
import 'package:path/path.dart' as path;

// human_wear_assets.dart fetches the hair, brows, shoes and teeth -- see
// human_wear.dart -- from MakeHuman's collections, only the files each
// needs out of the zips they are in. A cut-out piece keeps only where its
// picture is solid, small: its colour comes from the character.

/// humanWearBytes is about how much is downloaded, for saying so.
const int humanWearBytes = 45 << 20;

class HumanWearAssets {
  static Future<String> dir({bool create = false}) async {
    var d = path.join(await HumanAssets.dir(create: create), "wear");
    if (create) await Directory(d).create(recursive: true);
    return d;
  }

  static Future<bool> installed() async {
    if (inTestsUnaimed) return false;
    try {
      return await File(path.join(await dir(), "done")).exists();
    } catch (_) {
      return false;
    }
  }

  /// install fetches every piece, saying how far along to [progress].
  /// Throws a message fit to show when it cannot.
  static Future<void> install({void Function(double)? progress}) async {
    if (await networkIsProxied()) {
      throw "This app reaches the network through a proxy, which this "
          "download cannot use. Hair and shoes need a direct connection to "
          "MakeHuman's site.";
    }
    var root = await dir(create: true);
    var zips = <String, RemoteZip>{};
    for (var e in wearZips.entries) {
      zips[e.key] = await RemoteZip.open(e.value);
    }
    for (var (i, item) in wearCatalogue.indexed) {
      var zip = zips[item.zip]!;
      var to = Directory(path.join(root, item.id));
      await to.create(recursive: true);
      Future<List<int>> read(String name) => zip.read("${item.dir}/$name");
      await File(path.join(to.path, "mesh.obj")).writeAsBytes(await read(item.obj));
      await File(path.join(to.path, "fit.mhclo")).writeAsBytes(await read(item.mhclo));
      if (item.cutOut) {
        var mat = utf8.decode(await read(item.mhmat), allowMalformed: true);
        var texture = _diffuse(mat);
        if (texture != null) {
          var mask = await _maskOf(await read(texture));
          if (mask != null) await File(path.join(to.path, "mask.png")).writeAsBytes(mask);
        }
      }
      progress?.call((i + 1) / wearCatalogue.length);
    }
    await File(path.join(root, "done")).writeAsString(makeHumanCommit);
  }

  static String? _diffuse(String mhmat) {
    for (var line in const LineSplitter().convert(mhmat)) {
      var t = line.trim();
      if (t.startsWith("diffuseTexture ")) return t.substring(15).trim();
    }
    return null;
  }

  /// _maskOf is where [png] is solid, as white, no more than 512 across.
  static Future<List<int>?> _maskOf(List<int> png) async {
    try {
      var codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
      var frame = await codec.getNextFrame();
      var image = frame.image;
      var scale = math.min(1.0, 512 / math.max(image.width, image.height));
      var w = math.max(1, (image.width * scale).round());
      var h = math.max(1, (image.height * scale).round());
      var rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(
          image,
          ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()
            ..filterQuality = ui.FilterQuality.medium
            ..colorFilter = const ui.ColorFilter.matrix([
              0, 0, 0, 0, 255, //
              0, 0, 0, 0, 255,
              0, 0, 0, 0, 255,
              0, 0, 0, 1, 0,
            ]));
      var small = await rec.endRecording().toImage(w, h);
      var bytes = await small.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      small.dispose();
      codec.dispose();
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
