import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_timing.dart';
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
    test("a section to each line of the script, its direction at its start",
        () {
      // Its sentences are not cut apart: spoken in one go, they are one
      // voice, start to finish.
      var lines = scriptLines("[warm] Hello there. How are you?\n"
          "[say: tired, at the end of a long day] Fine. [laugh]\n\n"
          "[breath]\nRight.");
      expect(lines.map((l) => l.text),
          ["Hello there. How are you?", "Fine. [laugh]", "[breath] Right."],
          reason: "a line of cues alone goes with the words after it");
      expect(lines.map((l) => l.direction), [
        SpeechDirection.warm,
        SpeechDirection.plain,
        SpeechDirection.plain,
      ]);
      expect(lines[1].own, "tired, at the end of a long day");
      expect(lines[1].say, "tired, at the end of a long day");
      expect(lines[0].say, SpeechDirection.warm.say);
      expect(lines[1].written,
          "[say: tired, at the end of a long day] Fine. [laugh]");
    });

    test("typed again, the lines unchanged keep their takes", () {
      const take = SpeechTake("t1", 1, []);
      var spec =
          const SpeechSpec(script: "One.\nTwo.").withScript("One.\nTwo.");
      spec = spec.copyWith(lines: [
        spec.lines[0].copyWith(slots: [take], chosen: 0),
        spec.lines[1],
      ]);
      var typed = spec.withScript("One.\nTwo and three.");
      expect(typed.lines.first.takes.single.assetId, "t1");
      expect(typed.lines.first.chosen, 0);
      expect(typed.lines.last.takes, isEmpty);
      // Said another way, its words the same: its takes stay, only the
      // reader empties a slot.
      var sad = spec.withScript("[sad] One.\nTwo.").lines.first;
      expect((sad.direction, sad.takes.single.assetId),
          (SpeechDirection.sad, "t1"));
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
        spec.lines.single.copyWith(slots: [
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
      // A device from before there were sections: its script's lines.
      var old = SpeechSpec.fromJson({"script": "One. Two.\nThree."});
      expect(old.lines, isEmpty);
      expect(old.shownLines.map((l) => l.text), ["One. Two.", "Three."]);
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

    test("a section is one stretch, its cues written into it", () {
      // Cut at every cue, the voice started again at each, and was heard
      // to: a section is said in one go, but for a whisper's edge.
      var script = qwenScript(scriptLines(
          "Hi. [laugh]\n[breath] So [pause 0.2] we [whisper] go now."));
      expect(
          script.runs.map((r) => (r.soft, r.text, r.stretches.join(","))),
          [
            (false, "Hi. Haha! [pause:0.6s] So... we", "0,1"),
            (true, "go now.", "2"),
          ],
          reason: "said aloud in one run, the whisper softly in another");
      expect(script.spoken.map((s) => (s.text, s.whisper)), [
        ("Hi. Haha!", false),
        ("So... we", false),
        ("go now.", true),
      ]);
      expect(script.gaps[1].single, isA<QwenLineEnd>(),
          reason: "a breath at a section's start is in it, before its words");
      expect(script.gaps[2].single, isA<QwenJoin>(),
          reason: "the whisper starts there");
      expect(script.spoken[1].beats.map((b) => (b.$1, b.$2.runtimeType)),
          [(0, QwenSound), (1, QwenPause)],
          reason: "the breath before its words, the pause after the first");
      // The program's own markup is not the reader's to write.
      expect(qwenScript(scriptLines("A | B")).runs.single.text, "A , B");
    });

    test("Ken's line: cues after the words before them, beats as pauses", () {
      var said = qwenScript(scriptLines("[warm] This is the first time in "
          "history [breath] sound money has a chance to shine and dee-cred "
          "[pause 0.5] is leading the way [laugh]. What did you expect [sigh] "
          "a medel [cough]."));
      expect(
          said.runs.single.text,
          "This is the first time in history... sound money has a chance to "
          "shine and dee-cred... is leading the way, haha. What did you "
          "expect... a medel, ahem.");
      expect(said.runs.single.stretches, [0], reason: "one take, one voice");
      expect(said.spoken.single.beats.map((b) => (b.$1, b.$2.runtimeType)),
          [(7, QwenSound), (16, QwenPause), (25, QwenSound)],
          reason: "the breath, the pause and the sigh, put in the voice's "
              "own pauses");
    });

    test("a cough is written into the words too; a sigh and a breath not",
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var said = qwenScript(scriptLines("Well [cough] all right. [cough]"));
      expect(said.runs.single.text, "Well, ahem, all right. Ahem.");
      expect(said.spoken.single.words(2).map((w) => w.text),
          ["Well,", "all", "right."]);
      // Written so, Ken heard a sigh and a breath sound strange: a beat.
      var sigh = qwenScript(scriptLines("Well [sigh] all right."));
      expect(sigh.runs.single.text, "Well... all right.");
      expect(sigh.spoken.single.beats.single.$2, isA<QwenSound>());
      // A "..." alone, the breath the voice takes there itself, was not
      // heard: our recording too.
      var breath = qwenScript(scriptLines("Well [breath] all right."));
      expect(breath.runs.single.text, "Well... all right.");
      expect(breath.spoken.single.beats.single.$2, isA<QwenSound>());
      // A breath out too: a quiet one, after the words before it.
      var out = qwenScript(scriptLines("Well [exhale] all right."));
      expect(out.runs.single.text, "Well... all right.");
      expect((out.spoken.single.beats.single.$2 as QwenSound).cue,
          SpeechCue.exhale);
      expect(await cueRecording(SpeechCue.exhale, man: true), isNotNull);
      expect(await cueRecording(SpeechCue.exhale, man: false), isNotNull);
    });

    test("a laugh is written into the words, and not timed as one", () {
      // Ken heard a laugh of the model's own, put before the words, stop
      // dead where they began; written into them, it laughs into them.
      var said = qwenScript(scriptLines("[laughing] We won."));
      expect(said.runs.single.text, "Haha, We won.");
      expect(said.runs.single.stretches, [0],
          reason: "one stretch: nothing to cut");
      expect(said.spoken.single.words(2).map((w) => w.text), ["We", "won."]);
      // The cue mid-line: after the words before it, in one stretch.
      var mid = qwenScript(scriptLines("Well [laugh] all right."));
      expect(mid.runs.single.text, "Well, haha, all right.");
      expect(mid.spoken.single.words(2).map((w) => w.text),
          ["Well,", "all", "right."]);
      // Said in the reader's own words, the direction is theirs.
      expect(
          qwenScript([const SpeechLine("Fine.", own: "laughing a bit")])
              .runs
              .single
              .text,
          "Fine.");
    });

    test("words timed by the voice's own pauses; a beat put in one", () {
      // The voice's pauses are not silent: a breath's noise, 30dB down,
      // with a click in it.
      var noise = math.Random(1);
      Float32List tone(double s) => Float32List.fromList([
            for (var i = 0; i < (s * 48000).round(); i++)
              0.2 * math.sin(i * 0.1)
          ]);
      Float32List hush(double s) => Float32List.fromList([
            for (var i = 0; i < (s * 48000).round(); i++)
              i ~/ 480 == 15 ? 0.2 : 0.004 * (noise.nextDouble() - 0.5)
          ]);
      var sound = Float32List.fromList([...tone(1), ...hush(0.3), ...tone(1)]);
      var found = voicePauses(sound);
      expect(found.pauses, hasLength(1), reason: "the click is the pause");
      expect(found.pauses.single.$1, closeTo(1.0, 0.02));
      expect(found.pauses.single.$2, closeTo(1.3, 0.02));
      // Matched to the beat written, the words either side spread across
      // the time spoken.
      var timed = timeWords(sound, ["Hello", "there...", "my", "friend."]);
      expect(timed.after.keys, [1]);
      expect(timed.words[1].end, closeTo(1.0, 0.02));
      expect(timed.words[2].start, closeTo(1.3, 0.02));
      expect(timed.words.last.end, closeTo(2.3, 0.02));
      // A pause written where the voice did not pause: matched to none.
      expect(timeWords(tone(2), ["Hi,", "you."]).after, isEmpty);
      // Put in at the moment asked, the words after moved on by it.
      var sigh = Float32List.fromList(List.filled(24000, 0.1));
      var (placed, moved) =
          qwenPlaceBeats(sound, [(at: 1.15, sound: sigh, hush: null)]);
      expect(placed.length, sound.length + sigh.length);
      expect(moved.single.$1, closeTo(1.15, 1e-3));
      expect(moved.single.$2, 0.5);
      // A pause: the voice's own made silent with it -- its noise and its
      // click -- so the gap is silence, all of it.
      var (gap, _) = qwenPlaceBeats(sound, [
        (at: 1.15, sound: Float32List(4800), hush: found.pauses.single),
      ]);
      expect(gap.length, sound.length + 4800);
      expect(
          gap
              .sublist((1.02 * 48000).round(), (1.38 * 48000).round())
              .every((v) => v == 0),
          isTrue);
      expect(gap[(0.5 * 48000).round()], sound[(0.5 * 48000).round()],
          reason: "the words untouched");
      // With no pause to go in, between two words: the quietest moment
      // near.
      var dipped = Float32List.fromList(
          [...tone(0.7), ...Float32List(1920), ...tone(0.7)]);
      expect(quietestNear(dipped, 0.5), closeTo(0.72, 0.02));
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
      expect(qwenCut(pcm([1, -0.7, 1]), 0)!.sounds, hasLength(1),
          reason: "none asked for: the voice's own pause stays in");
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
        // The program's take: its words, a short pause of its own, more.
        fake(_wav24kOf([0.6, -0.2, 0.6]));
        var take = await QwenSpeech().speakLine(
            const SpeechSpec(voice: "serena"),
            const SpeechLine("Good evening [pause 0.5] everyone.",
                direction: SpeechDirection.warm),
            seed: 3);
        expect(take.seconds, closeTo(0.6 + 0.5 + 0.6, 0.01),
            reason: "the voice's own pause made as long as asked");
        // All of it silence: no click, no noise of the voice's.
        expect(
            take.l
                .sublist((0.62 * 48000).round(), (1.08 * 48000).round())
                .every((v) => v == 0),
            isTrue);
        expect(
            take.words.map((w) => w.text), ["Good", "evening...", "everyone."]);
        expect(take.words.last.start, closeTo(0.6 + 0.5, 0.02),
            reason: "after the words before it, and the pause");
        var run = runs().single;
        expect(run, contains("--text Good evening... everyone."),
            reason: "one stretch, the pause the voice's own beat");
        expect(run, contains("--seed 3"));
        expect(run, contains("--instruct ${SpeechDirection.warm.say}"));
      }, skip: Platform.isWindows);

      test("a whisper said softly, in a run of its own, and quieter", () async {
        fake(_wav24kOf([0.8]));
        var take = await QwenSpeech().speakLine(
            const SpeechSpec(),
            const SpeechLine("Hello [whisper] my friend.",
                direction: SpeechDirection.warm));
        var both = runs();
        expect(both, hasLength(2));
        expect(both.first, contains("--text Hello"));
        expect(both.last, contains("--text my friend."));
        expect(both.last,
            contains("--instruct ${qwenSoftly(SpeechDirection.warm.say)}"),
            reason: "the section's way, said softly");
        expect(qwenSoftly(""), SpeechDirection.whisper.say);
        // Not hiss: the voice itself, only quieter.
        double peak(double from, double to) => take.l
            .sublist((from * 48000).round(), (to * 48000).round())
            .fold(0.0, (m, v) => math.max(m, v.abs()));
        expect(peak(1.0, 1.5), closeTo(peak(0.1, 0.6) * qwenSoftLevel, 0.01));
      }, skip: Platform.isWindows);

      test("Stop ends the program, and nothing part made is kept", () async {
        var program = File(path.join(dir.path, qwenProgram));
        program.writeAsStringSync("#!/bin/sh\nexec sleep 30\n");
        Process.runSync("chmod", ["755", program.path]);
        var engine = QwenSpeech();
        var clock = Stopwatch()..start();
        var said =
            engine.speakLine(const SpeechSpec(), const SpeechLine("Hi."));
        await Future.delayed(const Duration(milliseconds: 300));
        engine.stopper.stop();
        await expectLater(said, throwsA(isA<SpeechStopped>()));
        expect(clock.elapsed.inSeconds, lessThan(5),
            reason: "the program ended, not waited out");
        // Stopped already, it does not start another.
        await expectLater(
            engine.speakLine(const SpeechSpec(), const SpeechLine("Hi.")),
            throwsA(isA<SpeechStopped>()));
      }, skip: Platform.isWindows);

      test("lines said the same way, in one run; each way, its own", () async {
        // Each about as long as its words take: not run on, nor short.
        fake(_wav24kOf([1.2, -1.3, 2.2]));
        var takes = await QwenSpeech().speakLines(
            const SpeechSpec(voice: "ryan"),
            scriptLines("Good evening, all.\nIt has been a long year."));
        expect(runs(), hasLength(1), reason: "the model loaded once");
        expect(runs().single,
            contains("--compose Good evening, all. [pause:0.6s] It has"));
        expect(takes.map((t) => t.seconds.toStringAsFixed(1)), ["1.2", "2.2"]);
        expect(takes.last.words.first.text, "It");
        // A line said another way is another run.
        fake(_wav24kOf([1]));
        File(path.join(dir.path, "runs.txt")).deleteSync();
        await QwenSpeech().speakLines(const SpeechSpec(voice: "ryan"),
            scriptLines("[sad] Gone.\nStill here."));
        expect(runs(), hasLength(2));
      }, skip: Platform.isWindows);

      test("a sigh mid-line is a sigh there; a run not as written, by line",
          () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        fake(_wav24kOf([0.5, -0.7, 0.5]));
        var take = await QwenSpeech().speakLine(const SpeechSpec(voice: "ryan"),
            const SpeechLine("Well [sigh] all right."));
        var sigh = await cueRecording(SpeechCue.sigh, man: true);
        expect(sigh, isNotNull);
        expect(take.seconds,
            closeTo(0.5 + 0.7 + sigh!.length / 48000 + 0.1 + 0.5, 0.01),
            reason: "the man's sigh, recorded, in the voice's own pause");
        // Two lines that cannot be cut apart: each spoken by itself.
        fake(_wav24kOf([1]));
        File(path.join(dir.path, "runs.txt")).deleteSync();
        var takes = await QwenSpeech()
            .speakLines(const SpeechSpec(), scriptLines("One.\nTwo."));
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
    late SpeechEngine Function(SpeechSpec) engineWas;
    setUp(() {
      engineWas = CanvasController.speechEngineFor;
      CanvasController.speechEngineFor = (spec) => _Voices();
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

    testWidgets("its sections: picked, said, cued, joined and split",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      // Tall enough for the directions' whole menu.
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.setSpeech("a",
          const SpeechSpec(script: "Hello there, my friend.\nGood night."));
      await show(tester, c);
      await tester.pump();
      expect(find.byKey(const ValueKey("speechLine-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("speechLine-1")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("speechLine-1")));
      await tester.pump();
      // How the section is said, under the script: on Built in, only those
      // Kokoro can say are offered.
      Future<void> say(String label) async {
        await tester.tap(find.byKey(const ValueKey("speechSaid")));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey("speechSaid")));
      await tester.pumpAndSettle();
      expect(find.text("Nervous"), findsNothing,
          reason: "Kokoro cannot say it, so it is not offered");
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("speechEngine-expressive")));
      await tester.pump();
      await say("Nervous");
      expect(c.speechOf("a")!.lines[1].direction, SpeechDirection.nervous);
      expect(c.speechOf("a")!.script,
          "Hello there, my friend.\n[nervous] Good night.");
      // A cue, from the same palette: at the end of the section picked.
      await tester.ensureVisible(find.byKey(const ValueKey("speechCue-cough")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("speechCue-cough")));
      await tester.pump();
      expect(c.speechOf("a")!.lines[1].text, "Good night. [cough]");
      // Own words, kept as it is left.
      await tester.enterText(
          find.byKey(const ValueKey("speechOwn")), "half asleep");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.speechOf("a")!.lines[1].own, "half asleep");
      // The first joined with the next, then split again -- at the
      // sentence's end.
      await tester.tap(find.byKey(const ValueKey("speechLine-0")));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey("speechJoin")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechJoin")));
      await tester.pump();
      expect(c.speechOf("a")!.lines, hasLength(1));
      await tester.tap(find.byKey(const ValueKey("speechSplit")));
      await tester.pump();
      expect(c.speechOf("a")!.lines.map((l) => l.text),
          ["Hello there, my friend.", "Good night. [cough]"]);
      // A preset moves the sliders; a slider makes it Custom.
      await tester.ensureVisible(find.byKey(const ValueKey("speechPreset")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("speechPreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Calm & close").last);
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

    testWidgets(
        "A, B and C always there; a slot in use, its actions; free, none",
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
              spec.lines.first.copyWith(slots: const [
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
          // Heard before it is picked.
          expect(find.byKey(const ValueKey("speechPreview-v1")), findsOneWidget,
              reason: why);
          expect(find.byKey(const ValueKey("speechHearFeel")), findsOneWidget,
              reason: why);
          // Every line's three, in use or not.
          for (var t = 0; t < 3; t++) {
            expect(find.byKey(ValueKey("speechTake-1-$t")), findsOneWidget,
                reason: why);
            expect(find.byKey(ValueKey("speechSlot-$t")), findsOneWidget,
                reason: why);
          }
          // The first line picked, its slot B: in use, so its actions.
          for (var action in [
            "speechHear",
            "speechSave",
            "speechAddTake",
            "speechRemoveTake",
            "speechReplace"
          ]) {
            expect(find.byKey(ValueKey(action)), findsOneWidget,
                reason: "$action, $why");
          }
        }
      }
      // Slot C picked: free, so none of them.
      await tester.tap(find.byKey(const ValueKey("speechSlot-2")));
      await tester.pump();
      expect(find.byKey(const ValueKey("speechSave")), findsNothing);
      expect(find.byKey(const ValueKey("speechReplace")), findsNothing);
      expect(find.textContaining("Slot C is free"), findsOneWidget);
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
