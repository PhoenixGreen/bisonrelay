import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonStr;

// pitch_edit.dart is a recording's notes as sung, and what is done to each
// -- moved, straightened onto its note, its wobble kept or smoothed, made
// louder or softer -- as Melodyne does it: read from the recording once,
// the recording made again from the original with them, its timing kept.

/// PitchNote is one note of a recording: from [start] to [end] seconds into
/// the original, sung at [sung] (a MIDI note, fractional: its mean), and
/// what is done to it.
class PitchNote {
  final double start, end;
  final double sung;

  /// shift is semitones up (down, negative).
  final double shift;

  /// straighten is how far onto the nearest semitone its middle is drawn,
  /// nought to one: Melodyne's pitch centre.
  final double straighten;

  /// wobble is how much of its own drift and vibrato round its middle is
  /// kept: one as sung, nought flat.
  final double wobble;

  /// gainDb is how much louder (softer, negative).
  final double gainDb;

  const PitchNote(this.start, this.end, this.sung,
      {this.shift = 0, this.straighten = 0, this.wobble = 1, this.gainDb = 0});

  double get length => end - start;

  /// target is the note it is moved to, as a MIDI note: its middle moved
  /// by [straighten] onto the nearest semitone, then by [shift].
  double get target =>
      sung + (sung.roundToDouble() - sung) * straighten + shift;

  /// edited is whether anything is done to it.
  bool get edited =>
      shift != 0 || straighten != 0 || wobble != 1 || gainDb != 0;

  PitchNote copyWith(
          {double? start,
          double? end,
          double? sung,
          double? shift,
          double? straighten,
          double? wobble,
          double? gainDb}) =>
      PitchNote(start ?? this.start, end ?? this.end, sung ?? this.sung,
          shift: (shift ?? this.shift).clamp(-24.0, 24.0),
          straighten: (straighten ?? this.straighten).clamp(0.0, 1.0),
          wobble: (wobble ?? this.wobble).clamp(0.0, 2.0),
          gainDb: (gainDb ?? this.gainDb).clamp(-24.0, 12.0));

  Map<String, dynamic> toJson() => {
        "s": _r(start),
        "e": _r(end),
        "p": _r(sung),
        if (shift != 0) "shift": _r(shift),
        if (straighten != 0) "straighten": _r(straighten),
        if (wobble != 1) "wobble": _r(wobble),
        if (gainDb != 0) "gain": _r(gainDb),
      };

  static double _r(double v) => (v * 1000).round() / 1000;

  static PitchNote? fromJson(Object? json) {
    if (json is! Map) return null;
    var s = jsonDouble(json["s"], -1), e = jsonDouble(json["e"], -1);
    if (s < 0 || e <= s) return null;
    return PitchNote(s, e, jsonDouble(json["p"], 60)).copyWith(
        shift: jsonDouble(json["shift"], 0),
        straighten: jsonDouble(json["straighten"], 0),
        wobble: jsonDouble(json["wobble"], 1),
        gainDb: jsonDouble(json["gain"], 0));
  }

  @override
  bool operator ==(Object other) =>
      other is PitchNote &&
      other.start == start &&
      other.end == end &&
      other.sung == sung &&
      other.shift == shift &&
      other.straighten == straighten &&
      other.wobble == wobble &&
      other.gainDb == gainDb;

  @override
  int get hashCode =>
      Object.hash(start, end, sung, shift, straighten, wobble, gainDb);
}

/// PitchEdit is a recording's notes and what is done to them: kept on its
/// MediaSource, with [original] the recording as it was made, so it can
/// always be made again from it.
class PitchEdit {
  final String original;
  final List<PitchNote> notes;

  /// madeWith is the [key] the recording now playing was made with: when
  /// the notes are changed again, it is made again.
  final String madeWith;

  const PitchEdit(this.original, {this.notes = const [], this.madeWith = ""});

  /// key is what the recording made from it depends on.
  String get key => [
        for (var n in notes)
          if (n.edited) n.toJson()
      ].toString();

  /// stale is whether the recording playing is not the notes as they are.
  bool get stale => key != madeWith;

  PitchEdit copyWith({List<PitchNote>? notes, String? madeWith}) =>
      PitchEdit(original,
          notes: notes ?? this.notes, madeWith: madeWith ?? this.madeWith);

  /// split cuts note [i] in two at [at] seconds.
  PitchEdit split(int i, double at) {
    if (i < 0 || i >= notes.length) return this;
    var n = notes[i];
    if (at <= n.start + 0.02 || at >= n.end - 0.02) return this;
    return copyWith(notes: [
      ...notes.take(i),
      n.copyWith(end: at),
      n.copyWith(start: at),
      ...notes.skip(i + 1),
    ]);
  }

  /// glue joins note [i] to the next: one note, sung at their mean (each
  /// weighed by its length), with the first one's changes.
  PitchEdit glue(int i) {
    if (i < 0 || i + 1 >= notes.length) return this;
    var a = notes[i], b = notes[i + 1];
    var sung = (a.sung * a.length + b.sung * b.length) / (a.length + b.length);
    return copyWith(notes: [
      ...notes.take(i),
      a.copyWith(end: b.end, sung: sung),
      ...notes.skip(i + 2),
    ]);
  }

  Map<String, dynamic> toJson() => {
        "original": original,
        "notes": [for (var n in notes) n.toJson()],
        if (madeWith.isNotEmpty) "madeWith": madeWith,
      };

  static PitchEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    var original = jsonStr(json["original"]);
    if (original == null || original.isEmpty) return null;
    return PitchEdit(original,
        notes: [
          if (json["notes"] case List raw)
            for (var n in raw)
              if (PitchNote.fromJson(n) case var note?) note,
        ],
        madeWith: jsonStr(json["madeWith"]) ?? "");
  }
}

/// findNotes is the notes in a pitch track -- a MIDI note every [frame]
/// seconds, null where nothing is voiced: each run of voicing cut where its
/// pitch steps more than [step] semitones from where the note was going,
/// and kept where it is at least [least] seconds long.
List<PitchNote> findNotes(List<double?> track,
    {double frame = 0.02, double step = 0.8, double least = 0.06}) {
  var out = <PitchNote>[];
  var run = <double>[];
  var from = 0;
  void close(int to) {
    if (run.isEmpty) return;
    if ((to - from) * frame >= least) {
      var sorted = [...run]..sort();
      var mid = sorted[sorted.length ~/ 2];
      var mean = run.reduce((a, b) => a + b) / run.length;
      // The mean, unless a slide pulled it off: then the middle reading.
      out.add(PitchNote(
          from * frame, to * frame, (mean - mid).abs() > 0.5 ? mid : mean));
    }
    run = [];
  }

  for (var (i, p) in track.indexed) {
    if (p == null) {
      close(i);
      from = i + 1;
      continue;
    }
    if (run.isNotEmpty) {
      // Where the note is going: the last few readings.
      var recent = run.sublist(math.max(0, run.length - 4));
      var going = recent.reduce((a, b) => a + b) / recent.length;
      // A step held for two readings is a new note; one alone is a wobble.
      var next = i + 1 < track.length ? track[i + 1] : null;
      if ((p - going).abs() > step &&
          next != null &&
          (next - going).abs() > step) {
        close(i);
        from = i;
      }
    }
    run.add(p);
  }
  close(track.length);
  return out;
}
