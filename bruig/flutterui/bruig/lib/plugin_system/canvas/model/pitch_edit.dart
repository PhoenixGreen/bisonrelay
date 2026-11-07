import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonStr;

// pitch_edit.dart is a recording's notes as sung, and what is done to each
// -- moved, straightened onto its note, its wobble kept or smoothed, made
// louder or softer -- as Melodyne does it: read from the recording once,
// the recording made again from the original with them, its timing kept.

/// PitchNote is one note of a recording: from [start] to [end] seconds into
/// the original, sung at [sung] (a MIDI note, fractional: its mean), and
/// what is done to it, as the prototype's Pitch editor does.
class PitchNote {
  final double start, end;
  final double sung;

  /// shift is semitones up (down, negative).
  final double shift;

  /// straighten is how far onto the nearest semitone its middle is drawn,
  /// nought to one: Melodyne's pitch centre.
  final double straighten;

  /// wobble is how much of its slow drift round its middle is kept, and
  /// vibrato how much of its quick swing: one as sung, nought flat.
  final double wobble, vibrato;

  /// gainDb is how much louder (softer, negative).
  final double gainDb;

  /// retuneMs is how long it takes to reach its note from the pitch sung,
  /// from its start: nought at once, longer as a singer's ear would.
  final double retuneMs;

  /// formant is its voice's colour moved, in semitones: up thinner, down
  /// deeper, its pitch the same.
  final double formant;

  /// slideMs is how long it glides in from the note before it.
  final double slideMs;

  /// curve is a pitch drawn over it -- (seconds into the original, MIDI
  /// note) -- heard in place of its note where it is drawn.
  final List<(double, double)> curve;

  const PitchNote(this.start, this.end, this.sung,
      {this.shift = 0,
      this.straighten = 0,
      this.wobble = 1,
      this.vibrato = 1,
      this.gainDb = 0,
      this.retuneMs = 0,
      this.formant = 0,
      this.slideMs = 0,
      this.curve = const []});

  double get length => end - start;

  /// target is the note it is moved to, as a MIDI note: its middle moved
  /// by [straighten] onto the nearest semitone, then by [shift].
  double get target =>
      sung + (sung.roundToDouble() - sung) * straighten + shift;

  /// edited is whether anything is done to it.
  bool get edited =>
      shift != 0 ||
      straighten != 0 ||
      wobble != 1 ||
      vibrato != 1 ||
      gainDb != 0 ||
      retuneMs != 0 ||
      formant != 0 ||
      slideMs != 0 ||
      curve.isNotEmpty;

  /// movedTo is it moved onto [note], its middle drawn right onto it.
  PitchNote movedTo(double note) =>
      copyWith(straighten: 1, shift: note - sung.roundToDouble());

  /// drawnAt is the pitch drawn at [t] seconds, or null where none is.
  double? drawnAt(double t) {
    if (curve.length < 2 || t < curve.first.$1 || t > curve.last.$1) {
      return null;
    }
    for (var i = 1; i < curve.length; i++) {
      var (t1, m1) = curve[i];
      if (t > t1) continue;
      var (t0, m0) = curve[i - 1];
      return t1 <= t0 ? m1 : m0 + (m1 - m0) * (t - t0) / (t1 - t0);
    }
    return curve.last.$2;
  }

  PitchNote copyWith(
          {double? start,
          double? end,
          double? sung,
          double? shift,
          double? straighten,
          double? wobble,
          double? vibrato,
          double? gainDb,
          double? retuneMs,
          double? formant,
          double? slideMs,
          List<(double, double)>? curve}) =>
      PitchNote(start ?? this.start, end ?? this.end, sung ?? this.sung,
          shift: (shift ?? this.shift).clamp(-24.0, 24.0),
          straighten: (straighten ?? this.straighten).clamp(0.0, 1.0),
          wobble: (wobble ?? this.wobble).clamp(0.0, 2.0),
          vibrato: (vibrato ?? this.vibrato).clamp(0.0, 2.0),
          gainDb: (gainDb ?? this.gainDb).clamp(-24.0, 12.0),
          retuneMs: (retuneMs ?? this.retuneMs).clamp(0.0, 400.0),
          formant: (formant ?? this.formant).clamp(-12.0, 12.0),
          slideMs: (slideMs ?? this.slideMs).clamp(0.0, 400.0),
          curve: curve ?? this.curve);

  /// reset is it as sung, where it is.
  PitchNote get reset => PitchNote(start, end, sung);

  Map<String, dynamic> toJson() => {
        "s": _r(start),
        "e": _r(end),
        "p": _r(sung),
        if (shift != 0) "shift": _r(shift),
        if (straighten != 0) "straighten": _r(straighten),
        if (wobble != 1) "wobble": _r(wobble),
        // Written always where it differs from the drift's: a file from
        // before, with no vibrato of its own, kept both by its wobble.
        if (vibrato != wobble) "vibrato": _r(vibrato),
        if (gainDb != 0) "gain": _r(gainDb),
        if (retuneMs != 0) "retune": _r(retuneMs),
        if (formant != 0) "formant": _r(formant),
        if (slideMs != 0) "slide": _r(slideMs),
        if (curve.isNotEmpty)
          "curve": [
            for (var (t, m) in curve) [_r(t), _r(m)]
          ],
      };

  static double _r(double v) => (v * 1000).round() / 1000;

  static PitchNote? fromJson(Object? json) {
    if (json is! Map) return null;
    var s = jsonDouble(json["s"], -1), e = jsonDouble(json["e"], -1);
    if (s < 0 || e <= s) return null;
    var wobble = jsonDouble(json["wobble"], 1);
    return PitchNote(s, e, jsonDouble(json["p"], 60)).copyWith(
        shift: jsonDouble(json["shift"], 0),
        straighten: jsonDouble(json["straighten"], 0),
        wobble: wobble,
        vibrato: jsonDouble(json["vibrato"], wobble),
        gainDb: jsonDouble(json["gain"], 0),
        retuneMs: jsonDouble(json["retune"], 0),
        formant: jsonDouble(json["formant"], 0),
        slideMs: jsonDouble(json["slide"], 0),
        curve: [
          if (json["curve"] case List points)
            for (var p in points)
              if (p case [num t, num m]) (t.toDouble(), m.toDouble()),
        ]);
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
      other.vibrato == vibrato &&
      other.gainDb == gainDb &&
      other.retuneMs == retuneMs &&
      other.formant == formant &&
      other.slideMs == slideMs &&
      _sameCurve(other.curve, curve);

  static bool _sameCurve(List<(double, double)> a, List<(double, double)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(start, end, sung, shift, straighten, wobble,
      vibrato, gainDb, retuneMs, formant, slideMs, curve.length);
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
      n.copyWith(end: at, curve: [
        for (var p in n.curve)
          if (p.$1 <= at) p
      ]),
      n.copyWith(start: at, curve: [
        for (var p in n.curve)
          if (p.$1 >= at) p
      ]),
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
      a.copyWith(end: b.end, sung: sung, curve: [...a.curve, ...b.curve]),
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
