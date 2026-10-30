import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_clip_editor_test.dart is the clip editor -- Ableton's clip view:
// a clip's start and loop, its gain, launch settings and follow action, its
// sound reversed and cropped, a MIDI clip's notes changed by the Notes
// tools, and the editor itself, opened by a double-click on a slot.

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
  group("the clip", () {
    test("its editor's settings are saved and read back", () {
      const clip = SessionClip(
        id: "c",
        start: 2,
        loopStart: 4,
        gain: -3,
        reversedOf: MediaSource(assetId: "fwd.wav"),
        quantise: Quantise.quarter,
        legato: true,
        follow: FollowAction.next,
        followBars: 2,
      );
      var back = SessionClip.fromJson(clip.toJson())!;
      expect(back.start, 2);
      expect(back.loopStart, 4);
      expect(back.gain, -3);
      expect(back.reversedOf!.assetId, "fwd.wav");
      expect(back.quantise, Quantise.quarter);
      expect(back.legato, isTrue);
      expect(back.follow, FollowAction.next);
      expect(back.followBars, 2);
      var plain = SessionClip.fromJson(const SessionClip(id: "p").toJson())!;
      expect(plain.follow, FollowAction.none);
      expect(plain.quantise, isNull);
      expect(
          const SessionClip(id: "p").toJson().keys, isNot(contains("follow")),
          reason: "what is as it was is not written");
    });

    test("it plays from its start on into its loop, then round the loop", () {
      // In four at a second a beat: a bar is four seconds.
      const clip = SessionClip(id: "c", bars: 1, start: 1, loopStart: 2);
      var pieces = clipPieces(clip, 10, 1, 4);
      expect(pieces, [(1.0, 6.0, 0.0), (2.0, 6.0, 5.0), (2.0, 3.0, 9.0)]);
      var once = clipPieces(clip.copyWith(loop: false), 10, 1, 4);
      expect(once, [(1.0, 6.0, 0.0)], reason: "once, to its loop's end");
    });
  });

  group("the Notes tools", () {
    const notes = [
      MidiNote(60, 0, 1),
      MidiNote(61, 1, 1),
      MidiNote(67, 2, 0.5),
    ];

    test("each changes the picked notes, or all of them", () {
      expect(applyNoteTool(NoteTool.up, notes, {}).map((n) => n.key),
          [61, 62, 68]);
      expect(applyNoteTool(NoteTool.up, notes, {1}).map((n) => n.key),
          [60, 62, 67]);
      expect(applyNoteTool(NoteTool.fitToScale, notes, {}).map((n) => n.key),
          [60, 60, 67],
          reason: "C sharp to C: the lower, between two");
      expect(applyNoteTool(NoteTool.invert, notes, {}).map((n) => n.key),
          [67, 66, 60]);
      expect(applyNoteTool(NoteTool.reverse, notes, {}).map((n) => n.start),
          [1.5, 0.5, 0]);
      expect(
          applyNoteTool(NoteTool.legato, notes, {}, loopEnd: 4)
              .map((n) => n.length),
          [1, 1, 2]);
      expect(applyNoteTool(NoteTool.faster, notes, {}).map((n) => n.start),
          [0, 0.5, 1]);
      expect(applyNoteTool(NoteTool.slower, notes, {}).map((n) => n.length),
          [2, 2, 1]);
      expect(applyNoteTool(NoteTool.third, notes, {0}), hasLength(4));
      expect(applyNoteTool(NoteTool.third, notes, {0}).last.key, 64);
      var played = [const MidiNote(60, 0.13, 0.9)];
      expect(applyNoteTool(NoteTool.quantise, played, {}).single.start, 0.25);
      var human = applyNoteTool(NoteTool.humanise, notes, {}, seed: 3);
      expect(human.map((n) => n.start), isNot([0, 1, 2]));
      expect(
          human.every(
              (n) => (n.start - notes[human.indexOf(n)].start).abs() <= 0.05),
          isTrue);
    });
  });

  group("playing", () {
    late Directory root;
    late String id;
    late FakeEngine engine;
    int micros = 0;

    setUp(() async {
      micros = 0;
      root = await Directory.systemTemp.createTemp("canvas_clip_editor");
      CanvasStorage.rootOverride = root.path;
      var file = File(path.join(root.path, "loop.wav"));
      await file.writeAsBytes(wav(4800));
      id = (await CanvasMedia.saveFile(MediaKind.audio, file.path))!;
      engine = FakeEngine({id: 16});
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });

    /// make is a piece at 120 a minute in four: a beat is half a second, a
    /// bar two. Channel "a" has two clips of the sound.
    CanvasController make() {
      var c = CanvasController(
          CanvasDocument(
              frames: 120 * 60,
              frameRate: 120,
              audio: const AudioSettings(tempo: 120),
              elements: [
                AudioElement(const ElementBase(id: "a", name: "a"),
                    clip: MediaClip(playlist: [
                      MediaSource(assetId: id, name: "Loop", length: 16)
                    ], timed: true)),
              ]),
          audioEngine: engine);
      c.clockForTest = () => micros;
      var sound = MediaSource(assetId: id, name: "Loop", length: 16);
      c.setSessionClip("a", 0, SessionClip(id: "one", sound: sound, bars: 1));
      c.setSessionClip("a", 1, SessionClip(id: "two", sound: sound, bars: 1));
      return c;
    }

    void at(CanvasController c, double seconds) {
      var to = (seconds * 1e6).round();
      while (micros < to) {
        var was = micros;
        micros = (micros + 8333).clamp(0, to);
        for (var v in engine.voices) {
          if (!v.alive || v.paused) continue;
          var launched = engine.launches.any((l) => l.$1 == v);
          v.at = launched ? v.at + (micros - was) / 1e6 : micros / 1e6;
        }
        c.tickClockForTest();
      }
      c.tickClockForTest();
    }

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test("from its start, round its loop, at its gain", () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSessionClip("a", 0,
          c.session.at("a", 0)!.copyWith(start: 1, loopStart: 2, gain: -6));
      c.pressClip("a", 0);
      await settle();
      var (voice, _, loop) = engine.launches.single;
      expect(voice.at, closeTo(0.5, 1e-6), reason: "a beat in");
      expect(loop, (1.0, 3.0), reason: "a bar's loop, from the third beat");
      expect(voice.volume, closeTo(0.501, 0.001), reason: "six decibels down");
      c.pause();
    });

    test("its own launch quantise", () async {
      var c = make();
      addTearDown(c.dispose);
      c.pressClip("a", 0);
      await settle();
      at(c, 0.3);
      c.setSessionClip(
          "a", 1, c.session.at("a", 1)!.copyWith(quantise: Quantise.quarter));
      c.pressClip("a", 1);
      await settle();
      expect(engine.launches.last.$2, closeTo(0.2, 0.02),
          reason: "the next beat, at half a second -- not the bar");
      c.pause();
    });

    test("its follow action launches the next clip when it has played",
        () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSessionClip(
          "a", 0, c.session.at("a", 0)!.copyWith(follow: FollowAction.next));
      c.pressClip("a", 0);
      await settle();
      at(c, 1.9);
      await settle();
      expect(engine.launches, hasLength(2), reason: "set up before it is due");
      expect(c.clipState("a", 1), ClipState.queued);
      at(c, 2.05);
      expect(c.clipState("a", 1), ClipState.playing);
      expect(c.clipState("a", 0), ClipState.stopped);
      c.pause();
    });

    test("a follow action of Stop stops it; Nothing leaves it going", () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSessionClip(
          "a",
          0,
          c.session
              .at("a", 0)!
              .copyWith(follow: FollowAction.stop, followBars: 2));
      c.pressClip("a", 0);
      await settle();
      at(c, 3.9);
      expect(c.clipState("a", 0), ClipState.stopping,
          reason: "round twice, then stopped");
      at(c, 4.1);
      expect(c.clipState("a", 0), ClipState.stopped);
      c.pause();
    });

    test("legato takes over where the last clip had got to", () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSessionClip(
          "a",
          1,
          c.session
              .at("a", 1)!
              .copyWith(legato: true, quantise: Quantise.quarter, bars: 2));
      c.pressClip("a", 0);
      await settle();
      at(c, 0.7);
      c.pressClip("a", 1); // on the next beat, at one second
      await settle();
      var (voice, delay, _) = engine.launches.last;
      expect(delay, closeTo(0.3, 0.02));
      expect(voice.at, closeTo(1, 0.02),
          reason: "a second in, as the first had got to -- not its start");
      c.pause();
    });

    group("its sound", () {
      late Future<(Float32List, Float32List)?> Function(String) audioWas;
      late Future<String?> Function(String) storeWas;
      final kept = <Float32List>[];

      setUp(() {
        audioWas = CanvasController.clipAudio;
        storeWas = CanvasController.speechStore;
        kept.clear();
        // Four samples a second's worth: a ramp, to see it turned round.
        CanvasController.clipAudio = (id) async {
          var l = Float32List.fromList(
              [for (var i = 0; i < 48000 * 4; i++) i / (48000 * 4)]);
          return (l, Float32List.fromList(l));
        };
        CanvasController.speechStore = (file) async {
          // The WAV written: its first sample after the header.
          var bytes = await File(file).readAsBytes();
          var data = ByteData.sublistView(bytes);
          kept.add(Float32List.fromList([
            data.getInt16(44, Endian.little) / 32767,
            data.getInt16(bytes.length - 4, Endian.little) / 32767,
          ]));
          return "new${kept.length}.wav";
        };
      });

      tearDown(() {
        CanvasController.clipAudio = audioWas;
        CanvasController.speechStore = storeWas;
      });

      test("reversed is a reversed copy, and reversed again the original",
          () async {
        var c = make();
        addTearDown(c.dispose);
        c.openClipEditor("a", 0);
        expect(await c.reverseClip(), isNull);
        var clip = c.session.at("a", 0)!;
        expect(clip.sound!.assetId, "new1.wav");
        expect(clip.reversedOf!.assetId, id);
        expect(kept.single[0], greaterThan(0.99), reason: "the end first");
        expect(kept.single[1], lessThan(0.01));
        expect(await c.reverseClip(), isNull);
        expect(c.session.at("a", 0)!.sound!.assetId, id);
        expect(c.session.at("a", 0)!.reversedOf, isNull);
      });

      test("reversed while it plays, it is heard reversed at once", () async {
        // Kept in the media store, as the app keeps it, for the engine to
        // open.
        String? reversedId;
        CanvasController.speechStore = (file) async {
          reversedId = await CanvasMedia.saveFile(MediaKind.audio, file);
          engine.lengths[reversedId!] = 4;
          return reversedId;
        };
        var c = make();
        addTearDown(c.dispose);
        c.pressClip("a", 0);
        await settle();
        at(c, 0.7);
        var first = engine.launches.single.$1;
        c.openClipEditor("a", 0);
        expect(await c.reverseClip(), isNull);
        await settle();
        expect(engine.launches, hasLength(2),
            reason: "played again, as it now is");
        var (voice, delay, _) = engine.launches.last;
        expect(delay, closeTo(0, 0.01), reason: "now, not at the next bar");
        expect(voice.track.path, reversedId);
        expect(engine.stopsIn.any((s) => s.$1 == first), isTrue,
            reason: "the forwards one stopped");
        // Renamed: nothing to hear, so nothing played again.
        c.editClip((x) => x.copyWith(name: "Backwards"));
        await settle();
        expect(engine.launches, hasLength(2));
        // Its gain: played again, at its new level.
        c.editClip((x) => x.copyWith(gain: -6));
        await settle();
        expect(engine.launches, hasLength(3));
        expect(engine.launches.last.$1.volume, closeTo(0.501, 0.001));
        c.pause();
      });

      test("reversed while another clip is opened goes to the first", () async {
        var c = make();
        addTearDown(c.dispose);
        c.openClipEditor("a", 0);
        var reversing = c.reverseClip();
        // The editor moved on before the sound was read.
        c.openClipEditor("a", 1);
        expect(await reversing, isNull);
        expect(c.session.at("a", 0)!.reversedOf, isNotNull);
        expect(c.session.at("a", 1)!.reversedOf, isNull);
      });

      test("cropped warped, it keeps what its beats play of its sound",
          () async {
        var c = make();
        addTearDown(c.dispose);
        // At 240 its sound is four beats a second: beats two to six are
        // half a second to a second and a half of it -- not, as at the
        // song's 120, one to three seconds.
        c.setSessionClip(
            "a",
            0,
            c.session.at("a", 0)!.copyWith(
                sound: MediaSource(assetId: id, length: 4),
                warp: true,
                bpm: 240,
                start: 2,
                loopStart: 2,
                bars: 1,
                markers: const [(seconds: 1, beat: 4)]));
        c.openClipEditor("a", 0);
        expect(await c.cropClip(), isNull);
        var clip = c.session.at("a", 0)!;
        expect(clip.sound!.length, closeTo(1, 0.001));
        expect(kept.single[0], closeTo(0.125, 0.001),
            reason: "from half a second in: an eighth of the ramp");
        expect(clip.markers.first, (seconds: 0.5, beat: 2.0),
            reason: "its marker moved with it");
        expect(clip.warpMap.beatAt(1), closeTo(4, 1e-9),
            reason: "its end where it was");
      });

      test("changed while it plays, its follow action keeps its time",
          () async {
        engine.lengths[id] = 16;
        var c = make();
        addTearDown(c.dispose);
        c.setSessionClip(
            "a", 0, c.session.at("a", 0)!.copyWith(follow: FollowAction.next));
        c.pressClip("a", 0);
        await settle();
        at(c, 1);
        c.openClipEditor("a", 0);
        c.editClip((x) => x.copyWith(gain: -3));
        await settle();
        at(c, 1.9);
        await settle();
        expect(c.clipState("a", 1), ClipState.queued,
            reason: "the next clip on the bar, as before the change");
        c.pause();
      });

      test("reversed, its warp markers are turned round with it", () async {
        var c = make();
        addTearDown(c.dispose);
        // A four-second sound at 120: eight beats; a marker a second in, on
        // beat three.
        c.setSessionClip(
            "a",
            0,
            c.session.at("a", 0)!.copyWith(
                sound: MediaSource(assetId: id, length: 4),
                warp: true,
                bpm: 120,
                markers: const [(seconds: 1, beat: 3)]));
        c.openClipEditor("a", 0);
        expect(await c.reverseClip(), isNull);
        // Its end pinned where its start was.
        expect(c.session.at("a", 0)!.markers.last, (seconds: 4.0, beat: 9.0));
        var m = c.session.at("a", 0)!.markers.first;
        expect(m.seconds, closeTo(3, 1e-9));
        // Nine beats long -- three to the marker, three seconds at two a
        // second after it -- so the marker is six from the end.
        expect(m.beat, closeTo(6, 1e-9), reason: "as far from the end");
        expect(c.session.at("a", 0)!.warpMap.beatAt(4), closeTo(9, 1e-9),
            reason: "as long as it was");
        expect(await c.reverseClip(), isNull);
        var back = c.session.at("a", 0)!;
        m = back.markers.first;
        expect((m.seconds, m.beat), (1.0, 3.0), reason: "and back");
        for (var s in [0.5, 1.0, 2.5, 4.0]) {
          expect(
              back.warpMap.beatAt(s),
              closeTo(
                  WarpMap(120, const [(seconds: 1, beat: 3)]).beatAt(s), 1e-9),
              reason: "every moment where it was, at $s s");
        }
      });

      test("cropped keeps only what it plays, as a new sound", () async {
        var c = make();
        addTearDown(c.dispose);
        c.setSessionClip(
            "a", 0, c.session.at("a", 0)!.copyWith(start: 2, loopStart: 2));
        c.openClipEditor("a", 0);
        expect(await c.cropClip(), isNull);
        var clip = c.session.at("a", 0)!;
        expect(clip.sound!.assetId, "new1.wav");
        expect(clip.sound!.length, closeTo(2, 0.001),
            reason: "the loop's bar: two seconds");
        expect(clip.start, 0);
        expect(clip.loopStart, 0);
        expect(kept.single[0], closeTo(0.25, 0.001),
            reason: "from a second in: a quarter of the ramp");
      });
    });

    group("warped", () {
      late Future<(Float32List, Float32List)?> Function(String) audioWas;
      late Future<String?> Function(Uint8List) storeWas;
      final stored = <int>[];
      String? warpedId;

      setUp(() {
        audioWas = CanvasController.clipAudio;
        storeWas = CanvasController.partStore;
        stored.clear();
        // Two bars of clicks at 100: 4.8 seconds.
        CanvasController.clipAudio = (id) async {
          var x = Float32List((4.8 * 48000).round());
          for (var t = 0.0; t < 4.8; t += 0.6) {
            var at = (t * 48000).round();
            for (var k = 0; k < 400 && at + k < x.length; k++) {
              x[at + k] = 0.8 * math.exp(-k / 60) * math.sin(k * 0.9);
            }
          }
          return (x, Float32List.fromList(x));
        };
        // Kept in the media store, as the app keeps it, for the engine to
        // open.
        CanvasController.partStore = (wav) async {
          stored.add(wav.length);
          var file = File(path.join(root.path, "warped${stored.length}.wav"));
          await file.writeAsBytes(wav);
          warpedId = await CanvasMedia.saveFile(MediaKind.audio, file.path);
          engine.lengths[warpedId!] = 4;
          return warpedId;
        };
      });

      tearDown(() {
        CanvasController.clipAudio = audioWas;
        CanvasController.partStore = storeWas;
      });

      test("on, its tempo is heard; launched, it plays its sound warped",
          () async {
        var c = make();
        addTearDown(c.dispose);
        c.openClipEditor("a", 0);
        expect(await c.setWarp(true), isNull);
        var clip = c.session.at("a", 0)!;
        expect(clip.warp, isTrue);
        expect(clip.bpm, closeTo(100, 0.01),
            reason: "two bars at 100, exactly");
        c.pressClip("a", 0);
        for (var i = 0; i < 40 && engine.launches.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        var (voice, _, _) = engine.launches.single;
        expect(voice.track.path, warpedId);
        // At 120 the two bars are four seconds: 48000 a second, two sides,
        // two bytes each, and the header.
        expect(stored.single, closeTo(44 + 4 * 48000 * 4, 4 * 4));
        var after = c.session.at("a", 0)!;
        expect(after.warped!.assetId, warpedId);
        expect(after.warpedFor, after.warpSignature(0.5));
        c.pause();
      });

      test("warped once, it is not warped again until it changes", () async {
        var c = make();
        addTearDown(c.dispose);
        c.openClipEditor("a", 0);
        await c.setWarp(true);
        c.pressClip("a", 0);
        for (var i = 0; i < 40 && engine.launches.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        c.stopAllClips();
        c.pause();
        c.pressClip("a", 0);
        for (var i = 0; i < 40 && engine.launches.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(stored, hasLength(1), reason: "the same, played again");
        c.editClip((x) => x.copyWith(pitch: 2));
        expect(c.session.at("a", 0)!.warpedFor,
            isNot(c.session.at("a", 0)!.warpSignature(0.5)));
        c.pause();
      });
    });
  });

  group("the editor", () {
    late Directory root;
    late String id;
    late FakeEngine engine;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_clip_editor_ui");
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

    Future<CanvasController> show(WidgetTester tester,
        {double scale = 1, double width = 1400, bool wide = true}) async {
      var c = CanvasController(
          CanvasDocument(
              frames: 120 * 60,
              frameRate: 120,
              audio: const AudioSettings(tempo: 120),
              elements: [
                AudioElement(const ElementBase(id: "a", name: "Vocals"),
                    clip: MediaClip(playlist: [
                      MediaSource(assetId: id, name: "Loop", length: 8)
                    ], timed: true)),
                const AudioElement(ElementBase(id: "keys", name: "Keys"),
                    clip: MediaClip(timed: true), instrument: InstrumentPart()),
              ]),
          audioEngine: engine);
      var sound = MediaSource(assetId: id, name: "Loop", length: 8);
      c.setSessionClip("a", 0,
          SessionClip(id: "one", name: "Patience", sound: sound, bars: 2));
      c.setSessionClip(
          "keys",
          0,
          const SessionClip(id: "m", name: "Chords", midi: true, notes: [
            MidiNote(60, 0, 1),
            MidiNote(64, 1, 1),
          ]));
      // Widened, every column showing -- see "narrow" below for one.
      if (wide) c.toggleEditorWide();
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CanvasMixer.effects(
                            controller: c,
                            height: 360,
                            onResize: (_) {},
                            onClose: () {}),
                        CanvasMixer(
                            controller: c,
                            height: 420,
                            onResize: (_) {},
                            onClose: () {}),
                      ]),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return c;
    }

    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
    }

    Future<void> done(WidgetTester tester, CanvasController c) async {
      c.pause();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    testWidgets("an audio clip double-clicked opens on its sound",
        (tester) async {
      var c = await show(tester);
      var slot = find.byKey(const ValueKey("clip-a-0"));
      await tester.tap(slot);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(slot);
      await tester.pump(const Duration(milliseconds: 400));
      await idle(tester);
      expect(c.clipEditorShown, isTrue);
      expect(find.byKey(const ValueKey("audioColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("clipSample")), findsOneWidget);
      expect(find.byKey(const ValueKey("clipEditorName")), findsOneWidget);
      // Start a beat on, then the loop's position.
      await tester.tap(find.byKey(const ValueKey("clipStart-up")));
      await tester.pump();
      expect(c.session.at("a", 0)!.start, 1);
      expect(find.text("1.2.1"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("clipLoopStart-up")));
      await tester.pump();
      expect(c.session.at("a", 0)!.loopStart, 1);
      // Gain down a decibel.
      await tester.tap(find.byKey(const ValueKey("clipGain-down")));
      await tester.pump();
      expect(c.session.at("a", 0)!.gain, -1);
      // Then: the next clip, from its dropdown.
      await tester.tap(find.byKey(const ValueKey("clipFollow")));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text("Next clip").last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.session.at("a", 0)!.follow, FollowAction.next);
      expect(find.byKey(const ValueKey("clipFollowAfter")), findsOneWidget);
      // Back to the effects.
      // Closed from its bar in the effects strip.
      await tester.tap(find.byKey(const ValueKey("editorClose")));
      await tester.pump();
      expect(c.clipEditorShown, isFalse);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("the ruler's flag and loop bar are dragged, to the beat",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      var ruler = tester.getRect(find.byKey(const ValueKey("clipSample")));
      // In view: eight seconds of sound, sixteen beats, and a bar more.
      var beatW = ruler.width / 20;
      // The loop's end, dragged two beats on: two bars and a half.
      var end = ruler.topLeft + Offset(8 * beatW, 12);
      var g = await tester.startGesture(end);
      await g.moveBy(Offset(2 * beatW, 0));
      await g.moveBy(Offset(0.2, 0));
      await g.up();
      await tester.pump();
      expect(c.session.at("a", 0)!.bars, 2.5);
      c.undo();
      expect(c.session.at("a", 0)!.bars, 2, reason: "one drag, one undo");
      // The start's flag, dragged three beats on.
      var flag = ruler.topLeft + const Offset(2, 14);
      g = await tester.startGesture(flag);
      await g.moveBy(Offset(3 * beatW, 0));
      await g.moveBy(Offset(0.2, 0));
      await g.up();
      await tester.pump();
      expect(c.session.at("a", 0)!.start, 3);
      expect(c.session.at("a", 0)!.loopStart, 0, reason: "the loop stays");
      await done(tester, c);
    });

    testWidgets("a MIDI clip opens on its notes, and the tools change them",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("keys", 0);
      await tester.pump();
      expect(find.byKey(const ValueKey("notesColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("rollDraw")), findsOneWidget,
          reason: "the piano roll, beside the columns");
      expect(find.byKey(const ValueKey("rollToEffects")), findsNothing,
          reason: "the editor's way back, not the roll's");
      await tester.tap(find.byKey(const ValueKey("noteTool-up")));
      await tester.pump();
      expect(c.session.at("keys", 0)!.notes.map((n) => n.key), [61, 65]);
      // Picked in the roll, only that one.
      c.rollSelected.add(0);
      await tester.tap(find.byKey(const ValueKey("noteTool-octaveDown")));
      await tester.pump();
      expect(c.session.at("keys", 0)!.notes.map((n) => n.key), [49, 65]);
      expect(find.text("On the 1 note picked."), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("warped: its tempo heard, halved, and markers put in",
        (tester) async {
      var audioWas = CanvasController.clipAudio;
      var storeWas = CanvasController.partStore;
      addTearDown(() {
        CanvasController.clipAudio = audioWas;
        CanvasController.partStore = storeWas;
      });
      // Two bars of clicks at 100.
      CanvasController.clipAudio = (id) async {
        var x = Float32List((4.8 * 48000).round());
        for (var t = 0.0; t < 4.8; t += 0.6) {
          var at = (t * 48000).round();
          for (var k = 0; k < 400 && at + k < x.length; k++) {
            x[at + k] = 0.8 * math.exp(-k / 60) * math.sin(k * 0.9);
          }
        }
        return (x, Float32List.fromList(x));
      };
      CanvasController.partStore = (wav) async => null;
      var c = await show(tester);
      // A sound of its own: another test's read of the file may still be
      // on its way.
      c.setSessionClip(
          "a",
          0,
          c.session.at("a", 0)!.copyWith(
              sound: const MediaSource(
                  assetId: "clicks.wav", name: "Clicks", length: 4.8)));
      c.openClipEditor("a", 0);
      await tester.pump();
      expect(find.byKey(const ValueKey("clipWarpMode")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("clipWarp")));
      for (var i = 0; i < 40 && !c.session.at("a", 0)!.warp; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      // The sound's drawing and hits, worked out in the background.
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(c.session.at("a", 0)!.bpm, closeTo(100, 0.01));
      expect(find.text("100.00"), findsOneWidget);
      expect(find.byKey(const ValueKey("clipWarpMode")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("clipBpmHalve")));
      await tester.pump();
      expect(c.session.at("a", 0)!.bpm, 50);
      await tester.tap(find.byKey(const ValueKey("clipBpmDouble")));
      await tester.pump();
      // A marker clicked in under the ruler, a beat and a half in.
      var view = tester.getRect(find.byKey(const ValueKey("clipSample")));
      var clip = c.session.at("a", 0)!;
      var beats =
          [clip.warpMap.beatAt(4.8), clip.loopEnd(4), 1.0].reduce(math.max) + 4;
      var beatW = view.width / beats;
      await tester.tapAt(view.topLeft + Offset(1.5 * beatW, 32));
      await tester.pump();
      var markers = c.session.at("a", 0)!.markers;
      expect(markers, hasLength(1));
      expect(markers.single.beat, closeTo(1.5, 0.15));
      // Dragged on half a beat: the sound pulled with it.
      var at = view.topLeft + Offset(markers.single.beat * beatW, 32);
      var g = await tester.startGesture(at);
      await g.moveBy(Offset(beatW / 2, 0));
      await g.moveBy(const Offset(0.2, 0));
      await g.up();
      await tester.pump();
      expect(c.session.at("a", 0)!.markers.single.beat,
          closeTo(markers.single.beat + 0.5, 0.26));
      // Right-clicked, taken out.
      var now = c.session.at("a", 0)!.markers.single.beat;
      await tester.tapAt(view.topLeft + Offset(now * beatW, 32),
          buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(c.session.at("a", 0)!.markers, isEmpty);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("in the effects strip: narrow, a column at a time; widened",
        (tester) async {
      var c = await show(tester, wide: false);
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      expect(find.byKey(const ValueKey("device-clip")), findsOneWidget);
      var narrow = tester.getSize(find.byKey(const ValueKey("device-clip")));
      expect(narrow.width, lessThanOrEqualTo(760));
      expect(find.byKey(const ValueKey("clipColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("audioColumn")), findsNothing);
      // The Audio column, picked above it.
      await tester.tap(find.byKey(const ValueKey("clipShow-2")));
      await tester.pump();
      expect(find.byKey(const ValueKey("audioColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("clipColumn")), findsNothing);
      // The rest of the channel's chain still beside it.
      expect(find.byKey(const ValueKey("addDeviceSlot")), findsOneWidget);
      // Widened: every column, and wider -- still in the strip.
      await tester.tap(find.byKey(const ValueKey("editorWide")));
      await tester.pump();
      await idle(tester);
      expect(c.editorWide, isTrue);
      expect(find.byKey(const ValueKey("clipColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("launchColumn")), findsOneWidget);
      expect(find.byKey(const ValueKey("audioColumn")), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey("device-clip"))).width,
          greaterThan(narrow.width));
      expect(find.byKey(const ValueKey("effectsChain")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    // Ken's log: a device's tooltip showing as the clip editor opened ahead
    // of it -- each device moved, not rebuilt, and a showing tooltip moved
    // in a layout asserts. Needs a real hover and the app's LayoutBuilder
    // over a Navigator, as the canvas page has; without either it passes.
    testWidgets("opened ahead of a device whose tooltip shows, nothing asserts",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(
              frames: 120 * 60,
              frameRate: 120,
              audio: const AudioSettings(tempo: 120),
              elements: [
                AudioElement(const ElementBase(id: "a", name: "Vocals"),
                    clip: MediaClip(playlist: [
                      MediaSource(assetId: id, name: "Loop", length: 8)
                    ], timed: true)),
              ]),
          audioEngine: engine);
      c.setSessionClip(
          "a",
          0,
          SessionClip(
              id: "one",
              name: "Patience",
              sound: MediaSource(assetId: id, name: "Loop", length: 8),
              bars: 2));
      c.pickStrip("a");
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
            body: LayoutBuilder(
              builder: (context, box) => Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CanvasMixer.effects(
                              controller: c,
                              height: 360,
                              onResize: (_) {},
                              onClose: () {}),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      var chain = find.byKey(const ValueKey("effectsChain"));
      var tips = find.descendant(of: chain, matching: find.byType(Tooltip));
      expect(tips, findsWidgets);
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(tips.first));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text("Fold Channel EQ"), findsOneWidget,
          reason: "the tooltip showing");
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      expect(find.byKey(const ValueKey("device-clip")), findsOneWidget);
      expect(tester.takeException(), isNull);
      // And shut again, the devices moving back.
      c.closeEditor();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    // The same, from the panel dragged down at a larger text size: its zoom
    // came to one, and the desk was laid out afresh under its tooltip.
    testWidgets("shrunk to its least while a tooltip shows, nothing asserts",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 120 * 60, frameRate: 120, elements: [
            AudioElement(const ElementBase(id: "a", name: "Vocals"),
                clip: MediaClip(playlist: [
                  MediaSource(assetId: id, name: "Loop", length: 8)
                ], timed: true)),
          ]),
          audioEngine: engine);
      c.pickStrip("a");
      var height = ValueNotifier(360.0);
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
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.25)),
              child: child!),
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, box) => Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (context, h, _) => Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CanvasMixer.effects(
                              controller: c,
                              height: h,
                              onResize: (_) {},
                              onClose: () {}),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      var tips = find.descendant(
          of: find.byKey(const ValueKey("effectsChain")),
          matching: find.byType(Tooltip));
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(tips.first));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text("Fold Channel EQ"), findsOneWidget,
          reason: "the tooltip showing");
      for (var h in [300.0, 250.0, effectsMinHeight, 320.0]) {
        height.value = h;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "at $h");
      }
      await done(tester, c);
    });

    testWidgets("its Velocity: how much a pad's velocity sets its volume",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      var up = find.byKey(const ValueKey("clipVelocity-up"));
      await tester.ensureVisible(up);
      await tester.pump();
      expect(find.text("0%"), findsOneWidget, reason: "none, to begin with");
      await tester.tap(up);
      await tester.pump();
      await tester.tap(up);
      await tester.pump();
      expect(c.session.at("a", 0)!.velocity, closeTo(0.2, 1e-9));
      expect(find.text("20%"), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    // Ken: the editor made wider or narrower by its right edge; and the
    // columns wide enough for their numbers.
    testWidgets("dragged by its right edge, wider and narrower",
        (tester) async {
      var c = await show(tester, wide: false);
      c.openClipEditor("keys", 0);
      await tester.pump();
      await idle(tester);
      var device = find.byKey(const ValueKey("device-clip"));
      var was = tester.getSize(device).width;
      expect(
          tester.getSize(find.byKey(const ValueKey("clipColumn"))).width, 220,
          reason: "room for 1.2.1 beside its steppers");
      var edge = find.byKey(const ValueKey("editorEdge-clip"));
      await tester.drag(edge, const Offset(-120, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(tester.getSize(device).width, closeTo(was - 120, 1));
      expect(c.editorWidth, closeTo(was - 120, 1));
      // Wider or Narrower: as they have it again.
      await tester.tap(find.byKey(const ValueKey("editorWide")));
      await tester.pump();
      expect(c.editorWidth, isNull);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("an audio clip's envelope is drawn over its sound",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey("clipEnvelopes")));
      await tester.pump();
      expect(find.byKey(const ValueKey("clipEnvelopeTarget")), findsOneWidget);
      var view = tester.getRect(find.byKey(const ValueKey("clipSample")));
      var clip = c.session.at("a", 0)!;
      // In view: sixteen beats of sound, and a bar more.
      var beats =
          [16.0, clip.loopEnd(4), 1.0].reduce((a, b) => a > b ? a : b) + 4;
      var beatW = view.width / beats;
      // A point two beats in, half way down the sound.
      var top = view.top + 26, bottom = view.bottom;
      var middle = top + 6 + (bottom - top - 12) / 2;
      await tester.tapAt(Offset(view.left + 2 * beatW, middle));
      await tester.pump();
      var points = c.session.at("a", 0)!.envelopes[ClipEnvelope.gain]!;
      expect(points, hasLength(1));
      expect(points.single.$1, 2);
      expect(points.single.$2, closeTo(0.5, 0.03));
      expect(c.session.at("a", 0)!.needsRender, isTrue,
          reason: "its gain rendered with its sound");
      // Dragged up, louder; right-clicked, gone.
      var g = await tester.startGesture(Offset(view.left + 2 * beatW, middle));
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(const Offset(0, -20));
      await g.up();
      await tester.pump();
      var moved = c.session.at("a", 0)!.envelopes[ClipEnvelope.gain]!.single;
      expect(moved.$2, greaterThan(0.55));
      var y = top + 6 + (1 - moved.$2) * (bottom - top - 12);
      await tester.tapAt(Offset(view.left + moved.$1 * beatW, y),
          buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(c.session.at("a", 0)!.envelopes[ClipEnvelope.gain], isEmpty);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    // Ken: a clip's envelope of a setting of its channel, its own length.
    testWidgets("a clip's envelope can move its channel's settings",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("a", 0);
      await tester.pump();
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey("clipEnvelopes")));
      await tester.pump();
      // The channel's volume, from the list.
      await tester.tap(find.byKey(const ValueKey("clipEnvelopeTarget")));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text("Channel › Volume").last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey("clipEnvelopeLength")), findsOneWidget,
          reason: "a setting's envelope can have a length of its own");
      var view = tester.getRect(find.byKey(const ValueKey("clipSample")));
      var clip = c.session.at("a", 0)!;
      var beats =
          [16.0, clip.loopEnd(4), 1.0].reduce((a, b) => a > b ? a : b) + 4;
      var beatW = view.width / beats;
      var top = view.top + 26, bottom = view.bottom;
      var middle = top + 6 + (bottom - top - 12) / 2;
      await tester.tapAt(Offset(view.left + 2 * beatW, middle));
      await tester.pump();
      clip = c.session.at("a", 0)!;
      expect(clip.curveOf("volume").single.$1, 2);
      expect(clip.envelopes[ClipEnvelope.gain] ?? const [], isEmpty);
      expect(clip.needsRender, isFalse,
          reason: "a setting's envelope is played, not rendered");
      // Its own length: a bar.
      await tester.tap(find.byKey(const ValueKey("clipEnvelopeLength")));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text("1 bar").last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.session.at("a", 0)!.lengthOf("volume"), 4);
      // A MIDI clip's: in a lane under its notes.
      c.openClipEditor("keys", 0);
      await tester.pump();
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey("rollLane")));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text("Channel › Volume").last);
      await tester.pump(const Duration(milliseconds: 400));
      var lane = find.byKey(const ValueKey("rollSetting-volume"));
      expect(lane, findsOneWidget);
      await tester.tapAt(tester.getTopLeft(lane) + const Offset(60, 20));
      await tester.pump();
      expect(c.session.at("keys", 0)!.curveOf("volume"), hasLength(1));
      expect(find.byKey(const ValueKey("rollLaneLength-0")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("a clip dragged by its name moves; with Option, is copied",
        (tester) async {
      var c = await show(tester);
      Future<void> drag(String from, String to) async {
        var start = tester.getCenter(find.byKey(ValueKey("clipName-$from")));
        var end = tester.getCenter(find.byKey(ValueKey("clip-$to")));
        var g = await tester.startGesture(start);
        await tester.pump();
        for (var i = 1; i <= 8; i++) {
          await g.moveTo(Offset.lerp(start, end, i / 8)!);
          await tester.pump();
        }
        await g.up();
        await tester.pump();
      }

      var id = c.session.at("a", 0)!.id;
      await drag("a-0", "a-1");
      expect(c.session.at("a", 0), isNull);
      expect(c.session.at("a", 1)!.id, id);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await drag("a-1", "a-2");
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(c.session.at("a", 1)!.id, id, reason: "the original stays");
      expect(c.session.at("a", 2)!.name, "Patience");
      // A sound is not let go on a MIDI channel's slot.
      await drag("a-1", "keys-3");
      expect(c.session.at("keys", 3), isNull);
      expect(c.session.at("a", 1), isNotNull);
      await done(tester, c);
    });

    testWidgets("clicked, a clip is the one the open editor shows",
        (tester) async {
      var c = await show(tester);
      c.setSessionClip(
          "a", 1, c.session.at("a", 0)!.copyWith(id: "two", name: "Chorus"));
      c.openClipEditor("a", 0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("clipName-a-1")));
      // Past the wait for a second click.
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selectedSlot, ("a", 1));
      expect(c.editedClip!.name, "Chorus");
      expect(find.text("Clip · Chorus"), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("the editor's Play plays it on its own; Stop stops it",
        (tester) async {
      var c = await show(tester);
      c.openClipEditor("a", 0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("clipPreview")));
      await idle(tester);
      expect(c.sessionOnly, isTrue, reason: "the timeline stays quiet");
      expect(engine.launches, hasLength(1));
      expect(engine.launches.single.$2, closeTo(0, 0.01), reason: "at once");
      expect(find.text("■ Stop"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("clipPreview")));
      await tester.pump();
      expect(c.clipPreviewing, isFalse);
      await done(tester, c);
    });

    testWidgets("nothing overflows at a larger text size", (tester) async {
      for (var scale in [1.0, 1.15, 1.25, 1.5]) {
        for (var channel in ["a", "keys"]) {
          var c = await show(tester,
              scale: scale, width: 1100, wide: scale != 1.15);
          // Warped, with every control showing.
          c.setSessionClip(
              "a",
              0,
              c.session
                  .at("a", 0)!
                  .copyWith(warp: true, bpm: 120, pitch: 2, markers: [
                (seconds: 1, beat: 2),
              ]));
          c.openClipEditor(channel, 0);
          await tester.pump();
          await idle(tester);
          expect(tester.takeException(), isNull,
              reason: "$channel at ${scale}x");
          await done(tester, c);
        }
      }
    });
  });
}
