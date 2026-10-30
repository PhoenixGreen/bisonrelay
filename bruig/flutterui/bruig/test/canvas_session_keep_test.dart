import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'canvas_audio_fake.dart';

// canvas_session_keep_test.dart is what the clip slots and the Speech device
// keep: saved with the canvas, read back after a restart -- and the sounds
// they play kept in the library, not swept away as unused.

/// wav is a silent WAV of [frames], told apart from another by [tag].
Uint8List wav(int frames, int tag) {
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
  b.setInt16(44, tag, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  late Directory root;
  var made = 0;

  /// stored is a new sound in the media store.
  Future<String> stored() async {
    var file = File(path.join(root.path, "s${made++}.wav"));
    await file.writeAsBytes(wav(480, made));
    return (await CanvasMedia.saveFile(MediaKind.audio, file.path))!;
  }

  Future<bool> exists(String id) async =>
      await CanvasMedia.existingPath(MediaKind.audio, id) != null;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_session_keep");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    // The library made before any sound is stored, as it is in the app: the
    // first time it is made it takes in every file already there, which
    // hid the sweep from this test.
    await CanvasLibrary.list();
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    await root.delete(recursive: true);
  });

  test("slots and speech come back after a restart, with their sounds",
      () async {
    var timeline = await stored();
    var slot = await stored();
    var reversed = await stored();
    var warped = await stored();
    var played = await stored();
    var take = await stored();
    var c = CanvasController(
        CanvasDocument(
            frames: 400,
            frameRate: 25,
            audio: const AudioSettings(tempo: 120),
            elements: [
              AudioElement(const ElementBase(id: "a", name: "Vocals"),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: timeline, length: 1)],
                      timed: true,
                      mix: ChannelMix(
                          speech: SpeechSpec(script: "Hello", takes: [
                        SpeechTake(take, 1, const [
                          (text: "Hello", start: 0, end: 0.5),
                        ]),
                      ])))),
              const AudioElement(ElementBase(id: "keys", name: "Keys"),
                  clip: MediaClip(timed: true), instrument: InstrumentPart()),
            ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(await c.saveAs("", "Song"), isTrue);
    // A sound in a slot, reversed and warped; a MIDI clip played into one.
    c.setSessionClip(
        "a",
        0,
        SessionClip(
            id: "s",
            name: "Verse",
            sound: MediaSource(assetId: reversed, length: 1),
            reversedOf: MediaSource(assetId: slot, length: 1),
            warp: true,
            bpm: 120,
            warped: MediaSource(assetId: warped, length: 1),
            warpedFor: "x"));
    c.setSessionClip(
        "keys",
        2,
        SessionClip(
            id: "m",
            midi: true,
            notes: const [MidiNote(60, 0, 1)],
            sound: MediaSource(assetId: played, length: 1),
            rendered: "y"));
    var unused = await stored();
    expect(await c.save(), isTrue);
    // The library tidied, as every save does: what nothing uses goes.
    await CanvasLibrary.tidy(open: {});
    expect(await exists(unused), isFalse, reason: "the sweep ran");
    for (var id in [timeline, slot, reversed, warped, played, take]) {
      expect(await exists(id), isTrue, reason: "$id kept");
    }
    // Read back, as after a restart.
    var back = (await CanvasStorage.load("", "Song"))!;
    var clip = back.session.at("a", 0)!;
    expect(clip.name, "Verse");
    expect(clip.reversedOf!.assetId, slot);
    expect(clip.warped!.assetId, warped);
    expect(back.session.at("keys", 2)!.notes, hasLength(1));
    var speech = (back.elementById("a") as AudioElement).clip.mix.speech!;
    expect(speech.takes.single.assetId, take);
  });

  test("a spoken take is saved with the canvas, and its sound kept", () async {
    var engineWas = CanvasController.speechEngineFor;
    var storeWas = CanvasController.speechStore;
    addTearDown(() {
      CanvasController.speechEngineFor = engineWas;
      CanvasController.speechStore = storeWas;
    });
    CanvasController.speechEngineFor = (spec, key) => _Quiet();
    // Kept as the app keeps it: in the media store.
    CanvasController.speechStore =
        (file) => CanvasMedia.saveFile(MediaKind.audio, file);
    var timeline = await stored();
    var c = CanvasController(
        CanvasDocument(frames: 400, frameRate: 25, elements: [
          AudioElement(const ElementBase(id: "a", name: "Narrator"),
              clip: MediaClip(
                  playlist: [MediaSource(assetId: timeline, length: 1)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(await c.saveAs("", "Talk"), isTrue);
    c.setSpeech("a", const SpeechSpec(script: "Hello there"));
    expect(await c.speak("a"), isNull);
    var take = c.speechOf("a")!.takes.single.assetId;
    // Its clip taken off the timeline: the take kept for the Vocaliser.
    var takeClip = c.document.elements
        .whereType<AudioElement>()
        .firstWhere((e) => e.clip.playlist.any((s) => s.assetId == take));
    expect(await c.save(), isTrue);
    await CanvasLibrary.tidy(open: {});
    expect(await exists(take), isTrue);
    expect(takeClip, isNotNull);
    var back = (await CanvasStorage.load("", "Talk"))!;
    var clips = back.elements
        .whereType<AudioElement>()
        .where((e) => e.clip.playlist.any((s) => s.assetId == take));
    expect(clips, hasLength(1), reason: "the take's clip on the timeline");
    var speech = clips.single.clip.mix.speech;
    expect(speech?.script, "Hello there");
    expect(speech?.takes.single.assetId, take);
  });

  test("an empty channel made in the mixer keeps its slots and its Speech",
      () async {
    var sound = await stored();
    var c = CanvasController(
        CanvasDocument(
            frames: 400, frameRate: 25, audio: const AudioSettings(tempo: 120)),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(await c.saveAs("", "Empty"), isTrue);
    var audio = c.addEmptyAudioChannel();
    var midi = c.addMidiChannel(onCanvas: false);
    var empty = c.addEmptyAudioChannel();
    var audioKey = c.timelineChannels
        .firstWhere((ch) => ch.lanes.any((l) => l.element.id == audio.id))
        .key;
    var midiKey = c.timelineChannels
        .firstWhere((ch) => ch.lanes.any((l) => l.element.id == midi.id))
        .key;
    var emptyKey = c.timelineChannels
        .firstWhere((ch) => ch.lanes.any((l) => l.element.id == empty.id))
        .key;
    c.setSessionClip(audioKey, 1,
        SessionClip(id: "s", sound: MediaSource(assetId: sound, length: 1)));
    c.setSessionClip(midiKey, 0,
        const SessionClip(id: "m", midi: true, notes: [MidiNote(60, 0, 1)]));
    c.setSpeech(emptyKey, const SpeechSpec(script: "Hello"));
    expect(await c.save(), isTrue);
    // Opened again, as after a restart.
    var d =
        CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
    addTearDown(d.dispose);
    d.load((await CanvasStorage.load("", "Empty"))!, folder: "", name: "Empty");
    var keys = {for (var ch in d.timelineChannels) ch.key};
    expect(keys, containsAll([audioKey, midiKey, emptyKey]));
    expect(d.session.at(audioKey, 1)?.sound?.assetId, sound);
    expect(d.session.at(midiKey, 0)?.notes, hasLength(1));
    expect(d.speechOf(emptyKey)?.script, "Hello");
  });

  test("reversed, saved, then warped: its reversed sound is still there",
      () async {
    // Ken's report: Reverse, then Warp -- an error, and no sound. The save
    // between them (the autosave) tidied the library and deleted the
    // reversed sound, which only the slot used.
    var audioWas = CanvasController.clipAudio;
    addTearDown(() => CanvasController.clipAudio = audioWas);
    // Read as the app reads them -- or not at all, where the file has gone.
    CanvasController.clipAudio = (id) async {
      if (await CanvasMedia.existingPath(MediaKind.audio, id) == null) {
        return null;
      }
      var l = Float32List(48000 * 2);
      for (var i = 0; i < l.length; i += 24000) {
        l[i] = 0.9;
      }
      return (l, Float32List.fromList(l));
    };
    var sound = await stored();
    var c = CanvasController(
        CanvasDocument(
            frames: 400,
            frameRate: 25,
            audio: const AudioSettings(tempo: 120),
            elements: [
              AudioElement(const ElementBase(id: "a", name: "a"),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: sound, length: 2)],
                      timed: true)),
            ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(await c.saveAs("", "Reversed"), isTrue);
    c.setSessionClip("a", 0,
        SessionClip(id: "s", sound: MediaSource(assetId: sound, length: 2)));
    c.openClipEditor("a", 0);
    expect(await c.reverseClip(), isNull);
    var reversed = c.session.at("a", 0)!.sound!.assetId;
    expect(await c.save(), isTrue);
    await CanvasLibrary.tidy(open: c.document.mediaIds);
    expect(await exists(reversed), isTrue, reason: "kept by the tidy");
    expect(await c.setWarp(true), isNull, reason: "no error");
    expect(c.session.at("a", 0)!.warp, isTrue);
  });
}

class _Quiet implements SpeechEngine {
  @override
  Future<List<SpeechVoice>> voices() async => const [];
  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    var l = Float32List(48000);
    l[0] = 0.5;
    return SpokenAudio(l, Float32List.fromList(l),
        const [(text: "Hello", start: 0, end: 0.4)]);
  }
}
