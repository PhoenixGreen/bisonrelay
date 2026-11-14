import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:flutter/painting.dart';

// score_sheet.dart is a Sheet music element showing a part of a score (Ken,
// 2026-11-14: "show one part on the canvas ... lighting the notes as the
// playhead passes"): the part (or one hand of it) engraved, a few systems
// at a time, turned to the page the playhead is on; the notes under the
// playhead lit, and the playhead drawn unless the sheet says highlight only.
//
// The playhead is the canvas's own: the frame, through the part's channel's
// start. Stopped or playing, the sheet, the timeline and the instrument
// agree on where it is.

/// SheetView is a score part as a sheet shows it at a frame.
class SheetView {
  final MusicScore score;
  final ScorePart part;
  final AudioElement channel;
  final EngravedScore engraved;

  /// scale is drawn size to the engraving's; origin where its (0, 0) is
  /// drawn; window the engraving's rows shown.
  final double scale;
  final Offset origin;
  final Rect window;

  /// seconds is where the playhead is in the part's playing, and place
  /// where that is in the score (null outside it).
  final double seconds;
  final ({int played, int bar, double at})? place;

  const SheetView(this.score, this.part, this.channel, this.engraved,
      this.scale, this.origin, this.window, this.seconds, this.place);

  /// toScore is [p] on the canvas as a place on the engraving.
  Offset toScore(Offset p) => (p - origin) / scale;
}

/// sheetStaves are the staves of [part] a sheet showing [hands] shows.
Set<int> sheetStaves(ScorePart part, PracticeHands hands) =>
    part.staves.length < 2 || hands == PracticeHands.both
        ? {for (var i = 0; i < part.staves.length; i++) i}
        : {hands == PracticeHands.right ? 0 : 1};

final _layouts = Expando<Map<String, EngravedScore>>();
final _notes = Expando<Map<String, List<ScoreNote>>>();

/// partNotesOf is [s]'s part [part] as played, worked out once per score.
List<ScoreNote> partNotesOf(MusicScore s, String part) =>
    (_notes[s] ??= {})[part] ??= s.partNotes(part);

/// sheetEventMarks are practice marks by note index in [channel]'s part,
/// as colours by the score's event ids.
Map<String, Color> sheetEventMarks(SheetView view, Map<int, Color> byNote) {
  var notes = view.channel.instrument?.notes ?? const [];
  var played = partNotesOf(view.score, view.part.id);
  var out = <String, Color>{};
  for (var MapEntry(key: i, value: c) in byNote.entries) {
    if (i < 0 || i >= notes.length) continue;
    var n = notes[i];
    for (var p in played) {
      if (p.note.key == n.key && (p.note.start - n.start).abs() < 1e-6) {
        out[p.event] = c;
        break;
      }
    }
  }
  return out;
}

EngravedScore _engraved(MusicScore s, String part, Set<int> staves) {
  var cache = _layouts[s] ??= {};
  var key = "$part|${(staves.toList()..sort()).join(",")}";
  return cache[key] ??= layoutScore(
      s,
      EngraveOptions(
          parts: {part}, staves: {part: staves}, heading: false, width: 860));
}

/// sheetViewOf is [e] showing its score part at [frame] in [bounds], or
/// null where it shows no score part (or its score or channel has gone).
SheetView? sheetViewOf(
    SheetElement e, Rect bounds, CanvasDocument doc, int frame) {
  if (e.score.isEmpty) return null;
  var s = doc.scores.where((x) => x.id == e.score).firstOrNull;
  var part = s?.partById(e.part);
  var channel = part == null ? null : doc.elementById(part.channel);
  if (s == null || part == null || channel is! AudioElement) return null;
  var es = _engraved(s, part.id, sheetStaves(part, e.hands));
  var seconds = (frame - channel.clip.at) / math.max(1, doc.frameRate);
  var order = s.playOrder();
  var place = s.placeAt(order, seconds);
  // The page: [e.lines] systems, the one the playhead is in among them.
  var systems = es.systems;
  if (systems.isEmpty) return null;
  var on = 0;
  if (place != null) {
    var at = es.xOf(place.bar, place.at);
    if (at != null) on = at.$2;
  }
  var lines = math.max(1, e.lines);
  var first = (on ~/ lines) * lines;
  var last = math.min(systems.length, first + lines) - 1;
  var window = Rect.fromLTRB(
      0, systems[first].top, es.options.width, systems[last].bottom);
  var scale =
      math.min(bounds.width / window.width, bounds.height / window.height);
  var drawn = window.size * scale;
  var origin = Offset(bounds.left + (bounds.width - drawn.width) / 2,
          bounds.top + (bounds.height - drawn.height) / 2) -
      window.topLeft * scale;
  return SheetView(s, part, channel, es, scale, origin, window, seconds, place);
}

/// paintScoreSheet draws [view] in [bounds]: the paper, the page of the
/// part, the notes under the playhead lit, practice marks by event, and the
/// playhead unless [e] shows the highlight only.
void paintScoreSheet(
    ui.Canvas canvas, Rect bounds, SheetElement e, SheetView view,
    {Map<String, Color> marks = const {}}) {
  canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
      Paint()..color = e.paper);
  var playing = <String>{};
  for (var n in partNotesOf(view.score, view.part.id)) {
    if (n.note.start <= view.seconds + 1e-6 &&
        n.note.end > view.seconds + 1e-6) {
      playing.add(n.event);
    }
  }
  canvas.save();
  canvas.clipRect(bounds);
  canvas.translate(view.origin.dx, view.origin.dy);
  canvas.scale(view.scale);
  paintScore(canvas, view.engraved,
      state: ScorePaintState(
          playing: playing,
          marks: marks,
          playhead: e.playhead && view.place != null
              ? (bar: view.place!.bar, at: view.place!.at)
              : null));
  canvas.restore();
}

/// sheetOnsets are the frames where a note of [e]'s part (the staves it
/// shows) starts, in order, through the repeats.
List<int> sheetOnsets(SheetElement e, CanvasDocument doc) {
  var s = doc.scores.where((x) => x.id == e.score).firstOrNull;
  var part = s?.partById(e.part);
  var channel = part == null ? null : doc.elementById(part.channel);
  if (s == null || part == null || channel is! AudioElement) return const [];
  var staves = sheetStaves(part, e.hands);
  var mine = <String>{
    for (var (si, st) in part.staves.indexed)
      if (staves.contains(si))
        for (var b in st.bars)
          for (var x in b) x.id
  };
  var rate = math.max(1, doc.frameRate);
  var frames = <int>{};
  for (var n in partNotesOf(s, part.id)) {
    if (!mine.contains(n.event)) continue;
    // A strum's strings are a moment apart: its first is the onset.
    // The first frame the note has started by, so that at its onset it is
    // lit and heard (rounded, a frame could fall just before it).
    frames.add(channel.clip.at + (n.note.start * rate - 1e-6).ceil());
  }
  var list = frames.toList()..sort();
  // Strings of one strum land a frame or so apart; keep the first.
  var out = <int>[];
  for (var f in list) {
    if (out.isEmpty || f - out.last > 1) out.add(f);
  }
  return out;
}
