import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' as notation;

// music_score.dart is a score as it is written (Ken, 2026-11-14: "the score
// is the source"): parts of staves of bars of notes, with everything a
// player reads -- dynamics, articulations, lyrics, chord symbols, repeats,
// endings, D.C. and D.S. -- and what is played from it: each part's notes
// through the repeats, at the tempo, as loud and as long as marked, for the
// instrument channel that part plays on.
//
// Times are in quarter notes throughout, as in notation.dart; a bar's events
// start at nought and run its length.

/// _grid rounds [quarters] to a 48th of a quarter: thirds and sixteenths
/// alike, so a time worked out two ways is one number.
double _grid(double quarters) => (quarters * 48).round() / 48;

const _letters = "CDEFGAB";
const _naturals = [0, 2, 4, 5, 7, 9, 11];

/// Pitch is a note as written: its letter (0 C to 6 B), alteration (-2 to
/// 2, flats to sharps) and octave (middle C is C4).
class Pitch {
  final int letter, alter, octave;
  const Pitch(this.letter, this.octave, [this.alter = 0]);

  /// key is the MIDI key it sounds as written (middle C is 60).
  int get key => (octave + 1) * 12 + _naturals[letter] + alter;

  /// step is its place in staff steps (a line or a space each), from C-1.
  int get step => (octave + 1) * 7 + letter;

  /// spelled is [key] as [fifths]'s key signature would write it.
  factory Pitch.spelled(int key, {int fifths = 0}) {
    var s = notation.spellKey(key, fifths);
    return Pitch(s.letter, s.octave, s.alter);
  }

  /// up is this pitch [steps] staff steps higher, keeping its alteration
  /// out: the natural of the new letter.
  Pitch up(int steps) {
    var s = step + steps;
    return Pitch(s % 7, s ~/ 7 - 1);
  }

  /// withAlter is the same letter and octave, sharpened or flattened.
  Pitch withAlter(int alter) => Pitch(letter, octave, alter.clamp(-2, 2));

  /// name is how it is saved and shown: "C4", "F#5", "Bb3", "Ebb2".
  String get name =>
      "${_letters[letter]}${alter > 0 ? "#" * alter : alter < 0 ? "b" * -alter : ""}$octave";

  static Pitch? parse(String? s) {
    if (s == null) return null;
    var m = RegExp(r"^([A-G])(#{1,2}|b{1,2})?(-?\d)$").firstMatch(s.trim());
    if (m == null) return null;
    var a = m.group(2) ?? "";
    return Pitch(_letters.indexOf(m.group(1)!), int.parse(m.group(3)!),
        a.startsWith("#") ? a.length : -a.length);
  }

  @override
  bool operator ==(Object other) =>
      other is Pitch &&
      other.letter == letter &&
      other.alter == alter &&
      other.octave == octave;

  @override
  int get hashCode => Object.hash(letter, alter, octave);

  @override
  String toString() => name;
}

/// Clef is a staff's clef: where its notes sit. treble8 is the tenor's and
/// the guitar's, sounding an octave lower than written.
enum Clef {
  treble("Treble", 5 * 7 + 2),
  bass("Bass", 3 * 7 + 4),
  alto("Alto", 4 * 7 + 3),
  tenor("Tenor", 4 * 7 + 1),
  treble8("Treble 8vb", 5 * 7 + 2),
  percussion("Percussion", 5 * 7 + 2);

  final String label;

  /// bottom is the staff's bottom line in staff steps as written: E4 for a
  /// treble, G2 for a bass, F3 for an alto, D3 for a tenor.
  final int bottom;
  const Clef(this.label, this.bottom);

  static Clef fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => treble);
}

/// Dynamic is a loudness mark, and the velocity it plays at.
enum Dynamic {
  ppp(20),
  pp(33),
  p(49),
  mp(64),
  mf(80),
  f(96),
  ff(112),
  fff(124),
  sfz(118),
  fp(96);

  final int velocity;
  const Dynamic(this.velocity);

  /// lasting is whether it holds until the next: sfz and fp mark one note
  /// and drop back.
  bool get lasting => this != sfz && this != fp;

  static Dynamic? fromName(String? name) =>
      values.where((d) => d.name == name).firstOrNull;
}

/// Articulation is a mark on a note that changes how it is played.
enum Articulation {
  staccato("Staccato"),
  staccatissimo("Staccatissimo"),
  tenuto("Tenuto"),
  accent("Accent"),
  marcato("Marcato"),
  fermata("Fermata");

  final String label;
  const Articulation(this.label);

  static Articulation? fromName(String? name) =>
      values.where((a) => a.name == name).firstOrNull;
}

/// Strum is a strum's direction: down (low strings first) or up.
enum Strum { down, up }

/// Tuplet is a group played in the time of fewer: three in the time of two
/// (a triplet) and so on.
class Tuplet {
  final int actual, normal;
  const Tuplet(this.actual, this.normal);
  static const triplet = Tuplet(3, 2);

  double get ratio => normal / actual;
  List<int> toJson() => [actual, normal];
  static Tuplet? fromJson(Object? j) => j is List &&
          j.length == 2 &&
          j[0] is num &&
          j[1] is num &&
          (j[0] as num) > 0 &&
          (j[1] as num) > 0
      ? Tuplet((j[0] as num).toInt(), (j[1] as num).toInt())
      : null;

  @override
  bool operator ==(Object other) =>
      other is Tuplet && other.actual == actual && other.normal == normal;
  @override
  int get hashCode => Object.hash(actual, normal);
}

/// MarkKind names a marking that can be dragged away from where it is
/// drawn, each kept as its own offset ([ScoreEvent.offsets],
/// [BarInfo.offsets], [MusicScore.offsets]).
abstract final class MarkKind {
  static const chord = "ch",
      dynamic = "dyn",
      strum = "strum",
      rehearsal = "mark",
      tempo = "tempo",
      jump = "jump",
      hairpin = "hairpin";
  static String lyric(int verse) => "lyr$verse";
}

Map<String, Offset> _offsetsFromJson(Object? j) => {
      if (j is Map)
        for (var e in j.entries)
          if (e.key is String &&
              e.value is List &&
              (e.value as List).length == 2 &&
              (e.value as List).every((v) => v is num))
            e.key as String: Offset(((e.value as List)[0] as num).toDouble(),
                ((e.value as List)[1] as num).toDouble()),
    };

Map<String, List<double>> _offsetsToJson(Map<String, Offset> o) => {
      for (var e in o.entries)
        if (e.value != Offset.zero) e.key: [e.value.dx, e.value.dy],
    };

/// ScoreEvent is one thing on a staff in a bar: a note or chord, a rest,
/// or a strum (a slash).
class ScoreEvent {
  /// id names it across edits: what lights when it plays, what a practice
  /// marks right or wrong.
  final String id;

  /// value is its written value in quarters without dots (4 a whole note,
  /// 0.5 a quaver); dots and [tuplet] make [quarters].
  final double value;
  final int dots;
  final Tuplet? tuplet;

  /// pitches are what it sounds as written, lowest first. Empty is a rest,
  /// unless [slash].
  final List<Pitch> pitches;

  /// slash is a strum of the chord in force: drawn as a slash head.
  final bool slash;
  final Strum? strum;

  /// tie carries every pitch on into the next event of its voice.
  final bool tie;

  /// voice is nought to three: up to four lines of notes on one staff.
  final int voice;

  final String? chord;
  final Dynamic? dyn;
  final Set<Articulation> articulations;

  /// lyrics are its syllable in each verse; a syllable ending "-" carries on
  /// into the next word's next syllable.
  final List<String> lyrics;

  /// grace is a quick note before the beat, of no length of its own.
  final bool grace;

  /// velocity is how hard it is played where that was set by hand (drawn
  /// in the piano roll), in place of what its dynamic says; null for the
  /// dynamic's. The printed dynamic is not changed by it.
  final int? velocity;

  /// sizes are markings drawn bigger or smaller than their own size, by
  /// kind (see MarkKind): a dynamic resized by its handle.
  final Map<String, double> sizes;

  final Map<String, Offset> offsets;

  const ScoreEvent(this.id, this.value,
      {this.dots = 0,
      this.tuplet,
      this.pitches = const [],
      this.slash = false,
      this.strum,
      this.tie = false,
      this.voice = 0,
      this.chord,
      this.dyn,
      this.articulations = const {},
      this.lyrics = const [],
      this.grace = false,
      this.velocity,
      this.sizes = const {},
      this.offsets = const {}});

  bool get isRest => pitches.isEmpty && !slash;

  /// sizeOf is how big marking [kind] is drawn, one its own size.
  double sizeOf(String kind) => sizes[kind] ?? 1;

  /// quarters is how long it lasts: its value, dotted, in its tuplet.
  double get quarters {
    if (grace) return 0;
    var q = value * (2 - math.pow(0.5, dots));
    return _grid(q * (tuplet?.ratio ?? 1));
  }

  ScoreEvent copyWith({
    String? id,
    double? value,
    int? dots,
    Tuplet? tuplet,
    bool noTuplet = false,
    List<Pitch>? pitches,
    bool? slash,
    Strum? strum,
    bool noStrum = false,
    bool? tie,
    int? voice,
    String? chord,
    bool noChord = false,
    Dynamic? dyn,
    bool noDyn = false,
    Set<Articulation>? articulations,
    List<String>? lyrics,
    bool? grace,
    int? velocity,
    bool noVelocity = false,
    Map<String, double>? sizes,
    Map<String, Offset>? offsets,
  }) =>
      ScoreEvent(id ?? this.id, value ?? this.value,
          dots: (dots ?? this.dots).clamp(0, 2),
          tuplet: noTuplet ? null : tuplet ?? this.tuplet,
          pitches: pitches ?? this.pitches,
          slash: slash ?? this.slash,
          strum: noStrum ? null : strum ?? this.strum,
          tie: tie ?? this.tie,
          voice: (voice ?? this.voice).clamp(0, 3),
          chord: noChord ? null : chord ?? this.chord,
          dyn: noDyn ? null : dyn ?? this.dyn,
          articulations: articulations ?? this.articulations,
          lyrics: lyrics ?? this.lyrics,
          grace: grace ?? this.grace,
          velocity: noVelocity
              ? null
              : (velocity ?? this.velocity)?.clamp(1, 127).toInt(),
          sizes: sizes ?? this.sizes,
          offsets: offsets ?? this.offsets);

  /// movedMark is this event with marking [kind] dragged to [to] from
  /// where it is drawn; Offset.zero puts it back.
  ScoreEvent movedMark(String kind, Offset to) => copyWith(
      offsets: {...offsets, kind: to}..removeWhere((_, o) => o == Offset.zero));

  Map<String, dynamic> toJson() => {
        "id": id,
        "v": value,
        if (dots != 0) "dots": dots,
        if (tuplet case var t?) "tup": t.toJson(),
        if (pitches.isNotEmpty) "p": [for (var p in pitches) p.name],
        if (slash) "slash": true,
        if (strum case var s?) "strum": s.name,
        if (tie) "tie": true,
        if (voice != 0) "voice": voice,
        if (chord case var c?) "ch": c,
        if (dyn case var d?) "dyn": d.name,
        if (articulations.isNotEmpty)
          "art": [for (var a in articulations) a.name],
        if (lyrics.any((l) => l.isNotEmpty)) "lyr": lyrics,
        if (grace) "grace": true,
        if (velocity case var v?) "vel": v,
        if (sizes.isNotEmpty) "size": sizes,
        if (offsets.isNotEmpty) "off": _offsetsToJson(offsets),
      };

  static ScoreEvent fromJson(Map<String, dynamic> j) {
    var v = jsonDouble(j["v"], 1);
    return ScoreEvent(jsonString(j["id"], ""), v > 0 ? v : 1,
        dots: jsonInt(j["dots"], 0).clamp(0, 2),
        tuplet: Tuplet.fromJson(j["tup"]),
        pitches: [
          for (var p in (j["p"] is List ? j["p"] as List : const []))
            if (Pitch.parse(p is String ? p : null) case var q?) q,
        ]..sort((a, b) => a.key.compareTo(b.key)),
        slash: jsonBool(j["slash"], false),
        strum: Strum.values.where((s) => s.name == j["strum"]).firstOrNull,
        tie: jsonBool(j["tie"], false),
        voice: jsonInt(j["voice"], 0).clamp(0, 3),
        chord: jsonStr(j["ch"]),
        dyn: Dynamic.fromName(jsonStr(j["dyn"])),
        articulations: {
          for (var a in (j["art"] is List ? j["art"] as List : const []))
            if (Articulation.fromName(a is String ? a : null) case var x?) x,
        },
        lyrics: [
          for (var l in (j["lyr"] is List ? j["lyr"] as List : const []))
            l is String ? l : "",
        ],
        grace: jsonBool(j["grace"], false),
        velocity:
            j["vel"] is num ? (j["vel"] as num).toInt().clamp(1, 127) : null,
        sizes: {
          if (j["size"] case Map m)
            for (var e in m.entries)
              if (e.key is String && e.value is num)
                e.key as String: (e.value as num).toDouble().clamp(0.3, 4.0),
        },
        offsets: _offsetsFromJson(j["off"]));
  }
}

/// ScoreStaff is one staff of a part: its clef and its bars' events, each
/// bar's events in the order they are written (voice by voice).
class ScoreStaff {
  final Clef clef;
  final List<List<ScoreEvent>> bars;
  const ScoreStaff(this.clef, this.bars);

  List<ScoreEvent> barAt(int i) =>
      i >= 0 && i < bars.length ? bars[i] : const [];

  ScoreStaff copyWith({Clef? clef, List<List<ScoreEvent>>? bars}) =>
      ScoreStaff(clef ?? this.clef, bars ?? this.bars);

  Map<String, dynamic> toJson() => {
        "clef": clef.name,
        "bars": [
          for (var b in bars) [for (var e in b) e.toJson()],
        ],
      };

  static ScoreStaff fromJson(Map<String, dynamic> j) =>
      ScoreStaff(Clef.fromName(jsonStr(j["clef"])), [
        for (var b in (j["bars"] is List ? j["bars"] as List : const []))
          [
            for (var e in (b is List ? b : const []))
              if (e is Map<String, dynamic>) ScoreEvent.fromJson(e),
          ],
      ]);
}

/// ScoreInstrument is an instrument a part can be written for: its name,
/// the General MIDI sound it plays with, its staves and how it is written.
class ScoreInstrument {
  final String id, name, short;
  final int program, bank;
  final List<Clef> clefs;

  /// transpose is how many semitones it sounds below what is written: a B♭
  /// clarinet 2, a guitar 12 (written an octave up).
  final int transpose;

  /// strum is a part written as slashes: a guitar's strumming pattern.
  final bool strum;
  final InstrumentLook look;

  const ScoreInstrument(this.id, this.name, this.short, this.program,
      {this.bank = 0,
      this.clefs = const [Clef.treble],
      this.transpose = 0,
      this.strum = false,
      this.look = InstrumentLook.keyboard});
}

/// scoreInstruments are the instruments a part can be written for.
const scoreInstruments = <ScoreInstrument>[
  ScoreInstrument("piano", "Piano", "Pno.", 0, clefs: [Clef.treble, Clef.bass]),
  ScoreInstrument("organ", "Organ", "Org.", 19,
      clefs: [Clef.treble, Clef.bass]),
  ScoreInstrument("violin", "Violin", "Vln.", 40),
  ScoreInstrument("viola", "Viola", "Vla.", 41, clefs: [Clef.alto]),
  ScoreInstrument("cello", "Cello", "Vc.", 42, clefs: [Clef.bass]),
  ScoreInstrument("contrabass", "Double bass", "Cb.", 43,
      clefs: [Clef.bass], transpose: 12),
  ScoreInstrument("flute", "Flute", "Fl.", 73),
  ScoreInstrument("oboe", "Oboe", "Ob.", 68),
  ScoreInstrument("clarinet", "Clarinet in B♭", "Cl.", 71, transpose: 2),
  ScoreInstrument("bassoon", "Bassoon", "Bsn.", 70, clefs: [Clef.bass]),
  ScoreInstrument("altoSax", "Alto saxophone", "A. Sax.", 65, transpose: 9),
  ScoreInstrument("tenorSax", "Tenor saxophone", "T. Sax.", 66, transpose: 14),
  ScoreInstrument("trumpet", "Trumpet in B♭", "Tpt.", 56, transpose: 2),
  ScoreInstrument("horn", "Horn in F", "Hn.", 60, transpose: 7),
  ScoreInstrument("trombone", "Trombone", "Tbn.", 57, clefs: [Clef.bass]),
  ScoreInstrument("tuba", "Tuba", "Tba.", 58, clefs: [Clef.bass]),
  ScoreInstrument("guitar", "Guitar", "Gtr.", 24,
      clefs: [Clef.treble8], transpose: 12, look: InstrumentLook.guitar),
  ScoreInstrument("guitarStrum", "Guitar (strum)", "Gtr.", 25,
      clefs: [Clef.treble], strum: true, look: InstrumentLook.guitar),
  ScoreInstrument("bassGuitar", "Bass guitar", "B. Gtr.", 33,
      clefs: [Clef.bass], transpose: 12, look: InstrumentLook.bass),
  ScoreInstrument("soprano", "Soprano", "S.", 52),
  ScoreInstrument("alto", "Alto", "A.", 52),
  ScoreInstrument("tenor", "Tenor", "T.", 52,
      clefs: [Clef.treble8], transpose: 12),
  ScoreInstrument("bassVoice", "Bass", "B.", 52, clefs: [Clef.bass]),
];

ScoreInstrument scoreInstrument(String id) => scoreInstruments
    .firstWhere((i) => i.id == id, orElse: () => scoreInstruments.first);

/// ScorePart is one instrument's part: its staves, and the instrument
/// channel it plays on.
class ScorePart {
  final String id, name, short;

  /// instrument is a [scoreInstruments] id: the sound, staves and writing.
  final String instrument;
  final List<ScoreStaff> staves;

  /// channel is the instrument channel element that plays it ("" for none
  /// yet), its clip made from this part.
  final String channel;

  const ScorePart(this.id, this.name, this.instrument, this.staves,
      {this.short = "", this.channel = ""});

  ScoreInstrument get kind => scoreInstrument(instrument);
  bool get strum => kind.strum;

  ScorePart copyWith(
          {String? name,
          String? short,
          String? instrument,
          List<ScoreStaff>? staves,
          String? channel}) =>
      ScorePart(id, name ?? this.name, instrument ?? this.instrument,
          staves ?? this.staves,
          short: short ?? this.short, channel: channel ?? this.channel);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        if (short.isNotEmpty) "short": short,
        "inst": instrument,
        "staves": [for (var s in staves) s.toJson()],
        if (channel.isNotEmpty) "channel": channel,
      };

  static ScorePart fromJson(Map<String, dynamic> j) => ScorePart(
      jsonString(j["id"], ""),
      jsonString(j["name"], ""),
      jsonString(j["inst"], "piano"),
      [
        for (var s in (j["staves"] is List ? j["staves"] as List : const []))
          if (s is Map<String, dynamic>) ScoreStaff.fromJson(s),
      ],
      short: jsonString(j["short"], ""),
      channel: jsonString(j["channel"], ""));
}

/// Jump is a bar's direction to go elsewhere, taken once, the second time
/// it is reached is never.
enum Jump {
  none(""),
  dc("D.C."),
  dcAlFine("D.C. al Fine"),
  dcAlCoda("D.C. al Coda"),
  ds("D.S."),
  dsAlFine("D.S. al Fine"),
  dsAlCoda("D.S. al Coda");

  final String label;
  const Jump(this.label);

  bool get toStart => this == dc || this == dcAlFine || this == dcAlCoda;
  bool get alFine => this == dcAlFine || this == dsAlFine;
  bool get alCoda => this == dcAlCoda || this == dsAlCoda;

  static Jump fromName(String? name) =>
      values.firstWhere((j) => j.name == name, orElse: () => none);
}

/// BarBreak is a break after a bar: a new system, or a new page.
enum BarBreak { none, system, page }

/// BarInfo is what a bar says for every part: its rehearsal mark, repeats,
/// endings, jumps and changes of time, key and tempo.
class BarInfo {
  final String mark;

  /// repeatStart and repeatEnd are its repeat signs; repeatEnd is how many
  /// times the passage plays in all (2 for a plain repeat), nought for none.
  final bool repeatStart;
  final int repeatEnd;

  /// endings are the passes this bar is played on, 1-based; empty plays
  /// every time. A bracket with 1 is a first-time bar.
  final List<int> endings;

  final Jump jump;

  /// segno, coda, toCoda and fine are where jumps go and stop.
  final bool segno, coda, toCoda, fine;

  /// time, key and tempo are changes that start here.
  final (int, int)? time;
  final int? key;
  final double? tempo;
  final String tempoText;

  final BarBreak breakAfter;
  final Map<String, Offset> offsets;

  /// width is how much wider (or narrower) than its notes ask the bar is
  /// drawn: its bar line dragged in the Studio. The line is still filled.
  final double width;

  const BarInfo(
      {this.mark = "",
      this.repeatStart = false,
      this.repeatEnd = 0,
      this.endings = const [],
      this.jump = Jump.none,
      this.segno = false,
      this.coda = false,
      this.toCoda = false,
      this.fine = false,
      this.time,
      this.key,
      this.tempo,
      this.tempoText = "",
      this.breakAfter = BarBreak.none,
      this.offsets = const {},
      this.width = 1});

  BarInfo copyWith({
    String? mark,
    bool? repeatStart,
    int? repeatEnd,
    List<int>? endings,
    Jump? jump,
    bool? segno,
    bool? coda,
    bool? toCoda,
    bool? fine,
    (int, int)? time,
    bool noTime = false,
    int? key,
    bool noKey = false,
    double? tempo,
    bool noTempo = false,
    String? tempoText,
    BarBreak? breakAfter,
    Map<String, Offset>? offsets,
    double? width,
  }) =>
      BarInfo(
          mark: mark ?? this.mark,
          repeatStart: repeatStart ?? this.repeatStart,
          repeatEnd: (repeatEnd ?? this.repeatEnd).clamp(0, 9),
          endings: endings ?? this.endings,
          jump: jump ?? this.jump,
          segno: segno ?? this.segno,
          coda: coda ?? this.coda,
          toCoda: toCoda ?? this.toCoda,
          fine: fine ?? this.fine,
          time: noTime ? null : time ?? this.time,
          key: noKey ? null : (key ?? this.key)?.clamp(-7, 7),
          tempo: noTempo ? null : (tempo ?? this.tempo)?.clamp(20.0, 400.0),
          tempoText: tempoText ?? this.tempoText,
          breakAfter: breakAfter ?? this.breakAfter,
          offsets: offsets ?? this.offsets,
          width: (width ?? this.width).clamp(0.4, 4.0));

  Map<String, dynamic> toJson() => {
        if (mark.isNotEmpty) "mark": mark,
        if (repeatStart) "rs": true,
        if (repeatEnd > 0) "re": repeatEnd,
        if (endings.isNotEmpty) "end": endings,
        if (jump != Jump.none) "jump": jump.name,
        if (segno) "segno": true,
        if (coda) "coda": true,
        if (toCoda) "toCoda": true,
        if (fine) "fine": true,
        if (time case (var b, var u)) "time": [b, u],
        if (key case var k?) "key": k,
        if (tempo case var t?) "tempo": t,
        if (tempoText.isNotEmpty) "tempoText": tempoText,
        if (breakAfter != BarBreak.none) "break": breakAfter.name,
        if (width != 1) "w": width,
        if (offsets.isNotEmpty) "off": _offsetsToJson(offsets),
      };

  static BarInfo fromJson(Map<String, dynamic> j) {
    var t = j["time"];
    return BarInfo(
        mark: jsonString(j["mark"], ""),
        repeatStart: jsonBool(j["rs"], false),
        repeatEnd: jsonInt(j["re"], 0).clamp(0, 9),
        endings: [
          for (var e in (j["end"] is List ? j["end"] as List : const []))
            if (e is num && e >= 1) e.toInt(),
        ],
        jump: Jump.fromName(jsonStr(j["jump"])),
        segno: jsonBool(j["segno"], false),
        coda: jsonBool(j["coda"], false),
        toCoda: jsonBool(j["toCoda"], false),
        fine: jsonBool(j["fine"], false),
        time: t is List && t.length == 2 && t[0] is num && t[1] is num
            ? ((t[0] as num).toInt().clamp(1, 32), (t[1] as num).toInt())
            : null,
        key: j["key"] is num ? (j["key"] as num).toInt().clamp(-7, 7) : null,
        tempo: j["tempo"] is num
            ? (j["tempo"] as num).toDouble().clamp(20.0, 400.0)
            : null,
        tempoText: jsonString(j["tempoText"], ""),
        breakAfter:
            BarBreak.values.where((b) => b.name == j["break"]).firstOrNull ??
                BarBreak.none,
        offsets: _offsetsFromJson(j["off"]),
        width: jsonDouble(j["w"], 1).clamp(0.4, 4.0));
  }
}

/// SpannerKind is a line over several notes.
enum SpannerKind { slur, crescendo, diminuendo, pedal, ottava }

/// ScoreTime is a place in a score: a bar and quarters into it.
typedef ScoreTime = ({int bar, double at});

/// Spanner is a slur, hairpin, pedal line or 8va on one staff of a part,
/// from one time to another (both written times, within the bars).
class Spanner {
  final String id;
  final SpannerKind kind;
  final String part;
  final int staff;
  final ScoreTime from, to;

  /// offset is where it was dragged from where it is drawn.
  final Offset offset;
  const Spanner(this.id, this.kind, this.part, this.staff, this.from, this.to,
      {this.offset = Offset.zero});

  Spanner copyWith({ScoreTime? from, ScoreTime? to, Offset? offset}) =>
      Spanner(id, kind, part, staff, from ?? this.from, to ?? this.to,
          offset: offset ?? this.offset);

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind.name,
        "part": part,
        if (staff != 0) "staff": staff,
        "from": [from.bar, from.at],
        "to": [to.bar, to.at],
        if (offset != Offset.zero) "off": [offset.dx, offset.dy],
      };

  static Spanner? fromJson(Map<String, dynamic> j) {
    ScoreTime? at(Object? v) =>
        v is List && v.length == 2 && v[0] is num && v[1] is num
            ? (bar: (v[0] as num).toInt(), at: (v[1] as num).toDouble())
            : null;
    var kind = SpannerKind.values.where((k) => k.name == j["kind"]).firstOrNull;
    var from = at(j["from"]), to = at(j["to"]);
    if (kind == null || from == null || to == null) return null;
    var off = j["off"];
    return Spanner(jsonString(j["id"], ""), kind, jsonString(j["part"], ""),
        jsonInt(j["staff"], 0), from, to,
        offset: off is List && off.length == 2 && off.every((v) => v is num)
            ? Offset((off[0] as num).toDouble(), (off[1] as num).toDouble())
            : Offset.zero);
  }
}

/// PlayedBar is one bar as it is played: which written bar, which time
/// round, and when it starts, in quarters from the start of the playing.
typedef PlayedBar = ({int bar, int pass, double start});

/// ScoreNote is a note as played: the MIDI note (seconds) and the event it
/// came from, with where it was in the play order.
typedef ScoreNote = ({MidiNote note, String event, int played});

/// MusicScore is a score: the source of every part's notes.
class MusicScore {
  final String id;
  final String title, subtitle, composer, lyricist;

  /// tempo is quarter notes a minute at the start; tempoText its word
  /// ("Allegro").
  final double tempo;
  final String tempoText;

  /// beats and beatUnit are the time signature at the start; fifths the key.
  final int beats, beatUnit, fifths;

  /// bars are what each bar says for every part. Its length is the score's.
  final List<BarInfo> bars;
  final List<ScorePart> parts;
  final List<Spanner> spanners;

  /// verses is how many verses of lyrics the score has.
  final int verses;

  final Map<String, Offset> offsets;

  const MusicScore(this.id,
      {this.title = "",
      this.subtitle = "",
      this.composer = "",
      this.lyricist = "",
      this.tempo = 100,
      this.tempoText = "",
      this.beats = 4,
      this.beatUnit = 4,
      this.fifths = 0,
      this.bars = const [],
      this.parts = const [],
      this.spanners = const [],
      this.verses = 1,
      this.offsets = const {}});

  /// blank is a new score of [bars] empty bars for [instruments].
  factory MusicScore.blank(String id,
      {String title = "Untitled score",
      List<String> instruments = const ["piano"],
      int bars = 8,
      int beats = 4,
      int beatUnit = 4,
      int fifths = 0,
      double tempo = 100}) {
    var barQ = beats * 4 / beatUnit;
    var n = 0;
    return MusicScore(id,
        title: title,
        tempo: tempo,
        beats: beats,
        beatUnit: beatUnit,
        fifths: fifths,
        bars: List.filled(bars, const BarInfo()),
        parts: [
          for (var (i, inst) in instruments.indexed)
            ScorePart(
                "p${i + 1}",
                scoreInstrument(inst).name,
                inst,
                [
                  for (var clef in scoreInstrument(inst).clefs)
                    ScoreStaff(clef, [
                      for (var b = 0; b < bars; b++)
                        [ScoreEvent("e${++n}", barQ)],
                    ]),
                ],
                short: scoreInstrument(inst).short),
        ]);
  }

  int get barCount => bars.length;

  ScorePart? partById(String id) => parts.where((p) => p.id == id).firstOrNull;

  /// timeAt is the time signature in force in [bar].
  (int, int) timeAt(int bar) {
    var t = (beats, beatUnit);
    for (var i = 0; i <= bar && i < bars.length; i++) {
      if (bars[i].time case var c?) t = c;
    }
    return t;
  }

  /// barQuarters is how long [bar] is, in quarters.
  double barQuarters(int bar) {
    var (b, u) = timeAt(bar);
    return b * 4 / u;
  }

  /// keyAt is the key signature in force in [bar].
  int keyAt(int bar) {
    var k = fifths;
    for (var i = 0; i <= bar && i < bars.length; i++) {
      if (bars[i].key case var c?) k = c;
    }
    return k;
  }

  /// tempoAt is the tempo in force in [bar].
  double tempoAt(int bar) {
    var t = tempo;
    for (var i = 0; i <= bar && i < bars.length; i++) {
      if (bars[i].tempo case var c?) t = c;
    }
    return t;
  }

  /// playOrder is the bars as played: through repeats (each repeat sign
  /// played as many times as it says, its endings on their passes, an end
  /// with no start going back to the last finished repeat or the top), then
  /// any D.C. or D.S., taken once, after which repeats are not taken again
  /// and only the last ending plays -- as players and MuseScore do -- on to
  /// Fine, or by the Coda.
  List<PlayedBar> playOrder() {
    var out = <PlayedBar>[];
    var at = 0.0;
    var i = 0, pass = 1, from = 0;
    Jump? jumped;
    var stepped = false;
    var done = <int>{};
    for (var guard = 0; i < bars.length && guard < 20000; guard++) {
      var b = bars[i];
      // Out of a block of endings, stepping on: the first time round again.
      if (stepped &&
          jumped == null &&
          b.endings.isEmpty &&
          i > 0 &&
          bars[i - 1].endings.isNotEmpty) {
        pass = 1;
      }
      if (b.repeatStart && jumped == null && from != i) {
        from = i;
        pass = 1;
      }
      stepped = false;
      var plays = b.endings.isEmpty ||
          b.endings.contains(jumped != null ? _lastEnding(i) : pass);
      if (plays) {
        out.add((bar: i, pass: jumped != null ? 1 : pass, start: at));
        at += barQuarters(i);
        if (jumped != null && b.fine && jumped.alFine) break;
        if (jumped != null && b.toCoda && jumped.alCoda) {
          var coda = bars.indexWhere((x) => x.coda, i + 1);
          if (coda < 0) break;
          i = coda;
          continue;
        }
        if (b.repeatEnd > 0 && jumped == null && !done.contains(i)) {
          if (pass < b.repeatEnd) {
            pass++;
            i = from;
            continue;
          }
          done.add(i);
          if (b.endings.isEmpty) pass = 1;
          from = i + 1;
        }
        if (b.jump != Jump.none && jumped == null) {
          jumped = b.jump;
          i = b.jump.toStart ? 0 : math.max(0, bars.indexWhere((x) => x.segno));
          continue;
        }
      } else if (b.repeatEnd > 0) {
        // An ending not played this time: its repeat is behind us.
        done.add(i);
        from = i + 1;
      }
      i++;
      stepped = true;
    }
    return out;
  }

  /// _lastEnding is the highest pass number in the block of endings that
  /// [bar] is in.
  int _lastEnding(int bar) {
    var best = 1;
    for (var j = bar; j >= 0 && bars[j].endings.isNotEmpty; j--) {
      best = math.max(best, bars[j].endings.reduce(math.max));
    }
    for (var j = bar + 1; j < bars.length && bars[j].endings.isNotEmpty; j++) {
      best = math.max(best, bars[j].endings.reduce(math.max));
    }
    return best;
  }

  /// secondsAt is how many seconds into the playing [quarters] is, through
  /// the tempo changes of [order].
  double secondsAt(List<PlayedBar> order, double quarters) {
    var s = 0.0;
    for (var p in order) {
      var len = barQuarters(p.bar);
      var spq = 60 / tempoAt(p.bar);
      if (quarters <= p.start + len) return s + (quarters - p.start) * spq;
      s += len * spq;
    }
    return s;
  }

  /// placeAt is where [seconds] into the playing of [order] is: which
  /// played bar (by index in [order]), its bar, and how many quarters into
  /// it; null before the start and past the end.
  ({int played, int bar, double at})? placeAt(
      List<PlayedBar> order, double seconds) {
    if (seconds < 0) return null;
    var s = 0.0;
    for (var (i, p) in order.indexed) {
      var spq = 60 / tempoAt(p.bar);
      var len = barQuarters(p.bar) * spq;
      if (seconds < s + len) {
        return (played: i, bar: p.bar, at: (seconds - s) / spq);
      }
      s += len;
    }
    return null;
  }

  /// lengthQuarters is how long the playing is.
  double lengthQuarters([List<PlayedBar>? order]) {
    var o = order ?? playOrder();
    return o.isEmpty ? 0 : o.last.start + barQuarters(o.last.bar);
  }

  /// partNotes is [part] as played, in seconds: every staff's notes
  /// through [playOrder], ties joined, as loud as the dynamics and hairpins
  /// in force and as long as the articulations say; a strum is the chord
  /// symbol in force voiced for guitar, its strings a moment apart, low to
  /// high down and high to low up. Each note knows its event.
  List<ScoreNote> partNotes(String part, {List<PlayedBar>? order}) {
    var p = partById(part);
    if (p == null) return const [];
    var o = order ?? playOrder();
    var out = <ScoreNote>[];
    var transpose = p.kind.transpose;
    for (var (si, staff) in p.staves.indexed) {
      var dyn = Dynamic.mf;
      String? chord;
      // Ties: in each voice, the keys held on from its last event, and
      // their notes' places in out.
      var held = <int, Map<int, int>>{};
      for (var (n, pb) in o.indexed) {
        var spq = 60 / tempoAt(pb.bar);
        var barStart = secondsAt(o, pb.start);
        var t = <int, double>{}; // each voice's time into the bar
        for (var e in staff.barAt(pb.bar)) {
          var at = t[e.voice] ?? 0;
          t[e.voice] = at + e.quarters;
          if (e.dyn case var d? when d.lasting) dyn = d;
          if (e.chord case var c?) chord = c;
          if (e.grace) continue;
          var was = held[e.voice] ?? const <int, int>{};
          var now = <int, int>{};
          held[e.voice] = now;
          if (e.isRest) continue;
          var vel = (e.dyn != null && !e.dyn!.lasting
                  ? e.dyn!.velocity
                  : dyn.velocity) *
              _hairpin(part, si, pb.bar, at);
          if (e.articulations.contains(Articulation.accent)) vel += 18;
          if (e.articulations.contains(Articulation.marcato)) vel += 26;
          var share = e.articulations.contains(Articulation.staccatissimo)
              ? 0.25
              : e.articulations.contains(Articulation.staccato)
                  ? 0.5
                  : e.articulations.contains(Articulation.tenuto)
                      ? 1.0
                      : 0.95;
          if (e.tie) share = 1;
          var hold = e.articulations.contains(Articulation.fermata) ? 2.0 : 1.0;
          var start = barStart + at * spq;
          var len = e.quarters * spq * hold;
          var v = (e.velocity ?? vel.round()).clamp(1, 127);
          if (e.slash) {
            var keys = chordKeys(chord ?? "C");
            if (e.strum == Strum.up) keys = keys.reversed.toList();
            for (var (k, key) in keys.indexed) {
              var gap = k * (e.strum == Strum.up ? 0.012 : 0.018);
              out.add((
                note: MidiNote(
                    key,
                    start + gap,
                    math.max(0.02, len * share - gap),
                    (v - k * 2).clamp(1, 127)),
                event: e.id,
                played: n
              ));
            }
            continue;
          }
          for (var pitch in e.pitches) {
            var key = (pitch.key - transpose).clamp(0, 127);
            if (was[key] case var i?) {
              // Tied on from before: that note grows instead.
              var w = out[i];
              out[i] = (
                note:
                    w.note.copyWith(length: start + len * share - w.note.start),
                event: w.event,
                played: w.played
              );
              if (e.tie) now[key] = i;
              continue;
            }
            out.add((
              note: MidiNote(key, start, math.max(0.02, len * share), v),
              event: e.id,
              played: n
            ));
            if (e.tie) now[key] = out.length - 1;
          }
        }
      }
    }
    out.sort((a, b) => a.note.start.compareTo(b.note.start));
    return out;
  }

  /// _hairpin is how much a hairpin swells or fades a note [at] quarters
  /// into [bar]: by the end of a crescendo a third louder, a diminuendo a
  /// third softer.
  double _hairpin(String part, int staff, int bar, double at) {
    double pos(ScoreTime t) {
      var q = 0.0;
      for (var i = 0; i < t.bar; i++) {
        q += barQuarters(i);
      }
      return q + t.at;
    }

    var here = pos((bar: bar, at: at));
    for (var s in spanners) {
      if (s.part != part || s.staff != staff) continue;
      if (s.kind != SpannerKind.crescendo && s.kind != SpannerKind.diminuendo) {
        continue;
      }
      var a = pos(s.from), b = pos(s.to);
      if (here < a - 1e-9 || here > b + 1e-9) continue;
      var f = b > a ? (here - a) / (b - a) : 1.0;
      return 1 + (s.kind == SpannerKind.crescendo ? 1 : -1) * 0.33 * f;
    }
    return 1;
  }

  MusicScore copyWith({
    String? title,
    String? subtitle,
    String? composer,
    String? lyricist,
    double? tempo,
    String? tempoText,
    int? beats,
    int? beatUnit,
    int? fifths,
    List<BarInfo>? bars,
    List<ScorePart>? parts,
    List<Spanner>? spanners,
    int? verses,
    Map<String, Offset>? offsets,
  }) =>
      MusicScore(id,
          title: title ?? this.title,
          subtitle: subtitle ?? this.subtitle,
          composer: composer ?? this.composer,
          lyricist: lyricist ?? this.lyricist,
          tempo: (tempo ?? this.tempo).clamp(20.0, 400.0),
          tempoText: tempoText ?? this.tempoText,
          beats: (beats ?? this.beats).clamp(1, 32),
          beatUnit: beatUnit ?? this.beatUnit,
          fifths: (fifths ?? this.fifths).clamp(-7, 7),
          bars: bars ?? this.bars,
          parts: parts ?? this.parts,
          spanners: spanners ?? this.spanners,
          verses: (verses ?? this.verses).clamp(1, 8),
          offsets: offsets ?? this.offsets);

  Map<String, dynamic> toJson() => {
        "id": id,
        if (title.isNotEmpty) "title": title,
        if (subtitle.isNotEmpty) "subtitle": subtitle,
        if (composer.isNotEmpty) "composer": composer,
        if (lyricist.isNotEmpty) "lyricist": lyricist,
        "tempo": tempo,
        if (tempoText.isNotEmpty) "tempoText": tempoText,
        "time": [beats, beatUnit],
        if (fifths != 0) "fifths": fifths,
        "bars": [for (var b in bars) b.toJson()],
        "parts": [for (var p in parts) p.toJson()],
        if (spanners.isNotEmpty)
          "spanners": [for (var s in spanners) s.toJson()],
        if (verses != 1) "verses": verses,
        if (offsets.isNotEmpty) "off": _offsetsToJson(offsets),
      };

  static MusicScore fromJson(Map<String, dynamic> j) {
    var t = j["time"];
    var (beats, unit) = t is List && t.length == 2 && t[0] is num && t[1] is num
        ? ((t[0] as num).toInt(), (t[1] as num).toInt())
        : (4, 4);
    return MusicScore(jsonString(j["id"], ""),
        title: jsonString(j["title"], ""),
        subtitle: jsonString(j["subtitle"], ""),
        composer: jsonString(j["composer"], ""),
        lyricist: jsonString(j["lyricist"], ""),
        tempo: jsonDouble(j["tempo"], 100).clamp(20.0, 400.0),
        tempoText: jsonString(j["tempoText"], ""),
        beats: beats.clamp(1, 32),
        beatUnit: const [1, 2, 4, 8, 16, 32].contains(unit) ? unit : 4,
        fifths: jsonInt(j["fifths"], 0).clamp(-7, 7),
        bars: [
          for (var b in (j["bars"] is List ? j["bars"] as List : const []))
            b is Map<String, dynamic> ? BarInfo.fromJson(b) : const BarInfo(),
        ],
        parts: [
          for (var p in (j["parts"] is List ? j["parts"] as List : const []))
            if (p is Map<String, dynamic>) ScorePart.fromJson(p),
        ],
        spanners: [
          for (var s
              in (j["spanners"] is List ? j["spanners"] as List : const []))
            if (s is Map<String, dynamic>)
              if (Spanner.fromJson(s) case var x?) x,
        ],
        verses: jsonInt(j["verses"], 1).clamp(1, 8),
        offsets: _offsetsFromJson(j["off"]));
  }
}

/// chordKeys is chord symbol [symbol] voiced as a guitar strums it: the
/// root low (or the bass after a slash), the chord's notes above it, six
/// strings' worth between E2 and E4. An unreadable symbol is C major.
List<int> chordKeys(String symbol) {
  var m = RegExp(r"^\s*([A-G])([#b♯♭]?)([^/]*)(?:/([A-G])([#b♯♭]?))?\s*$")
      .firstMatch(symbol);
  int pc(String l, String a) =>
      (_naturals[_letters.indexOf(l)] +
          (a == "#" || a == "♯"
              ? 1
              : a == "b" || a == "♭"
                  ? -1
                  : 0)) %
      12;
  if (m == null) return chordKeys("C");
  var root = pc(m.group(1)!, m.group(2) ?? "");
  var q = (m.group(3) ?? "").trim();
  var bass = m.group(4) != null ? pc(m.group(4)!, m.group(5) ?? "") : root;
  // The chord's intervals above its root.
  var minor = RegExp(r"^(m(?!aj)|min|-)").hasMatch(q);
  var dim = q.startsWith("dim") || q.startsWith("°");
  var aug = q.startsWith("aug") || q.startsWith("+");
  var third = q.contains("sus2")
      ? 2
      : q.contains("sus")
          ? 5
          : minor || dim
              ? 3
              : 4;
  var fifth = dim
      ? 6
      : aug
          ? 8
          : 7;
  var tones = <int>[0, third, fifth];
  if (q.contains("maj7") || q.contains("Δ")) {
    tones.add(11);
  } else if (q.contains("7") || q.contains("9") && !q.contains("add")) {
    tones.add(dim && q.contains("dim7") ? 9 : 10);
  }
  if (q.contains("6")) tones.add(9);
  if (q.contains("9")) tones.add(14);
  // From the bass upward, within the strings' reach.
  var low = 40 + ((bass - 40) % 12 + 12) % 12; // the bass's lowest from E2
  var keys = <int>[low];
  var pcs = {for (var t in tones) (root + t) % 12};
  for (var k = low + 1; k <= 64 && keys.length < 6; k++) {
    if (pcs.contains(k % 12)) keys.add(k);
  }
  return keys;
}

/// scoreFromNotes writes [notes] (in seconds, at [tempo]) out as a score of
/// one part, spelled, voiced and tied as notation.dart writes them: the way
/// a MIDI file, a MusicXML file or an instrument's own notes become a score.
MusicScore scoreFromNotes(String id, List<MidiNote> notes,
    {String title = "",
    String instrument = "piano",
    double tempo = 120,
    int beats = 4,
    int beatUnit = 4,
    int? fifths}) {
  var key = fifths ?? notation.keyFifthsOf(notes);
  var inst = scoreInstrument(instrument);
  var two = inst.clefs.length > 1;
  // One staff: lifted whole octaves above middle C, so notation.dart keeps
  // every note on the staff it writes, then put back.
  var lift = 0;
  if (!two && notes.isNotEmpty) {
    var low = notes.map((n) => n.key).reduce(math.min);
    if (low < notation.splitKey) {
      lift = ((notation.splitKey - low) / 12).ceil() * 12;
    }
  }
  var written = notation.writeScore(
      [for (var n in notes) n.copyWith(key: n.key + lift)],
      tempo: tempo,
      beatsPerBar: beats,
      beatUnit: beatUnit,
      fifths: key,
      only: two ? null : {notation.Staff.treble});
  var n = 0;
  List<ScoreEvent> bar(List<notation.Written> items) {
    var out = <ScoreEvent>[];
    for (var w in items) {
      var value = w.base;
      out.add(ScoreEvent("e${++n}", value,
          dots: w.dots,
          tuplet: w.tuplet ? Tuplet.triplet : null,
          pitches: [
            for (var k in w.keys)
              Pitch.spelled(k - lift + inst.transpose, fifths: key),
          ]..sort((a, b) => a.key.compareTo(b.key)),
          tie: w.tiedOn,
          voice: w.voice));
    }
    return out;
  }

  var staves = <ScoreStaff>[];
  if (two) {
    for (var (s, clef) in [
      (notation.Staff.treble, inst.clefs[0]),
      (notation.Staff.bass, inst.clefs[1]),
    ]) {
      staves.add(ScoreStaff(
          clef, [for (var b in written.bars) bar(b.staves[s] ?? const [])]));
    }
  } else {
    staves.add(ScoreStaff(inst.clefs.first, [
      for (var b in written.bars)
        bar(b.staves[notation.Staff.treble] ?? const []),
    ]));
  }
  var barCount = written.bars.isEmpty ? 1 : written.bars.length;
  return MusicScore(id,
      title: title,
      tempo: tempo,
      beats: beats,
      beatUnit: beatUnit,
      fifths: key,
      bars: List.filled(barCount, const BarInfo()),
      parts: [
        ScorePart("p1", inst.name, inst.id, staves, short: inst.short),
      ]);
}

/// instrumentForProgram is the score instrument nearest General MIDI
/// [program]: the one that plays it, else one of its family, else a piano.
String instrumentForProgram(int? program) {
  if (program == null) return "piano";
  for (var i in scoreInstruments) {
    if (i.program == program && !i.strum) return i.id;
  }
  return switch (program ~/ 8) {
    3 => "guitar",
    4 => "bassGuitar",
    5 => "violin",
    7 => "clarinet",
    8 => "flute",
    _ => "piano",
  };
}

/// scoreFromMusicXml is a MusicXML file made a score: its title, tempo,
/// time and key, its notes written out.
MusicScore scoreFromMusicXml(String id, MusicXmlScore x) {
  var tempo = x.tempo ?? 100;
  return scoreFromNotes(id, x.played(tempo),
      title: x.title,
      tempo: tempo,
      beats: x.beatsPerBar,
      beatUnit: x.beatUnit,
      fifths: x.fifths);
}

/// scoreFromMidi is a MIDI file made a score of one part, for the
/// instrument its program asks for, its seconds read at [tempo].
MusicScore scoreFromMidi(String id, MidiImport m,
        {String title = "", double tempo = 120}) =>
    scoreFromNotes(id, m.notes,
        title: title,
        tempo: tempo,
        instrument: instrumentForProgram(m.program));
