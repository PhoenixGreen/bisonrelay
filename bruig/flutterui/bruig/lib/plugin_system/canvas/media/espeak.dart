import 'dart:io';

import 'package:flutter/foundation.dart';

// espeak.dart is espeak-ng, used where it is installed: for the Kokoro
// voices of Spanish, French, Hindi, Italian, Japanese and Portuguese, whose
// words Kokoro has no dictionary for. Each word of a script is given to
// espeak-ng, which writes how it is said in IPA -- the very sounds Kokoro
// speaks -- and those are handed to Kokoro as a dictionary of their own.
//
// Never bundled: espeak-ng is GPL, and Bison Relay is ISC. A program of the
// reader's, run as a program, as ffmpeg is -- see video_export.dart.

/// espeakHelp is what to tell somebody whose voice needs espeak-ng.
const String espeakHelp =
    "This voice speaks with espeak-ng's help, which is not installed. "
    "Install it with \"brew install espeak-ng\" on a Mac, \"apt install "
    "espeak-ng\" on Linux, or from github.com/espeak-ng/espeak-ng on "
    "Windows -- then try again.";

/// _candidates are where espeak-ng tends to be when it is not on PATH: a
/// GUI app on macOS does not inherit the shell's PATH.
const List<String> _candidates = [
  "/opt/homebrew/bin/espeak-ng",
  "/usr/local/bin/espeak-ng",
  "/usr/bin/espeak-ng",
  "/snap/bin/espeak-ng",
  r"C:\Program Files\eSpeak NG\espeak-ng.exe",
];

String? _found;
bool _pinned = false;

/// espeakPath is where espeak-ng is, or null. Found once and kept; not
/// found, it is looked for again next time -- installed meanwhile, it works
/// without a restart.
Future<String?> espeakPath() async {
  if (_pinned || _found != null) return _found;
  if (Platform.isAndroid || Platform.isIOS) return null;
  try {
    var found = await Process.run(
        Platform.isWindows ? "where" : "which", ["espeak-ng"]);
    if (found.exitCode == 0) {
      var first = (found.stdout as String).trim().split("\n").first.trim();
      if (first.isNotEmpty && await File(first).exists()) return _found = first;
    }
  } catch (exception) {
    debugPrint("Unable to look for espeak-ng on the path: $exception");
  }
  for (var candidate in _candidates) {
    if (await File(candidate).exists()) return _found = candidate;
  }
  return null;
}

/// useEspeakForTest fixes what [espeakPath] answers -- a script standing in
/// for it, or null for none; [forgetEspeakForTest] puts it back.
@visibleForTesting
void useEspeakForTest(String? path) {
  _pinned = true;
  _found = path;
}

@visibleForTesting
void forgetEspeakForTest() {
  _pinned = false;
  _found = null;
}

/// espeakLexicon is how each of [words] is said in espeak-ng [voice]'s
/// language, as dictionary lines' sounds: each a token of [tokens] --
/// Kokoro's -- separated by spaces, the rest left out. A word espeak-ng
/// says nothing for is left out too.
///
/// Run where it is called: in the isolate a take is spoken in.
Map<String, String> espeakLexicon(
    String exe, String voice, Iterable<String> words, Set<String> tokens) {
  var out = <String, String>{};
  for (var word in words) {
    if (out.containsKey(word)) continue;
    ProcessResult said;
    try {
      said = Process.runSync(exe, ["-q", "--ipa", "-v", voice, word]);
    } catch (exception) {
      debugPrint("espeak-ng could not say \"$word\": $exception");
      continue;
    }
    if (said.exitCode != 0) continue;
    var sounds = espeakSounds(said.stdout as String, tokens);
    if (sounds.isNotEmpty) out[word] = sounds;
  }
  return out;
}

/// espeakSounds is espeak-ng's IPA as Kokoro's tokens: the tie bars and
/// spaces taken out, every character it has a token for kept, a space
/// between each.
String espeakSounds(String ipa, Set<String> tokens) => [
      for (var c
          in ipa.replaceAll(RegExp("[\u0361\u035c\u203f^\\s]"), "").split(""))
        if (tokens.contains(c)) c,
    ].join(" ");

/// readTokens are the tokens of a Kokoro tokens.txt: the first thing on
/// each line.
Set<String> readTokens(String text) => {
      for (var line in text.split("\n"))
        if (line.isNotEmpty)
          // A space token is written as the line's first character.
          line.startsWith(" ") ? " " : line.split(" ").first,
    };
