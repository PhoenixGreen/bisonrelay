import 'dart:convert';
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
// device's cue buttons: [pause 0.5] for half a second's silence, [breath]
// and [exhale] for a breath in and out, [laugh], [sigh] and [cough] for
// those sounds, [whisper] and [slow] for
// the sentence after them, and [stress] for the word after it. Each engine
// offers only the cues it can really do -- see SpeechEngineKind.cues.

/// SpeechEngineKind is what speaks: our own voices, on this computer --
/// Kokoro, quick, or the expressive voices (Qwen3-TTS), which take a
/// direction for each line. ElevenLabs, in the cloud, was the third, and is
/// gone: a device saved with it opens on Built in.
enum SpeechEngineKind {
  local("Built in"),
  expressive("Expressive");

  final String label;
  const SpeechEngineKind(this.label);

  /// cues are the cues it can do: our own voices pause, breathe, laugh,
  /// sigh, cough -- recordings, see speech_cues.dart -- whisper and slow
  /// down, but cannot stress a word, and that is not faked.
  List<SpeechCue> get cues => switch (this) {
        local => [
            for (var c in SpeechCue.values)
              if (c != SpeechCue.stress) c
          ],
        // Its sounds and whisper are ours, laid in after; a stressed word or
        // a slower stretch mid-line it cannot do -- the line's direction
        // says those.
        expressive => [
            for (var c in SpeechCue.values)
              if (c != SpeechCue.stress && c != SpeechCue.slow) c
          ],
      };

  /// directs is whether this engine can say a line as [d] says: Kokoro
  /// only as far as its cues go -- a laugh, a sigh, a whisper, slower.
  bool directs(SpeechDirection d) =>
      this != local || d == SpeechDirection.plain || d.kokoro.isNotEmpty;

  /// ownWords is whether it takes a direction in the reader's own words.
  bool get ownWords => this != local;
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

  /// slots are the line's takes, A to C, each in its own place: null for
  /// one not in use. A take stays in its slot until the reader removes it
  /// or speaks the line again into it.
  final List<SpeechTake?> slots;

  /// chosen is the slot picked -- the one "Add all lines" puts on the
  /// timeline -- or -1 for none.
  final int chosen;

  const SpeechLine(this.text,
      {this.direction = SpeechDirection.plain,
      this.own = "",
      this.slots = const [],
      this.chosen = -1});

  /// speechSlots is how many takes a line keeps.
  static const speechSlots = 3;

  /// slot is the take in slot [i], or null for one not in use.
  SpeechTake? slot(int i) => i >= 0 && i < slots.length ? slots[i] : null;

  /// takes are those in use, A to C.
  List<SpeechTake> get takes => [
        for (var t in slots)
          if (t != null) t
      ];

  /// freeSlot is the first slot not in use, or -1 for all three in use.
  int get freeSlot {
    for (var i = 0; i < speechSlots; i++) {
      if (slot(i) == null) return i;
    }
    return -1;
  }

  /// say is the direction as the expressive voices are given it.
  String get say => own.isNotEmpty ? own : direction.say;

  /// take is the slot picked's take, or null.
  SpeechTake? get take => slot(chosen);

  /// withSlot is the line with [take] in slot [i] -- null to empty it --
  /// and, a take put there, that slot picked.
  SpeechLine withSlot(int i, SpeechTake? take) {
    var next = [for (var k = 0; k < speechSlots; k++) slot(k)];
    next[i] = take;
    var pick = take != null
        ? i
        : chosen == i
            ? next.indexWhere((t) => t != null)
            : chosen;
    return copyWith(slots: next, chosen: pick);
  }

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
          List<SpeechTake?>? slots,
          int? chosen}) =>
      SpeechLine(text ?? this.text,
          direction: direction ?? this.direction,
          own: own ?? this.own,
          slots: slots ?? this.slots,
          chosen: chosen ?? this.chosen);

  Map<String, dynamic> toJson() => {
        "text": text,
        if (direction != SpeechDirection.plain) "direction": direction.name,
        if (own.isNotEmpty) "own": own,
        if (takes.isNotEmpty)
          "slots": [for (var i = 0; i < speechSlots; i++) slot(i)?.toJson()],
        if (chosen >= 0) "chosen": chosen,
      };

  static SpeechLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var text = jsonString(json["text"], "");
    if (text.isEmpty) return null;
    // Slots in their places; or, from before there were slots, the takes
    // in order, A on.
    var slots = <SpeechTake?>[
      if (json["slots"] case List list)
        for (var t in list.take(speechSlots)) SpeechTake.fromJson(t)
      else if (json["takes"] case List list)
        for (var t in list.take(speechSlots)) SpeechTake.fromJson(t),
    ];
    var chosen = json["chosen"] is int ? json["chosen"] as int : -1;
    return SpeechLine(text,
        direction: SpeechDirection.values
                .where((d) => d.name == json["direction"])
                .firstOrNull ??
            SpeechDirection.plain,
        own: jsonString(json["own"], ""),
        slots: slots,
        chosen: chosen >= 0 && chosen < slots.length && slots[chosen] != null
            ? chosen
            : slots.indexWhere((t) => t != null));
  }
}

final _lineHead = RegExp(r"^\s*\[(say:[^\]]*|[a-z]+)\]\s*");

/// scriptLines is [script] as its sections: one for each line of the text,
/// spoken as one take -- in one go, so in one voice, start to finish; a
/// voice made to start again at every sentence sounded like a different
/// take each time (Ken, 2026-10-31). A new section is a new line of the
/// text, for a change in how it is said. One whose words are as in [was]
/// keeps its takes.
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
    // Said another way now, its words the same: its takes stay -- only the
    // reader empties a slot.
    var same = unused.where((l) => l.text == text).firstOrNull;
    if (same != null) {
      unused.remove(same);
      return same.copyWith(direction: direction, own: own);
    }
    return SpeechLine(text, direction: direction, own: own);
  }

  // A line of cues alone, with no words, goes with the words after it --
  // or before it, at the end: a section has words to say.
  var pieces = <String>[];
  var held = "";
  for (var paragraph in script.split("\n")) {
    var p = paragraph.trim();
    if (p.isEmpty) continue;
    if (p.replaceAll(RegExp(r"\[[^\]]*\]"), "").trim().isEmpty) {
      held = "$held $p";
      continue;
    }
    pieces.add("$held $p".trim());
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
  return [
    for (var l in out)
      if (l.text.trim().isNotEmpty) l
  ];
}

/// SpeechCue is one of the script's cues: see the note at the top.
enum SpeechCue {
  pause("Pause"),
  breath("Breath in"),
  exhale("Breath out"),
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
      this == breath ||
      this == exhale ||
      this == laugh ||
      this == sigh ||
      this == cough;
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

  /// spoken is the take as the voice spoke it, where it has been shaped
  /// since -- see Phrasing -- and [shapes] each of its words' shapes, by
  /// their place in spoken's words. Its own sound is spoken's shaped, as
  /// [shapedAs] -- the shapes it was made with -- says; they differ for a
  /// moment after a word is moved, until it is made again.
  final SpeechTake? spoken;
  final List<WordShape> shapes;
  final String shapedAs;

  /// exact is whether the words' times are the engine's own, or heard by
  /// whisper, rather than estimated.
  final bool exact;

  /// saved is whether it is in the Audio library -- saved, or put on the
  /// timeline. A line's take is not, until then: it is kept apart, with
  /// the canvas that has it -- see CanvasController.speechTakeStore.
  final bool saved;
  const SpeechTake(this.assetId, this.length, this.words,
      {this.exact = false,
      this.saved = false,
      this.spoken,
      this.shapes = const [],
      this.shapedAs = ""});

  SpeechTake copyWith({String? assetId, bool? saved}) =>
      SpeechTake(assetId ?? this.assetId, length, words,
          exact: exact,
          saved: saved ?? this.saved,
          spoken: spoken,
          shapes: shapes,
          shapedAs: shapedAs);

  /// asSpoken is the take as the voice spoke it: itself, never shaped.
  SpeechTake get asSpoken => spoken ?? this;

  /// shapeOf is word [i]'s shape: plain, where it has none.
  WordShape shapeOf(int i) =>
      i >= 0 && i < shapes.length ? shapes[i] : WordShape.plain;

  /// shaped is whether any of its words is.
  bool get shaped => shapes.any((s) => !s.isPlain);

  /// shapesKey is its shapes as [shapedAs] holds them.
  String get shapesKey => shaped ? jsonEncode(shapes) : "";

  /// needsShaping is whether its sound is not as its shapes say.
  bool get needsShaping => shapesKey != shapedAs;

  /// withShapes is it with [next] as its words' shapes, its sound as it was
  /// until it is made again.
  SpeechTake withShapes(List<WordShape> next) {
    var from = asSpoken;
    return SpeechTake(assetId, length, words,
        exact: exact,
        saved: saved,
        spoken: from,
        shapes: [
          for (var i = 0; i < from.words.length; i++)
            i < next.length ? next[i] : WordShape.plain
        ],
        shapedAs: shapedAs);
  }

  /// madeAs is it with its sound made from its shapes: [id], [length] long,
  /// its words where [words] say -- or, with none shaped, as spoken.
  SpeechTake madeAs(String id, double length, List<TimedWord> words) {
    if (!shaped) return asSpoken;
    return SpeechTake(id, length, words,
        exact: exact, spoken: spoken, shapes: shapes, shapedAs: shapesKey);
  }

  /// ids are the stored sounds it needs: its own, and the take as spoken.
  Set<String> get ids => {
        if (assetId.isNotEmpty) assetId,
        ...?spoken?.ids,
      };

  Map<String, dynamic> toJson() => {
        "asset": assetId,
        "length": length,
        if (exact) "exact": true,
        if (saved) "saved": true,
        if (spoken case var s?) "spoken": s.toJson(),
        if (shaped) "shapes": [for (var w in shapes) w.toJson()],
        if (shapedAs.isNotEmpty) "shapedAs": shapedAs,
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
      saved: json["saved"] == true,
      spoken: SpeechTake.fromJson(json["spoken"]),
      shapes: [
        if (json["shapes"] case List list)
          for (var w in list) WordShape.fromJson(w),
      ],
      shapedAs: jsonString(json["shapedAs"], ""),
    );
  }
}

/// WordShape is how one word of a take is shaped after it was spoken --
/// see phrasing.dart: moved in [pitch], in semitones; its rise and fall
/// made more or less of, [inflection] times what it was; drawn out or
/// hurried, [length] times as long; a [pause] after it, in seconds; and
/// louder or quieter by [loudness] dB.
class WordShape {
  final double pitch, inflection, length, pause, loudness;
  const WordShape(
      {this.pitch = 0,
      this.inflection = 1,
      this.length = 1,
      this.pause = 0,
      this.loudness = 0});

  static const plain = WordShape();

  bool get isPlain =>
      pitch == 0 &&
      inflection == 1 &&
      length == 1 &&
      pause == 0 &&
      loudness == 0;

  /// copyWith is it changed, each kept within what still sounds like the
  /// voice: six semitones either way, 0.7 to 1.4 times as long.
  WordShape copyWith(
          {double? pitch,
          double? inflection,
          double? length,
          double? pause,
          double? loudness}) =>
      WordShape(
        pitch: (pitch ?? this.pitch).clamp(-6.0, 6.0),
        inflection: (inflection ?? this.inflection).clamp(0.0, 2.0),
        length: (length ?? this.length).clamp(0.7, 1.4),
        pause: (pause ?? this.pause).clamp(0.0, 0.8),
        loudness: (loudness ?? this.loudness).clamp(-12.0, 6.0),
      );

  /// stressed is it stressed: a little higher, longer, louder, and more
  /// rise and fall.
  WordShape get stressed => copyWith(
      pitch: pitch + 1.5,
      length: length + 0.1,
      loudness: loudness + 3,
      inflection: inflection + 0.2);

  List<double> toJson() => [
        for (var v in [pitch, inflection, length, pause, loudness])
          (v * 1000).round() / 1000
      ];

  static WordShape fromJson(Object? json) {
    if (json is! List || json.length < 5) return plain;
    double at(int i) => json[i] is num ? (json[i] as num).toDouble() : 0;
    return const WordShape().copyWith(
        pitch: at(0),
        inflection: at(1),
        length: at(2),
        pause: at(3),
        loudness: at(4));
  }

  @override
  bool operator ==(Object other) =>
      other is WordShape &&
      other.pitch == pitch &&
      other.inflection == inflection &&
      other.length == length &&
      other.pause == pause &&
      other.loudness == loudness;

  @override
  int get hashCode => Object.hash(pitch, inflection, length, pause, loudness);
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
  /// one, and the expressive voices' alone.
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
    // One of ElevenLabs' voices is none of ours.
    var gone = json["engine"] == "cloud";
    return const SpeechSpec().copyWith(
      engine: SpeechEngineKind.values
          .where((e) => e.name == json["engine"])
          .firstOrNull,
      voice: gone ? "" : jsonString(json["voice"], ""),
      voiceName: gone ? "" : jsonString(json["voiceName"], ""),
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
