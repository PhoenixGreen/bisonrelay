import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:flutter/foundation.dart';

// score_channels.dart keeps the instrument channels a score's parts play on
// made from the score (Ken, 2026-11-14: "the score is the source"): every
// edit of the score writes each part's notes, as played, into its channel's
// part, so the timeline, the mix and the Sheet music element all hear and
// show what is written.

/// scoreLink is how a channel's part names the score part it is made from.
String scoreLink(String score, String part) => "$score/$part";

/// scoreSynced is [doc] with [score] in it -- in place of the one with its
/// id, or added -- and the channel of each of its parts that has one made
/// from it: its notes the part's as played, from the channel's start.
/// A channel already so made is left as it is.
CanvasDocument scoreSynced(CanvasDocument doc, MusicScore score) {
  var at = doc.scores.indexWhere((s) => s.id == score.id);
  var scores = [...doc.scores];
  if (at < 0) {
    scores.add(score);
  } else {
    scores[at] = score;
  }
  var next = doc.copyWith(scores: scores);
  var order = score.playOrder();
  for (var p in score.parts) {
    if (p.channel.isEmpty) continue;
    var e = next.elementById(p.channel);
    if (e is! AudioElement || e.instrument == null) continue;
    var part = e.instrument!;
    var notes = [for (var n in score.partNotes(p.id, order: order)) n.note];
    var link = scoreLink(score.id, p.id);
    if (part.score == link && listEquals(part.notes, notes)) continue;
    next = next.withElement(
        e.copyWith(instrument: part.copyWith(notes: notes, score: link)));
  }
  return next;
}

/// scoreRemoved is [doc] without score [id]; its channels keep the notes
/// they had, as their own now.
CanvasDocument scoreRemoved(CanvasDocument doc, String id) {
  var next = doc.copyWith(scores: [
    for (var s in doc.scores)
      if (s.id != id) s
  ]);
  for (var e in next.elements) {
    if (e is AudioElement && (e.instrument?.score ?? "").startsWith("$id/")) {
      next = next.withElement(
          e.copyWith(instrument: e.instrument!.copyWith(score: "")));
    }
  }
  return next;
}

/// scorePartOf is the score and part a channel's [part] is made from, or
/// null for one with notes of its own (or whose score has gone).
(MusicScore, ScorePart)? scorePartOf(CanvasDocument doc, InstrumentPart part) {
  if (!part.fromScore) return null;
  var i = part.score.indexOf("/");
  if (i < 0) return null;
  var s =
      doc.scores.where((x) => x.id == part.score.substring(0, i)).firstOrNull;
  var p = s?.partById(part.score.substring(i + 1));
  return s == null || p == null ? null : (s, p);
}

final Expando<Map<String, (List<ScoreNote>, Map<String, int>)>> _handNotes =
    Expando("handNotes");

/// scoreLeftHand are the keys of [part]'s notes sounding [seconds] in that
/// its score writes on a second staff -- a piano's bass staff, the left
/// hand's -- to be lit in the left hand's colour (Ken, 2026-11-15:
/// "different colours ... to demonstrate which hand is playing which
/// part"). Empty for a part of one staff, or one not from a score.
Set<int> scoreLeftHand(
    CanvasDocument doc, InstrumentPart part, double seconds) {
  var found = scorePartOf(doc, part);
  if (found == null) return const {};
  var (score, p) = found;
  if (p.staves.length < 2) return const {};
  var kept = _handNotes[score] ??= {};
  var (notes, staffOf) = kept[p.id] ??= (
    score.partNotes(p.id),
    {
      for (var (i, st) in p.staves.indexed)
        for (var b in st.bars)
          for (var e in b) e.id: i
    }
  );
  return {
    for (var n in notes)
      if (seconds >= n.note.start &&
          seconds < n.note.end &&
          (staffOf[n.event] ?? 0) >= 1)
        n.note.key,
  };
}
