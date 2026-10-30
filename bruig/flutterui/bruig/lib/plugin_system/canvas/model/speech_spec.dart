import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonString;
import 'package:bruig/plugin_system/canvas/model/text_document.dart'
    show TextDocumentRef;

// speech_spec.dart is the Speech device's settings: a script to be spoken,
// the voice and engine to speak it, how it is delivered, and the takes it
// has spoken -- each a sound file with its words timed, for a Character's
// lips and for the Vocaliser.
//
// It belongs to an audio channel -- see ChannelMix.speech -- and what it
// speaks is an ordinary clip on that channel, so the timeline, the mixer
// and an export treat it as any other sound.
//
// The script is plain text with cues in square brackets, put in from the
// device's cue buttons: [pause 0.5] for half a second's silence, [breath],
// [laugh], [sigh] and [cough] for those sounds, [whisper] and [slow] for
// the sentence after them, and [stress] for the word after it. Each engine
// offers only the cues it can really do -- see SpeechEngineKind.cues.

/// SpeechEngineKind is what speaks: our own voices (Kokoro, on this
/// computer), or ElevenLabs in the cloud -- off until switched on with the
/// reader's own key, since the script leaves the computer to be spoken.
enum SpeechEngineKind {
  local("Built in"),
  cloud("ElevenLabs");

  final String label;
  const SpeechEngineKind(this.label);

  /// cues are the cues it can do: our own voices pause, breathe, laugh,
  /// sigh, cough -- recordings, see speech_cues.dart -- whisper and slow
  /// down, but cannot stress a word, and that is not faked.
  List<SpeechCue> get cues => this == local
      ? [
          for (var c in SpeechCue.values)
            if (c != SpeechCue.stress) c
        ]
      : SpeechCue.values;
}

/// SpeechCue is one of the script's cues: see the note at the top.
enum SpeechCue {
  pause("Pause", "⏸"),
  breath("Breath", "〰"),
  laugh("Laugh", "😄"),
  sigh("Sigh", "😮‍💨"),
  cough("Cough", "🤧"),
  whisper("Whisper", "🤫"),
  stress("Stress", "❗"),
  slow("Slower", "🐢");

  final String label;
  final String icon;
  const SpeechCue(this.label, this.icon);

  /// token is the cue as it is written in the script.
  String get token => this == pause ? "[pause 0.5]" : "[$name]";

  /// sound is whether the cue is a sound of its own -- a breath, a laugh --
  /// rather than a way of saying the words around it.
  bool get sound =>
      this == breath || this == laugh || this == sigh || this == cough;
}

/// SpeechPiece is a stretch of the script: words, said a way, or a cue
/// that is a sound or a silence of its own.
sealed class SpeechPiece {
  const SpeechPiece();
}

/// SpokenText is words, and how they are said: whispered, slower, with one
/// of them stressed -- by its index among them.
class SpokenText extends SpeechPiece {
  final String text;
  final bool whisper;
  final bool slow;
  final Set<int> stressed;
  const SpokenText(this.text,
      {this.whisper = false, this.slow = false, this.stressed = const {}});

  List<String> get words =>
      text.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
}

/// SpokenPause is silence, for [seconds].
class SpokenPause extends SpeechPiece {
  final double seconds;
  const SpokenPause(this.seconds);
}

/// SpokenSound is a breath, a laugh, a sigh or a cough.
class SpokenSound extends SpeechPiece {
  final SpeechCue cue;
  const SpokenSound(this.cue);
}

final _token = RegExp(r"\[([a-z]+)(?:\s+([0-9.]+))?\]");

/// parseScript is [script] as the pieces it is spoken in. A [whisper] or a
/// [slow] holds to the end of its sentence; a [stress] to the next word; a
/// token it does not know is left out.
List<SpeechPiece> parseScript(String script) {
  var out = <SpeechPiece>[];
  var whisper = false, slow = false, stressNext = false;
  var words = <String>[];
  var stressed = <int>{};
  void flush() {
    if (words.isNotEmpty) {
      out.add(SpokenText(words.join(" "),
          whisper: whisper, slow: slow, stressed: {...stressed}));
    }
    words = [];
    stressed = {};
  }

  var at = 0;
  void text(String s) {
    for (var w in s.split(RegExp(r"\s+"))) {
      if (w.isEmpty) continue;
      if (stressNext) {
        stressed.add(words.length);
        stressNext = false;
      }
      words.add(w);
      // A sentence's end ends a whisper or a slower stretch.
      if (RegExp(r"[.!?]$").hasMatch(w) && (whisper || slow)) {
        flush();
        whisper = false;
        slow = false;
      }
    }
  }

  for (var m in _token.allMatches(script)) {
    text(script.substring(at, m.start));
    at = m.end;
    var cue = SpeechCue.values.where((c) => c.name == m[1]).firstOrNull;
    switch (cue) {
      case null:
        break;
      case SpeechCue.pause:
        flush();
        out.add(SpokenPause(
            (double.tryParse(m[2] ?? "") ?? 0.5).clamp(0.05, 10.0)));
      case SpeechCue.whisper || SpeechCue.slow:
        flush();
        if (cue == SpeechCue.whisper) whisper = true;
        if (cue == SpeechCue.slow) slow = true;
      case SpeechCue.stress:
        stressNext = true;
      default:
        flush();
        out.add(SpokenSound(cue));
    }
  }
  text(script.substring(at));
  flush();
  return out;
}

/// TimedWord is one word of a take and when it is said, in seconds from the
/// take's start.
typedef TimedWord = ({String text, double start, double end});

/// SpeechTake is what one press of Speak made: the file, how long, and its
/// words timed -- exactly where the engine says, or as near as the words'
/// lengths put them where it does not.
class SpeechTake {
  final String assetId;
  final double length;
  final List<TimedWord> words;

  /// exact is whether the words' times are the engine's own, or heard by
  /// whisper, rather than estimated.
  final bool exact;
  const SpeechTake(this.assetId, this.length, this.words, {this.exact = false});

  Map<String, dynamic> toJson() => {
        "asset": assetId,
        "length": length,
        if (exact) "exact": true,
        "words": [
          for (var w in words)
            [
              w.text,
              (w.start * 1000).round() / 1000,
              (w.end * 1000).round() / 1000
            ]
        ],
      };

  static SpeechTake? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = jsonString(json["asset"], "");
    if (id.isEmpty) return null;
    return SpeechTake(
      id,
      jsonDouble(json["length"], 0),
      [
        if (json["words"] case List list)
          for (var w in list)
            if (w is List && w.length >= 3 && w[0] is String)
              (
                text: w[0] as String,
                start: jsonDouble(w[1], 0),
                end: jsonDouble(w[2], 0)
              ),
      ],
      exact: json["exact"] == true,
    );
  }
}

/// SpeechSpec is the Speech device on a channel.
class SpeechSpec {
  final SpeechEngineKind engine;

  /// voice is the voice's id to its engine, and voiceName what it is called.
  final String voice;
  final String voiceName;
  final String script;

  /// speed is how fast, one as the voice speaks; expression how much the
  /// voice moves, and steadiness how alike each take is -- both nought to
  /// one, and ElevenLabs' alone.
  final double speed;
  final double expression;
  final double steadiness;

  /// takes are what has been spoken, the latest last.
  final List<SpeechTake> takes;

  /// document is the Writing Tools document the script is read from --
  /// kept up to date as it is edited, see text_documents.dart -- or none.
  /// Its wasText is the script typed before, given back when it is let go.
  final TextDocumentRef document;

  const SpeechSpec({
    this.engine = SpeechEngineKind.local,
    this.voice = "",
    this.voiceName = "",
    this.script = "",
    this.speed = 1,
    this.expression = 0.6,
    this.steadiness = 0.45,
    this.takes = const [],
    this.document = const TextDocumentRef(),
  });

  SpeechSpec copyWith({
    SpeechEngineKind? engine,
    String? voice,
    String? voiceName,
    String? script,
    double? speed,
    double? expression,
    double? steadiness,
    List<SpeechTake>? takes,
    TextDocumentRef? document,
  }) =>
      SpeechSpec(
        engine: engine ?? this.engine,
        voice: voice ?? this.voice,
        voiceName: voiceName ?? this.voiceName,
        script: script ?? this.script,
        speed: (speed ?? this.speed).clamp(0.5, 2.0),
        expression: (expression ?? this.expression).clamp(0.0, 1.0),
        steadiness: (steadiness ?? this.steadiness).clamp(0.0, 1.0),
        takes: takes ?? this.takes,
        document: document ?? this.document,
      );

  Map<String, dynamic> toJson() => {
        if (engine != SpeechEngineKind.local) "engine": engine.name,
        if (voice.isNotEmpty) "voice": voice,
        if (voiceName.isNotEmpty) "voiceName": voiceName,
        if (script.isNotEmpty) "script": script,
        if (speed != 1) "speed": speed,
        "expression": expression,
        "steadiness": steadiness,
        if (takes.isNotEmpty) "takes": [for (var t in takes) t.toJson()],
        if (document.on) "document": document.toJson(),
      };

  static SpeechSpec fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const SpeechSpec();
    return const SpeechSpec().copyWith(
      engine: SpeechEngineKind.values
          .where((e) => e.name == json["engine"])
          .firstOrNull,
      voice: jsonString(json["voice"], ""),
      voiceName: jsonString(json["voiceName"], ""),
      script: jsonString(json["script"], ""),
      speed: jsonDouble(json["speed"], 1),
      expression: jsonDouble(json["expression"], 0.6),
      steadiness: jsonDouble(json["steadiness"], 0.45),
      takes: [
        if (json["takes"] case List list)
          for (var t in list)
            if (SpeechTake.fromJson(t) case var take?) take,
      ],
      document: json["document"] is Map<String, dynamic>
          ? TextDocumentRef.fromJson(json["document"] as Map<String, dynamic>)
          : null,
    );
  }
}

/// estimateWords spreads [words] across [from] to [to] seconds by their
/// lengths -- a long word takes longer to say -- for an engine that does not
/// say where each one is.
List<TimedWord> estimateWords(List<String> words, double from, double to) {
  if (words.isEmpty || to <= from) return const [];
  var weights = [for (var w in words) math.max(1, w.length) + 1.0];
  var total = weights.reduce((a, b) => a + b);
  var out = <TimedWord>[];
  var t = from;
  for (var (i, w) in words.indexed) {
    var d = (to - from) * weights[i] / total;
    out.add((text: w, start: t, end: t + d));
    t += d;
  }
  return out;
}

/// VocaliserSpec is the Vocaliser on a channel: it sings the channel's
/// latest Speech take to a MIDI channel's notes -- see vocaliser.dart.
class VocaliserSpec {
  /// melody is the MIDI channel whose notes are sung, by key; "" for the
  /// first there is.
  final String melody;

  /// vibrato is how much each held note swings, nought to one -- a
  /// semitone at the most -- and glide how long each note slides in from
  /// the last, in seconds.
  final double vibrato;
  final double glide;

  const VocaliserSpec(
      {this.melody = "", this.vibrato = 0.3, this.glide = 0.06});

  VocaliserSpec copyWith({String? melody, double? vibrato, double? glide}) =>
      VocaliserSpec(
        melody: melody ?? this.melody,
        vibrato: (vibrato ?? this.vibrato).clamp(0.0, 1.0),
        glide: (glide ?? this.glide).clamp(0.0, 0.5),
      );

  Map<String, dynamic> toJson() => {
        if (melody.isNotEmpty) "melody": melody,
        "vibrato": vibrato,
        "glide": glide,
      };

  static VocaliserSpec fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const VocaliserSpec();
    return const VocaliserSpec().copyWith(
      melody: jsonString(json["melody"], ""),
      vibrato: jsonDouble(json["vibrato"], 0.3),
      glide: jsonDouble(json["glide"], 0.06),
    );
  }
}
