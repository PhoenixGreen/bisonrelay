import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/espeak.dart';
import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/media/speech_downloads.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_timing.dart';
import 'package:bruig/plugin_system/canvas/media/speech_text.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// kokoro_speech.dart is the Speech device's own voices: Kokoro (Apache 2.0)
// run locally by sherpa-onnx (Apache 2.0; from 2.0 without GPL espeak-ng).
// British, American and Chinese have dictionaries; the rest need espeak.dart.
// The model is downloaded once, pinned and SHA-256 checked; full precision,
// as int8 is three times slower on Apple Silicon.

/// KokoroFile is one of the model's files: its name, size and SHA-256.
typedef KokoroFile = ({String name, int bytes, String sha256});

/// kokoroRevision is the Hugging Face revision fetched: sherpa-onnx's
/// export of Kokoro v1.0, the same as its release archive.
const kokoroRevision = "f7b96bb6bef5c5da4d3aa4f4e0498fbbf62dc78b";

const kokoroFiles = <KokoroFile>[
  (
    name: "model.onnx",
    bytes: 325560556,
    sha256: "b40f62b166ac8164b0627ef48a0b358eda0985e272fb03ef5252e7206305da11"
  ),
  (
    name: "voices.bin",
    bytes: 28200960,
    sha256: "1c5a5b983d3d50d8586d437a51f3faa2da7919ce76a013c081e65671a3447c29"
  ),
  (
    name: "tokens.txt",
    bytes: 687,
    sha256: "6ebb6bb288f20f3ae8d004d3c2ca27697da27c037d75e81a60e2a6a663f95425"
  ),
  (
    name: "lexicon-gb-en.txt",
    bytes: 6366635,
    sha256: "c4cbb37316f62210dff52718a7afcaae24f50c032cc75ab47ae67b831d1049e7"
  ),
  (
    name: "lexicon-us-en.txt",
    bytes: 5956885,
    sha256: "7daaab53a181be9885b853a8582bf1838186317e5dadacbcef9c426d6fa0da14"
  ),
  // Chinese: its dictionary, and how numbers, dates and phone numbers are
  // said.
  (
    name: "lexicon-zh.txt",
    bytes: 2365182,
    sha256: "902bc2d20ac7c449c5ecbbbb23c89d12119c03ed5b8ed27f114f0260c9e35229"
  ),
  (
    name: "date-zh.fst",
    bytes: 59154,
    sha256: "eb8aa079ae3cb81d8f4404992f39d61a0cb990947512b5b8d1e54d1f6980e718"
  ),
  (
    name: "number-zh.fst",
    bytes: 64482,
    sha256: "743f402181fcfebf76cc2f0546b71fa26476e626fbe4e460fb7b4c3a7a8bd5bd"
  ),
  (
    name: "phone-zh.fst",
    bytes: 88630,
    sha256: "1ac2b6fa56b1442320c4de7db08353bab8963a2b57f365eebcdd3a2d3562f8d7"
  ),
];

/// kokoroBase and kokoroFilesOverride are where and which files are
/// fetched, for tests.
@visibleForTesting
String kokoroBase = "https://huggingface.co/csukuangfj/"
    "kokoro-multi-lang-v1_0/resolve/$kokoroRevision/";
@visibleForTesting
List<KokoroFile>? kokoroFilesOverride;

List<KokoroFile> get _files => kokoroFilesOverride ?? kokoroFiles;

/// kokoroBytes is the whole download, for saying how big it is first.
int get kokoroBytes => _files.fold(0, (n, f) => n + f.bytes);

/// _voiceTable is each voice: id, speaker number and grade (VOICES.md, A
/// best), by language, women then men, best first; espeak-ng voices last.
const _voiceTable = [
  ("bf_emma", 21, "B-"), ("bf_isabella", 22, "C"), ("bf_alice", 20, "D"), //
  ("bf_lily", 23, "D"),
  ("bm_george", 26, "C"), ("bm_fable", 25, "C"), ("bm_lewis", 27, "D+"),
  ("bm_daniel", 24, "D"),
  ("af_heart", 3, "A"), ("af_bella", 2, "A-"), ("af_nicole", 6, "B-"),
  ("af_aoede", 1, "C+"), ("af_kore", 5, "C+"), ("af_sarah", 9, "C+"),
  ("af_alloy", 0, "C"), ("af_nova", 7, "C"), ("af_sky", 10, "C-"),
  ("af_jessica", 4, "D"), ("af_river", 8, "D"),
  ("am_fenrir", 14, "C+"), ("am_michael", 16, "C+"), ("am_puck", 18, "C+"),
  ("am_echo", 12, "D"), ("am_eric", 13, "D"), ("am_liam", 15, "D"),
  ("am_onyx", 17, "D"), ("am_santa", 19, "D-"), ("am_adam", 11, "F+"),
  ("zf_xiaobei", 45, "D"), ("zf_xiaoni", 46, "D"), ("zf_xiaoxiao", 47, "D"),
  ("zf_xiaoyi", 48, "D"),
  ("zm_yunjian", 49, "D"), ("zm_yunxi", 50, "D"), ("zm_yunxia", 51, "D"),
  ("zm_yunyang", 52, "D"),
  ("ef_dora", 28, ""), ("em_alex", 29, ""), //
  ("ff_siwis", 30, "B-"),
  ("hf_alpha", 31, "C"), ("hf_beta", 32, "C"), ("hm_omega", 33, "C"),
  ("hm_psi", 34, "C"),
  ("if_sara", 35, "C"), ("im_nicola", 36, "C"),
  ("jf_alpha", 37, "C+"), ("jf_gongitsune", 38, "C"), ("jf_nezumi", 39, "C-"),
  ("jf_tebukuro", 40, "C"), ("jm_kumo", 41, "C-"),
  ("pf_dora", 42, ""), ("pm_alex", 43, ""), ("pm_santa", 44, ""),
];

/// _languages are what each voice's first letter says it speaks.
const _languages = {
  "b": "UK",
  "a": "US",
  "z": "Chinese",
  "e": "Spanish",
  "f": "French",
  "h": "Hindi",
  "i": "Italian",
  "j": "Japanese",
  "p": "Portuguese",
};

/// kokoroVoices are the voices, each named and described: "UK woman · B-".
final kokoroVoices = [
  for (var (id, _, grade) in _voiceTable)
    SpeechVoice(
        id,
        id[3].toUpperCase() + id.substring(4),
        "${_languages[id[0]]} "
        "${id[1] == "f" ? "woman" : "man"}${grade.isEmpty ? "" : " · $grade"}",
        gender: id[1]),
];

final _speakerOf = {for (var (id, sid, _) in _voiceTable) id: sid};

/// _Tongue is what a voice speaks: the dictionaries it needs, its own or,
/// with [espeak], espeak-ng's.
enum _Tongue {
  british,
  american,
  chinese,
  spanish("es"),
  french("fr-fr"),
  hindi("hi"),
  italian("it"),
  japanese("ja"),
  portuguese("pt-br");

  final String? espeak;
  const _Tongue([this.espeak]);
}

_Tongue _tongueOf(String voice) => switch (voice.isEmpty ? "b" : voice[0]) {
      "a" => _Tongue.american,
      "z" => _Tongue.chinese,
      "e" => _Tongue.spanish,
      "f" => _Tongue.french,
      "h" => _Tongue.hindi,
      "i" => _Tongue.italian,
      "j" => _Tongue.japanese,
      "p" => _Tongue.portuguese,
      _ => _Tongue.british,
    };

/// needsEspeak is whether [voice] speaks with espeak-ng's help.
bool needsEspeak(String voice) => _tongueOf(voice).espeak != null;

/// kokoroDir is where the model is kept, there or not. Tests may move it.
Future<String> Function() kokoroDir = () async =>
    path.join(await CanvasStorage.libraryDir(), canvasVoicesFolder, "kokoro-v1_0");

/// _pinned are the files as the shared downloader takes them.
List<PinnedFile> get _pinned => [
      for (var f in _files)
        (
          url: "$kokoroBase${f.name}",
          path: f.name,
          bytes: f.bytes,
          sha256: f.sha256,
          executable: false,
        ),
    ];

/// kokoroReady is whether every file is there at its size.
Future<bool> kokoroReady() async => pinnedReady(await kokoroDir(), _pinned);

/// downloadKokoro is [downloadPinned] for Kokoro's files.
Future<String?> downloadKokoro(
        {void Function(double share)? progress, bool Function()? stop}) async =>
    downloadPinned(await kokoroDir(), _pinned, progress: progress, stop: stop);

/// KokoroDownload is the voices' download, shared by every Speech device.
class KokoroDownload extends PinnedDownload {
  static final instance = KokoroDownload();
  KokoroDownload() : super(() => kokoroDir(), () => _pinned);
}

/// kokoroSoftLevel is how loud a whisper is kept: Kokoro cannot be told to
/// speak low, so it is only quieter.
const kokoroSoftLevel = 0.55;

/// KokoroSpeech speaks with Kokoro, locally. Breaths, laughs, sighs and
/// coughs are recordings; a whisper is the voice said softly (see
/// speech_cues.dart). It cannot stress a word, so that cue is dropped.
class KokoroSpeech extends SpeechEngine {
  /// library is sherpa-onnx's library path, for tests; null in the app,
  /// where it is already loaded.
  static String? library;

  /// voices are all of them; those needing a missing espeak-ng say so.
  @override
  Future<List<SpeechVoice>> voices() async {
    if (await espeakPath() != null) return kokoroVoices;
    return [
      for (var v in kokoroVoices)
        needsEspeak(v.id)
            ? SpeechVoice(
                v.id, v.name, "${v.about.split(" · ").first} · needs espeak-ng",
                gender: v.gender)
            : v,
    ];
  }

  /// _symbol is a function every sherpa-onnx library has, looked for to
  /// tell a library never loaded from a voice that failed.
  static const _symbol = "SherpaOnnxCreateOfflineTts";

  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async =>
      (await _speakAll(spec, [spec.script])).single;

  /// Kokoro loads its model on each call (most of a short line's time), so
  /// a script's lines are spoken in one call.
  @override
  bool get batches => true;

  @override
  Future<List<SpokenAudio>> speakLines(
          SpeechSpec spec, List<SpeechLine> lines) =>
      _speakAll(spec, [for (var l in lines) lineScript(l)]);

  /// _speakAll speaks a take of each of [scripts], loading the model once.
  Future<List<SpokenAudio>> _speakAll(
      SpeechSpec spec, List<String> scripts) async {
    var parsed = [for (var s in scripts) parseScript(s)];
    if (parsed.isEmpty || parsed.any((p) => !p.any((x) => x is SpokenText))) {
      throw const SpeechException("The script is empty.");
    }
    if (!await kokoroReady()) {
      throw const SpeechException(
          "The voices are not downloaded yet: press Download.");
    }
    // A new native library loads only on a full app start, not a hot
    // restart.
    if (library == null &&
        !Platform.isIOS &&
        !ffi.DynamicLibrary.process().providesSymbol(_symbol)) {
      throw const SpeechException("The voices' library is not loaded: quit "
          "the app and start it again -- a hot restart does not load it.");
    }
    var dir = await kokoroDir();
    var voice = _speakerOf.containsKey(spec.voice) ? spec.voice : "bf_emma";
    var speaker = _speakerOf[voice]!;
    var tongue = _tongueOf(voice);
    // A language Kokoro has no dictionary for: espeak-ng's, where it is.
    String? espeak;
    if (tongue.espeak != null) {
      espeak = await espeakPath();
      if (espeak == null) throw const SpeechException(espeakHelp);
    }
    // What is said, a stretch at a time at its speed, and the pauses.
    var jobs = <(String, double)>[
      for (var pieces in parsed)
        for (var p in pieces)
          if (p is SpokenText)
            (p.words.join(" "), spec.speed * (p.slow ? 0.8 : 1))
    ];
    var lib = library;
    // Resampled to the mix's rate in the isolate too, off the UI isolate.
    var spoken = await Isolate.run(() => [
          for (var s in _say(dir, lib, speaker, tongue, jobs, espeak: espeak))
            upsample2x(s)
        ]);
    var takes = <SpokenAudio>[];
    var k = 0;
    for (var pieces in parsed) {
      takes.add(await _assemble(pieces, spoken, k, voice));
      k += pieces.whereType<SpokenText>().length;
    }
    return takes;
  }

  /// _assemble is one script's take: [pieces], their words from [spoken]
  /// from [from] on, with pauses and cues between.
  Future<SpokenAudio> _assemble(List<SpeechPiece> pieces,
      List<Float32List> spoken, int from, String voice) async {
    var out = <(Float32List, Float32List, List<TimedWord>)>[];
    var k = from;
    for (var p in pieces) {
      switch (p) {
        case SpokenPause s:
          out.add(silence(s.seconds));
        case SpokenText t:
          var sound = spoken[k++];
          if (t.whisper) sound = softly(sound, by: kokoroSoftLevel);
          // Timed by the voice's own pauses, or failing those the words'
          // lengths.
          var timed = timeWords(sound, t.words).words;
          out.add((
            sound,
            Float32List.fromList(sound),
            timed.isEmpty
                ? estimateWords(t.words, 0, sound.length / 48000)
                : timed
          ));
        case SpokenSound s:
          var sound = await cueRecording(s.cue, man: voice[1] == "m");
          if (sound == null) break;
          out.add((sound, Float32List.fromList(sound), const []));
          // A breath leads straight into the words; a laugh, sigh or cough
          // has a moment after it.
          if (s.cue != SpeechCue.breath) out.add(silence(0.12));
      }
    }
    return assembleTake(out);
  }
}

/// _say runs Kokoro on [jobs] in its own isolate: the model loaded once,
/// each stretch at 24kHz.
List<Float32List> _say(String dir, String? library, int speaker, _Tongue tongue,
    List<(String, double)> jobs,
    {String? espeak}) {
  if (tongue.espeak case var language?) {
    return _sayWithEspeak(dir, library, speaker, language, espeak!, jobs);
  }
  // The dictionary's script plus our own dictionary for missing words (see
  // speech_text.dart). Chinese stays as written; English in it is American.
  var british = tongue == _Tongue.british;
  var main =
      path.join(dir, british ? "lexicon-gb-en.txt" : "lexicon-us-en.txt");
  var lexicon = readLexicon(File(main).readAsStringSync());
  var texts = [
    for (var (text, _) in jobs)
      tongue == _Tongue.chinese ? spacedChinese(text) : speakable(text)
  ];
  var extra = <String, String>{};
  for (var t in texts) {
    extra.addAll(missingWords(t, lexicon, american: !british));
  }
  var lexicons = tongue == _Tongue.chinese
      ? "$main,${path.join(dir, "lexicon-zh.txt")}"
      : main;
  Directory? scratch;
  if (extra.isNotEmpty) {
    scratch = Directory.systemTemp.createTempSync("canvas-words");
    var file = File(path.join(scratch.path, "lexicon-ours.txt"));
    file.writeAsStringSync(
        [for (var e in extra.entries) "${e.key} ${e.value}"].join("\n"));
    lexicons = "$lexicons,${file.path}";
  }
  sherpa.initBindings(library);
  var tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: path.join(dir, "model.onnx"),
        voices: path.join(dir, "voices.bin"),
        tokens: path.join(dir, "tokens.txt"),
        // No language: from sherpa-onnx 2.0 the dictionaries say it, and
        // one given is warned about on every model load.
        lexicon: lexicons,
      ),
      numThreads: math.max(1, math.min(4, Platform.numberOfProcessors - 1)),
    ),
    ruleFsts: tongue == _Tongue.chinese
        ? [
            for (var f in ["date-zh.fst", "phone-zh.fst", "number-zh.fst"])
              path.join(dir, f)
          ].join(",")
        : "",
    maxNumSentences: 1,
  ));
  try {
    return [
      for (var (i, (_, speed)) in jobs.indexed)
        tts
            .generateWithConfig(
                text: texts[i],
                config: sherpa.OfflineTtsGenerationConfig(
                    sid: speaker, speed: speed))
            .samples,
    ];
  } finally {
    tts.free();
    scratch?.deleteSync(recursive: true);
  }
}

/// _sayWithEspeak is [_say] for a language without a dictionary: espeak-ng
/// [exe] makes one of every word in [language], numbers included.
List<Float32List> _sayWithEspeak(String dir, String? library, int speaker,
    String language, String exe, List<(String, double)> jobs) {
  var tokens =
      readTokens(File(path.join(dir, "tokens.txt")).readAsStringSync());
  var words = {
    for (var (text, _) in jobs)
      for (var w in wordsOf(text)) w.toLowerCase(),
  };
  var lexicon = espeakLexicon(exe, language, words, tokens);
  if (lexicon.isEmpty) {
    throw const SpeechException("espeak-ng said nothing for the script.");
  }
  var scratch = Directory.systemTemp.createTempSync("canvas-words");
  var file = File(path.join(scratch.path, "lexicon-espeak.txt"))
    ..writeAsStringSync(
        [for (var e in lexicon.entries) "${e.key} ${e.value}"].join("\n"));
  sherpa.initBindings(library);
  var tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: path.join(dir, "model.onnx"),
        voices: path.join(dir, "voices.bin"),
        tokens: path.join(dir, "tokens.txt"),
        lexicon: file.path,
      ),
      numThreads: math.max(1, math.min(4, Platform.numberOfProcessors - 1)),
    ),
    maxNumSentences: 1,
  ));
  try {
    return [
      for (var (text, speed) in jobs)
        tts
            .generateWithConfig(
                text: text,
                config: sherpa.OfflineTtsGenerationConfig(
                    sid: speaker, speed: speed))
            .samples,
    ];
  } finally {
    tts.free();
    scratch.deleteSync(recursive: true);
  }
}
