import 'dart:math' as math;
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/media/speech_downloads.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_timing.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// qwen_speech.dart is the Speech device's expressive voices: Qwen3-TTS 1.7B
// CustomVoice (Apache 2.0), nine voices directed per line in plain words,
// run on the CPU by qwen3-tts (MIT). Both are downloaded once, pinned and
// SHA-256 checked; Apple Silicon and Linux only. Its server mode is unused:
// it listens on every network, not only localhost.

/// qwenVersion is the program's release; qwenRevision the model's.
const qwenVersion = "v0.23.0";
const qwenRevision = "0c0e3051f131929182e2c023b9537f8b1c68adfe";

/// _programs are the program's builds per platform: name, size, SHA-256.
const _programs = <Abi, (String, int, String)>{
  Abi.macosArm64: (
    "macos-arm64",
    1251384,
    "0bc3ad38d80d868ee845a40a24e72fbecacd6fd7d4436e2bb259a4c7b4d43572"
  ),
  Abi.linuxX64: (
    "linux-x86_64",
    1629432,
    "2bc83de6f424752de50d359306be0649eedf1ce392256552fa63bcef8c6b2775"
  ),
  Abi.linuxArm64: (
    "linux-aarch64",
    1474176,
    "7c3a6a6844f4a3a5896d3ef3a486a960f3da16596d6c9aff13e53f3b11dab8bb"
  ),
};

/// _modelFiles are the model's files: where in the folder, size, SHA-256.
const _modelFiles = <(String, int, String)>[
  (
    "config.json",
    4908,
    "17a07f527a1c25ea30b4e023a184482a23d3e279d697b1dc81b1bde498d29cf9"
  ),
  (
    "generation_config.json",
    245,
    "f1b90b4513f3b34c62851049e2492d7b4c5940daf1276f89c82b8ef04127f3aa"
  ),
  (
    "tokenizer_config.json",
    7344,
    "dc3c31c3bdaedd5016382bb3cbe07323026775ad51f5a4fb564505992ae4a670"
  ),
  (
    "preprocessor_config.json",
    127,
    "efdde1022ea9d76928bf7a9cd53139138f5ba2e466e837f08f6105ab1af1c119"
  ),
  (
    "vocab.json",
    2776833,
    "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
  ),
  (
    "merges.txt",
    1671839,
    "599bab54075088774b1733fde865d5bd747cbcc7a547c5bc12610e874e26f5e3"
  ),
  (
    "model.safetensors",
    3833402552,
    "38b1d5971bdbd982b561cccec982669a53b0537c3cf5e9bd4778ed07bb2f5137"
  ),
  (
    "speech_tokenizer/config.json",
    2336,
    "ee65bb901c876664ab8707c487157aa1a6ee57c65969b28fb5ec9dc211e68167"
  ),
  (
    "speech_tokenizer/configuration.json",
    76,
    "6bc26d64eb5024b4d1dab5a52371958b429256d6c9d59787f1f5294a54e0cebd"
  ),
  (
    "speech_tokenizer/model.safetensors",
    682293092,
    "836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258"
  ),
  (
    "speech_tokenizer/preprocessor_config.json",
    234,
    "fcb3805e597e786d4067706e602f6688524640f8d3396790e2e09b5942fcbdfb"
  ),
];

const qwenProgram = "qwen_tts";

bool get qwenSupported => _programs.containsKey(Abi.current());

/// qwenFilesOverride is what is downloaded instead, for tests.
@visibleForTesting
List<PinnedFile>? qwenFilesOverride;

/// qwenDir is where the program and model are kept; a test can move it.
Future<String> Function() qwenDir = () async =>
    path.join(await CanvasStorage.libraryDir(), canvasVoicesFolder, "qwen3-tts-1.7b");

/// qwenFiles are the program, for this computer, and the model.
List<PinnedFile> get qwenFiles {
  if (qwenFilesOverride case var files?) return files;
  var program = _programs[Abi.current()];
  return [
    if (program != null)
      (
        url: "https://github.com/gabriele-mastrapasqua/qwen3-tts/releases/"
            "download/$qwenVersion/qwen_tts-${program.$1}",
        path: qwenProgram,
        bytes: program.$2,
        sha256: program.$3,
        executable: true,
      ),
    for (var (name, bytes, sha) in _modelFiles)
      (
        url: "https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice/"
            "resolve/$qwenRevision/$name",
        path: name,
        bytes: bytes,
        sha256: sha,
        executable: false,
      ),
  ];
}

/// qwenBytes is the whole download size, to say before downloading.
int get qwenBytes => qwenFiles.fold(0, (n, f) => n + f.bytes);

/// QwenDownload is the expressive voices' download, shared by every Speech
/// device.
class QwenDownload extends PinnedDownload {
  static final instance = QwenDownload();
  QwenDownload() : super(() => qwenDir(), () => qwenFiles);
}

/// qwenVoices are the nine, each keeping its accent in every language.
const qwenVoices = [
  SpeechVoice("ryan", "Ryan", "English · lively, rhythmic", gender: "m"),
  SpeechVoice("aiden", "Aiden", "American · sunny, clear", gender: "m"),
  SpeechVoice("serena", "Serena", "Chinese accent · warm, gentle", gender: "f"),
  SpeechVoice("vivian", "Vivian", "Chinese accent · bright, edgy", gender: "f"),
  SpeechVoice("uncle_fu", "Uncle Fu", "Chinese accent · low, mellow",
      gender: "m"),
  SpeechVoice("dylan", "Dylan", "Beijing accent · clear, natural", gender: "m"),
  SpeechVoice("eric", "Eric", "Chengdu accent · husky, bright", gender: "m"),
  SpeechVoice("ono_anna", "Ono Anna", "Japanese accent · playful", gender: "f"),
  SpeechVoice("sohee", "Sohee", "Korean accent · warm, rich", gender: "f"),
];

const qwenLanguages = [
  "English",
  "Chinese",
  "Japanese",
  "Korean",
  "German",
  "French",
  "Russian",
  "Portuguese",
  "Spanish",
  "Italian",
];

/// qwenDirection is what the voice is told for [line], [expression] (nought
/// to one) saying how far to take it.
String qwenDirection(SpeechLine line, double expression) {
  var say = line.say.trim();
  if (say.isEmpty) {
    if (expression < 0.33) return "Calm, even and understated.";
    if (expression > 0.66) return "Lively and expressive.";
    return "";
  }
  if (expression < 0.33) return "$say Keep it subtle and understated.";
  if (expression > 0.66) return "$say Make it vivid and strongly felt.";
  return say;
}

/// qwenSampling is the temperature and nucleus for [steadiness]: at the
/// middle 0.9, or 1.1 with a direction, which lower values flatten.
(double, double) qwenSampling(double steadiness, {required bool directed}) {
  var s = steadiness.clamp(0.0, 1.0);
  var temperature = (directed ? 1.25 : 1.05) - 0.3 * s;
  var nucleus = s <= 0.5 ? 1.0 : 1.0 - 0.2 * (s - 0.5);
  return (temperature, nucleus);
}

/// qwenArguments are the program's arguments for [text] said as
/// [direction]: voice, language, sampling, speed and [seed].
List<String> qwenArguments(
    String dir, SpeechSpec spec, String direction, String text, String out,
    {required int seed, bool compose = false}) {
  var voice = qwenVoices.any((v) => v.id == spec.voice) ? spec.voice : "ryan";
  var language =
      qwenLanguages.contains(spec.language) ? spec.language : "English";
  var (temperature, nucleus) =
      qwenSampling(spec.steadiness, directed: direction.isNotEmpty);
  var rate = spec.speed.clamp(0.7, 1.3);
  // A line that runs on is stopped at three times its words' length.
  var words = text
      .replaceAll(RegExp(r"\[[^\]]*\]"), " ")
      .split(RegExp(r"\s+"))
      .where((w) => w.isNotEmpty)
      .length;
  var most = 4 + words * 0.4 * 3 / rate;
  return [
    "-d", dir, //
    "--int8",
    "-s", voice,
    "-l", language,
    if (direction.isNotEmpty) ...["--instruct", direction],
    "-T", temperature.toStringAsFixed(2),
    "-p", nucleus.toStringAsFixed(2),
    if (rate != 1) ...["--rate", rate.toStringAsFixed(2)],
    "--seed", "$seed",
    "--max-duration", most.toStringAsFixed(0),
    compose ? "--compose" : "--text", text,
    "-o", out,
    "-S",
  ];
}

/// spokenText is [line]'s words without its cues, which are put in after
/// (see qwenScript).
String spokenText(SpeechLine line) => [
      for (var p in parseScript(line.text))
        if (p is SpokenText) p.text
    ].join(" ");

// ---- Several lines, and their cues, in one run --------------------------
// The model loads on each run (nine seconds of a short line's twenty), so
// lines are spoken in one run, soft ones in another, split by pause markup.
// A pause renders as exact silence, where the take is cut and cues go in.

/// QwenGap is what lies between two stretches of speech in a run: line
/// ends and cues.
sealed class QwenGap {
  const QwenGap();
}

/// A line ends here.
class QwenLineEnd extends QwenGap {
  const QwenLineEnd();
}

/// A cue's sound, a recording.
class QwenSound extends QwenGap {
  final SpeechCue cue;
  const QwenSound(this.cue);
}

/// A pause, [seconds] long.
class QwenPause extends QwenGap {
  final double seconds;
  const QwenPause(this.seconds);
}

/// The words go on, but said another way: a whisper begins or ends.
class QwenJoin extends QwenGap {
  const QwenJoin();
}

/// QwenSpoken is one stretch of a run (a section, or part of one either
/// side of a whisper): its text, whether whispered, which words are
/// written-in cues not timed as words, and its beats (see qwenPlaceBeats).
class QwenSpoken {
  final String text;
  final bool whisper;
  final Set<int> cues;
  final List<(int, QwenGap)> beats;
  const QwenSpoken(this.text,
      {this.whisper = false, this.cues = const {}, this.beats = const []});

  /// words are its words, timed across [seconds], the cues left out.
  List<TimedWord> words(double seconds) =>
      spoken(estimateWords(SpokenText(text).words, 0, seconds));

  /// spoken is [all] (words and written-in cues, timed) without the cues.
  List<TimedWord> spoken(List<TimedWord> all) => [
        for (var (i, w) in all.indexed)
          if (!cues.contains(i)) w
      ];
}

/// qwenWritten are cues written into the words, so the voice does them in
/// the same breath ("the way, haha."); a recording there sounds laid on.
/// Each has two forms: within a sentence, and as one of its own.
const qwenWritten = {
  SpeechCue.laugh: ("haha", "Haha!"),
  SpeechCue.cough: ("ahem", "Ahem."),
};

/// QwenScript is a run's text and how it is to be cut: its stretches in
/// order and the gaps round them.
class QwenScript {
  final List<QwenSpoken> spoken;

  /// gaps are those before each stretch and after the last: one more than
  /// [spoken]. An empty one is no gap.
  final List<List<QwenGap>> gaps;
  const QwenScript(this.spoken, this.gaps);

  /// runs are its stretches as the program gets them: aloud in one run,
  /// whispered in another, a pause between each, where the take is cut.
  List<({bool soft, String text, List<int> stretches})> get runs => [
        for (var soft in [false, true])
          if ([
            for (var (k, s) in spoken.indexed)
              if (s.whisper == soft) k
          ]
              case var these when these.isNotEmpty)
            (
              soft: soft,
              text: these
                  .map((k) => spoken[k].text)
                  .join(" [pause:${qwenMark}s] "),
              stretches: these,
            ),
      ];
}

/// qwenMark is the pause written between a run's stretches: longer than
/// any natural silence, it renders as exact silence, which speech never is.
const qwenMark = 0.6;

/// qwenBreathing is the expression past which the voice breathes between
/// sentences: the vivid third.
const qwenBreathing = 0.66;

/// qwenSoftly is [direction] said softly, for a whisper: see softly in
/// speech_cues.dart.
String qwenSoftly(String direction) {
  var soft = SpeechDirection.whisper.say;
  return direction.isEmpty || direction == soft ? soft : "$direction $soft";
}

/// qwenSoftLevel is how loud a soft stretch is kept: asked to speak low,
/// the voice is hardly quieter, 2dB at most.
const qwenSoftLevel = 0.7;

final _leadingMarks = RegExp(r"^[.,!?;:…]+");

/// qwenScript is [lines] as one run's markup, a section a stretch, as cut
/// at every cue the voice audibly restarts. Laughs and coughs are written
/// as words; breaths, sighs and pauses as a "..." beat, our recording put in
/// after (see timeWords). Only a whisper's edge cuts a section; stress and
/// slowing are left to the direction.
QwenScript qwenScript(List<SpeechLine> lines) {
  var spoken = <QwenSpoken>[];
  var gaps = <List<QwenGap>>[[]];
  for (var (i, line) in lines.indexed) {
    if (i > 0) gaps.last.add(const QwenLineEnd());
    var words = <String>[];
    var cues = <int>{};
    var beats = <(int, QwenGap)>[];
    bool? whisper;
    // A cue with no words before it is written before the words after.
    String? before =
        line.own.isEmpty && line.direction == SpeechDirection.laughing
            ? "Haha,"
            : null;
    // A cue just written within a sentence: a comma after it before the
    // words go on.
    var cueOpen = false;
    void close() {
      if (words.isEmpty) return;
      spoken.add(QwenSpoken(words.join(" "),
          whisper: whisper ?? false, cues: {...cues}, beats: [...beats]));
      gaps.add([]);
      words.clear();
      cues.clear();
      beats.clear();
    }

    // A beat after the words so far: "..." on the last of them.
    void beat() {
      if (words.isEmpty) return;
      // A sentence's end is a pause already.
      if (RegExp(r"[.!?…]$").hasMatch(words.last)) return;
      words.last = "${words.last.replaceAll(RegExp(r"[,;:]$"), "")}...";
    }

    for (var p in parseScript(line.text)) {
      switch (p) {
        case SpokenText t:
          if (whisper != null && whisper != t.whisper && words.isNotEmpty) {
            // A whisper starting or ending: cut there, to whisper after.
            close();
            gaps.last.add(const QwenJoin());
          }
          whisper = t.whisper;
          // The program's own markup is not the reader's to write.
          var text =
              t.text.replaceAll("|", ",").replaceAll(RegExp(r"[\[\]]"), "");
          // A stop or comma written after a cue belongs to the words before.
          if (_leadingMarks.firstMatch(text) case var m?) {
            if (words.isNotEmpty) {
              words.last = "${words.last.replaceAll(RegExp(r"[,;:]$"), "")}"
                  "${m[0]}";
            }
            text = text.substring(m.end).trim();
            cueOpen = false;
          }
          for (var w in SpokenText(text).words) {
            if (before != null) {
              cues.add(words.length);
              words.add(before);
              before = null;
            }
            if (cueOpen) words.last = "${words.last},";
            cueOpen = false;
            words.add(w);
          }
        case SpokenPause s:
          beats.add((words.length, QwenPause(s.seconds)));
          beat();
        case SpokenSound s when qwenWritten.containsKey(s.cue):
          var (within, own) = qwenWritten[s.cue]!;
          if (words.isEmpty) {
            before = "${within[0].toUpperCase()}${within.substring(1)},";
          } else if (RegExp(r"[.!?]$").hasMatch(words.last)) {
            // After a sentence: a sentence of its own -- "Hi. Haha!"
            cues.add(words.length);
            words.add(own);
          } else {
            // Within one, after the words before it: "the way, haha".
            if (!RegExp(r"[,;:…]$").hasMatch(words.last)) {
              words.last = "${words.last},";
            }
            cues.add(words.length);
            words.add(within);
            cueOpen = true;
          }
        case SpokenSound s:
          beats.add((words.length, QwenSound(s.cue)));
          beat();
      }
    }
    close();
  }
  return QwenScript(spoken, gaps);
}

/// _readApart is WAV [bytes]' samples, read off the UI thread by a
/// top-level function: a closure would capture the unsendable program.
Future<Float32List?> _readApart(Uint8List bytes) =>
    Isolate.run(() => readWav16(ByteData.sublistView(bytes)));

/// QwenBeat is a beat in a stretch: [sound] at [at] seconds, and for a
/// pause the voice's own pause round it ([hush]) silenced too.
typedef QwenBeat = ({double at, Float32List sound, (double, double)? hush});

/// qwenPlaceBeats puts [beats] into [sound], fading the voice over 10ms
/// either side; returns the sound and each beat's place and length.
(Float32List, List<(double, double)>) qwenPlaceBeats(
    Float32List sound, List<QwenBeat> beats) {
  const fade = 480;
  var voice = Float32List.fromList(sound);
  for (var b in beats) {
    if (b.hush case (var from, var to)) {
      var a = (from * 48000).round().clamp(0, voice.length);
      var z = (to * 48000).round().clamp(a, voice.length);
      // Faded within the pause itself, where there is nothing to click.
      var edge = math.min(fade, (z - a) ~/ 4);
      for (var i = a; i < z; i++) {
        voice[i] *= edge == 0
            ? 0
            : i - a < edge
                ? 1 - (i - a) / edge
                : z - 1 - i < edge
                    ? 1 - (z - 1 - i) / edge
                    : 0;
      }
    }
  }
  var placed = [
    for (var b in beats)
      ((b.at * 48000).round().clamp(0, voice.length), b.sound)
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var out = <double>[];
  var moved = <(double, double)>[];
  var from = 0;
  for (var (at, insert) in placed) {
    var part = voice.sublist(from, at);
    for (var i = 0; i < fade && i < part.length; i++) {
      part[part.length - 1 - i] *= i / fade;
      if (from > 0) part[i] *= i / fade;
    }
    out.addAll(part);
    out.addAll(insert);
    moved.add((at / 48000, insert.length / 48000));
    from = at;
  }
  var rest = voice.sublist(from);
  for (var i = 0; i < fade && i < rest.length && from > 0; i++) {
    rest[i] *= i / fade;
  }
  out.addAll(rest);
  return (Float32List.fromList(out), moved);
}

/// qwenCut cuts [pcm] (24kHz) at exact silences of at least [least]
/// seconds; null without [markers] of them, as the run is not as written.
({List<Float32List> sounds, bool leading, bool trailing})? qwenCut(
    Float32List pcm, int markers,
    {double least = 0.35}) {
  // Asked for none: a silence of the voice's own is not a cut.
  if (markers == 0) return (sounds: [pcm], leading: false, trailing: false);
  var need = (least * 24000).round();
  var runs = <(int, int)>[];
  var start = -1;
  for (var i = 0; i <= pcm.length; i++) {
    var quiet = i < pcm.length && pcm[i] == 0;
    if (quiet) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      if (i - start >= need) runs.add((start, i));
      start = -1;
    }
  }
  if (runs.length != markers) return null;
  var sounds = <Float32List>[];
  var at = 0;
  for (var (a, b) in runs) {
    if (a > at) sounds.add(Float32List.sublistView(pcm, at, a));
    at = b;
  }
  if (at < pcm.length) sounds.add(Float32List.sublistView(pcm, at));
  return (
    sounds: sounds,
    leading: runs.isNotEmpty && runs.first.$1 == 0,
    trailing: runs.isNotEmpty && runs.last.$2 == pcm.length,
  );
}

/// qwenTrimmed is [pcm] (24kHz) without the model's near-silence round its
/// words (up to 1.5 s, a hesitation nobody wrote), a breath kept each end.
Float32List qwenTrimmed(Float32List pcm, {double floor = 0.004}) {
  var first = 0, last = pcm.length - 1;
  while (first < pcm.length && pcm[first].abs() < floor) {
    first++;
  }
  while (last > first && pcm[last].abs() < floor) {
    last--;
  }
  if (first >= pcm.length) return pcm;
  const margin = 960; // 40ms
  return Float32List.sublistView(pcm, (first - margin).clamp(0, pcm.length),
      (last + 1 + margin).clamp(0, pcm.length));
}

/// QwenSpeech speaks lines sharing a direction in one run, cut apart (see
/// qwenScript). A line far off its expected length is respoken alone with
/// another seed, twice at most, keeping the nearest.
class QwenSpeech extends SpeechEngine {
  @override
  Future<List<SpeechVoice>> voices() async => qwenVoices;

  @override
  bool get batches => true;

  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    var lines = spec.shownLines;
    if (lines.isEmpty) throw const SpeechException("The script is empty.");
    var takes = await speakLines(spec, lines);
    var pieces = <(Float32List, Float32List, List<TimedWord>)>[];
    for (var (i, t) in takes.indexed) {
      if (i > 0) pieces.add(silence(0.35));
      pieces.add((t.l, t.r, t.words));
    }
    return assembleTake(pieces);
  }

  @override
  Future<SpokenAudio> speakLine(SpeechSpec spec, SpeechLine line,
      {int seed = 1}) async {
    var dir = await _ready([line]);
    var words = SpokenText(spokenText(line)).words.length;
    var expected = words * 0.4 / spec.speed.clamp(0.7, 1.3);
    SpokenAudio? best;
    var bestOff = double.infinity;
    for (var attempt = 0; attempt < 3; attempt++) {
      var take = (await _run(dir, spec, [line], seed + attempt * 7919)).single;
      // How far out: its length against its words' expected length.
      var off = (take.seconds - expected).abs() / (expected + 0.5);
      if (off < bestOff) {
        best = take;
        bestOff = off;
      }
      if (!speechRunsOn(take.seconds, words, spec.speed)) break;
    }
    return best!;
  }

  @override
  Future<List<SpokenAudio>> speakLines(
      SpeechSpec spec, List<SpeechLine> lines) async {
    var dir = await _ready(lines);
    // Lines said the same way together: a run has one direction.
    var groups = <String, List<int>>{};
    for (var (i, l) in lines.indexed) {
      groups.putIfAbsent(qwenDirection(l, spec.expression), () => []).add(i);
    }
    var out = List<SpokenAudio?>.filled(lines.length, null);
    var seed = 1 + DateTime.now().microsecondsSinceEpoch % 100000;
    for (var group in groups.values) {
      var takes = await _run(dir, spec, [for (var i in group) lines[i]], seed);
      for (var (k, i) in group.indexed) {
        var take = takes[k];
        var words = SpokenText(spokenText(lines[i])).words.length;
        // Ran on, or stopped short: spoken again by itself.
        out[i] = speechRunsOn(take.seconds, words, spec.speed)
            ? await speakLine(spec, lines[i], seed: seed + 7919)
            : take;
      }
    }
    return [for (var t in out) t!];
  }

  /// _ready is the voices' folder, once sure [lines] can be spoken there.
  Future<String> _ready(List<SpeechLine> lines) async {
    if (lines.any((l) => spokenText(l).trim().isEmpty)) {
      throw const SpeechException("The line has no words.");
    }
    if (!qwenSupported && qwenFilesOverride == null) {
      throw const SpeechException(
          "The expressive voices are not made for this computer yet.");
    }
    var dir = await qwenDir();
    if (!await pinnedReady(dir, qwenFiles)) {
      throw const SpeechException(
          "The expressive voices are not downloaded yet: press Download.");
    }
    return dir;
  }

  /// _run speaks [lines], all said the same way, with cues in place; a run
  /// that cannot be cut as written is redone a line at a time.
  Future<List<SpokenAudio>> _run(
      String dir, SpeechSpec spec, List<SpeechLine> lines, int seed) async {
    // Told to be vivid, it breathes between sentences, as a voice given
    // the room does.
    var script = qwenScript([
      for (var l in lines)
        spec.expression > qwenBreathing
            ? l.copyWith(text: speechBreaths(l.text))
            : l,
    ]);
    var direction = qwenDirection(lines.first, spec.expression);
    var pieces = List<Float32List?>.filled(script.spoken.length, null);
    for (var run in script.runs) {
      stopper.check();
      var pcm = await _say(dir, spec,
          run.soft ? qwenSoftly(direction) : direction, run.text, seed,
          compose: run.stretches.length > 1);
      var cut = qwenCut(pcm, run.stretches.length - 1);
      if (cut != null && cut.sounds.length == run.stretches.length) {
        for (var (i, k) in run.stretches.indexed) {
          pieces[k] = cut.sounds[i];
        }
      } else if (lines.length > 1) {
        debugPrint("qwen_tts: a run of ${lines.length} lines did not cut "
            "as written; one at a time");
        return [
          for (var l in lines) ...await _run(dir, spec, [l], seed)
        ];
      } else {
        // One line's stretches cannot be told apart: each by itself.
        for (var k in run.stretches) {
          stopper.check();
          pieces[k] = await _say(
              dir,
              spec,
              run.soft ? qwenSoftly(direction) : direction,
              script.spoken[k].text,
              seed,
              compose: false);
        }
      }
    }
    var man =
        qwenVoices.where((v) => v.id == spec.voice).firstOrNull?.gender == "m";
    // Each line's pieces, in order: its gaps and its stretches.
    var takes = <List<(Float32List, Float32List, List<TimedWord>)>>[[]];
    Future<void> gap(List<QwenGap> items) async {
      for (var g in items) {
        switch (g) {
          case QwenLineEnd():
            takes.add([]);
          case QwenPause p:
            takes.last.add(silence(p.seconds));
          case QwenJoin():
            takes.last.add(silence(0.08));
          case QwenSound s:
            var sound = await cueRecording(s.cue, man: man);
            if (sound == null) break;
            takes.last.add((sound, Float32List.fromList(sound), const []));
            // A breath in leads straight into the words; a laugh, sigh or
            // cough has a moment after it.
            if (s.cue != SpeechCue.breath) takes.last.add(silence(0.12));
        }
      }
    }

    for (var (k, said) in script.spoken.indexed) {
      await gap(script.gaps[k]);
      var piece = pieces[k]!;
      var sound = await Isolate.run(() => upsample2x(qwenTrimmed(piece)));
      // Said softly, it is made quieter too: the voice speaks low but
      // hardly less loud.
      if (said.whisper) sound = softly(sound, by: qwenSoftLevel);
      // Timed, and its beats placed, by the voice's own pauses.
      var timed = timeWords(sound, SpokenText(said.text).words);
      var beats = <QwenBeat>[];
      for (var (after, gap) in said.beats) {
        var i = math.min(after, timed.words.length) - 1;
        var paused = i < 0 ? null : timed.after[i];
        var (a, b) = paused ??
            (i < 0
                ? (0.0, 0.0)
                : () {
                    var dip = quietestNear(sound, timed.words[i].end);
                    return (dip, dip);
                  }());
        switch (gap) {
          case QwenPause p:
            // The gap all silence, the voice's own pause with it, as long as
            // asked or as the voice's own, whichever is longer.
            beats.add((
              at: (a + b) / 2,
              sound: silence(math.max(0.0, p.seconds - (b - a))).$1,
              hush: paused,
            ));
          case QwenSound s:
            var cue = await cueRecording(s.cue, man: man);
            if (cue == null) break;
            beats.add(switch (s.cue) {
              // A breath in leads into the words after; one out follows
              // those before; a sigh has a moment either side.
              SpeechCue.breath => (
                  at: math.max(a, b - 0.04),
                  sound: cue,
                  hush: null
                ),
              SpeechCue.exhale => (
                  at: math.min(b, a + 0.03),
                  sound: cue,
                  hush: null
                ),
              _ => (
                  at: (a + b) / 2,
                  sound: Float32List.fromList([...cue, ...silence(0.1).$1]),
                  hush: null,
                ),
            });
          default:
        }
      }
      var words = said.spoken(timed.words);
      if (beats.isNotEmpty) {
        var (placed, moved) = qwenPlaceBeats(sound, beats);
        sound = placed;
        words = [
          for (var w in words)
            () {
              var by = 0.0;
              for (var (at, len) in moved) {
                if (w.start >= at - 0.02) by += len;
              }
              return (text: w.text, start: w.start + by, end: w.end + by);
            }(),
        ];
      }
      takes.last.add((sound, Float32List.fromList(sound), words));
    }
    await gap(script.gaps.last);
    return [for (var pieces in takes) assembleTake(pieces)];
  }

  /// _say runs the program on [text] said as [direction]: its take at
  /// 24kHz. Stop ends the program.
  Future<Float32List> _say(
      String dir, SpeechSpec spec, String direction, String text, int seed,
      {required bool compose}) async {
    stopper.check();
    var scratch = await Directory.systemTemp.createTemp("canvas-qwen");
    try {
      var out = path.join(scratch.path, "line.wav");
      var program = await Process.start(
          path.join(dir, qwenProgram),
          qwenArguments(dir, spec, direction, text, out,
              seed: seed, compose: compose));
      var forget = stopper.whenStopped(() => program.kill());
      var errors = StringBuffer();
      program.stdout.drain<void>();
      var said = program.stderr
          .transform(const SystemEncoding().decoder)
          .forEach(errors.write);
      var code = await program.exitCode;
      forget();
      stopper.check();
      await said;
      var file = File(out);
      if (code != 0 || !await file.exists()) {
        debugPrint("qwen_tts failed ($code): $errors");
        throw const SpeechException("The expressive voice could not speak "
            "the line: try again.");
      }
      var bytes = await file.readAsBytes();
      var pcm = await _readApart(bytes);
      if (pcm == null) {
        throw const SpeechException(
            "The expressive voice sent back nothing to play.");
      }
      return pcm;
    } finally {
      await scratch.delete(recursive: true);
    }
  }
}
