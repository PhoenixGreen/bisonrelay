import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_finish.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/speech_device.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_expressive_speech_test.dart is the Speech device line by line:
// the script cut into lines, each with how it is said; the expressive
// voices (Qwen3-TTS), run once for each line; the finish the joined lines
// are given; and the device's lines and feel, at every text size.

/// _wav24k is a mono 16-bit WAV at 24kHz, [seconds] of quiet tone, as the
/// expressive voices' program writes.
Uint8List _wav24k(double seconds) => _wav24kOf([seconds]);

/// _wav24kOf is one of tone and exact silence by turns: each part its
/// seconds, of tone or, negative, of silence -- as the program writes a run
/// with pauses in it.
Uint8List _wav24kOf(List<double> parts) {
  var samples = <int>[];
  for (var p in parts) {
    var m = (p.abs() * 24000).round();
    for (var i = 0; i < m; i++) {
      samples.add(p > 0 ? 1000 + (3000 * math.sin(i * 0.05)).round() : 0);
    }
  }
  var n = samples.length;
  var b = ByteData(44 + n * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, "RIFF");
  b.setUint32(4, 36 + n * 2, Endian.little);
  tag(8, "WAVE");
  tag(12, "fmt ");
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, "data");
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  group("lines", () {
    test("the script cut at sentences, each line's direction at its start", () {
      var lines = scriptLines("[warm] Hello there. How are you?\n"
          "[say: tired, at the end of a long day] Fine. [laugh]\n\n"
          "[breath] Right.");
      expect(lines.map((l) => l.text),
          ["Hello there.", "How are you?", "Fine. [laugh]", "[breath] Right."]);
      expect(lines.map((l) => l.direction), [
        SpeechDirection.warm,
        SpeechDirection.plain,
        SpeechDirection.plain,
        SpeechDirection.plain,
      ]);
      expect(lines[2].own, "tired, at the end of a long day");
      expect(lines[2].say, "tired, at the end of a long day");
      expect(lines[0].say, SpeechDirection.warm.say);
      expect(lines[2].written,
          "[say: tired, at the end of a long day] Fine. [laugh]");
    });

    test("typed again, the lines unchanged keep their takes", () {
      const take = SpeechTake("t1", 1, []);
      var spec = const SpeechSpec(script: "One. Two.").withScript("One. Two.");
      spec = spec.copyWith(lines: [
        spec.lines[0].copyWith(takes: [take], chosen: 0),
        spec.lines[1],
      ]);
      var typed = spec.withScript("One. Two and three.");
      expect(typed.lines.first.takes.single.assetId, "t1");
      expect(typed.lines.first.chosen, 0);
      expect(typed.lines.last.takes, isEmpty);
      // A new direction is a new line: spoken again.
      expect(spec.withScript("[sad] One. Two.").lines.first.takes, isEmpty);
    });

    test("a direction in the reader's own words is never spoken", () {
      var pieces = parseScript("[say: softly, please] Hello [warm] there");
      expect(pieces.whereType<SpokenText>().expand((t) => t.words),
          ["Hello", "there"]);
    });

    test("lines, takes and the feel are kept", () {
      var spec = const SpeechSpec(
        engine: SpeechEngineKind.expressive,
        voice: "serena",
        script: "[nervous] Hi.",
        language: "French",
        room: 0.6,
        boost: false,
        preset: "custom",
        clip: "e1",
      ).withScript("[nervous] Hi.");
      spec = spec.copyWith(lines: [
        spec.lines.single.copyWith(takes: [
          const SpeechTake("a", 1.5, [(text: "Hi.", start: 0, end: 0.4)]),
          const SpeechTake("b", 1.2, []),
        ], chosen: 1),
      ]);
      var back = SpeechSpec.fromJson(spec.toJson());
      expect(back.engine, SpeechEngineKind.expressive);
      expect((back.language, back.room, back.boost, back.preset, back.clip),
          ("French", 0.6, false, "custom", "e1"));
      var line = back.lines.single;
      expect((line.text, line.direction), ("Hi.", SpeechDirection.nervous));
      expect((line.takes.length, line.chosen, line.take!.assetId), (2, 1, "b"));
      // A device from before there were lines: its script, cut.
      var old = SpeechSpec.fromJson({"script": "One. Two."});
      expect(old.lines, isEmpty);
      expect(old.shownLines.map((l) => l.text), ["One.", "Two."]);
      expect((old.room, old.boost, old.preset), (0.0, true, "natural"),
          reason: "dry: a room was heard as an echo");
    });

    test("a preset sets the feel", () {
      var spec = const SpeechSpec().withPreset(SpeechPreset.drama);
      expect((spec.speed, spec.steadiness, spec.expression, spec.room),
          (0.99, 0.25, 0.85, 0.15));
      expect((spec.boost, spec.preset), (true, "drama"));
    });

    test("a line that runs on, or stops short, is known", () {
      expect(speechRunsOn(2.0, 5, 1), isFalse);
      expect(speechRunsOn(20.0, 5, 1), isTrue);
      expect(speechRunsOn(0.2, 10, 1), isTrue);
    });
  });

  group("the expressive voices", () {
    test("nine voices, ten languages, a program for this computer", () {
      expect(qwenVoices, hasLength(9));
      expect(qwenVoices.map((v) => v.id), contains("uncle_fu"));
      expect(qwenLanguages, hasLength(10));
      var files = qwenFiles;
      expect(files.where((f) => f.executable).length, qwenSupported ? 1 : 0);
      expect(files.where((f) => f.path == "model.safetensors").single.bytes,
          3833402552);
      for (var f in files) {
        expect(f.sha256, hasLength(64), reason: f.path);
        expect(f.url, startsWith("https://"), reason: f.path);
      }
      expect(qwenBytes, greaterThan(4e9));
    });

    test("the feel is the program's temperature, nucleus, rate and wording",
        () {
      var sad = qwenDirection(
          const SpeechLine("Hello there.", direction: SpeechDirection.sad),
          0.8);
      expect(
          sad, "${SpeechDirection.sad.say} Make it vivid and strongly felt.");
      var steady = qwenArguments(
          "/m",
          const SpeechSpec(
              voice: "aiden", language: "German", speed: 1.2, steadiness: 1),
          sad,
          "Hello there.",
          "/o.wav",
          seed: 4);
      String after(List<String> a, String flag) => a[a.indexOf(flag) + 1];
      expect(after(steady, "-s"), "aiden");
      expect(after(steady, "-l"), "German");
      expect(after(steady, "-T"), "0.95");
      expect(after(steady, "-p"), "0.90");
      expect(after(steady, "--rate"), "1.20");
      expect(after(steady, "--seed"), "4");
      expect(after(steady, "--instruct"), sad);
      expect(after(steady, "--text"), "Hello there.");
      expect(steady, containsAll(["--int8", "-S"]));
      expect(steady, isNot(contains("--serve")),
          reason: "its server listens on every network");
      var loose = qwenArguments(
          "/m",
          const SpeechSpec(voice: "kokoro-only", speed: 1, steadiness: 0),
          "",
          "Hi. [pause:0.6s] There.",
          "/o.wav",
          seed: 1,
          compose: true);
      expect(after(loose, "-s"), "ryan", reason: "a voice it has");
      expect(after(loose, "-l"), "English");
      expect(after(loose, "-T"), "1.05");
      expect(after(loose, "-p"), "1.00");
      expect(after(loose, "--compose"), "Hi. [pause:0.6s] There.");
      expect(loose, isNot(contains("--rate")));
      expect(loose, isNot(contains("--instruct")),
          reason: "as written, said as it comes");
      expect(qwenDirection(const SpeechLine("x", own: "very tired"), 0.1),
          "very tired Keep it subtle and understated.");
    });

    test("at the middle, the engine's own: freer with a direction", () {
      // Lower flattened a direction into the line said as written.
      expect(qwenSampling(0.5, directed: true), (1.1, 1.0));
      expect(qwenSampling(0.5, directed: false).$1, closeTo(0.9, 1e-9));
      expect(qwenSampling(1, directed: false).$2, closeTo(0.9, 1e-9));
    });

    test("lines and their cues, as one run's markup", () {
      var script = qwenScript(scriptLines(
          "Hi. [laugh]\n[cough] So [pause 0.2] we [whisper] go now."));
      expect(script.text,
          "Hi. [pause:1.2s] So [pause:0.6s] we [pause:0.6s] go now.");
      expect(script.spoken, [
        ("Hi.", false),
        ("So", false),
        ("we", false),
        ("go now.", true),
      ]);
      expect(script.markers, 3);
      expect(script.gaps.first, isEmpty);
      expect(script.gaps[1].map((g) => g.runtimeType),
          [QwenSound, QwenLineEnd, QwenSound],
          reason: "the laugh ends the first line, the cough starts the next");
      expect(script.gaps[3].single, isA<QwenJoin>(),
          reason: "the whisper starts there");
      // The program's own markup is not the reader's to write.
      expect(qwenScript(scriptLines("A | B")).text, "A , B");
    });

    test("a take cut at its exact silences, and only those", () {
      Float32List pcm(List<double> parts) {
        var out = <double>[];
        for (var p in parts) {
          var n = (p.abs() * 24000).round();
          for (var i = 0; i < n; i++) {
            out.add(p > 0 ? 0.1 + 0.05 * math.sin(i * 0.3) : 0);
          }
        }
        return Float32List.fromList(out);
      }

      var cut = qwenCut(pcm([1, -1.2, 0.5, -0.6, 0.8]), 2)!;
      expect(cut.sounds.map((s) => (s.length / 24000).toStringAsFixed(1)),
          ["1.0", "0.5", "0.8"]);
      expect((cut.leading, cut.trailing), (false, false));
      // A short hush in the speech is not one of them.
      expect(qwenCut(pcm([1, -0.1, 1]), 0)!.sounds, hasLength(1));
      var ends = qwenCut(pcm([-0.6, 1, -0.6]), 2)!;
      expect(
          (ends.leading, ends.trailing, ends.sounds.length), (true, true, 1));
      expect(qwenCut(pcm([1, -1.2, 1]), 2), isNull,
          reason: "not as written: done another way");
    });

    group("run as a program", () {
      late Directory dir;
      late Future<String> Function() dirWas;
      setUp(() {
        dir = Directory.systemTemp.createTempSync("qwen-fake");
        dirWas = qwenDir;
        qwenDir = () async => dir.path;
        qwenFilesOverride = const [];
      });
      tearDown(() {
        qwenDir = dirWas;
        qwenFilesOverride = null;
        dir.deleteSync(recursive: true);
      });

      /// fake puts a program in the folder that writes [wav] where it is
      /// told, and notes each run's arguments.
      void fake(Uint8List wav) {
        File(path.join(dir.path, "line.wav")).writeAsBytesSync(wav);
        var program = File(path.join(dir.path, qwenProgram));
        program.writeAsStringSync('''#!/bin/sh
echo "\$@" >> "${dir.path}/runs.txt"
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then out="\$2"; fi
  shift
done
cp "${dir.path}/line.wav" "\$out"
''');
        Process.runSync("chmod", ["755", program.path]);
      }

      List<String> runs() =>
          File(path.join(dir.path, "runs.txt")).readAsLinesSync();

      test("a line spoken once, at the mix's rate, its pause put back",
          () async {
        // The program's take: its words, the marker's exact silence, more.
        fake(_wav24kOf([0.6, -0.7, 0.6]));
        var take = await QwenSpeech().speakLine(
            const SpeechSpec(voice: "serena"),
            const SpeechLine("Good evening [pause 0.5] everyone.",
                direction: SpeechDirection.warm),
            seed: 3);
        expect(take.seconds, closeTo(0.6 + 0.5 + 0.6, 0.01),
            reason: "the marker swapped for the pause asked for");
        expect(take.words.map((w) => w.text), ["Good", "evening", "everyone."]);
        expect(take.words.last.start, closeTo(1.1, 1e-6),
            reason: "after the words before it, and the pause");
        var run = runs().single;
        expect(run, contains("--compose Good evening [pause:0.6s] everyone."));
        expect(run, contains("--seed 3"));
        expect(run, contains("--instruct ${SpeechDirection.warm.say}"));
      }, skip: Platform.isWindows);

      test("lines said the same way, in one run; each way, its own", () async {
        // Each about as long as its words take: not run on, nor short.
        fake(_wav24kOf([1.2, -1.3, 2.2]));
        var takes = await QwenSpeech().speakLines(
            const SpeechSpec(voice: "ryan"),
            scriptLines("Good evening, all.\nIt has been a long year."));
        expect(runs(), hasLength(1), reason: "the model loaded once");
        expect(runs().single,
            contains("--compose Good evening, all. [pause:1.2s] It has"));
        expect(takes.map((t) => t.seconds.toStringAsFixed(1)), ["1.2", "2.2"]);
        expect(takes.last.words.first.text, "It");
        // A line said another way is another run.
        fake(_wav24kOf([1]));
        File(path.join(dir.path, "runs.txt")).deleteSync();
        await QwenSpeech().speakLines(const SpeechSpec(voice: "ryan"),
            scriptLines("[sad] Gone.\nStill here."));
        expect(runs(), hasLength(2));
      }, skip: Platform.isWindows);

      test("a cough mid-line is a cough there; a run not as written, by line",
          () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        fake(_wav24kOf([0.5, -0.7, 0.5]));
        var take = await QwenSpeech().speakLine(const SpeechSpec(voice: "ryan"),
            const SpeechLine("Well [cough] all right."));
        var cough = await cueRecording(SpeechCue.cough, man: true);
        expect(cough, isNotNull);
        expect(take.seconds,
            closeTo(0.5 + cough!.length / 48000 + 0.12 + 0.5, 0.01),
            reason: "the man's cough, recorded, where it was written");
        // Two lines that cannot be cut apart: each spoken by itself.
        fake(_wav24kOf([1]));
        File(path.join(dir.path, "runs.txt")).deleteSync();
        var takes = await QwenSpeech()
            .speakLines(const SpeechSpec(), scriptLines("One. Two."));
        expect(runs(), hasLength(3), reason: "together, then one each");
        expect(takes, hasLength(2));
      }, skip: Platform.isWindows);

      test("a line that runs on is spoken again with other seeds, twice",
          () async {
        fake(_wav24k(12));
        var take = await QwenSpeech()
            .speakLine(const SpeechSpec(), const SpeechLine("Hi there."));
        expect(runs(), hasLength(3));
        expect(runs().map((r) => RegExp(r"--seed (\d+)").firstMatch(r)![1]),
            ["1", "7920", "15839"]);
        expect(take.seconds, closeTo(12, 0.01), reason: "the nearest kept");
      }, skip: Platform.isWindows);

      test("not downloaded, or failing, it says so", () async {
        qwenFilesOverride = [
          (
            url: "https://example.invalid/x",
            path: "missing.bin",
            bytes: 10,
            sha256: "0" * 64,
            executable: false,
          )
        ];
        await expectLater(
            QwenSpeech().speakLine(const SpeechSpec(), const SpeechLine("Hi.")),
            throwsA(isA<SpeechException>().having(
                (e) => e.message, "message", contains("not downloaded"))));
        qwenFilesOverride = const [];
        File(path.join(dir.path, qwenProgram))
          ..writeAsStringSync("#!/bin/sh\nexit 3\n")
          ..let((f) => Process.runSync("chmod", ["755", f.path]));
        await expectLater(
            QwenSpeech().speakLine(const SpeechSpec(), const SpeechLine("Hi.")),
            throwsA(isA<SpeechException>()
                .having((e) => e.message, "message", contains("try again"))));
      }, skip: Platform.isWindows);
    });
  });

  group("the finish", () {
    SpokenAudio tone(double seconds, double level) {
      var n = (seconds * mixRate).round();
      var l = Float32List(n);
      for (var i = 0; i < n; i++) {
        l[i] = level * math.sin(i * 2 * math.pi * 220 / mixRate);
      }
      return SpokenAudio(l, Float32List.fromList(l),
          const [(text: "Hi", start: 0.1, end: 0.5)]);
    }

    double rms(Float32List x, [int from = 0, int? to]) {
      var sum = 0.0;
      to ??= x.length;
      for (var i = from; i < to; i++) {
        sum += x[i] * x[i];
      }
      return math.sqrt(sum / (to - from));
    }

    test("lines joined with a pause that shortens as it speeds up", () {
      var joined = joinLines([tone(1, 0.1), tone(1, 0.1)], 1);
      expect(joined.seconds, closeTo(2 + lineGap(1), 0.001));
      expect(joined.words.last.start, closeTo(1 + lineGap(1) + 0.1, 0.001));
      expect(lineGap(1.3), lessThan(lineGap(1) * 0.8));
    });

    test("the boost brings a quiet voice up; dry and plain, it is as it was",
        () {
      var quiet = tone(1, 0.02);
      var boosted = finished(quiet, room: 0, boost: true);
      expect(rms(boosted.l), greaterThan(rms(quiet.l) * 2.5));
      expect(boosted.words, quiet.words, reason: "its words where they were");
      var plain = finished(quiet, room: 0, boost: false);
      expect(plain.l.length, quiet.l.length);
      expect(
          rms(plain.l, 1000, 40000), closeTo(rms(quiet.l, 1000, 40000), 1e-4),
          reason: "the limiter's delay taken back out");
      for (var x in boosted.l) {
        expect(x.abs(), lessThanOrEqualTo(0.9));
      }
    });

    test("room is a tail and a little room tone", () {
      var dry = tone(1, 0.1);
      var roomy = finished(dry, room: 1, boost: false);
      expect(roomy.seconds, greaterThan(dry.seconds + 0.3));
      var tail = rms(roomy.l, dry.l.length + 2000, dry.l.length + 6000);
      expect(tail, greaterThan(1e-4), reason: "the room after the voice");
    });
  });

  group("the device", () {
    late SpeechEngine Function(SpeechSpec, String) engineWas;
    setUp(() {
      engineWas = CanvasController.speechEngineFor;
      CanvasController.speechEngineFor = (spec, key) => _Voices();
      KokoroDownload.instance.ready = true;
    });
    tearDown(() {
      CanvasController.speechEngineFor = engineWas;
      KokoroDownload.instance.ready = null;
      QwenDownload.instance.ready = null;
    });

    CanvasController make() => CanvasController(
        CanvasDocument(frames: 200, frameRate: 25, elements: [
          AudioElement(const ElementBase(id: "a", name: "Narrator"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 2)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 2}));

    Future<void> show(WidgetTester tester, CanvasController c,
            {double scale = 1}) =>
        tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false),
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
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

    testWidgets("its lines: picked, directed, joined and split",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      // Tall enough for the directions' whole menu.
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.setSpeech(
          "a", const SpeechSpec(script: "Hello there, my friend. Good night."));
      await show(tester, c);
      await tester.pump();
      expect(find.byKey(const ValueKey("speechLine-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("speechLine-1")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("speechLine-1")));
      await tester.pump();
      // How it is said, from its chips: on Built in, only those Kokoro can
      // say -- nervous is not one, and does nothing.
      await tester.tap(find.byKey(const ValueKey("speechDirection-nervous")));
      await tester.pump();
      expect(c.speechOf("a")!.shownLines[1].direction, SpeechDirection.plain);
      await tester.tap(find.byKey(const ValueKey("speechEngine-expressive")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechDirection-nervous")));
      await tester.pump();
      expect(c.speechOf("a")!.lines[1].direction, SpeechDirection.nervous);
      expect(c.speechOf("a")!.script,
          "Hello there, my friend.\n[nervous] Good night.");
      // Own words, kept as it is left.
      await tester.enterText(
          find.byKey(const ValueKey("speechOwn")), "half asleep");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.speechOf("a")!.lines[1].own, "half asleep");
      // The first joined with the next, then split again.
      await tester.tap(find.byKey(const ValueKey("speechLine-0")));
      await tester.pump();
      // Below the directions: scrolled to.
      await tester.ensureVisible(find.byKey(const ValueKey("speechJoin")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechJoin")));
      await tester.pump();
      expect(c.speechOf("a")!.lines, hasLength(1));
      await tester.tap(find.byKey(const ValueKey("speechSplit")));
      await tester.pump();
      expect(c.speechOf("a")!.lines, hasLength(2));
      // A preset moves the sliders; a slider makes it Custom.
      await tester.tap(find.byKey(const ValueKey("speechPreset-calm")));
      await tester.pumpAndSettle();
      expect(c.speechOf("a")!.preset, "calm");
      expect(c.speechOf("a")!.boost, isFalse);
      // Kokoro cannot follow stability or expression: greyed.
      await tester.tap(find.byKey(const ValueKey("speechEngine-local")));
      await tester.pump();
      expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey("speechExpression")))
              .onChanged,
          isNull);
      // Room is below the fold of the feel's column: scrolled to.
      await tester.ensureVisible(find.byKey(const ValueKey("speechRoom")));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byKey(const ValueKey("speechRoom")), const Offset(30, 0));
      await tester.pump();
      expect(c.speechOf("a")!.preset, "custom");
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("heard before it is picked: our own voices, and each take",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      QwenDownload.instance.ready = true;
      var spec = const SpeechSpec(script: "One. Two.").withScript("One. Two.");
      for (var engine in SpeechEngineKind.values) {
        c.setSpeech(
            "a",
            spec.copyWith(engine: engine, lines: [
              spec.lines.first.copyWith(takes: const [
                SpeechTake("x.wav", 1, []),
                SpeechTake("y.wav", 1, []),
              ], chosen: 1),
              spec.lines.last,
            ]));
        for (var scale in [1.0, 1.5]) {
          await show(tester, c, scale: scale);
          await tester.pump();
          var why = "$engine at ${scale}x";
          expect(tester.takeException(), isNull, reason: why);
          var cloud = engine == SpeechEngineKind.cloud;
          expect(find.byKey(const ValueKey("speechPreview-v1")),
              cloud ? findsNothing : findsOneWidget,
              reason: "a preview from ElevenLabs costs: $why");
          expect(find.byKey(const ValueKey("speechHearFeel")),
              cloud ? findsNothing : findsOneWidget,
              reason: why);
          // The first line, picked: its two takes, each to hear.
          expect(find.byKey(const ValueKey("speechHear-0")), findsOneWidget,
              reason: why);
          expect(find.byKey(const ValueKey("speechHear-1")), findsOneWidget,
              reason: why);
          expect(find.byKey(const ValueKey("speechHear-2")), findsNothing,
              reason: why);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("every engine, every text size: nothing overflows",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var (engine, here) in [
        (SpeechEngineKind.local, true),
        (SpeechEngineKind.expressive, false),
        (SpeechEngineKind.expressive, true),
        (SpeechEngineKind.cloud, true),
      ]) {
        QwenDownload.instance.ready = here;
        c.setSpeech(
            "a",
            SpeechSpec(
                engine: engine,
                script: "[warm] A first line, quite a long one. A second."));
        for (var scale in [1.0, 1.15, 1.25, 1.5]) {
          await show(tester, c, scale: scale);
          await tester.pump();
          var why = "$engine, voices here $here, at ${scale}x";
          expect(tester.takeException(), isNull, reason: why);
          var expressiveHere =
              engine == SpeechEngineKind.expressive && here && qwenSupported;
          expect(find.byKey(const ValueKey("speechLanguage")),
              expressiveHere ? findsOneWidget : findsNothing,
              reason: why);
          var rect = tester.getRect(find.byKey(const ValueKey("speechSpeak")));
          expect(rect.bottom, lessThanOrEqualTo(260), reason: why);
          expect(
              tester
                  .widget<FilledButton>(
                      find.byKey(const ValueKey("speechSpeak")))
                  .onPressed,
              engine == SpeechEngineKind.expressive && !expressiveHere
                  ? isNull
                  : engine == SpeechEngineKind.cloud
                      ? isNull // no key
                      : isNotNull,
              reason: why);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// _Voices lists two voices, and speaks nothing.
class _Voices extends SpeechEngine {
  @override
  Future<List<SpeechVoice>> voices() async => const [
        SpeechVoice("v1", "Bella", "US woman", gender: "f"),
        SpeechVoice("v2", "Adam", "UK man", gender: "m"),
      ];
  @override
  Future<SpokenAudio> speak(SpeechSpec spec) =>
      throw const SpeechException("not here");
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
