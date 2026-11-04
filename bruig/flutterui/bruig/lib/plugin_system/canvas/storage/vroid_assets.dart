import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/vrm_convert.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:path/path.dart' as path;

// vroid_assets.dart fetches the characters the Character Studio builds from:
// four of pixiv's VRoid sample characters, released CC0, as bodies, and four
// more kept only for their hair. Each is fetched the first time it is wanted
// (the bodies when the Studio first opens, a hairstyle's source when it is
// first picked), turned from VRM 0.x into VRM 1.0 (vrm_convert.dart), and
// kept in the library. Fetched from GitHub at a pinned commit, and not at all
// through a proxy (canvas_network.dart).

/// VroidModel is one character to fetch: its name in the samples, and
/// whether it is kept whole or only for its hair.
typedef VroidModel = ({String id, bool hairOnly, int bytes});

/// vroidBodies are the bodies every character is built from.
const List<VroidModel> vroidBodies = [
  (id: "Vivi", hairOnly: false, bytes: 18089136),
  (id: "Victoria_Rubin", hairOnly: false, bytes: 15479480),
  (id: "Vita", hairOnly: false, bytes: 14359044),
  (id: "HairSample_Male", hairOnly: false, bytes: 18481892),
];

/// vroidHairSources are the characters kept only for their hair, for the
/// hairstyles the bodies do not have.
const List<VroidModel> vroidHairSources = [
  (id: "Sendagaya_Shino", hairOnly: true, bytes: 15074328),
  (id: "Sendagaya_Shibu", hairOnly: true, bytes: 17049284),
  (id: "HairSample_Female", hairOnly: true, bytes: 17518216),
  (id: "Sakurada_Fumiriya", hairOnly: true, bytes: 19342280),
];

/// vroidBodiesBytes is about how much the bodies are, for saying so.
int get vroidBodiesBytes => vroidBodies.fold(0, (s, m) => s + m.bytes);

class VroidAssets {
  /// _base is the samples, pinned to a commit: what is fetched never changes.
  static const String _base =
      "https://raw.githubusercontent.com/madjin/vrm-samples/"
      "e16eb187100149a315ad92c3c9968f1d5baa6c7d/vroid/beta";

  static Future<String> dir({bool create = false}) async {
    var d = path.join(await CanvasStorage.libraryDir(), canvasVroidFolder);
    if (create) await Directory(d).create(recursive: true);
    return d;
  }

  /// isModel is whether [id] is one of the models above: a body's id comes
  /// from documents other people send, and only these ever become paths.
  static bool isModel(String id) =>
      vroidBodies.any((m) => m.id == id) ||
      vroidHairSources.any((m) => m.id == id);

  /// modelPath is where [id], converted, is kept.
  static Future<String> modelPath(String id) async {
    if (!isModel(id)) throw ArgumentError.value(id, "id", "not a VRoid model");
    return path.join(await dir(), "$id.vrm");
  }

  static Future<String> _stampPath(String id) async {
    if (!isModel(id)) throw ArgumentError.value(id, "id", "not a VRoid model");
    return path.join(await dir(), "$id.version");
  }

  /// installed is whether [id] is here, converted the way this version of
  /// the app converts.
  static Future<bool> installed(String id) async {
    if (inTestsUnaimed) return false;
    try {
      if (!await File(await modelPath(id)).exists()) return false;
      return (await File(await _stampPath(id)).readAsString()).trim() ==
          "$vrmConvertVersion";
    } catch (_) {
      return false;
    }
  }

  /// missing is which of [models] are not here yet.
  static Future<List<VroidModel>> missing(List<VroidModel> models) async => [
        for (final m in models)
          if (!await installed(m.id)) m,
      ];

  /// install fetches each of [models] not here yet and converts it, saying
  /// how far along it is to [progress] as a share from nought to one.
  /// Throws a message fit to show when it cannot.
  static Future<void> install(List<VroidModel> models,
      {void Function(double)? progress}) async {
    final todo = await missing(models);
    if (todo.isEmpty) {
      progress?.call(1);
      return;
    }
    if (await networkIsProxied()) {
      throw "This app reaches the network through a proxy, which this "
          "download cannot use. The characters need a direct connection "
          "to GitHub.";
    }
    final root = await dir(create: true);
    final scratch = await Directory(root).createTemp("download");
    final total = todo.fold<int>(0, (s, m) => s + m.bytes);
    var done = 0;
    try {
      for (final m in todo) {
        final raw = File(path.join(scratch.path, "${m.id}.vrm"));
        var got = false;
        for (var attempt = 0; attempt < 3 && !got; attempt++) {
          got = await StockClient.instance.download("$_base/${m.id}.vrm", raw,
              maxBytes: 32 << 20, allowFetching: true, proxied: false);
        }
        if (!got) throw "A character could not be fetched (${m.id}).";
        final bytes = await raw.readAsBytes();
        final converted =
            await Isolate.run(() => _convertChecked(bytes, m.hairOnly));
        final out = File(await modelPath(m.id));
        await File("${out.path}.part").writeAsBytes(converted, flush: true);
        await File("${out.path}.part").rename(out.path);
        await File(await _stampPath(m.id)).writeAsString("$vrmConvertVersion");
        await raw.delete();
        done += m.bytes;
        progress?.call(done / total);
      }
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// remove deletes every fetched character, for when they are no longer
  /// wanted.
  static Future<void> remove() async {
    try {
      await Directory(await dir()).delete(recursive: true);
    } catch (_) {}
  }
}

/// _convertChecked converts [bytes], once it has made sure the file says it
/// is CC0: what is kept and built on must be free to use.
Uint8List _convertChecked(Uint8List bytes, bool hairOnly) {
  if (!isVrm0(bytes)) throw "A fetched character is not a VRM 0 file.";
  final jl = ByteData.sublistView(bytes).getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jl)))
      as Map<String, dynamic>;
  final licence =
      ((json['extensions'] as Map)['VRM'] as Map)['meta']?['licenseName'];
  if (licence != "CC0") {
    throw "A fetched character is not CC0 ($licence), so it is not kept.";
  }
  return convertVrm0(bytes, hairOnly: hairOnly);
}
