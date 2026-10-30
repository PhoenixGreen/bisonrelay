import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/espeak.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
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
class StubSpeech implements SpeechEngine {
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
          engine: SpeechEngineKind.cloud,
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
      expect(back.engine, SpeechEngineKind.cloud);
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
      expect(SpeechEngineKind.cloud.cues, SpeechCue.values);
      // A spec from before: the computer's voices are gone, and it opens
      // on our own.
      expect(SpeechSpec.fromJson({"engine": "system", "pitch": 3}).engine,
          SpeechEngineKind.local);
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

  group("ElevenLabs", () {
    test("is sent the script with its own tags, and its timing read back",
        () async {
      late Uri asked;
      late Map<String, String> headers;
      late Map<String, dynamic> sent;
      // Two samples of 24kHz PCM; "Hi you" timed a character at a time.
      var pcm = Uint8List(4)
        ..buffer.asByteData().setInt16(0, 16384, Endian.little)
        ..buffer.asByteData().setInt16(2, -16384, Endian.little);
      var engine = CloudSpeech("KEY", fetch: (method, url, h, body) async {
        asked = url;
        headers = h;
        sent = jsonDecode(body!) as Map<String, dynamic>;
        return (
          200,
          jsonEncode({
            "audio_base64": base64Encode(pcm),
            "alignment": {
              "characters": [..."[laughs] Hi you".split("")],
              "character_start_times_seconds": [
                for (var i = 0; i < 16; i++) i * 0.1
              ],
              "character_end_times_seconds": [
                for (var i = 0; i < 16; i++) i * 0.1 + 0.1
              ],
            },
          })
        );
      });
      var take = await engine.speak(const SpeechSpec(
          engine: SpeechEngineKind.cloud,
          voice: "abc",
          script: "[laugh] Hi [stress] you [pause 2]",
          expression: 0.3));
      expect(asked.path, "/v1/text-to-speech/abc/with-timestamps");
      expect(headers["xi-api-key"], "KEY");
      expect(sent["text"], "[laughs] Hi YOU [long pause]");
      expect(sent["voice_settings"]["style"], 0.3);
      expect(take.exact, isTrue);
      expect(take.words.map((w) => w.text), ["Hi", "you"],
          reason: "its tags left out");
      expect(take.words.first.start, closeTo(0.9, 1e-9));
      expect(take.l.length, 4, reason: "24kHz brought up to 48kHz");
      expect(take.l[1], closeTo(0, 1e-6), reason: "halfway between the two");
    });

    test("without a key, or with a wrong one, it says so", () async {
      expect(
          () =>
              CloudSpeech("").speak(const SpeechSpec(voice: "v", script: "x")),
          throwsA(isA<SpeechException>()));
      var engine = CloudSpeech("BAD", fetch: (m, u, h, b) async => (401, "{}"));
      expect(
          () => engine.speak(const SpeechSpec(voice: "v", script: "x")),
          throwsA(isA<SpeechException>()
              .having((e) => e.message, "message", contains("API key"))));
    });
  });

  group("on a channel", () {
    late StubSpeech stub;
    late SpeechEngine Function(SpeechSpec, String) engineWas;
    late Future<String?> Function(String) storeWas;

    setUp(() {
      // Our own voices downloaded, unless a test says not.
      KokoroDownload.instance.ready = true;
      stub = StubSpeech();
      engineWas = CanvasController.speechEngineFor;
      storeWas = CanvasController.speechStore;
      CanvasController.speechEngineFor = (spec, key) => stub;
      CanvasController.speechStore = (file) async => "take.wav";
    });

    tearDown(() {
      KokoroDownload.instance.ready = null;
      CanvasController.speechEngineFor = engineWas;
      CanvasController.speechStore = storeWas;
    });

    CanvasController make() => CanvasController(
        CanvasDocument(frames: 200, frameRate: 25, elements: [
          AudioElement(const ElementBase(id: "a", name: "Narrator"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 2)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 2}));

    test("Speak lays a take on the channel at the playhead, one undo",
        () async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("a", const SpeechSpec(script: "Hello world"));
      c.frame = 50;
      var before = c.document.elements.length;
      expect(await c.speak("a"), isNull);
      var added = c.document.elements.last as AudioElement;
      expect(c.document.elements, hasLength(before + 1));
      expect(added.clip.channel, "a");
      expect(added.clip.at, 50);
      expect(added.clip.playlist.single.assetId, "take.wav");
      var take = c.speechOf("a")!.takes.single;
      expect(take.words.map((w) => w.text), ["Hello", "world"]);
      expect(added.clip.mix.speech!.takes, hasLength(1),
          reason: "the new clip carries the channel's strip, take and all");
      c.undo();
      expect(c.document.elements, hasLength(before));
      expect(c.speechOf("a")!.takes, isEmpty);
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
      await tester.tap(find.byKey(const ValueKey("speechCue-slow")));
      await tester.pump();
      expect(c.speechOf("a")!.script, "Good evening. [slow] ");
      await tester.tap(find.byKey(const ValueKey("speechSpeak")));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(stub.spoken.single.voice, "v2");
      expect(c.speechOf("a")!.takes, hasLength(1));
      expect(find.textContaining("Take 1"), findsOneWidget);
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
      expect(find.text("Lines"), findsOneWidget, reason: "which document");
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey("speechScript")))
              .readOnly,
          isTrue);
      await tester.tap(find.byKey(const ValueKey("speechFromDocument")));
      await tester.pump();
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
      // Our own voices downloaded and not, and ElevenLabs.
      for (var (cloud, here) in [(false, true), (false, false), (true, true)]) {
        KokoroDownload.instance.ready = here;
        c.setSpeech(
            "a",
            SpeechSpec(
                script: "Hello",
                engine:
                    cloud ? SpeechEngineKind.cloud : SpeechEngineKind.local));
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
              reason: "cloud $cloud, voices here $here, at ${scale}x");
          expect(find.byKey(const ValueKey("speechDownload")),
              !cloud && !here ? findsOneWidget : findsNothing);
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
