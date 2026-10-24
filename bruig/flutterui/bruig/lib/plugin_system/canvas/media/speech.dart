import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// speech.dart is a voice-over heard as words: what is said, and when.
//
// The pauses in a recording say where its lines start -- see speechStarts --
// but not what the lines are, so cues found that way are called "Line 1" to
// "Line 53", and an element meant to arrive on "$300" has to be put there by
// ear. whisper.cpp hears the words and their times on the reader's own
// machine. Like ffmpeg it is the reader's program rather than one shipped
// here, and nothing is sent anywhere: the recording never leaves the disk.

/// speechModelName is the model whisper listens with: the small English one,
/// about 150 MB, which hears a clear voice-over word for word.
const speechModelName = "ggml-base.en.bin";

/// speechModelUrl is where that model is published by whisper.cpp's authors.
const speechModelUrl =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$speechModelName";

/// speechModelBytes is the most a download of it may be.
const speechModelBytes = 200 * 1024 * 1024;

/// speechHelp is what to do when whisper is not installed: the exact
/// commands, as ffmpegHelp gives them.
const speechHelp = "Hearing the words needs whisper.cpp, which is not "
    "installed. Install it with \"brew install whisper-cpp\" on a Mac, or "
    "build it from github.com/ggml-org/whisper.cpp, then restart.";

/// speechModelMissing is what to say when whisper is there and its model is
/// not: the one thing left, which the Cues section offers to fetch.
const speechModelMissing = "whisper needs its speech model "
    "($speechModelName, about 150 MB) before it can hear anything.";

/// HeardWord is one word and when it is said, in seconds from the start of
/// the stretch that was heard.
typedef HeardWord = ({String text, double start, double end});

bool _looked = false;
String? _found;
const _candidates = [
  "/opt/homebrew/bin/whisper-cli",
  "/usr/local/bin/whisper-cli",
  "/usr/bin/whisper-cli",
];

/// whisperPath is where whisper.cpp's command is, or null.
Future<String?> whisperPath() async {
  if (_looked) return _found;
  _looked = true;
  if (Platform.isAndroid || Platform.isIOS) return null;
  try {
    var which = Platform.isWindows ? "where" : "which";
    var found = await Process.run(which, ["whisper-cli"]);
    if (found.exitCode == 0) {
      var first = (found.stdout as String).trim().split("\n").first.trim();
      if (first.isNotEmpty && await File(first).exists()) return _found = first;
    }
  } catch (exception) {
    debugPrint("Unable to look for whisper on the path: $exception");
  }
  for (var candidate in _candidates) {
    if (await File(candidate).exists()) return _found = candidate;
  }
  return _found = null;
}

/// useWhisperForTest fixes what [whisperPath] answers; null pins "not there".
@visibleForTesting
void useWhisperForTest(String? path) {
  _looked = true;
  _found = path;
}

/// speechModelPath is where the model is kept: beside the library, in a
/// dotted folder the library's own listing skips.
Future<String> speechModelPath() async =>
    path.join(await CanvasStorage.libraryDir(), ".models", speechModelName);

/// listenTo is what is said in [audio] from [from] seconds to [to] (the end
/// when null), word by word, or null when it could not be heard.
Future<List<HeardWord>?> listenTo(
    {required String whisper,
    required String ffmpeg,
    required String model,
    required String audio,
    double from = 0,
    double? to}) async {
  Directory? work;
  try {
    work = await Directory.systemTemp.createTemp("canvas-speech");
    // whisper reads 16 kHz mono WAV and nothing else; ffmpeg cuts the
    // stretch that plays at the same time as it converts.
    var wav = path.join(work.path, "voice.wav");
    var cut = await Process.run(ffmpeg, [
      "-y",
      "-loglevel",
      "error",
      if (from > 0) ...["-ss", "$from"],
      if (to != null) ...["-to", "$to"],
      "-i",
      audio,
      "-ar",
      "16000",
      "-ac",
      "1",
      wav,
    ]);
    if (cut.exitCode != 0) return null;
    var out = path.join(work.path, "words");
    // One word a segment (-ml 1), split on words rather than tokens (-sow),
    // written as start,end,text in milliseconds.
    var heard = await Process.run(whisper,
        ["-m", model, "-f", wav, "-ml", "1", "-sow", "-np", "-ocsv", "-of", out]);
    var csv = File("$out.csv");
    if (heard.exitCode != 0 || !await csv.exists()) return null;
    return parseHeardWords(await csv.readAsString());
  } catch (exception) {
    debugPrint("Unable to hear the words: $exception");
    return null;
  } finally {
    try {
      await work?.delete(recursive: true);
    } catch (_) {}
  }
}

/// parseHeardWords reads whisper's CSV: a heading, then start,end,"text" in
/// milliseconds. The text keeps its own commas -- "8,640" is one word -- so
/// only the first two commas split a line. Empty words, which whisper writes
/// for a breath, are left out.
List<HeardWord> parseHeardWords(String csv) {
  var out = <HeardWord>[];
  for (var line in csv.split("\n")) {
    var a = line.indexOf(",");
    if (a < 0) continue;
    var b = line.indexOf(",", a + 1);
    if (b < 0) continue;
    var start = int.tryParse(line.substring(0, a).trim());
    var end = int.tryParse(line.substring(a + 1, b).trim());
    if (start == null || end == null) continue;
    var text = line.substring(b + 1).trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1).replaceAll('""', '"');
    }
    text = text.trim();
    if (text.isEmpty) continue;
    out.add((text: text, start: start / 1000, end: end / 1000));
  }
  return out;
}
