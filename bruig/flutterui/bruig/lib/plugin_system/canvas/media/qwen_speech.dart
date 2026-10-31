import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/media/speech_downloads.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// qwen_speech.dart is the Speech device's expressive voices: Qwen3-TTS
// 1.7B CustomVoice (Apache 2.0), nine voices that take a direction in
// plain words for each line -- "laughing as you speak", "close to tears".
// It is run by qwen3-tts (MIT), a C program that speaks with the model on
// the computer's own processor.
//
// Neither is shipped with the app. Both are downloaded once, when the
// Speech device asks, to the Canvas library's "voices" folder: the program
// from its project's release, the model from a fixed revision, every file
// checked against its SHA-256 before it is kept. The program is built for
// Apple Silicon Macs and for Linux; elsewhere the expressive voices are not
// offered.
//
// The program is run once for each line, then ends. It has a server mode
// that would keep the model loaded between lines, but that listens on every
// network the computer is on, not only on the computer itself -- so it is
// not used.

/// qwenVersion is the program's release; qwenRevision the model's.
const qwenVersion = "v0.23.0";
const qwenRevision = "0c0e3051f131929182e2c023b9537f8b1c68adfe";

/// _programs are the program's builds: one for each computer it runs on,
/// its size and SHA-256.
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

/// qwenProgram is the program's name in its folder.
const qwenProgram = "qwen_tts";

/// qwenSupported is whether the program is built for this computer.
bool get qwenSupported => _programs.containsKey(Abi.current());

/// qwenFilesOverride is what is downloaded instead, and qwenDir where to:
/// both for tests.
@visibleForTesting
List<PinnedFile>? qwenFilesOverride;

Future<String> Function() qwenDir = () async =>
    path.join(await CanvasStorage.libraryDir(), "voices", "qwen3-tts-1.7b");

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

/// qwenBytes is the whole download, for saying how big it is first.
int get qwenBytes => qwenFiles.fold(0, (n, f) => n + f.bytes);

/// QwenDownload is the expressive voices' download, one for every Speech
/// device.
class QwenDownload extends PinnedDownload {
  static final instance = QwenDownload();
  QwenDownload() : super(() => qwenDir(), () => qwenFiles);
}

/// qwenVoices are the nine, each with the accent it keeps in every
/// language it speaks.
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

/// qwenLanguages are what the voices speak.
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

/// qwenDirection is what the voice is told for [line], with [expression]
/// -- nought to one -- saying how far to take it.
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

/// qwenSampling is how freely the voice is let go, from [steadiness] --
/// nought to one -- for a line with a direction or without: the
/// temperature, and the nucleus. The engine's own, at the middle: 0.9 as
/// the model comes, and 1.1 with a direction, which a lower one flattens
/// into the voice saying it as written (Ken, 2026-10-31). Steadier
/// narrows both.
(double, double) qwenSampling(double steadiness, {required bool directed}) {
  var s = steadiness.clamp(0.0, 1.0);
  var temperature = (directed ? 1.25 : 1.05) - 0.3 * s;
  var nucleus = s <= 0.5 ? 1.0 : 1.0 - 0.2 * (s - 0.5);
  return (temperature, nucleus);
}

/// qwenArguments are the program's for [text] -- a line's words, or a
/// script of several as qwenScript writes them -- said as [direction]:
/// the voice, the language, the direction, how freely (temperature and
/// nucleus), how fast, and [seed] -- another seed, another take.
List<String> qwenArguments(
    String dir, SpeechSpec spec, String direction, String text, String out,
    {required int seed, bool compose = false}) {
  var voice = qwenVoices.any((v) => v.id == spec.voice) ? spec.voice : "ryan";
  var language =
      qwenLanguages.contains(spec.language) ? spec.language : "English";
  var (temperature, nucleus) =
      qwenSampling(spec.steadiness, directed: direction.isNotEmpty);
  var rate = spec.speed.clamp(0.7, 1.3);
  // A line that runs on is stopped at three times as long as its words
  // should take.
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

/// spokenText is [line]'s words as the expressive voices say them: its
/// cues left out -- they are put in afterwards, see qwenScript.
String spokenText(SpeechLine line) => [
      for (var p in parseScript(line.text))
        if (p is SpokenText) p.text
    ].join(" ");

// ---------------------------------------------------------------------------
// Several lines, and their cues, in one run
// ---------------------------------------------------------------------------
//
// The program loads its model for each run -- nine seconds of a short line's
// twenty -- and has no way to be given lines one after another but its
// server, which listens on every network. So the lines sharing a direction
// are spoken in one run, written with the program's own markup: each line,
// and each cue in it, kept apart by a pause. A pause it renders as exact
// silence, which speech never is: the take is cut at those, and the cues --
// our recordings, a whisper, a pause of the length asked for -- put back in
// their places.

/// QwenGap is what is between two stretches of speech in a run: the lines'
/// ends, and the cues.
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

/// QwenSpoken is one stretch of speech in a run: what it says, whether it
/// is whispered, and which of its words are a laugh -- written into the
/// words, not timed as one.
class QwenSpoken {
  final String text;
  final bool whisper;
  final Set<int> laughs;
  const QwenSpoken(this.text, {this.whisper = false, this.laughs = const {}});

  /// words are its words, timed across [seconds], the laughs left out.
  List<TimedWord> words(double seconds) {
    var all = estimateWords(SpokenText(text).words, 0, seconds);
    return [
      for (var (i, w) in all.indexed)
        if (!laughs.contains(i)) w
    ];
  }
}

/// qwenLaugh is a laugh as the expressive voices are given it: written into
/// the words, so they laugh into them -- a laugh of their own, put before
/// or after, stopped dead where the words began (Ken, 2026-10-31).
const qwenLaugh = "Haha,";

/// QwenScript is a run's text, and what it is to be cut into: its stretches
/// of speech in order and the gaps round them, each a list, as several can
/// fall together.
class QwenScript {
  final String text;
  final List<QwenSpoken> spoken;

  /// gaps are those before each stretch, and after the last: one more than
  /// [spoken]. An empty one is no gap, and no pause in [text].
  final List<List<QwenGap>> gaps;
  const QwenScript(this.text, this.spoken, this.gaps);

  /// markers is how many pauses [text] has, which the take must be cut at.
  int get markers => gaps.where((g) => g.isNotEmpty).length;
}

/// qwenMarkLine and qwenMarkCue are the pauses written for a line's end
/// and a cue: told apart by nothing but their order, they need only be
/// longer than any silence speech has.
const qwenMarkLine = 1.2;
const qwenMarkCue = 0.6;

/// qwenScript is [lines] as one run's markup. The cues the expressive
/// voices cannot do mid-line -- stressing a word, a slower stretch -- are
/// left out: the line's direction says those. A laugh -- the cue, or a line
/// said laughing -- is written into the words: see qwenLaugh.
QwenScript qwenScript(List<SpeechLine> lines) {
  var spoken = <QwenSpoken>[];
  var gaps = <List<QwenGap>>[[]];
  for (var (i, line) in lines.indexed) {
    if (i > 0) gaps.last.add(const QwenLineEnd());
    bool? whisper;
    // A laugh waiting for the words after it, and whether the last stretch
    // is this line's, with nothing between it and here: a laugh there is
    // written into it.
    var laughNext =
        line.own.isEmpty && line.direction == SpeechDirection.laughing;
    var open = false;
    // A laugh after the last words: written after them.
    void laughAfter(int k) {
      var was = spoken[k];
      spoken[k] = QwenSpoken("${was.text} ${qwenLaugh.replaceAll(",", "!")}",
          whisper: was.whisper,
          laughs: {...was.laughs, SpokenText(was.text).words.length});
    }

    for (var p in parseScript(line.text)) {
      switch (p) {
        case SpokenText t:
          // A whisper starting or ending mid-speech is cut there, to be
          // whispered after.
          if (whisper != null && whisper != t.whisper && gaps.last.isEmpty) {
            gaps.last.add(const QwenJoin());
          }
          whisper = t.whisper;
          // The program's own markup is not the reader's to write.
          var text =
              t.text.replaceAll("|", ",").replaceAll(RegExp(r"[\[\]]"), "");
          if (laughNext && open && gaps.last.isEmpty) {
            // Laughed between words: one stretch, the laugh in it.
            var was = spoken.last;
            var at = SpokenText(was.text).words.length;
            spoken.last = QwenSpoken("${was.text} $qwenLaugh $text",
                whisper: was.whisper, laughs: {...was.laughs, at});
          } else {
            spoken.add(QwenSpoken(laughNext ? "$qwenLaugh $text" : text,
                whisper: t.whisper, laughs: {if (laughNext) 0}));
            gaps.add([]);
          }
          laughNext = false;
          open = true;
        case SpokenPause s:
          gaps.last.add(QwenPause(s.seconds));
          open = false;
        case SpokenSound s when s.cue == SpeechCue.laugh:
          laughNext = true;
        case SpokenSound s:
          gaps.last.add(QwenSound(s.cue));
          open = false;
      }
    }
    // A laugh after the last words: after them, in the same breath.
    if (laughNext && open && spoken.isNotEmpty && gaps.last.isEmpty) {
      laughAfter(spoken.length - 1);
    }
  }
  var text = StringBuffer();
  for (var (k, gap) in gaps.indexed) {
    if (gap.isNotEmpty) {
      var mark = gap.any((g) => g is QwenLineEnd) ? qwenMarkLine : qwenMarkCue;
      text.write(" [pause:${mark}s] ");
    }
    if (k < spoken.length) text.write(spoken[k].text);
  }
  return QwenScript(text.toString().trim(), spoken, gaps);
}

/// qwenCut cuts [pcm] -- a run's take, at 24kHz -- at its exact silences of
/// at least [least] seconds: the stretches of sound between, and whether
/// it began and ended with one. Null where it has not [markers] of them,
/// for a run that is not as written.
({List<Float32List> sounds, bool leading, bool trailing})? qwenCut(
    Float32List pcm, int markers,
    {double least = 0.35}) {
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

/// qwenTrimmed is [pcm], at 24kHz, without the near-silence the model
/// leaves before and after its words -- a second and a half of it, at
/// times, which joined into a take is a hesitation nobody wrote. A breath
/// of it is kept at each end.
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

/// QwenSpeech speaks with the expressive voices: the lines sharing a
/// direction in one run, cut apart -- see qwenScript. A line that comes out
/// far longer or shorter than its words should take -- the model running
/// on, or stopping short -- is spoken again by itself with another seed,
/// twice at most; the nearest is kept.
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
      // How far out it is: its length against what its words should take.
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
    // The lines said the same way, together: a run's direction is one.
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

  /// _ready is the folder the voices are in, once it is sure [lines] can be
  /// spoken there.
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

  /// _run speaks [lines], all said the same way, in one run: a take of each,
  /// its cues in place. A run that cannot be cut as it was written is done
  /// again a line at a time.
  Future<List<SpokenAudio>> _run(
      String dir, SpeechSpec spec, List<SpeechLine> lines, int seed) async {
    var script = qwenScript(lines);
    var pcm = await _say(dir, spec, qwenDirection(lines.first, spec.expression),
        script.text, seed,
        compose: script.markers > 0);
    var cut = qwenCut(pcm, script.markers);
    var expected = script.spoken.length;
    if (cut == null || cut.sounds.length != expected) {
      if (lines.length > 1) {
        debugPrint("qwen_tts: a run of ${lines.length} lines did not cut "
            "as written; one at a time");
        return [
          for (var l in lines) ...await _run(dir, spec, [l], seed)
        ];
      }
      // One line, its cues not to be found: its words as they came.
      var whole = upsample2x(qwenTrimmed(pcm));
      return [
        SpokenAudio(
            whole,
            Float32List.fromList(whole),
            estimateWords(SpokenText(spokenText(lines.single)).words, 0,
                whole.length / 48000))
      ];
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
            // A breath leads straight into the words; a laugh, a sigh or a
            // cough has a moment after it.
            if (s.cue != SpeechCue.breath) takes.last.add(silence(0.12));
        }
      }
    }

    for (var (k, said) in script.spoken.indexed) {
      await gap(script.gaps[k]);
      var piece = cut.sounds[k];
      var sound = await Isolate.run(() => upsample2x(qwenTrimmed(piece)));
      if (said.whisper) sound = whispered(sound);
      takes.last.add((
        sound,
        Float32List.fromList(sound),
        said.words(sound.length / 48000)
      ));
    }
    await gap(script.gaps.last);
    return [for (var pieces in takes) assembleTake(pieces)];
  }

  /// _say runs the program on [text], said as [direction]: its take at
  /// 24kHz, as it wrote it.
  Future<Float32List> _say(
      String dir, SpeechSpec spec, String direction, String text, int seed,
      {required bool compose}) async {
    var scratch = await Directory.systemTemp.createTemp("canvas-qwen");
    try {
      var out = path.join(scratch.path, "line.wav");
      var run = await Process.run(
          path.join(dir, qwenProgram),
          qwenArguments(dir, spec, direction, text, out,
              seed: seed, compose: compose));
      var file = File(out);
      if (run.exitCode != 0 || !await file.exists()) {
        debugPrint("qwen_tts failed (${run.exitCode}): ${run.stderr}");
        throw const SpeechException("The expressive voice could not speak "
            "the line: try again.");
      }
      var bytes = await file.readAsBytes();
      var pcm = await Isolate.run(() => readWav16(ByteData.sublistView(bytes)));
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
