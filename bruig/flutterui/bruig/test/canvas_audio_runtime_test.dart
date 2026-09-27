import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_audio_runtime_test.dart is the rules about what plays, against an
// engine whose clock the test moves. See audio_runtime.dart.

AudioElement sound(String id, MediaClip clip) =>
    AudioElement(ElementBase(id: id), clip: clip);

MediaSource file(String id, {double start = 0, double end = 0}) =>
    MediaSource(assetId: id, start: start, end: end);

void main() {
  late FakeEngine engine;
  late AudioRuntime runtime;

  setUp(() {
    engine = FakeEngine({"a.mp3": 30, "b.mp3": 20, "c.mp3": 10});
    runtime = AudioRuntime(
        engine: engine,
        locate: (id) async => engine.lengths.containsKey(id) ? id : null);
  });
  tearDown(() => runtime.dispose());

  group("a range", () {
    test("starts where it is told and stops where it is told", () async {
      var e =
          sound("s", MediaClip(playlist: [file("a.mp3", start: 10, end: 25)]));
      await runtime.play(e);
      expect(engine.last.at, 10);
      expect(runtime.isPlaying("s"), isTrue);

      engine.last.at = 24.99;
      runtime.tick();
      expect(runtime.isPlaying("s"), isFalse,
          reason: "the end of the range is the end, not the end of the file");
      expect(engine.last.alive, isFalse);
    });

    test("with no end, plays to the end of the file", () async {
      var e = sound("s", MediaClip(playlist: [file("a.mp3", start: 5)]));
      await runtime.play(e);
      engine.last.at = 20;
      runtime.tick();
      expect(runtime.isPlaying("s"), isTrue);
      engine.last.alive = false; // the file ran out
      runtime.tick();
      expect(runtime.isPlaying("s"), isFalse);
    });
  });

  group("fades", () {
    test("in from silence, to the volume it should be at", () async {
      var e = sound(
          "s", MediaClip(playlist: [file("a.mp3")], volume: 0.6, fadeIn: 2));
      await runtime.play(e);
      expect(engine.last.fades.first, (0.6, 2.0));
    });

    test("out, once, timed to finish on the end of the range", () async {
      var e =
          sound("s", MediaClip(playlist: [file("a.mp3", end: 20)], fadeOut: 3));
      await runtime.play(e);
      engine.last.at = 16.5;
      runtime.tick();
      expect(engine.last.fades, isEmpty, reason: "not yet");
      engine.last.at = 17.5;
      runtime.tick();
      runtime.tick();
      expect(engine.last.fades, hasLength(1),
          reason: "begun once, not per tick");
      expect(engine.last.fades.single.$1, 0);
      expect(engine.last.fades.single.$2, closeTo(2.5, 1e-9));
    });

    test("moving the volume mid-fade does not snap it back up", () async {
      var e =
          sound("s", MediaClip(playlist: [file("a.mp3", end: 20)], fadeOut: 3));
      await runtime.play(e);
      engine.last.at = 18;
      runtime.tick();
      runtime.setVolume(e, 1);
      expect(engine.last.volume, 0);
    });
  });

  group("a playlist", () {
    var list = [file("a.mp3"), file("b.mp3"), file("c.mp3")];

    test("plays in order and stops after the last", () async {
      var e = sound("s", MediaClip(playlist: list));
      await runtime.play(e);
      for (var expected in ["b.mp3", "c.mp3"]) {
        engine.last.alive = false;
        runtime.tick();
        await pumpEventQueue();
        expect(engine.last.track.path, expected);
      }
      engine.last.alive = false;
      runtime.tick();
      await pumpEventQueue();
      expect(runtime.isPlaying("s"), isFalse);
      expect(engine.voices, hasLength(3));
    });

    test("repeat the list goes back to the first", () async {
      var e = sound("s", MediaClip(playlist: list, loop: MediaLoop.all));
      await runtime.play(e);
      for (var i = 0; i < 3; i++) {
        engine.last.alive = false;
        runtime.tick();
        await pumpEventQueue();
      }
      expect(engine.last.track.path, "a.mp3");
      expect(runtime.isPlaying("s"), isTrue);
    });

    test("repeat each plays the same one again, from its range", () async {
      var e = sound("s",
          MediaClip(playlist: [file("b.mp3", start: 4)], loop: MediaLoop.one));
      await runtime.play(e);
      engine.last.alive = false;
      runtime.tick();
      await pumpEventQueue();
      expect(engine.voices, hasLength(2));
      expect(engine.last.track.path, "b.mp3");
      expect(engine.last.at, 4);
    });

    test("a missing file is skipped, not the end of the list", () async {
      var e =
          sound("s", MediaClip(playlist: [file("gone.mp3"), file("c.mp3")]));
      await runtime.play(e);
      expect(engine.last.track.path, "c.mp3");
      expect(runtime.isPlaying("s"), isTrue);
    });
  });

  group("the reader's controls", () {
    test("pause holds the place and play carries on from it", () async {
      var e = sound("s", MediaClip(playlist: [file("a.mp3")]));
      await runtime.play(e);
      engine.last.at = 7;
      runtime.pause("s");
      expect(engine.last.paused, isTrue);
      await runtime.play(e);
      expect(engine.voices, hasLength(1), reason: "the same voice, resumed");
      expect(engine.last.paused, isFalse);
    });

    test("mute silences without forgetting the volume", () async {
      var e = sound("s", MediaClip(playlist: [file("a.mp3")], volume: 0.5));
      await runtime.play(e);
      runtime.setMuted(e, true);
      expect(engine.last.volume, 0);
      expect(runtime.view(e).volume, 0.5);
      runtime.setMuted(e, false);
      expect(engine.last.volume, 0.5);
    });

    test("stopped before the file opens, nothing starts", () async {
      var e = sound("s", MediaClip(playlist: [file("a.mp3")]));
      var starting = runtime.play(e);
      runtime.stop("s");
      await starting;
      expect(engine.voices, isEmpty);
      expect(runtime.isPlaying("s"), isFalse);
    });

    test("no sound device says so rather than failing silently", () async {
      engine.works = false;
      var e = sound("s", MediaClip(playlist: [file("a.mp3")]));
      await runtime.play(e);
      expect(runtime.unavailable, isTrue);
      expect(runtime.isPlaying("s"), isFalse);
    });
  });

  group("turning the page", () {
    test("keeps what may carry on and forgets the rest", () async {
      var page = sound("page", MediaClip(playlist: [file("a.mp3")]));
      var master = sound("master", MediaClip(playlist: [file("b.mp3")]));
      await runtime.play(page);
      await runtime.play(master);
      runtime.setMuted(page, true);

      runtime.keepOnly((id) => id == "master");
      expect(runtime.isPlaying("master"), isTrue);
      expect(runtime.isPlaying("page"), isFalse);
      expect(runtime.view(page).muted, isFalse,
          reason: "coming back finds it as the author left it");
    });

    test("autoplay starts what asks to, once", () async {
      var auto =
          sound("a", MediaClip(playlist: [file("a.mp3")], autoplay: true));
      var pressed = sound("p", MediaClip(playlist: [file("b.mp3")]));
      runtime.autoplay([auto, pressed]);
      await pumpEventQueue();
      runtime.autoplay([auto, pressed]);
      await pumpEventQueue();
      expect(runtime.playingIds, {"a"});
      expect(engine.voices, hasLength(1));
    });
  });

  test("a clip reads back what it wrote", () {
    var clip = MediaClip(
      playlist: [
        const MediaSource(
            assetId: "0123456789abcdef.mp3",
            name: "Intro",
            start: 1.5,
            end: 9,
            length: 30),
      ],
      volume: 0.4,
      muted: true,
      fadeIn: 1,
      fadeOut: 2,
      loop: MediaLoop.all,
      autoplay: true,
      acrossPages: false,
    );
    var back = MediaClip.fromJson(clip.toJson());
    expect(back.playlist.single.name, "Intro");
    expect(back.playlist.single.start, 1.5);
    expect(back.playlist.single.end, 9);
    expect(back.volume, 0.4);
    expect(back.muted, isTrue);
    expect(back.fadeOut, 2);
    expect(back.loop, MediaLoop.all);
    expect(back.autoplay, isTrue);
    expect(back.acrossPages, isFalse);
    expect(const MediaClip().toJson(), isEmpty,
        reason: "a clip nobody has touched writes nothing");
  });
}
