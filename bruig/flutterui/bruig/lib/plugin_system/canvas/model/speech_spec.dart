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

/// SpeechEngineKind is what speaks: our own voices on this computer --
/// Kokoro, quick, or the expressive voices (Qwen3-TTS), which take a
/// direction for each line -- or ElevenLabs in the cloud, off until switched
/// on with the reader's own key, since the script leaves the computer.
enum SpeechEngineKind {
  local("Built in"),
  expressive("Expressive"),
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

/// SpeechDirection is how a line is said, chosen for it in the device: to
/// the expressive voices, a direction in plain words; to Kokoro, the
/// nearest of its own cues, where it has one.
enum SpeechDirection {
  plain("As written", ""),
  warm("Warm", "Warm and friendly, with a hint of excitement held back."),
  laughing("Laughing as you speak",
      "Laughing with genuine delight as you speak, the laughter spilling into the words."),
  whisper("Whisper",
      "Whisper this very softly, breathy, almost no voice, as if someone might overhear."),
  sigh("Sigh first",
      "Begin with a long, weary sigh, then speak resignedly, as if bracing yourself."),
  overjoyed("Overjoyed",
      "Bursting with joy and disbelief, almost breathless with happiness."),
  sad("Sad", "Quietly sad, close to tears."),
  angry("Angry", "Angry, clipped and forceful."),
  nervous("Nervous", "Nervous and hesitant, almost apologetic."),
  slower("Slower", "Slowly and deliberately, weighing every word.");

  final String label;

  /// say is the direction as the expressive voices are given it.
  final String say;
  const SpeechDirection(this.label, this.say);

  /// token is the direction as it is written at the start of its line.
  String get token => "[$name]";

  /// kokoro is the nearest of Kokoro's cues, written before the line, or
  /// "" where it has none.
  String get kokoro => switch (this) {
        laughing => "[laugh]",
        whisper => "[whisper]",
        sigh => "[sigh]",
        slower => "[slow]",
        _ => "",
      };
}

/// SpeechPreset is a starting point for a voice's feel: its speed, how
/// steady and how expressive it is, how much room and whether the speaker
/// boost is on. Moving any of them makes the device "custom".
enum SpeechPreset {
  natural("Natural", 1.0, 0.5, 0.5, 0, true),
  narrator("Audiobook narrator", 0.97, 0.7, 0.4, 0, true),
  chat("Conversational", 1.03, 0.35, 0.6, 0.1, false),
  drama("Dramatic", 0.99, 0.25, 0.85, 0.15, true),
  calm("Calm & close", 0.95, 0.65, 0.3, 0, false);

  final String label;
  final double speed, steadiness, expression, room;
  final bool boost;
  const SpeechPreset(this.label, this.speed, this.steadiness, this.expression,
      this.room, this.boost);
}

/// SpeechLine is one line of the script, as the device speaks it: its
/// words, how it is said -- a direction, or the reader's own words for one
/// -- and the takes spoken of it, one of them chosen for the clip.
class SpeechLine {
  final String text;
  final SpeechDirection direction;

  /// own is a direction in the reader's own words, over [direction]; ""
  /// for none.
  final String own;
  final List<SpeechTake> takes;

  /// chosen is the take in the clip, by its place, or -1 for none yet.
  final int chosen;

  const SpeechLine(this.text,
      {this.direction = SpeechDirection.plain,
      this.own = "",
      this.takes = const [],
      this.chosen = -1});

  /// say is the direction as the expressive voices are given it.
  String get say => own.isNotEmpty ? own : direction.say;

  SpeechTake? get take =>
      chosen >= 0 && chosen < takes.length ? takes[chosen] : null;

  /// written is the line as the script shows it: its direction first.
  String get written => [
        if (own.isNotEmpty)
          "[say: ${own.replaceAll("]", "")}]"
        else if (direction != SpeechDirection.plain)
          direction.token,
        text,
      ].join(" ");

  SpeechLine copyWith(
          {String? text,
          SpeechDirection? direction,
          String? own,
          List<SpeechTake>? takes,
          int? chosen}) =>
      SpeechLine(text ?? this.text,
          direction: direction ?? this.direction,
          own: own ?? this.own,
          takes: takes ?? this.takes,
          chosen: chosen ?? this.chosen);

  Map<String, dynamic> toJson() => {
        "text": text,
        if (direction != SpeechDirection.plain) "direction": direction.name,
        if (own.isNotEmpty) "own": own,
        if (takes.isNotEmpty) "takes": [for (var t in takes) t.toJson()],
        if (chosen >= 0) "chosen": chosen,
      };

  static SpeechLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var text = jsonString(json["text"], "");
    if (text.isEmpty) return null;
    var takes = [
      if (json["takes"] case List list)
        for (var t in list)
          if (SpeechTake.fromJson(t) case var take?) take,
    ];
    var chosen = json["chosen"] is int ? json["chosen"] as int : -1;
    return SpeechLine(text,
        direction: SpeechDirection.values
                .where((d) => d.name == json["direction"])
                .firstOrNull ??
            SpeechDirection.plain,
        own: jsonString(json["own"], ""),
        takes: takes,
        chosen: chosen < takes.length ? chosen : takes.length - 1);
  }
}

final _lineHead = RegExp(r"^\s*\[(say:[^\]]*|[a-z]+)\]\s*");

/// scriptLines is [script] as lines: one for each line of the text, and
/// each of those cut at its sentences' ends -- but for one that is a line
/// already in [was], kept whole, as joined. A line whose words and
/// direction are as one in [was] keeps its takes.
List<SpeechLine> scriptLines(String script, [List<SpeechLine> was = const []]) {
  var out = <SpeechLine>[];
  var unused = [...was];
  SpeechLine line(String piece) {
    var direction = SpeechDirection.plain;
    var own = "";
    var text = piece.trim();
    // Its direction, at its start: one of ours, or the reader's own words.
    var head = _lineHead.firstMatch(text);
    if (head != null) {
      var token = head[1]!;
      if (token.startsWith("say:")) {
        own = token.substring(4).trim();
        text = text.substring(head.end);
      } else if (SpeechDirection.values
              .where((d) => d.name == token)
              .firstOrNull
          case var d?) {
        direction = d;
        text = text.substring(head.end);
      }
    }
    var kept = unused
        .where(
            (l) => l.text == text && l.direction == direction && l.own == own)
        .firstOrNull;
    if (kept != null) {
      unused.remove(kept);
      return kept;
    }
    return SpeechLine(text, direction: direction, own: own);
  }

  for (var paragraph in script.split("\n")) {
    var p = paragraph.trim();
    if (p.isEmpty) continue;
    if (was.any((l) => l.written == p)) {
      out.add(line(p));
      continue;
    }
    // Cut after a sentence's end -- the direction stays with the first. A
    // piece of cues alone, with no words, stays with the words after it,
    // or before it at the end: a line has words to say.
    var pieces = <String>[];
    var held = "";
    for (var piece in p.split(RegExp(r"(?<=[.!?…])\s+(?=\S)"))) {
      if (piece.trim().isEmpty) continue;
      if (piece.replaceAll(RegExp(r"\[[^\]]*\]"), "").trim().isEmpty) {
        held = "$held $piece";
        continue;
      }
      pieces.add("$held $piece".trim());
      held = "";
    }
    if (held.trim().isNotEmpty) {
      if (pieces.isEmpty) {
        pieces.add(held.trim());
      } else {
        pieces.last = "${pieces.last} ${held.trim()}";
      }
    }
    for (var piece in pieces) {
      out.add(line(piece));
    }
  }
  return [
    for (var l in out)
      if (l.text.trim().isNotEmpty) l
  ];
}

/// SpeechCue is one of the script's cues: see the note at the top.
enum SpeechCue {
  pause("Pause"),
  breath("Breath"),
  laugh("Laugh"),
  sigh("Sigh"),
  cough("Cough"),
  whisper("Whisper"),
  stress("Stress"),
  slow("Slower");

  final String label;
  const SpeechCue(this.label);

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

/// _ownDirection is a direction in the reader's own words: never spoken.
final _ownDirection = RegExp(r"\[say:[^\]]*\]");

/// parseScript is [script] as the pieces it is spoken in. A [whisper] or a
/// [slow] holds to the end of its sentence; a [stress] to the next word; a
/// token it does not know is left out.
List<SpeechPiece> parseScript(String script) {
  script = script.replaceAll(_ownDirection, " ");
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

  /// lines are the script line by line, each with its direction and its
  /// takes -- see scriptLines -- kept in step with [script].
  final List<SpeechLine> lines;

  /// language is what the expressive voices speak: each keeps its own
  /// accent in it. "" for English.
  final String language;

  /// room is how much room is heard round the voice, nought (close and
  /// dry, where a voice starts) to one; boost is the speaker boost -- gentle compression and an
  /// even level -- and preset the feel it was set from, or "custom". All
  /// ours, after the voice: see speech_finish.dart.
  final double room;
  final bool boost;
  final String preset;

  /// clip is the element the joined lines play in, or "" for none yet.
  final String clip;

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
    this.lines = const [],
    this.language = "",
    this.room = 0,
    this.boost = true,
    this.preset = "natural",
    this.clip = "",
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
    List<SpeechLine>? lines,
    String? language,
    double? room,
    bool? boost,
    String? preset,
    String? clip,
  }) =>
      SpeechSpec(
        lines: lines ?? this.lines,
        language: language ?? this.language,
        room: (room ?? this.room).clamp(0.0, 1.0),
        boost: boost ?? this.boost,
        preset: preset ?? this.preset,
        clip: clip ?? this.clip,
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
        if (lines.isNotEmpty) "lines": [for (var l in lines) l.toJson()],
        if (language.isNotEmpty) "language": language,
        "room": room,
        if (!boost) "boost": false,
        if (preset != "natural") "preset": preset,
        if (clip.isNotEmpty) "clip": clip,
      };

  /// withPreset is the device with [p]'s feel.
  SpeechSpec withPreset(SpeechPreset p) => copyWith(
      speed: p.speed,
      steadiness: p.steadiness,
      expression: p.expression,
      room: p.room,
      boost: p.boost,
      preset: p.name);

  /// withScript is the device with [script] typed -- its lines cut again,
  /// those unchanged keeping their takes.
  SpeechSpec withScript(String script) =>
      copyWith(script: script, lines: scriptLines(script, lines));

  /// withLines is the device with [lines] -- the script written from them.
  SpeechSpec withLines(List<SpeechLine> lines) => copyWith(
      lines: lines, script: [for (var l in lines) l.written].join("\n"));

  /// shownLines are the lines as the device lists them: its own, or the
  /// script's, cut, where it has none yet.
  List<SpeechLine> get shownLines =>
      lines.isNotEmpty || script.trim().isEmpty ? lines : scriptLines(script);

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
      lines: [
        if (json["lines"] case List list)
          for (var l in list)
            if (SpeechLine.fromJson(l) case var line?) line,
      ],
      language: jsonString(json["language"], ""),
      room: jsonDouble(json["room"], 0),
      boost: json["boost"] != false,
      preset: jsonString(json["preset"], "natural"),
      clip: jsonString(json["clip"], ""),
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
