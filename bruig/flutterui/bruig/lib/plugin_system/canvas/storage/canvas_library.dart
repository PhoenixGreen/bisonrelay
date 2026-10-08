import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_library.dart is the pictures, videos and sounds somebody has added,
// as a library they can see, use again and clear out -- the Assets sidebar.
//
// The files themselves are where they always were: content-addressed, in the
// Pictures, Videos and Audio folders. What this adds is a list of which of
// them are *assets*, with the names they were added under -- a hash says
// nothing to a person -- and, for a video, the poster and the soundtrack that
// came with it, which are files too but are not things anybody added.
//
// An asset stays until it is removed from the sidebar. Before this, a file no
// saved canvas used was deleted on the next save, so a picture added and not
// used yet was gone by the time anybody went looking for it. The tidy-up is
// kept for what is not an asset: a poster whose video has gone, a crest a
// table no longer shows.

/// AssetKind is which of the three sections an asset is in.
enum AssetKind {
  picture("Pictures"),
  video("Videos"),
  audio("Audio"),

  /// vector is the drawings -- .svg files, kept in their own store and
  /// placed as a Vector element. See VectorElement.
  vector("Vectors");

  final String label;
  const AssetKind(this.label);

  static AssetKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => picture);
}

/// LibraryAsset is one thing in the library.
class LibraryAsset {
  /// id is the stored file's: a picture's in the picture store, a video's or
  /// a sound's in the media store.
  final String id;
  final AssetKind kind;
  final String name;
  final DateTime added;

  /// width and height are a picture's or a video's, when known; length a
  /// video's or a sound's, in seconds.
  final int width;
  final int height;
  final double length;

  /// poster, sound and fps are what a video brought with it -- see
  /// MediaSource.
  final String poster;
  final String sound;
  final double fps;

  /// author, license, origin and from are the credit an asset from a stock
  /// library keeps: who made it, under what licence, its page, and which
  /// library. Empty for anything added from a file.
  final String author;
  final String license;
  final String origin;
  final String from;

  const LibraryAsset({
    required this.id,
    required this.kind,
    required this.name,
    required this.added,
    this.width = 0,
    this.height = 0,
    this.length = 0,
    this.poster = "",
    this.sound = "",
    this.fps = 0,
    this.author = "",
    this.license = "",
    this.origin = "",
    this.from = "",
  });

  /// credited is whether there is anybody to credit.
  bool get credited => author.isNotEmpty || license.isNotEmpty;

  /// credit is the line somebody using it would print.
  String get credit => [
        author.isEmpty ? name : "$name by $author",
        if (from.isNotEmpty) "from $from",
        if (license.isNotEmpty) "($license)",
      ].join(" ");

  /// files is every stored file this asset is: itself, and a video's poster
  /// and sound.
  Set<String> get files => {
        id,
        if (poster.isNotEmpty) poster,
        if (sound.isNotEmpty) sound,
      };

  /// source is the asset as a clip's playlist entry, for a video or a sound.
  MediaSource get source => MediaSource(
        assetId: id,
        name: name,
        length: length,
        posterId: poster,
        soundId: sound,
        width: width,
        height: height,
        fps: fps,
      );

  LibraryAsset copyWith(
          {String? name,
          String? author,
          String? license,
          String? origin,
          String? from}) =>
      LibraryAsset(
        id: id,
        kind: kind,
        name: name ?? this.name,
        added: added,
        width: width,
        height: height,
        length: length,
        poster: poster,
        sound: sound,
        fps: fps,
        author: author ?? this.author,
        license: license ?? this.license,
        origin: origin ?? this.origin,
        from: from ?? this.from,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind.name,
        "name": name,
        "added": added.toUtc().toIso8601String(),
        if (width > 0) "w": width,
        if (height > 0) "h": height,
        if (length > 0) "length": length,
        if (poster.isNotEmpty) "poster": poster,
        if (sound.isNotEmpty) "sound": sound,
        if (fps > 0) "fps": fps,
        if (author.isNotEmpty) "author": author,
        if (license.isNotEmpty) "license": license,
        if (origin.isNotEmpty) "origin": origin,
        if (from.isNotEmpty) "from": from,
      };

  static LibraryAsset? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = json["id"];
    if (id is! String || id.isEmpty) return null;
    num n(String key) => json[key] is num ? json[key] as num : 0;
    String text(String key) => json[key] is String ? json[key] as String : "";
    return LibraryAsset(
      id: id,
      // A drawing listed as a picture before the two were separated is a
      // drawing.
      kind: path.extension(id) == ".svg"
          ? AssetKind.vector
          : AssetKind.fromName(json["kind"] as String?),
      name: json["name"] is String ? json["name"] as String : id,
      added: DateTime.tryParse(json["added"] as String? ?? "") ??
          DateTime.fromMillisecondsSinceEpoch(0),
      width: n("w").toInt(),
      height: n("h").toInt(),
      length: n("length").toDouble(),
      poster: json["poster"] is String ? json["poster"] as String : "",
      sound: json["sound"] is String ? json["sound"] as String : "",
      fps: n("fps").toDouble(),
      author: text("author"),
      license: text("license"),
      origin: text("origin"),
      from: text("from"),
    );
  }

  /// fromSource is a video or a sound as an asset, from what was learned about
  /// it when it was added.
  static LibraryAsset fromSource(AssetKind kind, MediaSource s,
          {DateTime? added}) =>
      LibraryAsset(
        id: s.assetId,
        kind: kind,
        name: s.name.isEmpty ? s.assetId : s.name,
        added: added ?? DateTime.now(),
        width: s.width,
        height: s.height,
        length: s.length,
        poster: s.posterId,
        sound: s.soundId,
        fps: s.fps,
      );
}

/// CanvasLibrary is the list of assets, kept beside the canvases.
class CanvasLibrary {
  CanvasLibrary._();

  static const String _file = "assets.json";

  /// changes counts every change to the library, for the sidebar to follow.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// _pending chains every read-modify-write, so two assets added at once do
  /// not each write a list without the other.
  static Future<void> _pending = Future.value();

  static Future<T> _serial<T>(Future<T> Function() work) {
    var done = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        done.complete(await work());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static Future<File> _path() async =>
      File(path.join(await CanvasStorage.libraryDir(), _file));

  /// list is every asset, most recently added first -- or those of [kind].
  static Future<List<LibraryAsset>> list({AssetKind? kind}) async {
    var all = await _serial(_read);
    return [
      for (var a in all)
        if (kind == null || a.kind == kind) a,
    ];
  }

  /// _movedVectors is whether this session has moved the drawings out of the
  /// pictures yet -- once, before the library is first read.
  static bool _movedVectors = false;

  static Future<List<LibraryAsset>> _read() async {
    if (!_movedVectors) {
      _movedVectors = true;
      await CanvasMedia.migrateVectors();
    }
    var file = await _path();
    if (!await file.exists()) {
      // The first time: whatever is already stored joins the library, named
      // after what the canvases that use it call it.
      var found = await _discover();
      await _write(found);
      return found;
    }
    try {
      var raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      var out = [
        for (var entry in raw)
          if (LibraryAsset.fromJson(entry) case var a?) a,
      ]..sort((a, b) => b.added.compareTo(a.added));
      return out;
    } catch (exception) {
      debugPrint("Unable to read the canvas library: $exception");
      return const [];
    }
  }

  static Future<void> _write(List<LibraryAsset> assets) async {
    var file = await _path();
    var tmp = File("${file.path}.tmp");
    await tmp.writeAsString(jsonEncode([for (var a in assets) a.toJson()]));
    await tmp.rename(file.path);
  }

  /// add puts [asset] in the library, or renames it where it is there already.
  static Future<void> add(LibraryAsset asset) async {
    await _serial(() async {
      var all = [...await _read()];
      var at = all.indexWhere((a) => a.id == asset.id);
      if (at >= 0) {
        // The same file added again from disk keeps the credit it came with.
        var had = all[at];
        all[at] = asset.credited
            ? asset
            : asset.copyWith(
                author: had.author,
                license: had.license,
                origin: had.origin,
                from: had.from);
      } else {
        all.insert(0, asset);
      }
      await _write(all);
    });
    changes.value++;
  }

  /// addPicture puts the stored picture [id] in the library as [name], with
  /// its size read from [bytes] -- which is what lets one dragged onto the
  /// canvas arrive the shape it is. A drawing has no pixels to count.
  static Future<void> addPicture(
      String id, String name, List<int> bytes) async {
    var width = 0, height = 0;
    try {
      var codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      var frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      // An SVG, or something the codec will not read: no size, which is fine.
    }
    await add(LibraryAsset(
        id: id,
        kind: AssetKind.picture,
        name: name,
        added: DateTime.now(),
        width: width,
        height: height));
  }

  /// addVector puts a drawing in the library, under the Vectors.
  static Future<void> addVector(String id, String name) => add(LibraryAsset(
      id: id, kind: AssetKind.vector, name: name, added: DateTime.now()));

  /// named is what the library calls [id], or null where it is not an asset.
  static Future<String?> named(String id) async {
    for (var a in await list()) {
      if (a.id == id) return a.name;
    }
    return null;
  }

  /// rename gives the asset [id] a new name.
  static Future<void> rename(String id, String name) async {
    await _serial(() async {
      var all = [...await _read()];
      var at = all.indexWhere((a) => a.id == id);
      if (at < 0) return;
      all[at] = all[at].copyWith(name: name);
      await _write(all);
    });
    changes.value++;
  }

  /// credit records where the asset [id] came from.
  static Future<void> credit(String id,
      {required String author,
      required String license,
      required String origin,
      required String from}) async {
    await _serial(() async {
      var all = [...await _read()];
      var at = all.indexWhere((a) => a.id == id);
      if (at < 0) return;
      all[at] = all[at].copyWith(
          author: author, license: license, origin: origin, from: from);
      await _write(all);
    });
    changes.value++;
  }

  /// remove takes the asset [id] out of the library, and deletes its files
  /// where no other asset shares them. Anything still using it is left
  /// pointing at nothing, which is what the sidebar warns about first -- see
  /// usedBy.
  static Future<void> remove(String id) async {
    await _serial(() async {
      var all = [...await _read()];
      var gone = all.where((a) => a.id == id).toList();
      if (gone.isEmpty) return;
      all.removeWhere((a) => a.id == id);
      await _write(all);
      var kept = {for (var a in all) ...a.files};
      for (var asset in gone) {
        for (var file in asset.files) {
          if (kept.contains(file)) continue;
          await _delete(file, asset);
        }
      }
    });
    changes.value++;
  }

  static Future<void> _delete(String file, LibraryAsset owner) async {
    // A video's poster is a picture, and its sound is audio, whatever the
    // asset itself is.
    String? where;
    if (file == owner.poster ||
        (owner.kind == AssetKind.picture && file == owner.id)) {
      where = await CanvasAssets.pathOf(file);
    } else if (owner.kind == AssetKind.vector && file == owner.id) {
      where = await CanvasMedia.existingPath(MediaKind.vector, file);
    } else {
      where = await CanvasMedia.existingPath(CanvasMedia.kindOf(file), file);
    }
    if (where == null) return;
    try {
      await File(where).delete();
    } catch (_) {}
  }

  /// usedBy is the canvases that use the asset [id], by name.
  static Future<List<String>> usedBy(String id) async {
    var out = <String>[];
    await for (var (folder, name, document) in _documents()) {
      if (document.assetIds.contains(id) || document.mediaIds.contains(id)) {
        out.add(folder.isEmpty ? name : "$folder/$name");
      }
    }
    return out;
  }

  /// tidy deletes stored files that are neither an asset -- nor a video's
  /// poster or sound -- nor used by any saved canvas, nor by [open], the canvas
  /// in the editor, which may not have been saved.
  static Future<int> tidy({Set<String> open = const {}}) async {
    try {
      var assets = await list();
      var keep = <String>{
        for (var a in assets) ...a.files,
        ...open,
        ...await CanvasStorage.liveAssetIds(),
        ...await CanvasStorage.liveMediaIds(),
      };
      return await CanvasAssets.sweep(keep) +
          await CanvasMedia.sweep(MediaKind.audio, keep) +
          await CanvasMedia.sweep(MediaKind.video, keep) +
          await CanvasMedia.sweep(MediaKind.vector, keep);
    } catch (_) {
      return 0;
    }
  }

  /// _documents is every saved canvas, with the folder and name it is under.
  static Stream<(String, String, CanvasDocument)> _documents() async* {
    var folders = <String>[""];
    for (var entry in await CanvasStorage.list("")) {
      if (entry.isFolder) folders.add(entry.name);
    }
    for (var folder in folders) {
      for (var entry in await CanvasStorage.list(folder)) {
        if (entry.isFolder) continue;
        var document = await CanvasStorage.load(folder, entry.name);
        if (document != null) yield (folder, entry.name, document);
      }
    }
  }

  /// _discover is what is already stored, as assets: every picture, video and
  /// sound, less the posters and soundtracks that came with videos, named as
  /// the canvases that use them name them.
  static Future<List<LibraryAsset>> _discover() async {
    var names = <String, String>{};
    var sources = <String, MediaSource>{};
    var extras = <String>{};
    await for (var (_, _, document) in _documents()) {
      for (var scene in [
        ...document.allScenes,
        if (document.master != null) document.master!,
      ]) {
        var elements = [
          ...scene.elements,
          ...?scene.background?.media,
          if (scene.background?.picture case var p?) p,
        ];
        for (var e in elements) {
          switch (e) {
            case VideoElement v:
              for (var s in v.clip.playlist) {
                sources.putIfAbsent(s.assetId, () => s);
                if (s.posterId.isNotEmpty) extras.add(s.posterId);
                if (s.soundId.isNotEmpty) extras.add(s.soundId);
              }
            case AudioElement a:
              for (var s in a.clip.playlist) {
                sources.putIfAbsent(s.assetId, () => s);
              }
            case ImageElement i when i.assetId.isNotEmpty:
              names.putIfAbsent(i.assetId, () => i.name);
            default:
              break;
          }
        }
      }
    }

    var out = <LibraryAsset>[];
    Future<DateTime> when(String? where) async {
      if (where == null) return DateTime.now();
      try {
        return (await File(where).stat()).modified;
      } catch (_) {
        return DateTime.now();
      }
    }

    var pictures = 0;
    for (var id in await CanvasAssets.stored()) {
      if (extras.contains(id) || path.extension(id) == ".svg") continue;
      var name = names[id];
      out.add(LibraryAsset(
        id: id,
        kind: AssetKind.picture,
        name: name == null || name.isEmpty ? "Picture ${++pictures}" : name,
        added: await when(await CanvasAssets.pathOf(id)),
      ));
    }
    for (var kind in MediaKind.values) {
      for (var id in await CanvasMedia.stored(kind)) {
        if (extras.contains(id)) continue;
        var source = sources[id] ?? MediaSource(assetId: id);
        out.add(LibraryAsset.fromSource(
            switch (kind) {
              MediaKind.video => AssetKind.video,
              MediaKind.audio => AssetKind.audio,
              MediaKind.vector => AssetKind.vector,
            },
            source,
            added: await when(await CanvasMedia.existingPath(kind, id))));
      }
    }
    out.sort((a, b) => b.added.compareTo(a.added));
    return out;
  }

  /// resetForTest forgets the pending chain, so one test's failure cannot
  /// hold the next one up.
  @visibleForTesting
  static void resetForTest() => _pending = Future.value();
}
