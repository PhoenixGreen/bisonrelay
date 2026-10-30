import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_core.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_session_test.dart is the session view: clips in slots, launched on
// the next bar, scenes, stopping, the launch modes, recording into a slot,
// and what the slots played written onto the timeline. See session.dart.

/// wav is a short silent WAV file's bytes: enough for the media store to
/// take it for a sound.
Uint8List wav(int frames) {
  var data = frames * 4;
  var b = ByteData(44 + data);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, "RIFF");
  b.setUint32(4, 36 + data, Endian.little);
  str(8, "WAVE");
  str(12, "fmt ");
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 2, Endian.little);
  b.setUint32(24, 48000, Endian.little);
  b.setUint32(28, 48000 * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, "data");
  b.setUint32(40, data, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group("the grid", () {
    test("a clip and the scenes are saved and read back", () {
      const clip = SessionClip(
        id: "c1",
        name: "Beat",
        color: 3,
        sound: MediaSource(assetId: "beat.wav", length: 4),
        bars: 2,
        loop: false,
        launch: LaunchMode.gate,
      );
      var grid = const SessionGrid()
          .put("a", 2, clip)
          .put(
              "m",
              0,
              const SessionClip(
                  id: "c2", midi: true, notes: [MidiNote(60, 0, 1)]))
          .renameScene(1, "Verse");
      var doc = CanvasDocument(session: grid);
      var back = CanvasDocument.fromJson(doc.toJson()).session;
      expect(back.scenes[1], "Verse");
      expect(back.rows, defaultSceneCount);
      var c = back.at("a", 2)!;
      expect(c.name, "Beat");
      expect(c.bars, 2);
      expect(c.loop, isFalse);
      expect(c.launch, LaunchMode.gate);
      expect(c.sound!.assetId, "beat.wav");
      expect(back.at("a", 0), isNull);
      expect(back.at("m", 0)!.midi, isTrue);
      expect(back.at("m", 0)!.notes.single.key, 60);
      expect(const CanvasDocument().toJson().containsKey("session"), isFalse,
          reason: "an empty grid is not written");
    });

    test("scenes added and taken away move the clips with them", () {
      var grid = const SessionGrid()
          .put("a", 0, const SessionClip(id: "x"))
          .put("a", 1, const SessionClip(id: "y"));
      var more = grid.withScene(after: 0);
      expect(more.rows, defaultSceneCount + 1);
      expect(more.at("a", 0)!.id, "x");
      expect(more.at("a", 1), isNull);
      expect(more.at("a", 2)!.id, "y");
      var fewer = more.withoutScene(0);
      expect(fewer.at("a", 1)!.id, "y");
      expect(fewer.find("x"), isNull);
      // A clip put below the last row adds rows to hold it.
      expect(const SessionGrid().put("a", 10, const SessionClip(id: "z")).rows,
          11);
    });
  });

  group("the mix core", () {
    MemoryTrack ramp(int frames) => MemoryTrack(
        Float32List.fromList([for (var i = 0; i < frames; i++) (i + 1) / 1e4]),
        Float32List.fromList([for (var i = 0; i < frames; i++) (i + 1) / 1e4]));

    Float32List render(MixCore core, int n) {
      var l = Float32List(n), r = Float32List(n);
      core.render(l, r, n);
      return l;
    }

    test("a launch waits to the frame, then goes round its loop", () {
      var core = MixCore();
      // 100 frames waited, then frames 0..49 round and round.
      core.play(ramp(1000),
          volume: 1, delay: 100 / mixRate, loop: (0, 50 / mixRate));
      var out = render(core, 256);
      expect(out.sublist(0, 100).every((v) => v == 0), isTrue,
          reason: "silent until it starts");
      expect(out[100], greaterThan(0));
      // Round: frame 150 is the file's frame 0 again, as 100 was.
      expect(out[150], closeTo(out[100], 1e-6));
      expect(out[149], greaterThan(out[148]));
    });

    test("a loop longer than its sound is silence to its end", () {
      var core = MixCore();
      core.play(ramp(30), volume: 1, loop: (0, 50 / mixRate));
      var out = render(core, 120);
      expect(out[29], greaterThan(0));
      expect(out.sublist(30, 50).every((v) => v == 0), isTrue);
      expect(out[50], greaterThan(0), reason: "and round again");
    });

    test("a stop set ends it to the frame, faded, not clicked", () {
      var core = MixCore();
      var v = core.play(ramp(48000), volume: 1);
      core.stopIn(v, 1000 / mixRate);
      var out = render(core, 2048);
      expect(out[700], greaterThan(0));
      // Faded over its last frames: quieter just before the end than the
      // ramp alone would be.
      expect(out[995], lessThan(0.0996 * 0.1));
      expect(out.sublist(1000).every((v) => v == 0), isTrue);
      expect(v.alive, isFalse);
    });
  });

  group("launching", () {
    late Directory root;
    late String id;
    late FakeEngine engine;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_session_test");
      CanvasStorage.rootOverride = root.path;
      var file = File(path.join(root.path, "loop.wav"));
      await file.writeAsBytes(wav(4800));
      id = (await CanvasMedia.saveFile(MediaKind.audio, file.path))!;
      engine = FakeEngine({id: 8, "loop.wav": 8});
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });

    AudioElement sound(String elementId, {String channel = ""}) =>
        AudioElement(ElementBase(id: elementId, name: elementId),
            clip: MediaClip(
                playlist: [MediaSource(assetId: id, name: "Loop", length: 8)],
                timed: true,
                channel: channel));

    /// make is a piece at 120 a minute in four: a bar is two seconds.
    CanvasController make(List<CanvasElement> elements) {
      var c = CanvasController(
          CanvasDocument(
              frames: 120 * 60,
              frameRate: 120,
              audio: const AudioSettings(tempo: 120),
              elements: elements),
          audioEngine: engine);
      return c;
    }

    /// at moves the play clock on to [seconds], a frame at a time, ticking
    /// as the timer does.
    int micros = 0;
    void at(CanvasController c, double seconds) {
      var to = (seconds * 1e6).round();
      while (micros < to) {
        var was = micros;
        micros = (micros + 8333).clamp(0, to);
        // The sound goes on as a sound card's would: the playhead keeps
        // with it, and a fake voice standing still held it back.
        // The timeline's sounds start at nought, so are where the clock
        // is; a clip goes on from where it was launched.
        for (var v in engine.voices) {
          if (!v.alive || v.paused) continue;
          var launched = engine.launches.any((l) => l.$1 == v);
          v.at = launched ? v.at + (micros - was) / 1e6 : micros / 1e6;
        }
        c.tickClockForTest();
      }
      c.tickClockForTest();
    }

    setUp(() => micros = 0);

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test("a clip from the channel's sound is as long as it is, in bars", () {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      expect(c.soundsOf("a").single.assetId, id);
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      var clip = c.session.at("a", 0)!;
      expect(clip.bars, 4, reason: "eight seconds is four bars of two");
      expect(clip.name, "Loop");
      c.undo();
      expect(c.session.at("a", 0), isNull, reason: "one undoable change");
    });

    test("with nothing playing, a launch starts the transport, at once",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.frame = 300; // two and a half seconds in: bar two
      c.pressClip("a", 0);
      expect(c.playing, isTrue);
      // Only the slots: on their own clock, the playhead left where it was
      // and the timeline not playing -- see sessionOnly.
      expect(c.sessionOnly, isTrue);
      expect(c.frame, 300, reason: "the timeline does not move");
      expect(c.clipState("a", 0), ClipState.queued);
      await settle();
      var (voice, delay, loop) = engine.launches.single;
      expect(delay, closeTo(0, 0.01));
      expect(loop, (0.0, 8.0));
      expect(engine.onChannel[voice], "a");
      c.tickClockForTest();
      expect(c.clipState("a", 0), ClipState.playing);
      c.pause();
    });

    // Ken: a clip's envelope of a channel's setting, with its own length.
    test("a clip's envelope moves its channel while it plays, then lets go",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      // The volume: low, then up over a beat -- two beats of its own,
      // round and round.
      c.setSessionClip(
          "a",
          0,
          c.session.at("a", 0)!.withCurve(
              "volume", const [(0, 0.2), (1, 0.9)]).withLength("volume", 2));
      var back = SessionClip.fromJson(c.session.at("a", 0)!.toJson())!;
      expect(back.automation.single.length, 2);
      expect(back.curveOf("volume"), const [(0.0, 0.2), (1.0, 0.9)]);
      c.pressClip("a", 0);
      await settle();
      c.tickClockForTest();
      var ch = c.timelineChannels.single;
      double heard() => c.mixNow(ch).gainDb;
      // At 120 a beat is half a second: a quarter second in is half a beat
      // up the slope; three-quarters in, past its top; and a second and a
      // quarter, round again to where a quarter second was.
      at(c, 0.25);
      var half = AutomationTarget.volume.valueAt(0.55);
      expect(heard(), closeTo(half, 1.5));
      expect(engine.channels["a"]!.mix!.gainDb, closeTo(half, 1.5),
          reason: "what the channel plays, not only what it shows");
      at(c, 0.75);
      expect(heard(), closeTo(AutomationTarget.volume.valueAt(0.9), 1.5));
      at(c, 1.25);
      expect(heard(), closeTo(half, 1.5), reason: "its own length, again");
      // Stopped, the channel is its own again.
      c.pause();
      c.tickClockForTest();
      expect(c.mixNow(ch).gainDb, 0);
    });

    test("playing, a launch waits for the next bar, and the last stops on it",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.clipFromSound("a", 1, c.soundsOf("a").single);
      c.pressClip("a", 0);
      await settle();
      at(c, 0.5);
      expect(c.clipState("a", 0), ClipState.playing);
      c.pressClip("a", 1);
      await settle();
      expect(c.clipState("a", 1), ClipState.queued);
      expect(c.clipState("a", 0), ClipState.playing);
      var (second, delay, _) = engine.launches.last;
      expect(delay, closeTo(1.5, 0.02), reason: "the next bar, at two");
      var first = engine.launches.first.$1;
      expect(engine.stopsIn.single.$1, first);
      expect(engine.stopsIn.single.$2, closeTo(1.5, 0.02),
          reason: "stopped on the same frame the next starts");
      expect(second, isNot(first));
      at(c, 2.01);
      expect(c.clipState("a", 1), ClipState.playing);
      expect(c.clipState("a", 0), ClipState.stopped);
      c.pause();
    });

    test("only the slots: the timeline silent and still, until Play", () async {
      var c = make([sound("t"), sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.frame = 100;
      c.pressClip("a", 0);
      await settle();
      at(c, 1.5);
      expect(c.clipState("a", 0), ClipState.playing);
      expect(c.frame, 100, reason: "the playhead stands still");
      expect(c.offTimeline, isTrue);
      // The timeline's own sounds are not playing.
      var timeline = engine.voices
          .where((v) => !engine.launches.any((l) => l.$1 == v))
          .where((v) => v.alive && !v.paused);
      expect(timeline, isEmpty, reason: "the timeline is silent");
      // Play is the timeline's: the slots stop, the piece plays.
      c.play();
      expect(c.sessionOnly, isFalse);
      expect(c.clipPlaying("a"), isFalse);
      expect(c.playing, isTrue);
      c.pause();
    });

    test("a channel left for its slots stays off the timeline until Back",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.play(); // the timeline playing
      at(c, 0.5);
      c.pressClip("a", 0); // on the next bar, at two
      await settle();
      at(c, 2.1);
      expect(c.clipState("a", 0), ClipState.playing);
      c.stopChannelClips("a"); // at four
      at(c, 4.1);
      expect(c.clipPlaying("a"), isFalse);
      // As Ableton's: its timeline stays silent, the button lit.
      expect(c.offTimeline, isTrue);
      var heard = engine.voices
          .where((v) => !engine.launches.any((l) => l.$1 == v))
          .where((v) => v.alive && !v.paused);
      expect(heard, isEmpty, reason: "not back on the timeline yet");
      c.backToTimeline();
      expect(c.offTimeline, isFalse);
      // Its file opened again.
      await settle();
      at(c, 4.3);
      await settle();
      heard = engine.voices
          .where((v) => !engine.launches.any((l) => l.$1 == v))
          .where((v) => v.alive && !v.paused);
      expect(heard, isNotEmpty, reason: "the timeline heard again");
      c.pause();
    });

    test("moved to another slot, or copied; only to a channel of its kind", () {
      var c = make([sound("a"), sound("b")]);
      addTearDown(c.dispose);
      c.clipFromSound("a", 0, c.soundsOf("a").first);
      var id = c.session.at("a", 0)!.id;
      c.moveClip("a", 0, "b", 2);
      expect(c.session.at("a", 0), isNull);
      expect(c.session.at("b", 2)!.id, id);
      expect(c.selectedSlot, ("b", 2));
      c.undo();
      expect(c.session.at("a", 0)!.id, id, reason: "one change to undo");
      c.moveClip("a", 0, "a", 3, copy: true);
      expect(c.session.at("a", 0)!.id, id);
      expect(c.session.at("a", 3)!.id, isNot(id), reason: "a copy");
      expect(c.canMoveClip(c.session.at("a", 0)!, "a"), isTrue);
    });

    test("the engine's latency is taken off the wait", () async {
      engine.latency = 0.08;
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.play();
      at(c, 1);
      c.pressClip("a", 0);
      await settle();
      expect(engine.launches.single.$2, closeTo(1 - 0.08, 0.02));
      c.pause();
    });

    test("a scene launches its row and stops the channels with nothing in it",
        () async {
      var c = make([sound("a"), sound("b")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.clipFromSound("b", 0, c.soundsOf("b").single);
      c.clipFromSound("a", 1, c.soundsOf("a").single);
      c.launchScene(0);
      await settle();
      expect(engine.launches, hasLength(2));
      at(c, 0.3);
      expect(c.clipState("a", 0), ClipState.playing);
      expect(c.clipState("b", 0), ClipState.playing);
      expect(c.sceneLaunched, 0);
      c.launchScene(1);
      await settle();
      expect(c.clipState("a", 1), ClipState.queued);
      expect(c.clipState("b", 0), ClipState.stopping,
          reason: "nothing in its row: it stops on the bar");
      at(c, 2.05);
      expect(c.clipState("a", 1), ClipState.playing);
      expect(c.clipState("b", 0), ClipState.stopped);
      expect(c.clipPlaying("b"), isFalse);
      c.stopAllClips();
      at(c, 4.05);
      expect(c.anyClipPlaying, isFalse);
      c.pause();
    });

    test("toggle stops pressed again; gate only plays while held", () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.setSessionClip(
          "a", 0, c.session.at("a", 0)!.copyWith(launch: LaunchMode.toggle));
      c.pressClip("a", 0);
      await settle();
      at(c, 0.5);
      expect(c.clipState("a", 0), ClipState.playing);
      c.pressClip("a", 0);
      expect(c.clipState("a", 0), ClipState.stopping);
      at(c, 2.05);
      expect(c.clipState("a", 0), ClipState.stopped);

      c.setSessionClip(
          "a", 0, c.session.at("a", 0)!.copyWith(launch: LaunchMode.gate));
      c.pressClip("a", 0);
      await settle();
      at(c, 4.1);
      expect(c.clipState("a", 0), ClipState.playing);
      c.releaseClip("a", 0);
      expect(c.clipState("a", 0), ClipState.stopped,
          reason: "let go, it stops at once");
      expect(engine.softStops, isNotEmpty);
      c.pause();
    });

    // Ableton's Repeat: held, it plays again on every launch step.
    test("repeat plays again on every step while held, and stops let go",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.setSessionClip(
          "a",
          0,
          c.session
              .at("a", 0)!
              .copyWith(launch: LaunchMode.repeat, quantise: Quantise.quarter));
      expect(SessionClip.fromJson(c.session.at("a", 0)!.toJson())!.launch,
          LaunchMode.repeat);
      c.pressClip("a", 0);
      await settle();
      var first = engine.launches.length;
      // Two seconds held at 120: a quarter is half a second -- four more.
      for (var t = 0.25; t <= 2.0; t += 0.25) {
        at(c, t);
        await settle();
      }
      expect(engine.launches.length - first, inInclusiveRange(3, 4),
          reason: "launched again on each beat");
      c.releaseClip("a", 0);
      expect(c.clipState("a", 0), ClipState.stopped);
      var held = engine.launches.length;
      for (var t = 2.25; t <= 3.0; t += 0.25) {
        at(c, t);
        await settle();
      }
      expect(engine.launches.length, held, reason: "let go, no more");
      c.pause();
    });

    test("velocity: how much a pad's velocity sets the clip's volume",
        () async {
      var clip = SessionClip(
          id: "x", name: "x", sound: const MediaSource(assetId: "a"));
      expect(CanvasController.launchLevel(clip, 64), 1,
          reason: "none by default: as loud played softly");
      var full = clip.copyWith(velocity: 1);
      expect(CanvasController.launchLevel(full, 127), 1);
      expect(CanvasController.launchLevel(full, 64), closeTo(64 / 127, 1e-9));
      expect(
          CanvasController.launchLevel(clip.copyWith(velocity: 0.5), 0), 0.5);
      expect(SessionClip.fromJson(full.toJson())!.velocity, 1);

      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.setSessionClip("a", 0, c.session.at("a", 0)!.copyWith(velocity: 1));
      c.pressClip("a", 0, velocity: 32);
      await settle();
      at(c, 0.1);
      await settle();
      expect(engine.launches.last.$1.volume, closeTo(32 / 127, 1e-6),
          reason: "a soft pad, a quiet clip");
      c.pause();
    });

    // A Push in Session mode: its pads the slots.
    test("a Push's pad in Session mode launches its slot, at its velocity",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      expect(c.pushPad(0, 0), PadClip.stopped);
      expect(c.pushPad(0, 1), PadClip.empty);
      expect(c.pushPad(5, 0), PadClip.empty, reason: "no sixth channel");
      c.pushClip(0, 0, 100);
      await settle();
      at(c, 0.1);
      expect(c.pushPad(0, 0), PadClip.playing);
      c.pushClip(0, 0, 0);
      c.pause();
    });

    test("a clip played once ends after its length", () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.setSessionClip(
          "a", 0, c.session.at("a", 0)!.copyWith(loop: false, bars: 1));
      c.pressClip("a", 0);
      await settle();
      var (voice, _, loop) = engine.launches.single;
      expect(loop, isNull);
      expect(engine.stopsIn.single.$1, voice);
      expect(engine.stopsIn.single.$2, closeTo(2, 0.02));
      at(c, 2.05);
      expect(c.clipState("a", 0), ClipState.stopped);
      c.pause();
    });

    test("while a channel plays from its slots its timeline is quiet",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.play();
      at(c, 0.2);
      await settle();
      bool heard(FakeVoice v) => v.alive && !v.paused && v.volume > 0;
      var timeline = engine.voices
          .where((v) => !engine.launches.any((l) => l.$1 == v))
          .toList();
      expect(timeline.any(heard), isTrue, reason: "the timeline's sound plays");
      c.pressClip("a", 0);
      await settle();
      at(c, 2.05);
      await settle();
      expect(
          engine.voices
              .where((v) => !engine.launches.any((l) => l.$1 == v))
              .any(heard),
          isFalse,
          reason: "not under the clip");
      c.pause();
    });

    test("stopped, everything the slots play stops", () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.pressClip("a", 0);
      await settle();
      at(c, 0.5);
      c.pause();
      expect(c.anyClipPlaying, isFalse);
      expect(engine.launches.single.$1.alive, isFalse);
    });

    test("with Record on, what the slots played is written on the timeline",
        () async {
      var c = make([sound("a")]);
      addTearDown(c.dispose);
      c.clockForTest = () => micros;
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.setSessionClip("a", 0, c.session.at("a", 0)!.copyWith(bars: 1));
      c.recording = true;
      at(c, 0.5);
      c.pressClip("a", 0); // from bar two, at 2s
      await settle();
      at(c, 4.05);
      c.stopChannelClips("a"); // to the next bar, at 6s
      at(c, 6.1);
      var before = c.document.elements.length;
      c.recording = false;
      var added = c.document.elements.skip(before).single as AudioElement;
      expect(added.clip.channel, "a");
      expect(added.clip.at, 240, reason: "from two seconds");
      expect(added.clip.playlist, hasLength(2),
          reason: "four seconds of a two-second clip: round twice");
      expect(added.clip.playlist.first.end, closeTo(2, 0.01));
      c.undo();
      expect(c.document.elements, hasLength(before),
          reason: "one change with the take");
      c.pause();
    });

    group("a MIDI channel", () {
      late Future<Uint8List> Function(InstrumentPart part, {String? bankPath})
          renderer;
      late Future<String?> Function(Uint8List wav) store;
      late Future<bool> Function() bank;
      final rendered = <InstrumentPart>[];

      setUp(() {
        renderer = CanvasController.partRenderer;
        store = CanvasController.partStore;
        bank = CanvasController.bankReady;
        rendered.clear();
        CanvasController.partRenderer = (part, {bankPath}) async {
          rendered.add(part);
          return wav(480);
        };
        CanvasController.partStore = (bytes) async => id;
        CanvasController.bankReady = () async => false;
      });

      tearDown(() {
        CanvasController.partRenderer = renderer;
        CanvasController.partStore = store;
        CanvasController.bankReady = bank;
      });

      AudioElement keys() =>
          AudioElement(const ElementBase(id: "keys", name: "Keys"),
              clip: const MediaClip(timed: true),
              instrument: const InstrumentPart(notes: [
                MidiNote(60, 0, 0.5),
                MidiNote(64, 1, 0.5),
              ]));

      test("armed, an empty slot records what is played, to whole bars",
          () async {
        var c = make([keys()]);
        addTearDown(c.dispose);
        c.clockForTest = () => micros;
        c.toggleArm("keys");
        var e = c.document.elements.single as AudioElement;
        c.pressClip("keys", 0);
        expect(c.playing, isTrue);
        expect(c.clipState("keys", 0), ClipState.recordQueued);
        c.tickClockForTest();
        expect(c.clipState("keys", 0), ClipState.recording);
        at(c, 0.5);
        c.noteOn(e, 67, velocity: 90);
        at(c, 1.0);
        c.noteOff(e, 67);
        at(c, 2.5);
        c.pressClip("keys", 0); // ends at the end of the bar it is in: 4s
        expect(c.session.at("keys", 0), isNull, reason: "not until the bar");
        at(c, 4.05);
        var clip = c.session.at("keys", 0)!;
        expect(clip.midi, isTrue);
        expect(clip.bars, 2);
        var n = clip.notes.single;
        expect(n.key, 67);
        expect(n.start, closeTo(1, 0.05), reason: "half a second: a beat");
        expect(n.length, closeTo(1, 0.05));
        expect(n.velocity, 90);
        // Into the slot, not the part: Record was not on.
        expect((c.document.elements.single as AudioElement).instrument!.notes,
            hasLength(2));
        // And played round at once, its notes played into a file first.
        await settle();
        expect(rendered.single.notes.single.start, closeTo(0.5, 0.03),
            reason: "a beat at 120 is half a second");
        expect(engine.launches.single.$3, (0.0, 4.0));
        expect(c.session.at("keys", 0)!.sound?.assetId, id);
        c.pause();
      });

      test("the channel's part copied into a slot, in beats", () {
        var c = make([keys()]);
        addTearDown(c.dispose);
        c.newMidiClip("keys", 0, fromPart: true);
        var clip = c.session.at("keys", 0)!;
        expect(clip.notes.map((n) => n.start), [0, 2]);
        expect(clip.bars, 1);
      });
    });
  });

  group("the mixer's slots", () {
    late Directory root;
    late String id;
    late FakeEngine engine;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_session_ui");
      CanvasStorage.rootOverride = root.path;
      var file = File(path.join(root.path, "loop.wav"));
      await file.writeAsBytes(wav(4800));
      id = (await CanvasMedia.saveFile(MediaKind.audio, file.path))!;
      engine = FakeEngine({id: 8});
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });

    Future<CanvasController> show(WidgetTester tester) async {
      var c = CanvasController(
          CanvasDocument(
              frames: 120 * 60,
              frameRate: 120,
              audio: const AudioSettings(tempo: 120),
              elements: [
                AudioElement(const ElementBase(id: "a", name: "Drums"),
                    clip: MediaClip(playlist: [
                      MediaSource(assetId: id, name: "Loop", length: 8)
                    ], timed: true)),
              ]),
          audioEngine: engine);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
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
                    child: CanvasMixer(
                        controller: c,
                        height: 520,
                        onResize: (_) {},
                        onClose: () {})))),
      ));
      await tester.pump();
      return c;
    }

    /// idle lets the real file reads a launch makes finish: each a turn of
    /// the real loop and a pump.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
    }

    /// menu lets a menu open or close: the meters never settle.
    Future<void> menu(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> done(WidgetTester tester, CanvasController c) async {
      c.pause();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    testWidgets("an empty slot right-clicked takes the channel's sound",
        (tester) async {
      var c = await show(tester);
      var slot = find.byKey(const ValueKey("clip-a-0"));
      expect(slot, findsOneWidget);
      await tester.tap(slot, buttons: kSecondaryMouseButton);
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey("clipSound-0")));
      await menu(tester);
      expect(c.session.at("a", 0)?.name, "Loop");
      expect(find.descendant(of: slot, matching: find.text("Loop")),
          findsOneWidget);

      // Its settings, right-clicked: two bars long.
      await tester.tap(slot, buttons: kSecondaryMouseButton);
      await menu(tester);
      await tester.tap(find.text("Length: 4 bars"));
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey("clipBars-2")));
      await menu(tester);
      expect(c.session.at("a", 0)!.bars, 2);
      await done(tester, c);
    });

    testWidgets("right-clicked, a clip's menu opens -- one after another too",
        (tester) async {
      var c = await show(tester);
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      c.clipFromSound("a", 1, c.soundsOf("a").single);
      await tester.pump();
      for (var round = 0; round < 3; round++) {
        for (var row in [0, 1]) {
          await tester.tap(find.byKey(ValueKey("clip-a-$row")),
              buttons: kSecondaryMouseButton);
          await menu(tester);
          expect(find.byKey(const ValueKey("clipRename")), findsOneWidget,
              reason: "slot $row, round $round");
        }
      }
      // A Mac's Control-click is a right-click.
      await tester.tapAt(const Offset(5, 5));
      await menu(tester);
      expect(find.byKey(const ValueKey("clipRename")), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byKey(const ValueKey("clip-a-0")));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await menu(tester);
      expect(find.byKey(const ValueKey("clipRename")), findsOneWidget,
          reason: "control-clicked");
      expect(c.clipState("a", 0), isNot(ClipState.queued),
          reason: "not launched by it");
      await done(tester, c);
    });

    testWidgets("a clip pressed plays; the stop button stops it",
        (tester) async {
      var c = await show(tester);
      c.clipFromSound("a", 0, c.soundsOf("a").single);
      await tester.pump();
      // Launched from its triangle, as in Ableton.
      await tester.tap(find.byKey(const ValueKey("clipLaunch-a-0")));
      await idle(tester);
      // A tick of the playhead: it was launched on the bar it is on.
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.clipState("a", 0), ClipState.playing);
      expect(c.playing, isTrue);
      expect(c.clipPlaying("a"), isTrue);
      expect(engine.launches, hasLength(1));
      await tester.tap(find.byKey(const ValueKey("clipStop-a")));
      await tester.pump();
      expect(c.clipState("a", 0), ClipState.stopping);
      await done(tester, c);
    });

    testWidgets("the master's scenes launch rows, and are added and named",
        (tester) async {
      var c = await show(tester);
      c.clipFromSound("a", 1, c.soundsOf("a").single);
      await tester.pump();
      var rows = c.session.rows;
      await tester.tap(find.byKey(const ValueKey("addClipScene")));
      await tester.pump();
      expect(c.session.rows, rows + 1);
      await tester.tap(find.byKey(const ValueKey("scene-1")));
      await tester.pump();
      expect(c.sceneLaunched, 1);
      expect(c.clipState("a", 1), ClipState.queued);

      await tester.tap(find.byKey(const ValueKey("scene-0")),
          buttons: kSecondaryMouseButton);
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey("sceneRename")));
      await menu(tester);
      await tester.enterText(
          find.byKey(const ValueKey("sceneNameField")), "Intro");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.session.scenes[0], "Intro");
      expect(find.text("Intro"), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("every column's slots scroll together", (tester) async {
      var c = await show(tester);
      for (var i = 0; i < 12; i++) {
        c.addClipScene();
      }
      await tester.pump();
      var a = find.byKey(const ValueKey("clip-a-0"));
      var scene = find.byKey(const ValueKey("scene-0"));
      expect(tester.getRect(a).top, closeTo(tester.getRect(scene).top, 0.5));
      await tester.drag(a, const Offset(0, -60));
      await tester.pump();
      // Rows that have gone up out of view on one have on the other.
      var a5 = find.byKey(const ValueKey("clip-a-5"));
      var s5 = find.byKey(const ValueKey("scene-5"));
      expect(tester.getRect(a5).top, closeTo(tester.getRect(s5).top, 0.5));
      await done(tester, c);
    });
  });
}
