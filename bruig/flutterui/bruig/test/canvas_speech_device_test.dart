import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/espeak.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/speech_device.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/ui/text_documents.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_speech_device_test.dart is the Speech device: a script with its
// cues, spoken by our own voices (Kokoro) or by ElevenLabs, put together as
// one take with its words timed, and laid on its channel as a clip.

/// StubSpeech is an engine that speaks a second of quiet tone, a word a
/// quarter of a second.
class StubSpeech extends SpeechEngine {
  final List<SpeechSpec> spoken = [];
  @override
  Future<List<SpeechVoice>> voices() async => const [
        SpeechVoice("v1", "Bella", "English (US)", gender: "f"),
        SpeechVoice("v2", "Adam", "English (US)", gender: "m"),
        SpeechVoice("v3", "Clara", "English (UK)", gender: "f"),
      ];
  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    spoken.add(spec);
    var l = Float32List(mixRate)..fillRange(0, mixRate, 0.1);
    var words = parseScript(spec.script)
        .whereType<SpokenText>()
        .expand((t) => t.words)
        .toList();
    return SpokenAudio(l, Float32List.fromList(l), [
      for (var (i, w) in words.indexed)
        (text: w, start: i * 0.25, end: i * 0.25 + 0.2),
    ]);
  }
}

/// _Held is an engine that does not finish until it is stopped.
class _Held extends StubSpeech {
  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    while (!stopper.stopped) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw const SpeechStopped();
  }
}

/// BatchSpeech is StubSpeech speaking a script's lines together, as Kokoro
/// does: each call to speakLines noted.
class BatchSpeech extends StubSpeech {
  final List<List<String>> batched = [];
  @override
  bool get batches => true;
  @override
  Future<List<SpokenAudio>> speakLines(
      SpeechSpec spec, List<SpeechLine> lines) async {
    batched.add([for (var l in lines) l.text]);
    return [
      for (var l in lines)
        await speak(spec.copyWith(script: lineScript(l), lines: const []))
    ];
  }
}

void main() {
  group("the script", () {
    test("is read as words, cues and silences", () {
      var pieces = parseScript(
          "Hello there. [pause 1.5] [laugh] [whisper] This is quiet. "
          "Then [stress] this word. [unknown] End");
      expect(pieces[0], isA<SpokenText>());
      expect((pieces[0] as SpokenText).text, "Hello there.");
      expect((pieces[1] as SpokenPause).seconds, 1.5);
      expect((pieces[2] as SpokenSound).cue, SpeechCue.laugh);
      var quiet = pieces[3] as SpokenText;
      expect(quiet.whisper, isTrue);
      expect(quiet.text, "This is quiet.",
          reason: "to the end of its sentence");
      var then = pieces[4] as SpokenText;
      expect(then.whisper, isFalse);
      expect(then.words[then.stressed.single], "this");
      expect(pieces.whereType<SpokenText>().last.text, contains("End"),
          reason: "a token it does not know is left out");
    });

    test("a spec and its takes are kept", () {
      var spec = const SpeechSpec(
          engine: SpeechEngineKind.expressive,
          voice: "v1",
          voiceName: "Bella",
          script: "Hi [laugh]",
          speed: 1.2,
          takes: [
            SpeechTake("take.wav", 1.5, [(text: "Hi", start: 0.1, end: 0.4)],
                exact: true)
          ]);
      var mix = ChannelMix(speech: spec);
      var back = ChannelMix.fromJson(mix.toJson()).speech!;
      expect(back.engine, SpeechEngineKind.expressive);
      expect(back.voiceName, "Bella");
      expect(back.speed, 1.2);
      expect(back.takes.single.words.single.text, "Hi");
      expect(back.takes.single.exact, isTrue);
    });

    test("words are spread across their stretch by their length", () {
      var w = estimateWords(["a", "longer"], 0, 1);
      expect(w.first.end, closeTo(w.last.start, 1e-9));
      expect(
          w.last.end - w.last.start, greaterThan(w.first.end - w.first.start));
      expect(w.last.end, closeTo(1, 1e-9));
    });

    test("a take is its pieces end to end, the words moved with them", () {
      var take = assembleTake([
        silence(0.5),
        (
          Float32List(mixRate),
          Float32List(mixRate),
          [(text: "hi", start: 0.1, end: 0.3)]
        ),
      ]);
      expect(take.seconds, closeTo(1.5, 1e-6));
      expect(take.words.single.start, closeTo(0.6, 1e-9));
    });

    test("each engine offers only the cues it can do", () {
      // Our own: every cue but a stressed word.
      expect(SpeechEngineKind.local.cues, [
        for (var c in SpeechCue.values)
          if (c != SpeechCue.stress) c
      ]);
      // The expressive voices: no stress, nor a slower stretch mid-line.
      expect(SpeechEngineKind.expressive.cues,
          isNot(anyOf(contains(SpeechCue.stress), contains(SpeechCue.slow))));
      // A spec from before: the computer's voices are gone, and it opens
      // on our own; ElevenLabs too, its voice with it.
      expect(SpeechSpec.fromJson({"engine": "system", "pitch": 3}).engine,
          SpeechEngineKind.local);
      var gone = SpeechSpec.fromJson(
          {"engine": "cloud", "voice": "21m00", "voiceName": "Rachel"});
      expect((gone.engine, gone.voice, gone.voiceName),
          (SpeechEngineKind.local, "", ""));
    });
  });

  group("our own voices", () {
    test("a voice at 24kHz is twice the rate, without mirrored highs", () {
      // A 5kHz tone: halfway samples read from the sound, not a straight
      // line between its samples -- which is off by a tenth of the tone.
      const hz = 5000.0;
      var x = Float32List(2400);
      for (var i = 0; i < x.length; i++) {
        x[i] = math.sin(2 * math.pi * hz * i / 24000);
      }
      var y = upsample2x(x);
      expect(y.length, 4800);
      var worst = 0.0;
      for (var i = 200; i < 4600; i++) {
        var want = math.sin(2 * math.pi * hz * i / 48000);
        worst = math.max(worst, (y[i] - want).abs());
      }
      expect(worst, lessThan(0.01));
    });

    test("they are Kokoro's voices, graded", () async {
      var voices = await KokoroSpeech().voices();
      expect(voices, hasLength(53),
          reason: "English and Chinese, and the six espeak-ng speaks for");
      expect(voices.first.name, "Emma");
      expect(voices.first.about, "UK woman · B-");
      var heart = voices.firstWhere((v) => v.id == "af_heart");
      expect(heart.about, "US woman · A");
      expect(heart.gender, "f");
      expect(voices.where((v) => v.about.startsWith("Chinese")), hasLength(8));
      expect(voices.map((v) => v.id).toSet(), hasLength(53));
      expect(voices.where((v) => v.about.startsWith("Japanese")), hasLength(5));
    });

    test("the download is each file checked, and a damaged one refused",
        () async {
      var root = await Directory.systemTemp.createTemp("kokoro-download");
      var dirWas = kokoroDir, filesWas = kokoroFilesOverride;
      var baseWas = kokoroBase;
      addTearDown(() async {
        kokoroDir = dirWas;
        kokoroFilesOverride = filesWas;
        kokoroBase = baseWas;
        await root.delete(recursive: true);
      });
      // A server of our own with the two files, one of them wrong.
      var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      // A widget test's binding answers every request 400: the real
      // network, for this one.
      var overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      var bodies = {"/a.txt": "hello", "/b.txt": "world"};
      server.listen((request) {
        var body = bodies[request.uri.path];
        request.response.statusCode = body == null ? 404 : 200;
        if (body != null) request.response.write(body);
        request.response.close();
      });
      kokoroBase = "http://127.0.0.1:${server.port}/";
      kokoroDir = () async => root.path;
      String hashOf(String text) =>
          sha256.convert(utf8.encode(text)).toString();
      kokoroFilesOverride = [
        (name: "a.txt", bytes: 5, sha256: hashOf("hello")),
        (name: "b.txt", bytes: 5, sha256: hashOf("there")),
      ];
      var shares = <double>[];
      expect(await downloadKokoro(progress: shares.add), contains("damaged"));
      expect(File("${root.path}/a.txt").existsSync(), isTrue);
      expect(File("${root.path}/b.txt").existsSync(), isFalse);
      expect(File("${root.path}/b.txt.part").existsSync(), isFalse);
      expect(await kokoroReady(), isFalse);
      bodies["/b.txt"] = "there";
      expect(await downloadKokoro(progress: shares.add), isNull);
      expect(await kokoroReady(), isTrue);
      expect(shares.last, 1);
    });

    test("Kokoro speaks a script's lines together, a take of each", () async {
      var dir = Platform.environment["CANVAS_KOKORO"];
      var lib = Platform.environment["CANVAS_SHERPA"];
      if (dir == null || lib == null) {
        markTestSkipped("no Kokoro model to hand");
        return;
      }
      var dirWas = kokoroDir;
      kokoroDir = () async => dir;
      KokoroSpeech.library = lib;
      addTearDown(() {
        kokoroDir = dirWas;
        KokoroSpeech.library = null;
      });
      var kokoro = KokoroSpeech();
      expect(kokoro.batches, isTrue);
      var lines = scriptLines(
          "Good evening.\n[whisper] It is a secret.\n[laughing] We won!");
      var takes =
          await kokoro.speakLines(const SpeechSpec(voice: "bf_emma"), lines);
      expect(takes, hasLength(3));
      expect([for (var t in takes) t.words.map((w) => w.text).join(" ")],
          ["Good evening.", "It is a secret.", "We won!"]);
      for (var t in takes) {
        expect(t.seconds, greaterThan(0.5));
      }
      // The laugh, a recording, before the words of the third.
      expect(takes[2].words.first.start, greaterThan(0.3));
    });

    test("Kokoro speaks the script, where its model is to hand", () async {
      // Run with CANVAS_KOKORO set to a folder of the model's files, and
      // CANVAS_SHERPA to sherpa_onnx_macos's macos folder.
      var dir = Platform.environment["CANVAS_KOKORO"];
      var lib = Platform.environment["CANVAS_SHERPA"];
      if (dir == null || lib == null) {
        markTestSkipped("no Kokoro model to hand");
        return;
      }
      var dirWas = kokoroDir;
      kokoroDir = () async => dir;
      KokoroSpeech.library = lib;
      addTearDown(() {
        kokoroDir = dirWas;
        KokoroSpeech.library = null;
      });
      // An American voice, and a Chinese one, speak too.
      for (var (voice, script) in [
        ("af_heart", "Decred launched in 2016."),
        ("zf_xiaoxiao", "你好，欢迎来到 Decred。"),
      ]) {
        var other = await KokoroSpeech()
            .speak(SpeechSpec(voice: voice, script: script));
        expect(other.seconds, greaterThan(1), reason: voice);
        expect(other.l.any((v) => v.abs() > 0.05), isTrue, reason: voice);
      }
      var take = await KokoroSpeech().speak(const SpeechSpec(
          voice: "bm_george",
          script: "Good evening. [pause 0.5] [laugh] [slow] And goodnight."));
      expect(take.words.map((w) => w.text),
          ["Good", "evening.", "And", "goodnight."]);
      expect(take.seconds, greaterThan(2));
      var peak = take.l.fold(0.0, (m, v) => math.max(m, v.abs()));
      expect(peak, inInclusiveRange(0.1, 1.0));
      // Between the two stretches: the pause, then the man's laugh.
      var laugh = (await cueRecording(SpeechCue.laugh, man: true))!;
      var gap = take.words[2].start - take.words[1].end;
      expect(gap, greaterThanOrEqualTo(0.5 + laugh.length / 48000));
      // Whispered, the same words: quieter, and no longer voiced.
      var said = await KokoroSpeech()
          .speak(const SpeechSpec(voice: "bf_emma", script: "Good evening."));
      var hushed = await KokoroSpeech().speak(const SpeechSpec(
          voice: "bf_emma", script: "[whisper] Good evening."));
      double rms(Float32List x) =>
          math.sqrt(x.fold(0.0, (s, v) => s + v * v) / x.length);
      expect(rms(hushed.l), lessThan(rms(said.l) * 0.8));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // Ken: the voices of Spanish, French, Hindi, Italian, Japanese and
  // Portuguese, with espeak-ng's help where it is installed -- never
  // bundled, it is GPL.
  group("with espeak-ng", () {
    late Directory scratch;
    late String fake;
    setUp(() {
      scratch = Directory.systemTemp.createTempSync("espeak");
      // A stand-in espeak-ng: how two words are said, the last argument.
      fake = "${scratch.path}/espeak-ng";
      File(fake).writeAsStringSync('''#!/bin/sh
for w in "\$@"; do word="\$w"; done
case "\$word" in
  hola) echo " ˈola" ;;
  amigos) echo " amˈiɣos" ;;
  *) exit 1 ;;
esac
''');
      Process.runSync("chmod", ["+x", fake]);
    });
    tearDown(() {
      forgetEspeakForTest();
      scratch.deleteSync(recursive: true);
    });

    test("its IPA is Kokoro's tokens; a word it cannot say left out", () {
      var tokens =
          readTokens("ˈ 156\no 56\nl 54\na 43\nm 55\ni 51\nɣ 139\ns 61\n");
      expect(espeakSounds(" t͡ʃˈola\n", tokens), "ˈ o l a",
          reason: "tie bars, spaces and what has no token taken out");
      expect(espeakLexicon(fake, "es", ["hola", "amigos", "xyz"], tokens), {
        "hola": "ˈ o l a",
        "amigos": "a m ˈ i ɣ o s",
      });
    });

    test("its voices say they need it, until it is there", () async {
      useEspeakForTest(null);
      var without = await KokoroSpeech().voices();
      var dora = without.firstWhere((v) => v.id == "ef_dora");
      expect(dora.about, "Spanish woman · needs espeak-ng");
      expect(without.firstWhere((v) => v.id == "bf_emma").about,
          isNot(contains("espeak")));
      expect(needsEspeak("jf_alpha"), isTrue);
      expect(needsEspeak("af_heart"), isFalse);
      useEspeakForTest(fake);
      var withIt = await KokoroSpeech().voices();
      expect(withIt.firstWhere((v) => v.id == "ff_siwis").about,
          "French woman · B-");
      expect(withIt.length, 53, reason: "every one of Kokoro's voices");
    });

    test("spoken without it, the voice says how to get it", () async {
      useEspeakForTest(null);
      var dirWas = kokoroDir;
      kokoroDir = () async => scratch.path;
      addTearDown(() => kokoroDir = dirWas);
      // kokoroReady is asked first: a model there, of no size, is not.
      await expectLater(
          KokoroSpeech()
              .speak(const SpeechSpec(voice: "ef_dora", script: "hola")),
          throwsA(isA<SpeechException>()));
    });

    test("Spanish spoken, where the model is to hand", () async {
      var dir = Platform.environment["CANVAS_KOKORO"];
      var lib = Platform.environment["CANVAS_SHERPA"];
      if (dir == null || lib == null) {
        markTestSkipped("no Kokoro model to hand");
        return;
      }
      var dirWas = kokoroDir;
      kokoroDir = () async => dir;
      KokoroSpeech.library = lib;
      addTearDown(() {
        kokoroDir = dirWas;
        KokoroSpeech.library = null;
      });
      useEspeakForTest(fake);
      var take = await KokoroSpeech()
          .speak(const SpeechSpec(voice: "ef_dora", script: "Hola amigos."));
      expect(take.seconds, greaterThan(0.8));
      expect(take.l.any((v) => v.abs() > 0.05), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group("on a channel", () {
    late StubSpeech stub;
    late SpeechEngine Function(SpeechSpec) engineWas;
    late Future<String?> Function(String) storeWas;
    late Future<Float32List?> Function(String) audioWas;
    late Future<void> Function(String, String, double) libraryWas;
    late Future<void> Function(String) unlistWas;
    late Future<String?> Function(Uint8List) takeStoreWas;
    late Future<String?> Function(String) takePathWas;
    // What the Audio library was given, and had taken off its list.
    var listed = <String, String>{};
    var unlisted = <String>[];

    setUp(() {
      // Our own voices downloaded, unless a test says not.
      KokoroDownload.instance.ready = true;
      stub = StubSpeech();
      engineWas = CanvasController.speechEngineFor;
      storeWas = CanvasController.speechStore;
      audioWas = CanvasController.takeAudio;
      CanvasController.speechEngineFor = (spec) => stub;
      var kept = 0;
      CanvasController.speechStore = (file) async => "take${++kept}.wav";
      CanvasController.takeAudio =
          (id) async => Float32List(mixRate)..fillRange(0, mixRate, 0.1);
      libraryWas = CanvasController.speechLibrary;
      unlistWas = CanvasController.speechUnlist;
      listed = {};
      unlisted = [];
      CanvasController.speechLibrary =
          (id, name, seconds) async => listed[id] = name;
      CanvasController.speechUnlist = (id) async => unlisted.add(id);
      takeStoreWas = CanvasController.speechTakeStore;
      takePathWas = CanvasController.takePath;
      var lines = 0;
      CanvasController.speechTakeStore = (wav) async => "line${++lines}.wav";
      CanvasController.takePath = (id) async => "/kept/$id";
    });

    tearDown(() {
      KokoroDownload.instance.ready = null;
      CanvasController.speechEngineFor = engineWas;
      CanvasController.speechStore = storeWas;
      CanvasController.takeAudio = audioWas;
      CanvasController.speechLibrary = libraryWas;
      CanvasController.speechUnlist = unlistWas;
      CanvasController.speechTakeStore = takeStoreWas;
      CanvasController.takePath = takePathWas;
    });

    CanvasController make() => CanvasController(
        CanvasDocument(frames: 200, frameRate: 25, elements: [
          AudioElement(const ElementBase(id: "a", name: "Narrator"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 2)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 2}));

    test(
        "Speak all fills a slot of each line -- nothing on the timeline, "
        "nothing in the library -- and Add all lines joins them, one undo",
        () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a",
          const SpeechSpec(script: "Hello world.\n[laughing] Good night."));
      c.frame = 50;
      var before = c.document.elements.length;
      expect(await c.speakLines("a"), isNull);
      expect(stub.spoken.map((s) => s.script),
          ["Hello world.", "[laugh] Good night."],
          reason: "a line at a time, its direction Kokoro's nearest cue");
      var spec = c.speechOf("a")!;
      expect(spec.lines.map((l) => (l.slot(0)?.assetId, l.chosen)),
          [("line1.wav", 0), ("line2.wav", 0)]);
      expect(spec.lines.first.slot(0)!.saved, isFalse);
      expect(c.document.elements, hasLength(before),
          reason: "only by asking is anything put on the timeline");
      expect(listed, isEmpty, reason: "nor in the Audio library");
      // Add all lines: each line's picked take, joined.
      expect(await c.joinSpeech("a"), isNull);
      spec = c.speechOf("a")!;
      var added = c.document.elements.last as AudioElement;
      expect(c.document.elements, hasLength(before + 1));
      expect(added.clip.channel, "a");
      expect(added.clip.at, 50);
      expect(added.id, spec.clip);
      var joined = spec.takes.single;
      expect(added.clip.playlist.single.assetId, joined.assetId);
      expect(joined.words.map((w) => w.text),
          ["Hello", "world.", "Good", "night."]);
      expect(joined.words[2].start, greaterThan(1.2),
          reason: "the second line after the first and a pause");
      expect(added.clip.mix.speech!.takes, hasLength(1),
          reason: "the new clip carries the channel's strip, take and all");
      expect(added.clip.mediaIds, containsAll(["line1.wav", "line2.wav"]),
          reason: "the lines' takes are kept with the canvas");
      expect(
          listed, {joined.assetId: "Speech · voice · Hello world. Good night."},
          reason: "the clip in the library; the lines' takes not");
      c.undo();
      expect(c.document.elements, hasLength(before));
      expect(c.speechOf("a")!.takes, isEmpty);
      expect(c.speechOf("a")!.lines.first.slot(0), isNotNull,
          reason: "the slots stay: only the reader empties one");
    });

    test(
        "slots: another take fills the next free one; full, it asks; "
        "Replace speaks into the one picked; Remove empties it", () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a", const SpeechSpec(script: "One.\nTwo."));
      await c.speakLines("a");
      for (var i = 0; i < 2; i++) {
        var line = c.speechOf("a")!.lines.first;
        expect(await c.anotherTake("a", line), isNull);
      }
      var line = c.speechOf("a")!.lines.first;
      expect([for (var i = 0; i < 3; i++) line.slot(i)?.assetId],
          ["line1.wav", "line3.wav", "line4.wav"]);
      expect(line.chosen, 2, reason: "the new take, picked");
      expect(await c.anotherTake("a", line), contains("All three slots"),
          reason: "a take is only replaced by the reader");
      expect(stub.spoken, hasLength(4));
      // Replace B.
      expect(await c.replaceTake("a", 0, 1), isNull);
      line = c.speechOf("a")!.lines.first;
      expect([for (var i = 0; i < 3; i++) line.slot(i)?.assetId],
          ["line1.wav", "line5.wav", "line4.wav"]);
      expect(line.chosen, 1);
      // Picked: no change to the timeline.
      var count = c.document.elements.length;
      c.chooseTake("a", 0, 0);
      expect(c.speechOf("a")!.lines.first.chosen, 0);
      expect(c.document.elements, hasLength(count));
      // Removed: one undo.
      c.removeTake("a", 0, 2);
      expect(c.speechOf("a")!.lines.first.slot(2), isNull);
      c.undo();
      expect(c.speechOf("a")!.lines.first.slot(2)?.assetId, "line4.wav");
      // A slot free again, Another take fills it -- the one picked, where
      // it is free.
      c.removeTake("a", 0, 1);
      expect(await c.anotherTake("a", c.speechOf("a")!.lines.first, slot: 1),
          isNull);
      expect(c.speechOf("a")!.lines.first.slot(1)?.assetId, "line6.wav");
    });

    test(
        "a slot's take saved, or put on the timeline: then, and only then, "
        "in the Audio library", () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a", const SpeechSpec(voiceName: "Emma", script: "One."));
      await c.speakLines("a");
      var (saved, problem) = await c.saveTake("a", 0, 0);
      expect(problem, isNull);
      expect(saved!.saved, isTrue);
      expect(listed, {saved.assetId: "Emma · line 1 · take A · One."});
      expect(c.speechOf("a")!.lines.single.slot(0)!.assetId, saved.assetId);
      // On the timeline: a clip of its own at the playhead, kept with the
      // device for lip sync -- saved once, not again.
      c.frame = 20;
      var before = c.document.elements.length;
      expect(await c.addTake("a", 0, 0), isNull);
      var clip = c.document.elements.last as AudioElement;
      expect(c.document.elements, hasLength(before + 1));
      expect((clip.clip.at, clip.clip.playlist.single.assetId),
          (20, saved.assetId));
      expect(c.speechOf("a")!.takes.map((t) => t.assetId), [saved.assetId]);
      expect(listed, hasLength(1));
      c.undo();
      expect(c.document.elements, hasLength(before));
      // Emptied, the library keeps its copy.
      c.removeTake("a", 0, 0);
      expect(c.speechOf("a")!.lines.single.slot(0), isNull);
      expect(listed, hasLength(1));
    });

    test("slots kept in their places, through saving and opening", () {
      const a = SpeechTake("a.wav", 1, []);
      const c = SpeechTake("c.wav", 1, [], saved: true);
      var line = const SpeechLine("x").withSlot(0, a).withSlot(2, c);
      expect([for (var i = 0; i < 3; i++) line.slot(i)?.assetId],
          ["a.wav", null, "c.wav"]);
      expect((line.chosen, line.freeSlot), (2, 1));
      // Emptying the one picked picks another in use.
      expect(line.withSlot(2, null).chosen, 0);
      var back = SpeechLine.fromJson(line.toJson())!;
      expect([for (var i = 0; i < 3; i++) back.slot(i)?.assetId],
          ["a.wav", null, "c.wav"]);
      expect((back.chosen, back.slot(2)!.saved), (2, true));
      // From before there were slots: its takes, A on.
      var old = SpeechLine.fromJson({
        "text": "x",
        "takes": [a.toJson(), c.toJson()],
        "chosen": 1
      })!;
      expect([for (var i = 0; i < 3; i++) old.slot(i)?.assetId],
          ["a.wav", "c.wav", null]);
      expect(old.chosen, 1);
      // Said another way, its words the same: its slots stay.
      var typed = scriptLines("[sad] x", [line]);
      expect(typed.single.slot(0)?.assetId, "a.wav");
    });

    group("heard on its own", () {
      late Future<String?> Function(String) pathWas;
      late FakeEngine engine;
      setUp(() {
        pathWas = CanvasController.takePath;
        CanvasController.takePath = (id) async => "/takes/$id";
      });
      tearDown(() => CanvasController.takePath = pathWas);

      CanvasController hearing() {
        engine = FakeEngine({"t": 2, "take1.wav": 2, "voice-0.wav": 1.5});
        return CanvasController(
            CanvasDocument(frames: 200, frameRate: 25, elements: [
              AudioElement(const ElementBase(id: "a", name: "Narrator"),
                  clip: const MediaClip(
                      playlist: [MediaSource(assetId: "t", length: 2)],
                      timed: true)),
            ]),
            audioEngine: engine);
      }

      test("a take, played and stopped, outside the mix", () async {
        var c = hearing();
        addTearDown(c.dispose);
        expect(await c.hearTake("take1.wav"), isNull);
        expect(c.speechHeard, "take1.wav");
        var voice = engine.last;
        expect(voice.alive, isTrue);
        expect(engine.onChannel[voice], isNull,
            reason: "not through a channel");
        // Pressed again, it stops.
        expect(await c.hearTake("take1.wav"), isNull);
        expect(c.speechHeard, isNull);
        expect(voice.alive, isFalse);
        expect(await c.hearTake("gone.wav"), contains("could not be played"));
      });

      test("a voice previewed in the device's feel, spoken once", () async {
        var c = hearing();
        addTearDown(c.dispose);
        c.setSpeech("a", const SpeechSpec(voice: "v2", room: 0.4));
        expect(await c.previewVoice("a", "v1"), isNull);
        expect(stub.spoken.single.voice, "v1", reason: "the voice asked for");
        expect(stub.spoken.single.script, CanvasController.speechSample);
        expect(c.speechHeard, "voice:v1");
        expect(c.speechOf("a")!.voice, "v2", reason: "not picked by hearing");
        expect(listed, isEmpty, reason: "nothing kept in the library");
        // Again: stopped; and again: heard, not spoken again.
        await c.previewVoice("a", "v1");
        expect(c.speechHeard, isNull);
        await c.previewVoice("a", "v1");
        expect(c.speechHeard, "voice:v1");
        expect(stub.spoken, hasLength(1));
        // Another feel is another preview.
        c.setSpeech("a", c.speechOf("a")!.copyWith(room: 0));
        c.stopHearing();
        await c.previewVoice("a", "v1");
        expect(stub.spoken, hasLength(2));
      });
    });

    test("an engine that speaks lines together is given them together",
        () async {
      var batch = BatchSpeech();
      CanvasController.speechEngineFor = (spec) => batch;
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a", const SpeechSpec(script: "One.\nTwo.\nThree."));
      expect(await c.speakLines("a"), isNull);
      expect(
          batch.batched,
          [
            ["One.", "Two.", "Three."]
          ],
          reason: "one call, the voice loaded once");
      var spec = c.speechOf("a")!;
      expect([for (var l in spec.lines) l.takes.length], [1, 1, 1]);
      expect({for (var l in spec.lines) l.take!.assetId}, hasLength(3),
          reason: "a take of each, kept apart");
      expect(spec.takes, isEmpty, reason: "nothing on the timeline unasked");
      // Another take of one line: that line alone.
      expect(await c.anotherTake("a", spec.lines[1]), isNull);
      expect(batch.batched.last, ["Two."]);
    });

    test("lines joined and split by hand, the script written from them", () {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a",
          const SpeechSpec(script: "[warm] Hello there, my friend.\nBye."));
      c.joinSpeechLine("a", 0);
      var spec = c.speechOf("a")!;
      expect(spec.lines.single.text, "Hello there, my friend. Bye.");
      expect(spec.lines.single.direction, SpeechDirection.warm);
      expect(spec.script, "[warm] Hello there, my friend. Bye.");
      // Typed again, a section joined by hand is kept whole.
      var typed = spec.withScript(spec.script);
      expect(typed.lines, hasLength(1));
      c.splitSpeechLine("a", 0);
      spec = c.speechOf("a")!;
      expect(spec.lines.map((l) => l.text), ["Hello there, my friend.", "Bye."],
          reason: "at a sentence's end, before a comma");
      expect(spec.lines.map((l) => l.direction),
          [SpeechDirection.warm, SpeechDirection.warm]);
      expect(spec.script, "[warm] Hello there, my friend.\n[warm] Bye.");
      // One sentence: at the comma nearest its middle.
      c.setSpeech("a", const SpeechSpec(script: "Hello there, my friend"));
      c.splitSpeechLine("a", 0);
      expect(c.speechOf("a")!.lines.map((l) => l.text),
          ["Hello there,", "my friend"]);
    });

    testWidgets("added from the effects, spoken, and seen on the strip",
        (tester) async {
      var c = make();
      c.openEffects("a");
      tester.view.physicalSize = const Size(1600, 900);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 380,
                                  onResize: (_) {},
                                  onClose: () {}),
                              CanvasMixer(
                                  controller: c,
                                  height: 420,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("addDevice-speech")));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.speechOf("a"), isNotNull);
      expect(find.byKey(const ValueKey("device-speech")), findsOneWidget);
      // A voice from the list -- once the chain has scrolled to the device:
      // a list being scrolled takes no presses.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey("speechVoice-v2")));
      await tester.pump();
      expect(c.speechOf("a")!.voiceName, "Adam");
      // The script typed, and a cue put in after it.
      await tester.enterText(
          find.byKey(const ValueKey("speechScript")), "Good evening.");
      await tester.pump();
      // Our own voices offer only the cues they can do: no stress.
      expect(find.byKey(const ValueKey("speechCue-stress")), findsNothing);
      expect(find.byKey(const ValueKey("speechCue-laugh")), findsOneWidget);
      // The cues scroll sideways: the last one brought into view.
      await tester.ensureVisible(find.byKey(const ValueKey("speechCue-slow")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechCue-slow")));
      await tester.pump();
      expect(c.speechOf("a")!.script, "Good evening. [slow] ");
      expect(c.speechOf("a")!.lines.single.text, "Good evening. [slow]",
          reason: "a cue on its own stays with the words before it");
      await tester.tap(find.byKey(const ValueKey("speechSpeak")));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(stub.spoken.single.voice, "v2");
      expect(c.speechOf("a")!.lines.single.slot(0), isNotNull,
          reason: "the line's take, in its first slot");
      expect(c.speechOf("a")!.takes, isEmpty,
          reason: "nothing on the timeline until it is added");
      expect(
          find.textContaining("1 of 1 sections with a take"), findsOneWidget);
      // On the channel's strip, its slot.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("strip-a")),
              matching: find.byKey(const ValueKey("speechSlot"))),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets("Stop lets go of a voice that takes too long", (tester) async {
      var held = _Held();
      CanvasController.speechEngineFor = (_) => held;
      var c = make();
      c.openEffects("a");
      c.setSpeech("a",
          const SpeechSpec(voice: "v1", script: "Hello there.\nGood night."));
      tester.view.physicalSize = const Size(1600, 900);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 380,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey("speechStop")), findsNothing,
          reason: "nothing to stop");
      String? problem = "not done";
      unawaited(c.speakLines("a").then((p) => problem = p));
      await tester.pump();
      // While it speaks, Speak all is Stop.
      expect(find.byKey(const ValueKey("speechSpeak")), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey("speechStop")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechStop")));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(held.stopper.stopped, isTrue, reason: "the engine told");
      expect(problem, isNull, reason: "stopped as asked: nothing to say");
      expect(c.speechQueue["a"], isNull, reason: "the sections waiting too");
      expect(c.speechOf("a")!.lines.every((l) => l.take == null), isTrue,
          reason: "nothing part made kept");
      expect(find.byKey(const ValueKey("speechSpeak")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // The script read from a Writing Tools document, kept up to date.
    test("read from a Writing document, and kept up to date", () async {
      var root = Directory.systemTemp.createTempSync("speech-doc");
      PostStorage.rootOverride = root.path;
      addTearDown(() {
        PostStorage.rootOverride = null;
        root.deleteSync(recursive: true);
      });
      var name = await PostStorage.write("", "Lines", "Hello **there**.");
      var c = make();
      addTearDown(c.dispose);
      expect(wantsDocumentPoll(c.document, controller: c), isFalse);
      c.setSpeech(
          "a",
          SpeechSpec(
              script: "Typed",
              document: TextDocumentRef(name: name!, wasText: "Typed")));
      expect(wantsDocumentPoll(c.document, controller: c), isTrue);
      expect(await refreshTextDocuments(c), isTrue);
      expect(c.speechOf("a")!.script, "Hello there.",
          reason: "as plain text: its marks taken out");
      await PostStorage.write("", name, "Good night.");
      await refreshTextDocuments(c);
      expect(c.speechOf("a")!.script, "Good night.");
      var kept = SpeechSpec.fromJson(c.speechOf("a")!.toJson());
      expect((kept.document.name, kept.document.wasText), (name, "Typed"));
    });

    testWidgets(
        "From document: read-only while it reads one; the typed "
        "script back after", (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech(
          "a",
          const SpeechSpec(
              script: "From the page",
              document: TextDocumentRef(name: "Lines", wasText: "Typed")));
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.5]) {
        await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false),
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  // Rebuilt as the effects chain rebuilds it.
                  body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Align(
                      alignment: Alignment.topLeft,
                      child: SpeechDevice(
                          controller: c,
                          channel: "a",
                          folded: false,
                          onFold: () {},
                          height: 260),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "at ${scale}x");
      }
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("speechDocument")))
              .data,
          "Lines",
          reason: "which document");
      // Its lines, until it is shown as text.
      expect(find.byKey(const ValueKey("speechLines")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("speechAsText")));
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey("speechScript")))
              .readOnly,
          isTrue);
      // Typed here again, from the dropdown.
      await tester.tap(find.byKey(const ValueKey("speechFromDocument")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Typed here").last);
      await tester.pumpAndSettle();
      expect(c.speechOf("a")!.document.on, isFalse);
      expect(c.speechOf("a")!.script, "Typed");
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey("speechScript")))
              .readOnly,
          isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("Speak and Sing stay in reach at a larger text size",
        (tester) async {
      // Ken's text is larger than the default: the controls above each
      // button scroll in what room is left, and nothing overflows.
      var c = make();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Our own voices downloaded and not, and the expressive voices.
      for (var (engine, here) in [
        (SpeechEngineKind.local, true),
        (SpeechEngineKind.local, false),
        (SpeechEngineKind.expressive, true),
      ]) {
        KokoroDownload.instance.ready = here;
        QwenDownload.instance.ready = here;
        c.setSpeech("a", SpeechSpec(script: "Hello", engine: engine));
        c.setVocaliser("a", const VocaliserSpec());
        for (var scale in [1.0, 1.15, 1.25, 1.5]) {
          await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: MaterialApp(
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SpeechDevice(
                              controller: c,
                              channel: "a",
                              folded: false,
                              onFold: () {},
                              height: 260),
                          VocaliserDevice(
                              controller: c,
                              channel: "a",
                              folded: false,
                              onFold: () {},
                              height: 260),
                        ]),
                  ),
                ),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: "$engine, voices here $here, at ${scale}x");
          expect(find.byKey(const ValueKey("speechDownload")),
              here ? findsNothing : findsOneWidget);
          for (var button in ["speechSpeak", "vocaliserSing"]) {
            var rect = tester.getRect(find.byKey(ValueKey(button)));
            expect(rect.bottom, lessThanOrEqualTo(260),
                reason: "$button at ${scale}x");
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
