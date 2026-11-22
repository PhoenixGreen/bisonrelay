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
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_library.dart is the Assets sidebar: the pictures, videos and sounds
// somebody has added, to see, use again and clear out. The files stay
// content-addressed in the Pictures, Videos and Audio folders; this lists
// which are assets, with their names and a video's poster and soundtrack.
// An asset stays until removed from the sidebar, used or not; the tidy-up
// is for what is not an asset, such as a poster whose video has gone.

enum AssetKind {
  picture("Pictures"),
  video("Videos"),
  audio("Audio"),

  /// vector is .svg drawings, in their own store, placed as a VectorElement.
  vector("Vectors"),

  /// model is .glb 3D objects, in the model store, placed as an
  /// Object3dElement.
  model("3D objects");

  final String label;
  const AssetKind(this.label);

  static AssetKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => picture);
}

/// AssetView is how the Assets sidebar shows one kind's assets: as icons, or
/// as a list. Chosen per kind, and kept in CanvasPreferences.
enum AssetView {
  icons,
  list;

  /// AssetView.defaultFor is [kind]'s view until another is chosen. Sounds
  /// start as a list: they have no picture to make an icon of, so as icons
  /// they would all look alike.
  static AssetView defaultFor(AssetKind kind) =>
      kind == AssetKind.audio ? list : icons;
}

class LibraryAsset {
  /// id is the stored file's: a picture's in the picture store, a video's or
  /// a sound's in the media store.
  final String id;
  final AssetKind kind;
  final String name;
  final DateTime added;

  /// width and height are a picture's or video's, when known; length a
  /// video's or sound's, in seconds.
  final int width;
  final int height;
  final double length;

  /// poster, sound and fps are what a video brought with it (MediaSource).
  final String poster;
  final String sound;
  final double fps;

  /// author, license, origin and from credit an asset from a stock library:
  /// who made it, the licence, its page, and which library. Empty for
  /// anything added from a file.
  final String author;
  final String license;
  final String origin;
  final String from;

  /// animations are a 3D object's own, from its file (glbAnimations).
  final List<ModelAnimation> animations;

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
    this.animations = const [],
  });

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
        animations: animations,
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
        if (animations.isNotEmpty)
          "anims": [
            for (var (name, length) in animations) [name, length]
          ],
      };

  static LibraryAsset? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = json["id"];
    if (id is! String || id.isEmpty) return null;
    num n(String key) => json[key] is num ? json[key] as num : 0;
    String text(String key) => json[key] is String ? json[key] as String : "";
    return LibraryAsset(
      id: id,
      kind: AssetKind.fromName(jsonStr(json["kind"])),
      name: json["name"] is String ? json["name"] as String : id,
      added: DateTime.tryParse(jsonStr(json["added"]) ?? "") ??
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
      animations: [
        if (json["anims"] case List anims)
          for (var a in anims)
            if (a case [String name, num length]) (name, length.toDouble()),
      ],
    );
  }

  /// fromSource is a video or sound as an asset, from what was learned when
  /// it was added.
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

  static Future<List<LibraryAsset>> _read() async {
    var file = await _path();
    if (!await file.exists()) {
      // The first time, whatever is already stored joins the library, named as
      // the canvases using it name it.
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
      // Kept aside before anything writes over it, or the next add would save a
      // library of one.
      debugPrint("Unable to read the canvas library: $exception");
      try {
        await file.rename("${file.path}.unreadable");
      } catch (_) {}
      return const [];
    }
  }

  static Future<void> _write(List<LibraryAsset> assets) async {
    var file = await _path();
    await writeWholeText(
        file.path, jsonEncode([for (var a in assets) a.toJson()]));
  }

  /// add puts [asset] in the library, or renames it if already there.
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

  /// addPicture puts the stored picture [id] in the library as [name], sized
  /// from [bytes] so one dragged onto the canvas arrives its own shape. A
  /// drawing has no pixels to count.
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

  /// addModel puts a 3D object in the library, with its animations.
  static Future<void> addModel(
          String id, String name, List<ModelAnimation> animations,
          {String author = "",
          String license = "",
          String origin = "",
          String from = ""}) =>
      add(LibraryAsset(
          id: id,
          kind: AssetKind.model,
          name: name,
          added: DateTime.now(),
          animations: animations,
          author: author,
          license: license,
          origin: origin,
          from: from));

  static Future<void> addVector(String id, String name) => add(LibraryAsset(
      id: id, kind: AssetKind.vector, name: name, added: DateTime.now()));

  /// byId is the asset whose stored file is [id], of whatever kind, or null
  /// where that file is not an asset.
  static Future<LibraryAsset?> byId(String id) async {
    for (var a in await list()) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// named is what the library calls [id], or null where it is not an asset.
  static Future<String?> named(String id) async => (await byId(id))?.name;

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

  /// unlist takes the asset [id] off the list but keeps its files, for one
  /// replaced by another that a canvas, or its undo, may still use. A tidy
  /// deletes them once nothing does.
  static Future<void> unlist(String id) async {
    await _serial(() async {
      var all = [...await _read()];
      var before = all.length;
      all.removeWhere((a) => a.id == id);
      if (all.length != before) await _write(all);
    });
    changes.value++;
  }

  /// remove takes the asset [id] out, deleting its files where no other asset
  /// shares them. Anything still using it is left pointing at nothing, which
  /// the sidebar warns about first (see usedBy).
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
    // A video's poster is a picture and its sound is audio, whatever the asset
    // itself is.
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

  /// usedBy is the names of the canvases that use the asset [id].
  static Future<List<String>> usedBy(String id) async {
    var out = <String>[];
    await for (var (folder, name, document) in _documents()) {
      if (document.assetIds.contains(id) || document.mediaIds.contains(id)) {
        out.add(folder.isEmpty ? name : "$folder/$name");
      }
    }
    return out;
  }

  /// tidy deletes stored files that are not an asset, a video's poster or
  /// sound, or used by any saved canvas or by [open], the canvas in the
  /// editor, which may not be saved.
  static Future<int> tidy({Set<String> open = const {}}) {
    // One at a time: two at once would each walk the library. A failed one
    // does not stop the next: chained on its error, every later tidy would
    // fail with it.
    var run = (_tidying ?? Future.value(0))
        .then((_) => 0, onError: (_) => 0)
        .then((_) => _tidy(open))
        .whenComplete(() => _tidied = DateTime.now());
    _tidying = run;
    return run;
  }

  static Future<int>? _tidying;
  static DateTime? _tidied;

  /// tidyEvery is the least time between the tidies saves ask for.
  static const Duration tidyEvery = Duration(minutes: 5);

  /// tidySoon is a tidy after a save, unless one ran within [tidyEvery]: a
  /// tidy walks the whole library. What it would delete waits for a later
  /// save, as it waits for sweepGrace anyway. What [open] names is kept.
  static void tidySoon({Set<String> open = const {}}) {
    var last = _tidied;
    if (last != null && DateTime.now().difference(last) < tidyEvery) return;
    _tidied = DateTime.now();
    unawaited(tidy(open: open));
  }

  static Future<int> _tidy(Set<String> open) async {
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
          await CanvasMedia.sweep(MediaKind.vector, keep) +
          // 3D objects' models too: a canvas previewed in a chat stores its
          // own, which must go once it is gone.
          await CanvasMedia.sweep(MediaKind.model, keep) +
          await _sweepSpeechTakes(keep);
    } catch (_) {
      return 0;
    }
  }

  /// _sweepSpeechTakes deletes Speech device takes no canvas has (removed,
  /// replaced, or its canvas deleted); see CanvasStorage.speechTakesDir.
  static Future<int> _sweepSpeechTakes(Set<String> keep) async {
    var gone = 0;
    var dir = Directory(await CanvasStorage.speechTakesDir());
    await for (var f in dir.list()) {
      if (f is File && !keep.contains(path.basename(f.path))) {
        // Not one just made: a fresh take is in no saved canvas yet.
        if (DateTime.now().difference(await f.lastModified()) < sweepGrace) {
          continue;
        }
        await f.delete();
        gone++;
      }
    }
    return gone;
  }

  /// _documents is every saved canvas, with its folder and name.
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

  /// _discover is what is already stored, as assets: every picture, video
  /// and sound but videos' posters and soundtracks, named as the canvases
  /// using them name them.
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
      if (extras.contains(id) || isMaskId(id)) {
        continue;
      }
      var name = names[id];
      out.add(LibraryAsset(
        id: id,
        kind: AssetKind.picture,
        name: name == null || name.isEmpty ? "Picture ${++pictures}" : name,
        added: await when(await CanvasAssets.pathOf(id)),
      ));
    }
    // The models with them: 3D files imported for old characters are 3D
    // objects.
    for (var kind in [
      MediaKind.audio,
      MediaKind.video,
      MediaKind.vector,
      MediaKind.model
    ]) {
      for (var id in await CanvasMedia.stored(kind)) {
        if (extras.contains(id)) continue;
        var source = sources[id] ?? MediaSource(assetId: id);
        out.add(LibraryAsset.fromSource(
            switch (kind) {
              MediaKind.video => AssetKind.video,
              MediaKind.audio => AssetKind.audio,
              MediaKind.vector => AssetKind.vector,
              MediaKind.model => AssetKind.model,
            },
            source,
            added: await when(await CanvasMedia.existingPath(kind, id))));
      }
    }
    out.sort((a, b) => b.added.compareTo(a.added));
    return out;
  }

  /// resetForTest forgets the pending chain and tidy, so one test's failure,
  /// or a tidy a widget test never let finish, cannot hold up the next.
  @visibleForTesting
  static void resetForTest() {
    _pending = Future.value();
    _tidying = null;
    _tidied = null;
  }
}
