import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_interactive_channels_test.dart is a sound on the canvas that plays
// when pressed: on a channel of its own like every other sound, so it has a
// strip, a level and effects -- greyed on the timeline, where it has no time.

const song = "aaaaaaaaaaaaaaaa.mp3";

AudioElement speaker(String id, {bool timed = false, bool empty = false}) =>
    AudioElement(ElementBase(id: id, name: id, width: 80, height: 80),
        clip: MediaClip(
            playlist: empty ? const [] : [MediaSource(assetId: song, name: song, length: 30)],
            timed: timed));

void main() {
  late Directory root;
  late FakeEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_interactive");
    CanvasStorage.rootOverride = root.path;
    engine = FakeEngine({song: 30});
    var dir = Directory(path.join(root.path, "Canvas", canvasAudioFolder));
    await dir.create(recursive: true);
    await File(path.join(dir.path, song)).writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  CanvasController with_(CanvasDocument doc) {
    var c = CanvasController(doc, audioEngine: engine);
    addTearDown(c.dispose);
    return c;
  }

  test("a pressed sound has a channel, after those on the timeline", () {
    var c = with_(CanvasDocument(frames: 100, elements: [
      speaker("press"),
      speaker("music", timed: true),
      speaker("silent", empty: true),
    ]));
    expect(c.timedLanes.map((l) => l.element.id), ["music"]);
    expect(c.interactiveLanes.map((l) => l.element.id), ["press"],
        reason: "a speaker with no sound has nothing to mix");
    var channels = c.timelineChannels;
    expect(channels.map((ch) => ch.key), ["music", "press"]);
    expect(channels.last.interactive, isTrue);
    expect(channels.first.interactive, isFalse);
  });

  test("a pressed video has one too, and a link does not", () {
    var film = VideoElement(const ElementBase(id: "film", name: "Talk"),
        clip: const MediaClip(playlist: [
          MediaSource(assetId: "cccccccccccccccc.mp4", name: "talk", length: 10)
        ]));
    var link = const VideoElement(ElementBase(id: "link"),
        link: "https://example.com/watch");
    var c = with_(CanvasDocument(frames: 100, elements: [film, link]));
    expect(c.interactiveLanes.map((l) => l.element.id), ["film"]);
    var channel = c.timelineChannels.single;
    expect(channel.interactive && channel.video, isTrue);
    c.setChannelMix(channel, const ChannelMix(gainDb: -3));
    expect((c.document.elementById("film")! as VideoElement).clip.mix.gainDb,
        -3);
  });

  test("its strip is set like any other, and undone", () {
    var c = with_(CanvasDocument(frames: 100, elements: [speaker("press")]));
    var channel = c.timelineChannels.single;
    c.setChannelMix(channel, const ChannelMix(gainDb: -6, balance: 0.3));
    var e = c.document.elementById("press")! as AudioElement;
    expect(e.clip.mix.gainDb, -6);
    expect(e.clip.timed, isFalse, reason: "still played by pressing it");
    c.undo();
    expect((c.document.elementById("press")! as AudioElement).clip.mix.gainDb,
        0);
  });

  test("pressed, it plays through its strip; opening the canvas opens no device",
      () async {
    var c = with_(CanvasDocument(frames: 100, elements: [speaker("press")]));
    c.setChannelMix(c.timelineChannels.single, const ChannelMix(gainDb: -6));
    expect(engine.starts, 0, reason: "nothing pressed yet");
    c.pressAudio(c.document.elementById("press")! as AudioElement,
        AudioControl.playPause);
    await pumpEventQueue();
    expect(c.audio.isPlaying("press"), isTrue);
    expect(engine.channels.containsKey("press"), isTrue);
    expect(engine.onChannel[engine.last], "press");
    expect(engine.returns.map((r) => r.id), ["returnA", "returnB"],
        reason: "the document's returns, for its sends to feed");
  });

  testWidgets("its lane is greyed, says why, and picks the channel",
      (tester) async {
    var c = with_(CanvasDocument(frames: 100, elements: [speaker("press")]));
    tester.view.physicalSize = const Size(1000, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                      height: 120,
                      child: CanvasChannels(
                          controller: c,
                          view: TimelineView.whole(c.document.frames)))))),
    ));
    await tester.pumpAndSettle();
    var lane = find.byKey(const ValueKey("lane-press"));
    expect(lane, findsOneWidget);
    await tester.tap(lane);
    await tester.pumpAndSettle();
    expect(c.selectedChannel, "press");
    expect(c.clipSelection, isEmpty, reason: "nothing on it to pick");
    expect(tester.takeException(), isNull);
  });
}
