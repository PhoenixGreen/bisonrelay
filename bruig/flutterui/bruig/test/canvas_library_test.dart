import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'canvas_store_age.dart';
import 'package:path/path.dart' as path;

// canvas_library_test.dart is the Assets sidebar's library against real files:
// what is already stored joins it the first time, less a video's poster and
// soundtrack; an asset stays whether or not anything uses it, until it is
// removed; and the tidy-up still clears what was never an asset.

List<int> png(int seed) => [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      seed, seed + 1, seed + 2, 0, 0, 0,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_library");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  // Named by their digests, as the store requires.
  String idOf(List<int> bytes, String ext) =>
      "${sha256.convert(bytes).toString().substring(0, 16)}$ext";
  final song = idOf([1, 2, 3], ".mp3");
  final film = idOf([7, 8, 9], ".mp4");
  final filmSound = idOf([4, 5, 6], ".flac");

  Future<(String, String)> storeSome() async {
    var badge = (await CanvasAssets.save(png(1)))!;
    var poster = (await CanvasAssets.save(png(7)))!;
    await CanvasMedia.saveBytes(MediaKind.audio, song, [1, 2, 3]);
    await CanvasMedia.saveBytes(MediaKind.audio, filmSound, [4, 5, 6]);
    await CanvasMedia.saveBytes(MediaKind.video, film, [7, 8, 9]);
    await CanvasStorage.save(
        "",
        "Match day",
        CanvasDocument(elements: [
          ImageElement(const ElementBase(id: "i", name: "Club badge"),
              assetId: badge),
          VideoElement(const ElementBase(id: "v"),
              clip: MediaClip(playlist: [
                MediaSource(
                    assetId: film,
                    name: "Goal",
                    length: 4,
                    posterId: poster,
                    soundId: filmSound),
              ])),
        ]));
    return (badge, poster);
  }

  test("what is stored joins the library the first time, named", () async {
    var (badge, poster) = await storeSome();
    var all = await CanvasLibrary.list();
    expect({
      for (var a in all) a.id: a.name
    }, {
      badge: "Club badge",
      song: song,
      film: "Goal",
    }, reason: "the poster and the film's sound came with the film");
    var goal = all.firstWhere((a) => a.id == film);
    expect(goal.kind, AssetKind.video);
    expect(goal.poster, poster);
    expect(goal.sound, filmSound);
    expect(await CanvasLibrary.list(kind: AssetKind.audio), hasLength(1));
  });

  test("an asset nothing uses stays; a stray file does not", () async {
    await storeSome();
    await CanvasLibrary.list();
    // A picture stored and never added as an asset -- a crest a table has
    // since dropped -- and nothing using the song or the badge.
    var stray = (await CanvasAssets.save(png(40)))!;
    await CanvasStorage.save("", "Match day", const CanvasDocument());
    await ageStores();
    await CanvasLibrary.tidy();
    expect(await CanvasAssets.exists(stray), isFalse);
    expect(await CanvasMedia.existingPath(MediaKind.audio, song), isNotNull);
    expect(await CanvasMedia.existingPath(MediaKind.video, film), isNotNull);
    expect(
        await CanvasMedia.existingPath(MediaKind.audio, filmSound), isNotNull,
        reason: "a video's sound stays with the video");
  });

  test("removing an asset says who used it, and takes its files", () async {
    var (_, poster) = await storeSome();
    expect(await CanvasLibrary.usedBy(film), ["Match day"]);
    expect(await CanvasLibrary.usedBy(song), isEmpty);

    await CanvasLibrary.remove(film);
    expect(
        (await CanvasLibrary.list()).map((a) => a.id), isNot(contains(film)));
    expect(await CanvasMedia.existingPath(MediaKind.video, film), isNull);
    expect(await CanvasMedia.existingPath(MediaKind.audio, filmSound), isNull);
    expect(await CanvasAssets.exists(poster), isFalse);
  });

  test("added and renamed, newest first", () async {
    await CanvasLibrary.add(LibraryAsset.fromSource(
        AssetKind.audio, MediaSource(assetId: song, name: "Anthem")));
    await CanvasLibrary.rename(song, "Club anthem");
    var all = await CanvasLibrary.list();
    expect(all.single.name, "Club anthem");
    var audio = AudioElement(const ElementBase(id: "a"),
        clip: MediaClip(playlist: [all.single.source]));
    expect(audio.clip.playlist.single.assetId, song);
  });

  test("a library index that cannot be read is kept, not written over",
      () async {
    await storeSome();
    await CanvasLibrary.list();
    var index =
        File(path.join(await CanvasStorage.libraryDir(), "assets.json"));
    await index.writeAsString("{ not json");
    CanvasLibrary.resetForTest();
    await CanvasLibrary.list();
    expect(await File("${index.path}.unreadable").readAsString(), "{ not json");
  });
}
