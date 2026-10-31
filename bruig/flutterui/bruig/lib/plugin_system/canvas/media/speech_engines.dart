import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// speech_engines.dart speaks a Speech device's script: with the voices of
// our own (Kokoro, on this computer -- see kokoro_speech.dart) or, when it
// has been switched on with the reader's key, ElevenLabs.
//
// Our own voices speak the script a piece at a time (see parseScript), and
// the pieces are put end to end here as one take at the mix's rate: the
// words as the engine says them, a pause as silence. Each word is kept with
// its time: exactly where the engine says it (ElevenLabs does), or spread
// across its stretch by length.

/// SpeechVoice is a voice an engine can speak in.
class SpeechVoice {
  final String id;
  final String name;

  /// about is what it sounds like: its accent or language, and how.
  final String about;

  /// gender is "f" or "m" where the engine says, for the filter; "" where
  /// it does not.
  final String gender;
  const SpeechVoice(this.id, this.name, this.about, {this.gender = ""});
}

/// SpokenAudio is a take: the sound, at the mix rate, and its words.
class SpokenAudio {
  final Float32List l, r;
  final List<TimedWord> words;
  final bool exact;
  const SpokenAudio(this.l, this.r, this.words, {this.exact = false});

  double get seconds => l.length / mixRate;
}

/// SpeechException is a take that could not be spoken, with why.
class SpeechException implements Exception {
  final String message;
  const SpeechException(this.message);
  @override
  String toString() => message;
}

abstract class SpeechEngine {
  Future<List<SpeechVoice>> voices();
  Future<SpokenAudio> speak(SpeechSpec spec);

  /// speakLine speaks one of the device's lines as directed -- by default
  /// as a script of its own, its direction the nearest cue the engine has.
  /// Another [seed] is another take, where the engine can vary.
  Future<SpokenAudio> speakLine(SpeechSpec spec, SpeechLine line,
          {int seed = 1}) =>
      speak(spec.copyWith(
          script: "${line.direction.kokoro} ${line.text}".trim(),
          lines: const []));
}

/// speechRunsOn is whether a line of [words] words, said at [speed], that
/// came out [seconds] long ran on or stopped short: far longer or shorter
/// than its words should take, at about two and a half a second.
bool speechRunsOn(double seconds, int words, double speed) {
  var expected = words * 0.4 / speed.clamp(0.5, 2.0);
  return seconds > expected * 2.2 + 1.5 || seconds < expected * 0.35;
}

/// decodeFile reads [file] whole through the mix engine's decoder.
(Float32List, Float32List)? decodeFile(String file) => readWhole(file);

// ---------------------------------------------------------------------------
// Putting a take together
// ---------------------------------------------------------------------------

/// assembleTake puts [pieces] end to end, as one take: each the sound of a
/// piece and its words in seconds from the piece's own start.
SpokenAudio assembleTake(
    List<(Float32List, Float32List, List<TimedWord>)> pieces,
    {bool exact = false}) {
  var total = pieces.fold(0, (n, p) => n + p.$1.length);
  var l = Float32List(total), r = Float32List(total);
  var words = <TimedWord>[];
  var at = 0;
  for (var (pl, pr, pw) in pieces) {
    l.setRange(at, at + pl.length, pl);
    r.setRange(at, at + pr.length, pr);
    var offset = at / mixRate;
    for (var w in pw) {
      words.add((text: w.text, start: w.start + offset, end: w.end + offset));
    }
    at += pl.length;
  }
  return SpokenAudio(l, r, words, exact: exact);
}

(Float32List, Float32List, List<TimedWord>) silence(double seconds) {
  var n = (seconds * mixRate).round();
  return (Float32List(n), Float32List(n), const []);
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------

/// Fetch is an HTTPS request: stand-in for the network in tests. It answers
/// the status and the body.
typedef Fetch = Future<(int, String)> Function(
    String method, Uri url, Map<String, String> headers, String? body);

Future<(int, String)> _fetch(
    String method, Uri url, Map<String, String> headers, String? body) async {
  var client = HttpClient();
  try {
    var request = await client.openUrl(method, url);
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    var response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

/// CloudSpeech is ElevenLabs, with the reader's own API key: the script is
/// sent there to be spoken, and comes back with each character's time, so
/// its words are timed exactly.
class CloudSpeech extends SpeechEngine {
  final String apiKey;
  final Fetch fetch;
  CloudSpeech(this.apiKey, {Fetch? fetch}) : fetch = fetch ?? _fetch;

  static final _base = Uri.parse("https://api.elevenlabs.io/v1/");

  void _needKey() {
    if (apiKey.trim().isEmpty) {
      throw const SpeechException(
          "ElevenLabs needs your API key: paste it in the Speech device.");
    }
  }

  @override
  Future<List<SpeechVoice>> voices() async {
    _needKey();
    var (status, body) = await fetch(
        "GET", _base.resolve("voices"), {"xi-api-key": apiKey}, null);
    if (status != 200) throw SpeechException(_failed(status, body));
    var json = jsonDecode(body);
    return [
      if (json case {"voices": List list})
        for (var v in list)
          if (v is Map && v["voice_id"] is String)
            SpeechVoice(
              v["voice_id"] as String,
              (v["name"] ?? "Voice") as String,
              [
                if (v["labels"] case Map labels) ...[
                  if (labels["accent"] case String a) a,
                  if (labels["description"] case String d) d,
                ]
              ].join(" · "),
              gender: switch (v["labels"]) {
                Map l when "${l["gender"]}".startsWith("f") => "f",
                Map l when "${l["gender"]}".startsWith("m") => "m",
                _ => "",
              },
            ),
    ];
  }

  @override
  Future<SpokenAudio> speak(SpeechSpec spec) async {
    _needKey();
    if (spec.voice.isEmpty) throw const SpeechException("Pick a voice first.");
    var text = elevenLabsText(parseScript(spec.script));
    if (text.trim().isEmpty)
      throw const SpeechException("The script is empty.");
    return _say(spec, text);
  }

  /// speakLine gives ElevenLabs the line's direction as one of its own
  /// tags, in words -- "[warmly]", "[nervous]" -- which it follows.
  @override
  Future<SpokenAudio> speakLine(SpeechSpec spec, SpeechLine line,
      {int seed = 1}) async {
    _needKey();
    if (spec.voice.isEmpty) throw const SpeechException("Pick a voice first.");
    var text = elevenLabsText(parseScript(line.text));
    if (text.trim().isEmpty) {
      throw const SpeechException("The line has no words.");
    }
    var tag = line.own.isNotEmpty
        ? "[${line.own.replaceAll(RegExp(r"[\[\]]"), "")}]"
        : elevenLabsDirection(line.direction);
    return _say(spec, tag.isEmpty ? text : "$tag $text");
  }

  Future<SpokenAudio> _say(SpeechSpec spec, String text) async {
    var (status, body) = await fetch(
        "POST",
        _base.resolve(
            "text-to-speech/${Uri.encodeComponent(spec.voice)}/with-timestamps"
            "?output_format=pcm_24000"),
        {"xi-api-key": apiKey, "content-type": "application/json"},
        jsonEncode({
          "text": text,
          "model_id": "eleven_v3",
          "voice_settings": {
            "stability": spec.steadiness,
            "similarity_boost": 0.75,
            "style": spec.expression,
            "speed": spec.speed.clamp(0.7, 1.2),
          },
        }));
    if (status != 200) throw SpeechException(_failed(status, body));
    var json = jsonDecode(body);
    if (json is! Map || json["audio_base64"] is! String) {
      throw const SpeechException("ElevenLabs sent nothing back to play.");
    }
    var pcm = base64Decode(json["audio_base64"] as String);
    var (l, r) = upsample24k(pcm);
    var words = wordsFromAlignment(json["alignment"]);
    return SpokenAudio(l, r, words, exact: words.isNotEmpty);
  }

  static String _failed(int status, String body) => switch (status) {
        401 => "ElevenLabs did not accept the API key.",
        429 => "ElevenLabs says the account has spoken all it may for now.",
        _ => "ElevenLabs could not speak it ($status).",
      };
}

/// elevenLabsDirection is [d] as ElevenLabs' own tag, or "" for none.
String elevenLabsDirection(SpeechDirection d) => switch (d) {
      SpeechDirection.plain => "",
      SpeechDirection.warm => "[warmly]",
      SpeechDirection.laughing => "[laughing]",
      SpeechDirection.whisper => "[whispers]",
      SpeechDirection.sigh => "[sighs]",
      SpeechDirection.overjoyed => "[excited]",
      SpeechDirection.sad => "[sad]",
      SpeechDirection.angry => "[angry]",
      SpeechDirection.nervous => "[nervous]",
      SpeechDirection.slower => "[slowly]",
    };

/// elevenLabsText is the script as ElevenLabs reads it: its own tags for
/// the cues it can do -- laughs, sighs, whispers -- a stressed word in
/// capitals, which it says harder.
String elevenLabsText(List<SpeechPiece> pieces) => [
      for (var p in pieces)
        switch (p) {
          SpokenPause s => s.seconds >= 1 ? "[long pause]" : "[short pause]",
          SpokenSound s => switch (s.cue) {
              SpeechCue.laugh => "[laughs]",
              SpeechCue.sigh => "[sighs]",
              SpeechCue.cough => "[coughs]",
              _ => "[exhales]",
            },
          SpokenText t => [
              if (t.whisper) "[whispers]",
              if (t.slow) "[slowly]",
              for (var (i, w) in t.words.indexed)
                t.stressed.contains(i) ? w.toUpperCase() : w,
            ].join(" "),
        }
    ].join(" ");

/// upsample24k is ElevenLabs' 16-bit mono at 24kHz as the mix's 48kHz, two
/// sides.
(Float32List, Float32List) upsample24k(Uint8List pcm) {
  var data = ByteData.sublistView(pcm);
  var x = Float32List(pcm.length ~/ 2);
  for (var i = 0; i < x.length; i++) {
    x[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  var out = upsample2x(x);
  return (out, Float32List.fromList(out));
}

const _halfTaps = 16;

/// _between are the weights of the samples either side of a point halfway
/// between two: a sinc, windowed by a Blackman window, summing to one.
final _between = () {
  var w = Float64List(_halfTaps * 2);
  for (var k = 0; k < _halfTaps * 2; k++) {
    var t = k - _halfTaps + 0.5; // from the point, in samples
    var sinc = math.sin(math.pi * t) / (math.pi * t);
    var u = (k + 0.5) / (_halfTaps * 2);
    var window = 0.42 -
        0.5 * math.cos(2 * math.pi * u) +
        0.08 * math.cos(4 * math.pi * u);
    w[k] = sinc * window;
  }
  var sum = w.reduce((a, b) => a + b);
  for (var k = 0; k < w.length; k++) {
    w[k] /= sum;
  }
  return w;
}();

/// upsample2x is [x] at twice its rate: its own samples, and between each
/// two the sound's value there -- read from a windowed sinc, not a straight
/// line, which would leave a hiss of mirrored highs over a voice.
Float32List upsample2x(Float32List x) {
  var n = x.length;
  var out = Float32List(n * 2);
  for (var i = 0; i < n; i++) {
    out[i * 2] = x[i];
    var v = 0.0;
    for (var k = 0; k < _halfTaps * 2; k++) {
      var j = i + k - _halfTaps + 1;
      if (j >= 0 && j < n) v += x[j] * _between[k];
    }
    out[i * 2 + 1] = v;
  }
  return out;
}

/// wordsFromAlignment reads ElevenLabs' timing -- each character, when it
/// starts and ends -- as words, leaving out its tags in brackets.
List<TimedWord> wordsFromAlignment(Object? alignment) {
  if (alignment is! Map) return const [];
  var chars = alignment["characters"],
      starts = alignment["character_start_times_seconds"],
      ends = alignment["character_end_times_seconds"];
  if (chars is! List || starts is! List || ends is! List) return const [];
  var out = <TimedWord>[];
  var word = StringBuffer();
  double? from;
  var to = 0.0;
  var inTag = false;
  void flush() {
    if (word.isNotEmpty && from != null) {
      out.add((text: word.toString(), start: from!, end: to));
    }
    word.clear();
    from = null;
  }

  for (var i = 0;
      i < chars.length && i < starts.length && i < ends.length;
      i++) {
    var ch = "${chars[i]}";
    if (ch == "[") {
      flush();
      inTag = true;
      continue;
    }
    if (inTag) {
      if (ch == "]") inTag = false;
      continue;
    }
    if (ch.trim().isEmpty) {
      flush();
      continue;
    }
    from ??= (starts[i] as num).toDouble();
    to = (ends[i] as num).toDouble();
    word.write(ch);
  }
  flush();
  return out;
}
