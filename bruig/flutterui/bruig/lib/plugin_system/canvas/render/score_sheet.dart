import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart'
    show paintBoxBorder, paintBoxFill;
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:flutter/painting.dart';

// score_sheet.dart is a Sheet music element showing a part of a score: the
// part (or one hand of it) engraved a few systems at a time, turned to the
// playhead's page, the notes under the playhead lit, and the playhead drawn
// unless the sheet says highlight only.
//
// The playhead is the canvas's own (the frame, through the part's channel's
// start), so the sheet, timeline and instrument agree on where it is.

/// SheetView is a score part as a sheet shows it at a frame.
class SheetView {
  final MusicScore score;
  final ScorePart part;
  final AudioElement channel;
  final EngravedScore engraved;

  /// scale is drawn size to the engraving's; origin is where its (0, 0) is
  /// drawn; window is the engraving's rows shown.
  final double scale;
  final Offset origin;
  final Rect window;

  /// seconds is the playhead's place in the part's playing; place is where
  /// that is in the score (null outside it).
  final double seconds;
  final ({int played, int bar, double at})? place;

  const SheetView(this.score, this.part, this.channel, this.engraved,
      this.scale, this.origin, this.window, this.seconds, this.place);

  /// toScore is [p] on the canvas as a place on the engraving.
  Offset toScore(Offset p) => (p - origin) / scale;
}

/// SheetBarPart is a piece of a sheet's playbar.
enum SheetBarPart {
  start,
  back,
  play,
  on,
  track,

  /// click switches its metronome; slower, faster and reset set its speed,
  /// shown by speed. In the editor only: a book's sound is made at the
  /// written speed.
  click,
  slower,
  speed,
  faster,
  reset,
}

/// sheetBarRect is [e]'s playbar in [bounds], or null if it has none: a
/// strip across the top, a finger's height however small the sheet.
Rect? sheetBarRect(SheetElement e, Rect bounds) {
  if (!e.playbar || e.score.isEmpty) return null;
  var room = e.box.inner(bounds);
  var h = (room.height * 0.085).clamp(18.0, 44.0);
  return Rect.fromLTWH(room.left, room.top, room.width, h);
}

/// sheetBars are the first and last bars [e] shows of [s], from nought.
(int, int) sheetBars(SheetElement e, MusicScore s) {
  var last = math.max(0, s.barCount - 1);
  var a = e.fromBar > 0 ? (e.fromBar - 1).clamp(0, last) : 0;
  var b = e.toBar > 0 ? (e.toBar - 1).clamp(a, last) : last;
  return (a, b);
}

/// sheetSpan is when [e]'s bars play in the part's playing, in seconds:
/// from its first bar's first start to the end of its last bar after that.
(double, double) sheetSpan(SheetElement e, MusicScore s) {
  var order = s.playOrder();
  if (order.isEmpty) return (0, 0);
  var (a, b) = sheetBars(e, s);
  var i = math.max(0, order.indexWhere((p) => p.bar == a));
  var j = order.indexWhere((p) => p.bar == b, i);
  if (e.toBar <= 0 || j < 0) j = order.length - 1;
  if (e.fromBar <= 0) i = 0;
  return (
    s.secondsAt(order, order[i].start),
    s.secondsAt(order, order[j].start + s.barQuarters(order[j].bar))
  );
}

/// sheetFrames is [sheetSpan] in [doc]'s frames from the part's channel's
/// start. Null without a part.
(int, int)? sheetFrames(SheetElement e, CanvasDocument doc) {
  var s = doc.scores.where((x) => x.id == e.score).firstOrNull;
  var part = s?.partById(e.part);
  var channel = part == null ? null : doc.elementById(part.channel);
  if (s == null || channel is! AudioElement) return null;
  var (from, to) = sheetSpan(e, s);
  var rate = math.max(1, doc.frameRate);
  return (
    channel.clip.at + (from * rate - 1e-6).ceil(),
    channel.clip.at + (to * rate).round()
  );
}

/// sheetBarParts are where each piece of a playbar in [bar] is: four square
/// buttons, then the track to the end.
Map<SheetBarPart, Rect> sheetBarParts(Rect bar, {bool practice = true}) {
  var side = bar.height;
  var pad = side * 0.15;
  var out = <SheetBarPart, Rect>{};
  var x = bar.left + pad;
  for (var p in [
    SheetBarPart.start,
    SheetBarPart.back,
    SheetBarPart.play,
    SheetBarPart.on,
  ]) {
    out[p] = Rect.fromLTWH(x, bar.top, side, side);
    x += side;
  }
  // The practice parts along the right: click, then speed between slower
  // and faster, and reset.
  var right = bar.right - pad;
  if (practice) {
    for (var (p, w) in [
      (SheetBarPart.reset, side),
      (SheetBarPart.faster, side),
      (SheetBarPart.speed, side * 1.9),
      (SheetBarPart.slower, side),
      (SheetBarPart.click, side * 1.2),
    ]) {
      out[p] = Rect.fromLTWH(right - w, bar.top, w, side);
      right -= w;
    }
    right -= pad * 2;
  }
  out[SheetBarPart.track] =
      Rect.fromLTRB(x + pad * 2, bar.top, right - pad * 2, bar.bottom);
  return out;
}

/// sheetSpeedStep is how much slower and faster change the speed by.
const sheetSpeedStep = 0.05;

/// sheetTrackLine is the line a playbar's [track] draws its fill along.
Rect sheetTrackLine(Rect track) {
  var h = track.height * 0.14;
  return Rect.fromLTWH(track.left, track.center.dy - h / 2, track.width, h);
}

double sheetKnobRadius(Rect track) => sheetTrackLine(track).height * 1.6;

/// sheetPlaying says whether the canvas is playing, so play shows pause;
/// set by the editor (null in a video).
bool Function()? sheetPlaying;

/// paintSheetBar draws [e]'s playbar in [bar]: buttons in the sheet's ink
/// on a tint of it, the track filled to [progress].
///
/// A book draws the track's fill and knob as pictures of their own, moved
/// by its clock: [knob] false leaves the knob out.
void paintSheetBar(
    ui.Canvas canvas, Rect bar, SheetElement e, double progress, bool playing,
    {bool knob = true, bool practice = true}) {
  var ink = e.ink;
  var r = bar.height * 0.22;
  canvas.drawRRect(
      RRect.fromRectAndCorners(bar,
          topLeft: Radius.circular(r), topRight: Radius.circular(r)),
      Paint()..color = ink.withValues(alpha: 0.07));
  canvas.drawLine(
      bar.bottomLeft,
      bar.bottomRight,
      Paint()
        ..color = ink.withValues(alpha: 0.18)
        ..strokeWidth = 1);
  var parts = sheetBarParts(bar, practice: practice);
  var fill = Paint()..color = ink.withValues(alpha: 0.82);
  void label(String t, Offset c, double size, Color colour) {
    var tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: "Inter",
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: colour)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  for (var MapEntry(key: p, value: box) in parts.entries) {
    var c = box.center, u = box.height * 0.16;
    switch (p) {
      case SheetBarPart.start:
        canvas.drawRect(
            Rect.fromLTWH(c.dx - u * 1.3, c.dy - u, u * 0.45, u * 2), fill);
        canvas.drawPath(
            Path()
              ..moveTo(c.dx + u * 1.1, c.dy - u)
              ..lineTo(c.dx - u * 0.75, c.dy)
              ..lineTo(c.dx + u * 1.1, c.dy + u)
              ..close(),
            fill);
      case SheetBarPart.back:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx + u * 0.7, c.dy - u)
              ..lineTo(c.dx - u * 0.9, c.dy)
              ..lineTo(c.dx + u * 0.7, c.dy + u)
              ..close(),
            fill);
      case SheetBarPart.on:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - u * 0.7, c.dy - u)
              ..lineTo(c.dx + u * 0.9, c.dy)
              ..lineTo(c.dx - u * 0.7, c.dy + u)
              ..close(),
            fill);
      case SheetBarPart.play:
        if (playing) {
          for (var dx in [-u * 0.75, u * 0.25]) {
            canvas.drawRect(
                Rect.fromLTWH(c.dx + dx, c.dy - u * 1.1, u * 0.5, u * 2.2),
                fill);
          }
        } else {
          canvas.drawPath(
              Path()
                ..moveTo(c.dx - u * 0.8, c.dy - u * 1.25)
                ..lineTo(c.dx + u * 1.3, c.dy)
                ..lineTo(c.dx - u * 0.8, c.dy + u * 1.25)
                ..close(),
              fill);
        }
      case SheetBarPart.click:
        // A metronome: its body, and its arm; lit while on.
        if (e.click) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(box.deflate(box.height * 0.12),
                  Radius.circular(box.height * 0.2)),
              Paint()..color = const Color(0xFFE2622B).withValues(alpha: 0.2));
        }
        var colour = e.click ? const Color(0xFFE2622B) : fill.color;
        var h = box.height * 0.56, w = h * 0.8;
        var bottom = c.dy + h / 2;
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - w * 0.22, c.dy - h / 2)
              ..lineTo(c.dx + w * 0.22, c.dy - h / 2)
              ..lineTo(c.dx + w / 2, bottom)
              ..lineTo(c.dx - w / 2, bottom)
              ..close(),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = h * 0.1
              ..strokeJoin = StrokeJoin.round
              ..color = colour);
        canvas.drawLine(
            Offset(c.dx, bottom - h * 0.15),
            Offset(c.dx + w * 0.38, c.dy - h * 0.62),
            Paint()
              ..strokeWidth = h * 0.1
              ..strokeCap = StrokeCap.round
              ..color = colour);
      case SheetBarPart.slower:
        label("−", c, box.height * 0.55, fill.color);
      case SheetBarPart.faster:
        label("+", c, box.height * 0.55, fill.color);
      case SheetBarPart.speed:
        // Speed as a share of real time, picked out when not real time.
        var real = (e.tempo - 1).abs() < 1e-6;
        label("${(e.tempo * 100).round()}%", c, box.height * 0.34,
            real ? fill.color : const Color(0xFFE2622B));
      case SheetBarPart.reset:
        // Reset to real time: only when not already.
        if ((e.tempo - 1).abs() > 1e-6) {
          label("1×", c, box.height * 0.36, fill.color);
        }
      case SheetBarPart.track:
        var t = sheetTrackLine(box);
        var h = t.height;
        canvas.drawRRect(RRect.fromRectAndRadius(t, Radius.circular(h / 2)),
            Paint()..color = ink.withValues(alpha: 0.18));
        var done = progress.clamp(0.0, 1.0);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(t.left, t.top, t.width * done, h),
                Radius.circular(h / 2)),
            Paint()..color = const Color(0xFFE2622B));
        if (knob) {
          canvas.drawCircle(Offset(t.left + t.width * done, c.dy), h * 1.6,
              Paint()..color = const Color(0xFFE2622B));
        }
    }
  }
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

/// sheetEventMarks turns practice marks by note index into colours by the
/// score's event ids.
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

EngravedScore _engraved(
    MusicScore s, String part, Set<int> staves, SheetElement e,
    {double width = 860}) {
  var cache = _layouts[s] ??= {};
  var title = e.title.isNotEmpty ? e.title : s.title;
  var bars = sheetBars(e, s);
  var key = "$part|${(staves.toList()..sort()).join(",")}|$title|"
      "${e.showTitle}${e.showSubtitle}${e.showComposer}${e.showTempo}"
      "${e.showNames}${e.showMarks}${e.showDiagrams}|$bars|$width";
  return cache[key] ??= layoutScore(
      s,
      EngraveOptions(
          parts: {part},
          staves: {part: staves},
          heading:
              e.showTitle || e.showSubtitle || e.showComposer || e.showTempo,
          titled: e.showTitle,
          subtitled: e.showSubtitle,
          credited: e.showComposer,
          tempoed: e.showTempo,
          names: e.showNames,
          marks: e.showMarks,
          diagrams: e.showDiagrams,
          bars: bars,
          title: title,
          width: width));
}

/// _pageWidth is how wide [e]'s part is engraved to fill [room] across, as
/// the Studio's page does: a page of systems at 860 across is as tall as it
/// is; engraved as much wider as the room is for its height.
double _pageWidth(EngravedScore engraved, SheetElement e, Rect room,
    {double at = 860}) {
  var systems = engraved.systems;
  if (systems.isEmpty || room.height <= 0) return at;
  var lines = math.min(math.max(1, e.lines), systems.length);
  var tall = systems[lines - 1].bottom;
  var w = room.width / room.height * tall;
  // To the nearest twenty, within reason: a page is not one bar tall.
  return ((w / 20).round() * 20).clamp(360, 3200).toDouble();
}

/// sheetViewOf is [e] showing its score part at [frame] in [bounds], or
/// null where it shows none (or its score or channel has gone).
SheetView? sheetViewOf(
    SheetElement e, Rect bounds, CanvasDocument doc, int frame) {
  if (e.score.isEmpty) return null;
  var s = doc.scores.where((x) => x.id == e.score).firstOrNull;
  var part = s?.partById(e.part);
  var channel = part == null ? null : doc.elementById(part.channel);
  if (s == null || part == null || channel is! AudioElement) return null;
  var bar = sheetBarRect(e, bounds);
  bounds = e.box.inner(bounds);
  if (bar != null) {
    bounds =
        Rect.fromLTRB(bounds.left, bar.bottom, bounds.right, bounds.bottom);
  }
  if (bounds.width <= 0 || bounds.height <= 0) return null;
  var staves = sheetStaves(part, e.hands);
  // As wide as its room for a page's height, worked out twice: a page's
  // height moves a little with how many bars are on a line.
  var width = _pageWidth(_engraved(s, part.id, staves, e), e, bounds);
  width = _pageWidth(_engraved(s, part.id, staves, e, width: width), e, bounds,
      at: width);
  var es = _engraved(s, part.id, staves, e, width: width);
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
  // The first page has the heading over it.
  var window = Rect.fromLTRB(0, first == 0 ? 0 : systems[first].top,
      es.options.width, systems[last].bottom);
  var scale =
      math.min(bounds.width / window.width, bounds.height / window.height);
  var drawn = window.size * scale;
  var origin = Offset(bounds.left + (bounds.width - drawn.width) / 2,
          bounds.top + (bounds.height - drawn.height) / 2) -
      window.topLeft * scale;
  return SheetView(s, part, channel, es, scale, origin, window, seconds, place);
}

/// paintScoreSheet draws [view] in [bounds]: paper, the part's page, notes
/// under the playhead lit, practice marks, and the playhead unless [e]
/// shows the highlight only.
///
/// A book draws it a piece at a time (epub_layers.dart): [lit] in place of
/// what is under the playhead, [head] whether the playhead is drawn,
/// [progress] and [playing] for the playbar, [bar] whether it is drawn.
void paintScoreSheet(
    ui.Canvas canvas, Rect bounds, SheetElement e, SheetView view,
    {Map<String, Color> marks = const {},
    Set<String>? lit,
    bool? head,
    double? progress,
    bool? playing,
    bool bar = true,
    bool knob = true,
    bool practice = true}) {
  // Its frame: the paper inside its corners, the border drawn over the
  // music.
  var frame = e.box.copyWith(fill: e.paper);
  paintBoxFill(canvas, bounds, frame);
  var sounding = lit ?? sheetSounding(view);
  canvas.save();
  canvas.clipRRect(frame.rounded(bounds));
  canvas.clipRect(e.box.inner(bounds));
  canvas.translate(view.origin.dx, view.origin.dy);
  canvas.scale(view.scale);
  paintScore(canvas, view.engraved,
      state: ScorePaintState(
          playing: sounding,
          marks: marks,
          // The paper is the box's, drawn above; the music in the sheet's
          // own ink.
          paper: const Color(0x00000000),
          ink: e.ink,
          // Each hand in its instrument's colour, on a piano's part.
          sounding: e.handColours && view.part.staves.length >= 2
              ? view.channel.accent
              : null,
          left: e.handColours && view.part.staves.length >= 2
              ? view.channel.leftAccent
              : null,
          playhead: (head ?? e.playhead) && view.place != null
              ? (bar: view.place!.bar, at: view.place!.at)
              : null));
  canvas.restore();
  if (sheetBarRect(e, bounds) case var strip? when bar) {
    paintSheetBar(canvas, strip, e, progress ?? sheetProgress(e, view),
        playing ?? sheetPlaying?.call() ?? false,
        knob: knob, practice: practice);
  }
  paintBoxBorder(canvas, bounds, frame);
}

/// sheetSounding are the events of [view]'s part under its playhead.
Set<String> sheetSounding(SheetView view) => {
      for (var n in partNotesOf(view.score, view.part.id))
        if (n.note.start <= view.seconds + 1e-6 &&
            n.note.end > view.seconds + 1e-6)
          n.event
    };

double sheetProgress(SheetElement e, SheetView view) {
  var (from, to) = sheetSpan(e, view.score);
  return to <= from ? 0 : ((view.seconds - from) / (to - from)).clamp(0.0, 1.0);
}

/// sheetOnsets are the frames where a note of [e]'s shown staves starts, in
/// order, through the repeats.
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
  // Only those in its bars, as they play in its span.
  var (from, to) = sheetSpan(e, s);
  for (var n in partNotesOf(s, part.id)) {
    if (!mine.contains(n.event)) continue;
    if (n.note.start < from - 1e-6 || n.note.start >= to - 1e-6) continue;
    // A strum's first string is the onset. Rounded up so at its onset the
    // note is lit and heard (rounding could fall a frame before it).
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
