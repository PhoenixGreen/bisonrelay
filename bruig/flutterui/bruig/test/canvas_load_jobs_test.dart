import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

import 'support/canvas_audio_fake.dart';
import 'support/temp_dirs.dart';

// canvas_load_jobs_test.dart holds a job that takes a while -- a voice
// speaking, a file read, a sound worked on off the app's isolate, a canvas
// written to disk -- to the canvas it was started on. Each test starts one,
// opens another canvas while it waits (often the same canvas opened again,
// whose elements and channels have the same ids), lets it finish, and
// expects the canvas open now to be as it was opened: what the job brought
// back belonged to the last one.

/// _Gated is a voice that speaks a second of quiet tone once [gate] is
/// opened, whatever it is told to stop.
class _Gated extends SpeechEngine {
  final gate = Completer<void>();
  int asked = 0;

  @override
  Future<List<SpeechVoice>> voices() async => const [];

  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    asked++;
    await gate.future;
    var l = Float32List(mixRate)..fillRange(0, mixRate, 0.1);
    return SpokenAudio(l, Float32List.fromList(l),
        const [(text: "Hello", start: 0, end: 0.4)]);
  }
}

/// _held is a stand-in made to wait on a [Completer] of its own.
Future<T> _held<T>(Completer<void> gate, T value) async {
  await gate.future;
  return value;
}

Float32List _tone(double seconds) =>
    Float32List((seconds * mixRate).round())..fillRange(0, 1, 0.1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("speech", () {
    late SpeechEngine Function(SpeechSpec) engineWas;
    late Future<String?> Function(String) storeWas;
    late Future<Float32List?> Function(String) audioWas;
    late Future<void> Function(String, String, double) libraryWas;
    late Future<String?> Function(Uint8List) takeStoreWas;
    late Future<String?> Function(String) takePathWas;
    var listed = <String>[];

    setUp(() {
      engineWas = CanvasController.speechEngineFor;
      storeWas = CanvasController.speechStore;
      audioWas = CanvasController.takeAudio;
      libraryWas = CanvasController.speechLibrary;
      takeStoreWas = CanvasController.speechTakeStore;
      takePathWas = CanvasController.takePath;
      listed = [];
      var kept = 0;
      CanvasController.speechStore = (file) async => "kept${++kept}.wav";
      CanvasController.takeAudio = (id) async => _tone(1);
      CanvasController.speechLibrary =
          (id, name, seconds) async => listed.add(id);
      CanvasController.speechTakeStore = (wav) async => "line${++kept}.wav";
      CanvasController.takePath = (id) async => "/kept/$id";
    });

    tearDown(() {
      CanvasController.speechEngineFor = engineWas;
      CanvasController.speechStore = storeWas;
      CanvasController.takeAudio = audioWas;
      CanvasController.speechLibrary = libraryWas;
      CanvasController.speechTakeStore = takeStoreWas;
      CanvasController.takePath = takePathWas;
    });

    const take = SpeechTake("said.wav", 1, [(text: "Hello", start: 0, end: 1)]);

    /// voiced is a canvas with a narrator whose one line is set out, and
    /// spoken where [spoken].
    CanvasDocument voiced({bool spoken = false}) {
      var line = const SpeechLine("Hello there.");
      return CanvasDocument(frames: 200, frameRate: 25, elements: [
        AudioElement(const ElementBase(id: "a", name: "Narrator"),
            clip: MediaClip(
                playlist: const [MediaSource(assetId: "t", length: 2)],
                timed: true,
                mix: ChannelMix(
                    speech: SpeechSpec(
                        script: "Hello there.",
                        lines: [spoken ? line.withSlot(0, take) : line])))),
      ]);
    }

    CanvasController make(CanvasDocument doc, [FakeEngine? engine]) {
      var c = CanvasController(doc,
          audioEngine: engine ?? FakeEngine({"t": 2, "said.wav": 1}));
      addTearDown(c.dispose);
      return c;
    }

    test("lines being spoken are not kept as the next canvas's takes",
        () async {
      var voice = _Gated();
      CanvasController.speechEngineFor = (_) => voice;
      var c = make(voiced());
      var speaking = c.speakLines("a");
      await pumpEventQueue();
      var line = c.speechOf("a")!.lines.single;
      expect(c.speechLineState("a", line), "speaking");

      c.load(voiced());
      expect(c.speechLineState("a", c.speechOf("a")!.lines.single), isNull,
          reason: "nothing of this canvas's is being spoken");
      voice.gate.complete();
      expect(await speaking, isNull);
      expect(c.speechOf("a")!.lines.single.takes, isEmpty,
          reason: "the last canvas's take is not this one's");
      expect(c.canUndo, isFalse);
      expect(c.dirty, isFalse);
    });

    test("lines joined are not put on the next canvas's timeline", () async {
      var gate = Completer<void>();
      CanvasController.takeAudio = (id) => _held(gate, _tone(1));
      var c = make(voiced(spoken: true));
      var joining = c.joinSpeech("a");
      await pumpEventQueue();
      expect(c.joining, contains("a"));

      c.load(voiced(spoken: true));
      expect(c.joining, isEmpty, reason: "nothing here is being joined");
      gate.complete();
      expect(await joining, isNull);
      expect(c.document.elements, hasLength(1), reason: "no clip added");
      expect(c.speechOf("a")!.takes, isEmpty);
      expect(listed, isEmpty, reason: "nor put in the library");
      expect(c.canUndo, isFalse);
    });

    test("a take saved lands on no slot of the next canvas", () async {
      var gate = Completer<void>();
      CanvasController.speechStore = (file) => _held(gate, "saved.wav");
      var c = make(voiced(spoken: true));
      var saving = c.addTake("a", 0, 0);
      await pumpEventQueue();

      c.load(voiced(spoken: true));
      gate.complete();
      expect(await saving, isNull);
      expect(c.speechOf("a")!.lines.single.slot(0)!.saved, isFalse);
      expect(c.document.elements, hasLength(1));
      expect(c.canUndo, isFalse);
    });

    test("a take still opening is not heard over the next canvas", () async {
      var gate = Completer<void>();
      CanvasController.takePath = (id) => _held(gate, "/takes/$id");
      var engine = FakeEngine({"t": 2, "said.wav": 1});
      var c = make(voiced(spoken: true), engine);
      var hearing = c.hearTake("said.wav");
      await pumpEventQueue();

      c.load(voiced(spoken: true));
      gate.complete();
      expect(await hearing, isNull);
      expect(c.speechHeard, isNull);
      expect(engine.voices.where((v) => v.alive), isEmpty);
    });

    test("a voice previewed is not heard over the next canvas", () async {
      var voice = _Gated();
      CanvasController.speechEngineFor = (_) => voice;
      var engine = FakeEngine({"t": 2, "voice-0.wav": 1});
      var c = make(voiced(), engine);
      var previewing = c.previewVoice("a", "v1");
      await pumpEventQueue();
      expect(c.speechPreviewing, "v1");

      c.load(voiced());
      expect(c.speechPreviewing, isNull);
      voice.gate.complete();
      expect(await previewing, isNull);
      expect(c.speechHeard, isNull);
      expect(engine.voices.where((v) => v.alive), isEmpty);
    });

    test("a take sung is not laid on the next canvas", () async {
      var gate = Completer<void>();
      CanvasController.takeAudio = (id) => _held(gate, _tone(1));
      CanvasDocument singer() =>
          CanvasDocument(frames: 400, frameRate: 25, elements: [
            const AudioElement(ElementBase(id: "a", name: "Singer"),
                clip: MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 1)],
                    timed: true,
                    mix: ChannelMix(
                        speech: SpeechSpec(script: "la la", takes: [
                          SpeechTake("take.wav", 1, [
                            (text: "la", start: 0.1, end: 0.4),
                            (text: "la", start: 0.5, end: 0.9),
                          ]),
                        ]),
                        vocaliser: VocaliserSpec(vibrato: 0)))),
            const AudioElement(ElementBase(id: "keys", name: "Tune"),
                clip: MediaClip(timed: true, at: 50),
                instrument: InstrumentPart(notes: [
                  MidiNote(60, 0.5, 0.5),
                  MidiNote(62, 1.0, 0.5),
                ])),
          ]);
      var c = make(singer(), FakeEngine({"t": 1}));
      var singing = c.sing("a");
      await pumpEventQueue();
      expect(c.singing, contains("a"));

      c.load(singer());
      expect(c.singing, isEmpty);
      gate.complete();
      expect(await singing, isNull);
      expect(c.document.elements, hasLength(2), reason: "no sung take laid");
      expect(c.canUndo, isFalse);
    });
  });

  test("cues found for a voice are not put on the next canvas", () async {
    // Its shape arrives after another canvas has opened.
    const asset = "late-cues.mp3";
    var voice = AudioElement(const ElementBase(id: "vo", visible: false),
        clip: const MediaClip(
            timed: true, playlist: [MediaSource(assetId: asset, length: 10)]));
    var doc = CanvasDocument(frames: 400, elements: [voice]);
    var c = CanvasController(doc);
    addTearDown(c.dispose);
    var finding = c.findCues(voice);
    c.load(doc);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    var peaks = Float32List(100);
    for (var i = 0; i < 100; i++) {
      peaks[i] = i >= 30 && i < 40 ? 0.0 : 0.6;
    }
    CanvasController.seedWaveform(asset, peaks);
    expect(await finding, 0);
    expect(c.cues, isEmpty);
    expect(c.canUndo, isFalse);
  });

  group("a MIDI file read", () {
    late Future<MidiImport?> Function(String) midiWas;
    late Completer<void> gate;
    setUp(() {
      gate = Completer<void>();
      midiWas = CanvasController.midiOfAsset;
      CanvasController.midiOfAsset =
          (id) => _held(gate, const MidiImport([MidiNote(60, 0, 0.5)], 0));
    });
    tearDown(() => CanvasController.midiOfAsset = midiWas);

    test("lands on no channel or slot of the next canvas", () async {
      CanvasDocument keys() => const CanvasDocument(
              frames: 400,
              frameRate: 25,
              audio: AudioSettings(tempo: 120),
              elements: [
                AudioElement(ElementBase(id: "keys", name: "Keys"),
                    clip: MediaClip(timed: true), instrument: InstrumentPart()),
              ]);
      var c = CanvasController(keys(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var jobs = [
        c.addMidiChannelFrom(const MediaSource(assetId: "tune.mid")),
        c.putMidiOn("keys", "tune.mid", 0),
        c.midiClipFromFile("keys", 0, "tune.mid"),
      ];
      await pumpEventQueue();

      c.load(keys());
      gate.complete();
      await Future.wait(jobs);
      expect(c.document.elements, hasLength(1), reason: "no channel made");
      var e = c.document.elementById("keys") as AudioElement;
      expect(e.instrument!.notes, isEmpty, reason: "no notes put on");
      expect(c.session.at("keys", 0), isNull, reason: "no slot filled");
      expect(c.canUndo, isFalse);
    });
  });

  group("a clip's sound worked on", () {
    late Future<(Float32List, Float32List)?> Function(String) audioWas;
    late Future<String?> Function(String) storeWas;
    late Completer<void> gate;
    setUp(() {
      gate = Completer<void>();
      audioWas = CanvasController.clipAudio;
      storeWas = CanvasController.speechStore;
      // A click a beat, so slicing at its hits finds some.
      CanvasController.clipAudio = (id) {
        var l = Float32List(mixRate * 4);
        for (var beat = 0; beat < 8; beat++) {
          var at = (beat * 0.5 * mixRate).round();
          for (var i = 0; i < 2400; i++) {
            l[at + i] = i.isEven ? 0.9 : -0.9;
          }
        }
        return _held(gate, (l, Float32List.fromList(l)));
      };
      CanvasController.speechStore = (file) async => "reversed.wav";
    });
    tearDown(() {
      CanvasController.clipAudio = audioWas;
      CanvasController.speechStore = storeWas;
    });

    CanvasDocument drums() {
      var doc = const CanvasDocument(
          frames: 600,
          frameRate: 60,
          audio: AudioSettings(tempo: 120),
          elements: [
            AudioElement(ElementBase(id: "a", name: "Drums"),
                clip: MediaClip(
                    playlist: [MediaSource(assetId: "beat.wav", length: 4)],
                    timed: true)),
          ]);
      return doc.copyWith(
          session: doc.session.put(
              "a",
              0,
              const SessionClip(
                  id: "bed",
                  name: "Bed",
                  sound: MediaSource(assetId: "beat.wav", length: 4),
                  bars: 2)));
    }

    CanvasController editing() {
      var c = CanvasController(drums(),
          audioEngine: FakeEngine({"beat.wav": 4, "reversed.wav": 4}));
      addTearDown(c.dispose);
      c.openClipEditor("a", 0);
      return c;
    }

    for (var (name, job)
        in <(String, Future<String?> Function(CanvasController))>[
      ("sliced", (c) => c.sliceClip(SliceBy.hits)),
      ("sliced onto pads", (c) => c.sliceToInstrument(pads: true)),
      ("reversed", (c) => c.reverseClip()),
      ("cropped", (c) => c.cropClip()),
      ("normalised", (c) => c.normaliseClip()),
      ("warped, its tempo heard first", (c) => c.setWarp(true)),
    ]) {
      test("$name: the next canvas, its clip of the same id, is left as it is",
          () async {
        var c = editing();
        var working = job(c);
        await pumpEventQueue();

        c.load(drums());
        gate.complete();
        expect(await working, isNull);
        expect(jsonEncode(c.document.toJson()), jsonEncode(drums().toJson()));
        expect(c.canUndo, isFalse);
      });
    }
  });

  group("saving", () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas-load-save");
      CanvasStorage.rootOverride = root.path;
    });
    tearDown(() async {
      CanvasStorage.rootOverride = null;
      await deleteTempDir(root);
    });

    test(
        "Save as finishing does not rename the next canvas or point it at "
        "the file", () async {
      var c = CanvasController(const CanvasDocument(title: "First"));
      addTearDown(c.dispose);
      var saving = c.saveAs("", "First");
      c.load(const CanvasDocument(title: "Second"));

      expect(await saving, isTrue, reason: "the first canvas was written");
      expect(c.name, isNull, reason: "the second has never been saved");
      expect(c.folder, isNull);
      expect(c.document.title, "Second");
      expect(c.dirty, isFalse);
    });

    test("a save finishing does not mark the next canvas unsaved", () async {
      var c = CanvasController(const CanvasDocument(title: "First"));
      addTearDown(c.dispose);
      expect(await c.saveAs("", "First"), isTrue);
      c.apply(c.document.copyWith(frames: 50));
      var saving = c.save();
      // An edit after the save began, then the next canvas.
      c.apply(c.document.copyWith(frames: 60));
      c.load(const CanvasDocument(title: "Second"), folder: "", name: "Second");

      expect(await saving, isTrue);
      expect(c.dirty, isFalse, reason: "nothing has been done to it");
    });
  });
}
