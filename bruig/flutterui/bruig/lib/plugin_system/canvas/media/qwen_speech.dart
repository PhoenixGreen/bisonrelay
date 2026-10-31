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

/// qwenArguments are the program's for [line]: the voice, the language,
/// the direction, how steady (temperature and nucleus), how fast, and
/// [seed] -- another seed, another take.
List<String> qwenArguments(
    String dir, SpeechSpec spec, SpeechLine line, String text, String out,
    {required int seed}) {
  var voice = qwenVoices.any((v) => v.id == spec.voice) ? spec.voice : "ryan";
  var language =
      qwenLanguages.contains(spec.language) ? spec.language : "English";
  var steady = spec.steadiness.clamp(0.0, 1.0);
  var rate = spec.speed.clamp(0.7, 1.3);
  var direction = qwenDirection(line, spec.expression);
  // A line that runs on is stopped at three times as long as its words
  // should take.
  var words = text.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).length;
  var most = 4 + words * 0.4 * 3 / rate;
  return [
    "-d", dir, //
    "--int8",
    "-s", voice,
    "-l", language,
    if (direction.isNotEmpty) ...["--instruct", direction],
    "-T", (0.9 - 0.6 * steady).toStringAsFixed(2),
    "-p", (1 - 0.15 * steady).toStringAsFixed(2),
    if (rate != 1) ...["--rate", rate.toStringAsFixed(2)],
    "--seed", "$seed",
    "--max-duration", most.toStringAsFixed(0),
    "--text", text,
    "-o", out,
    "-S",
  ];
}

/// spokenText is [line]'s words as the expressive voices say them: its
/// cues left out, which they cannot do -- its direction does instead.
String spokenText(SpeechLine line) => [
      for (var p in parseScript(line.text))
        if (p is SpokenText) p.text
    ].join(" ");

/// QwenSpeech speaks with the expressive voices, a line at a time. A line
/// that comes out far longer or shorter than its words should take -- the
/// model running on, or stopping short -- is spoken again with another
/// seed, twice at most; the nearest is kept.
class QwenSpeech extends SpeechEngine {
  @override
  Future<List<SpeechVoice>> voices() async => qwenVoices;

  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    var lines = spec.shownLines;
    if (lines.isEmpty) throw const SpeechException("The script is empty.");
    var takes = [for (var l in lines) await speakLine(spec, l)];
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
    var text = spokenText(line);
    if (text.trim().isEmpty) {
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
    var words = SpokenText(text).words;
    var expected = words.length * 0.4 / spec.speed.clamp(0.7, 1.3);
    SpokenAudio? best;
    var bestOff = double.infinity;
    for (var attempt = 0; attempt < 3; attempt++) {
      var take = await _run(dir, spec, line, text, seed + attempt * 7919);
      // How far out it is: its length against what its words should take.
      var off = (take.seconds - expected).abs() / (expected + 0.5);
      if (off < bestOff) {
        best = take;
        bestOff = off;
      }
      if (!speechRunsOn(take.seconds, words.length, spec.speed)) break;
    }
    return best!;
  }

  Future<SpokenAudio> _run(String dir, SpeechSpec spec, SpeechLine line,
      String text, int seed) async {
    var scratch = await Directory.systemTemp.createTemp("canvas-qwen");
    try {
      var out = path.join(scratch.path, "line.wav");
      var run = await Process.run(path.join(dir, qwenProgram),
          qwenArguments(dir, spec, line, text, out, seed: seed));
      var file = File(out);
      if (run.exitCode != 0 || !await file.exists()) {
        debugPrint("qwen_tts failed (${run.exitCode}): ${run.stderr}");
        throw const SpeechException("The expressive voice could not speak "
            "the line: try again.");
      }
      var bytes = await file.readAsBytes();
      var sound = await Isolate.run(() {
        var pcm = readWav16(ByteData.sublistView(bytes));
        return pcm == null ? null : upsample2x(pcm);
      });
      if (sound == null) {
        throw const SpeechException(
            "The expressive voice sent back nothing to play.");
      }
      return SpokenAudio(sound, Float32List.fromList(sound),
          estimateWords(SpokenText(text).words, 0, sound.length / 48000));
    } finally {
      await scratch.delete(recursive: true);
    }
  }
}
