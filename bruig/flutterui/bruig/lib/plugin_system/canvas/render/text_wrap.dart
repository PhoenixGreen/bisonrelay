import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// text_wrap.dart sets words around the things in their way.
//
// An opt-in alternative to Flutter's one-rectangle layout: lines are worked
// out one at a time (what is in the way at this height, how many words fit),
// one measurement per word, mostly absorbed by the layout cache. It runs
// only for a text element that asks, and only while something overlaps.

/// WrappedLine is one line of wrapped text: its characters, position, and
/// the paragraph they were measured as.
class WrappedLine {
  final int from;
  final int to;
  final Rect box;
  final LaidOutWords words;

  /// outline is the line laid out as an outline, where the type has one.
  /// Laid out here because a line's styled runs depend on the words before
  /// it, a fact of setting, not painting.
  final LaidOutWords? outline;

  /// soft is this line's shadow and glow, laid out on their own: drawn
  /// behind everything and never written on by the pen (see softFor).
  final LaidOutWords? soft;

  /// drop is how far below the line's top these words are drawn, so the
  /// runs either side of something in the way share one baseline.
  final double drop;

  const WrappedLine(this.from, this.to, this.box, this.words,
      {this.outline, this.soft, this.drop = 0});
}

class WrappedText {
  final List<WrappedLine> lines;

  /// consumed is how many characters were set: what a chained box passes
  /// on, and whether an overflow grip turns red.
  final int consumed;

  final double height;

  const WrappedText(this.lines, this.consumed, this.height);
}

/// WrapShape is one thing the words go around: a rectangle and, where the
/// element has one, its outline, so words can reach a circle's corners.
class WrapShape {
  /// bounds is the element's box spread by the gap: what the outline is
  /// tested against, and the whole answer where there is no outline.
  final Rect bounds;

  /// path is the element's own shape in document space, turned with it and
  /// not spread: the gap is added to the span it gives, so the shape is not
  /// distorted by an outset.
  final Path? path;

  /// silhouette is where a picture's ink is, with [drawn] the rectangle it
  /// is drawn into and [shown] the part of the picture in it, so text wraps
  /// a cut-out's ink rather than its box.
  final ImageSilhouette? silhouette;
  final Rect drawn;
  final Rect shown;
  final Size picture;

  final double gap;

  const WrapShape(
    this.bounds, {
    this.path,
    this.silhouette,
    this.drawn = Rect.zero,
    this.shown = Rect.zero,
    this.picture = Size.zero,
    this.gap = 0,
  });

  /// spanIn is the horizontal room this takes from a line between [top] and
  /// [bottom], or null for none. Asked per line, so a wrap is tight round a
  /// curve.
  (double, double)? spanIn(double top, double bottom) {
    if (bounds.bottom <= top || bounds.top >= bottom) return null;

    // A picture's ink, once read; the band widened by the gap as an
    // outline's is.
    if (silhouette case var ink?) {
      var span = ink.spanIn(drawn, shown, picture, top - gap, bottom + gap);
      if (span == null) return null;
      return (span.$1 - gap, span.$2 + gap);
    }

    var outline = path;
    if (outline == null) return (bounds.left, bounds.right);

    var band = Path()
      ..addRect(Rect.fromLTRB(
          bounds.left - 1, top - gap, bounds.right + 1, bottom + gap));
    var hit = Path.combine(PathOperation.intersect, outline, band);
    var box = hit.getBounds();
    if (box.width <= 0 || box.height <= 0) return null;
    return (box.left - gap, box.right + gap);
  }
}

/// wrapObstacles is what a text element sets its words around: everything
/// visible overlapping its box, less itself, the line it may ride,
/// backgrounds, and anything covering the whole box (a panel behind a
/// headline is a background). Rectangles are in document space, spread by
/// the gap. Nothing is left out for being tall (a picture beside a column
/// usually is); wrapFits catches what really covers the words.
///
/// [images] is where a picture's ink is read from; without it (a model
/// test, or before decoding) a picture is its box.
List<WrapShape> wrapObstacles(
    TextElement e, CanvasDocument? doc, int frame, Rect inner,
    {CanvasImageSource? images}) {
  if (doc == null || e.wordsSetIn(doc) != WordsSet.wrapped) return const [];

  var out = <WrapShape>[];
  for (var other in doc.elements) {
    if (other.id == e.id || !other.visible) continue;
    if (other.kind == ElementKind.background) continue;
    if (e.curve?.elementId == other.id) continue;
    // Never the boxes this one shares its words with: one paragraph in
    // several places, often overlapping while arranged; going round them
    // would squeeze the words out of sight.
    if (_sameChain(e, other, doc)) continue;

    var at = other.boundsAt(frame);
    var box = at.inflate(e.wrap.gap);
    if (!box.overlaps(inner)) continue;
    if (other is ImageElement) {
      out.add(_pictureShape(other, at, box, e.wrap.gap, images));
      continue;
    }
    out.add(WrapShape(box, path: _outlineOf(other, at), gap: e.wrap.gap));
  }
  return out;
}

/// _pictureShape is a picture as an obstacle: its ink once read, else its
/// box, always its box if turned (the profile is rows of the unturned
/// picture).
WrapShape _pictureShape(
    ImageElement e, Rect at, Rect box, double gap, CanvasImageSource? images) {
  var ink = images?.resolveOutline(e.assetId, e.removal);
  var image = images?.resolve(e.assetId, e.removal);
  if (ink == null || image == null || e.rotationRadians != 0) {
    return WrapShape(box, gap: gap);
  }

  // Where the picture is drawn in its element, and which part: a crop or a
  // cover fit means they differ.
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var placed = placeImage(size, at, e.fit, crop: e.crop, framing: e.framing);
  return WrapShape(box,
      silhouette: ink,
      drawn: placed.dst,
      shown: placed.src,
      picture: size,
      gap: gap);
}

/// _outlineOf is an element's own shape in document space, or null where
/// its shape is its box. Pictures are handled by _pictureShape.
Path? _outlineOf(CanvasElement e, Rect at) {
  if (e is! ShapeElement) return null;
  var path = shapePath(e.shape, at,
      points: e.points,
      cornerRadius: e.cornerRadius,
      corners: e.corners,
      bubble: e.bubble);
  if (e.rotationRadians == 0) return path;

  // Turned about its own centre, as it is drawn.
  var centre = at.center;
  var cos = math.cos(e.rotationRadians);
  var sin = math.sin(e.rotationRadians);
  return path.transform(Float64List.fromList([
    cos, sin, 0, 0, //
    -sin, cos, 0, 0, //
    0, 0, 1, 0, //
    centre.dx - cos * centre.dx + sin * centre.dy,
    centre.dy - sin * centre.dx - cos * centre.dy,
    0,
    1,
  ]));
}

/// _sameChain is whether [other] shares its words with [e], in either
/// direction. Walked here because text_flow imports this file.
bool _sameChain(TextElement e, CanvasElement other, CanvasDocument doc) {
  if (other is! TextElement) return false;

  bool reaches(TextElement from, String id) {
    var at = from;
    for (var guard = 0; guard < 64; guard++) {
      if (!at.flowsOnIn(doc)) return false;
      var next = doc.elementById(at.flowTo);
      if (next is! TextElement) return false;
      if (next.id == id) return true;
      at = next;
    }
    return false;
  }

  return reaches(e, other.id) || reaches(other, e.id);
}

/// freeRuns is the room left on a line between [top] and [bottom]: the
/// box's width less every obstacle in that band, overlaps merged.
List<(double, double)> freeRuns(Rect box, List<WrapShape> blocked, double top,
    double bottom, WrapSide side) {
  var holes = <(double, double)>[];
  for (var it in blocked) {
    var span = it.spanIn(top, bottom);
    if (span == null) continue;
    var from = math.max(box.left, span.$1);
    var to = math.min(box.right, span.$2);
    if (to > from) holes.add((from, to));
  }
  if (holes.isEmpty) return [(box.left, box.right)];

  holes.sort((a, b) => a.$1.compareTo(b.$1));
  var merged = <(double, double)>[holes.first];
  for (var hole in holes.skip(1)) {
    var last = merged.last;
    if (hole.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, math.max(last.$2, hole.$2));
    } else {
      merged.add(hole);
    }
  }

  var runs = <(double, double)>[];
  var at = box.left;
  for (var hole in merged) {
    if (hole.$1 > at) runs.add((at, hole.$1));
    at = math.max(at, hole.$2);
  }
  if (at < box.right) runs.add((at, box.right));

  // A run too narrow to hold anything is a sliver, not room.
  runs = [
    for (var run in runs)
      if (run.$2 - run.$1 > 4) run,
  ];
  if (runs.isEmpty || side == WrapSide.both) return runs;
  return [side == WrapSide.left ? runs.first : runs.last];
}

/// wordsSetRound is how [e]'s [text] is set in [inner] on this frame, once
/// what is in its way is known ([blocked], from wrapObstacles): wrapped only
/// while something is and there is room round it (wrapFits), else as with
/// nothing in the way. The painter and the flow ask it alike, so a chain
/// passes on what the box really drew.
WordsSet wordsSetRound(TextElement e, CanvasDocument? doc, String text,
    TextSpec spec, Rect inner, List<WrapShape> blocked,
    {required List<TextPart> parts}) {
  var set = e.wordsSetIn(doc);
  if (set != WordsSet.wrapped) return set;
  if (blocked.isNotEmpty &&
      wrapFits(text, spec, inner, blocked, e.wrap, parts: parts)) {
    return set;
  }
  return e.unwrappedSet;
}

/// wrapFits is whether wrapping round these obstacles leaves anywhere to
/// put the text. Where not, it is laid out the ordinary way and drawn over
/// the obstacle: visibly wrong rather than silently deleted.
bool wrapFits(String text, TextSpec spec, Rect box, List<WrapShape> blocked,
        TextWrap wrap, {required List<TextPart> parts}) =>
    text.trim().isEmpty ||
    layoutWrapped(text, spec, box, blocked, wrap, parts: parts)
        .lines
        .isNotEmpty;

/// layoutWrapped sets [text] inside [box] around [blocked], greedily a line
/// at a time with Flutter's line-breaking rule, so a box with nothing in
/// its way sets identically to one that never asked to wrap.
WrappedText layoutWrapped(
  String text,
  TextSpec spec,
  Rect box,
  List<WrapShape> blocked,
  TextWrap wrap, {
  required List<TextPart> parts,
  double scale = 1,

  /// outlineSpec is the type the outline is drawn in, or null for none (see
  /// outlineSpecFor).
  TextSpec? outlineSpec,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) {
    return const WrappedText([], 0, 0);
  }

  // The type's own line height: an empty line's, and the least a line with
  // words on it takes (see _setLine).
  var probe = layOutWords("Ag", spec,
      parts: const [], maxWidth: double.infinity, scale: scale);
  var lineHeight = math.max(1.0, probe.height);

  var lines = <WrappedLine>[];
  var at = 0;
  var y = box.top;
  _Before before = (words: 0, letters: 0);

  while (at < text.length && y + lineHeight <= box.bottom + 0.5) {
    // An empty line between paragraphs, taken here because the word fitting
    // below cannot advance past a break and would stall.
    if (text[at] == "\n") {
      at++;
      y += lineHeight;
      continue;
    }
    // The space a line broke on belongs to the line that broke.
    while (at < text.length && text[at] != "\n" && text[at].trim().isEmpty) {
      at++;
    }
    if (at >= text.length) break;

    var line = _setLine(text, at, before, spec, box, blocked, wrap.side, y,
        lineHeight, parts, scale);
    // Taller than the type (a part set bigger), the line is set again in the
    // band it really takes, as what is in the way may reach further lower
    // down.
    if (line.height > lineHeight + 0.5) {
      line = _setLine(text, at, before, spec, box, blocked, wrap.side, y,
          line.height, parts, scale);
    }
    if (line.placed.isEmpty) {
      // Not one word fits beside what is in the way here: the line is
      // skipped, which is how words get past a picture reaching the edge.
      y += lineHeight;
      continue;
    }
    // A line that would hang out of the bottom is not drawn, and its words
    // pass on, as in a box.
    if (y + line.height > box.bottom + 0.5) break;

    for (var p in line.placed) {
      var shown = text.substring(p.from, p.end).trimRight();
      lines.add(WrappedLine(
          p.from,
          p.end,
          Rect.fromLTWH(p.left, y, p.width, line.height),
          // A fade runs across the whole box, so the lines together show
          // one; measured without it, as it changes no glyph's place.
          spec.fade == null
              ? p.laid
              : _line(shown, spec, parts, before, scale, over: box),
          drop: line.baseline - _baselineOf(p.laid),
          outline: outlineSpec == null
              ? null
              : _line(shown, outlineSpec, parts, before, scale,
                  pass: WordsPass.outline),
          soft: !spec.softPasses
              ? null
              : _line(shown, spec, parts, before, scale,
                  pass: WordsPass.soft)));
      before = _past(before, text, p.from, p.end);
    }
    at = line.next;
    y += line.height;
  }

  return WrappedText(lines, at, lines.isEmpty ? 0 : y - box.top);
}

/// _Placed is one run of a wrapped line: where its room starts across and
/// how wide it is, its characters, and their paragraph.
typedef _Placed = ({
  double left,
  double width,
  int from,
  int end,
  LaidOutWords laid,
});

/// _SetLine is one line of a wrap before it is kept: its runs, where the
/// next line starts, how tall the line is and how far down it its runs'
/// baseline lies.
typedef _SetLine = ({
  List<_Placed> placed,
  int next,
  double height,
  double baseline,
});

/// _setLine fits the words from [at] into the room left between [top] and
/// [top] + [height]. The line is as tall as the tallest thing on it, and
/// never less than [height], as a paragraph's lines are.
_SetLine _setLine(
    String text,
    int at,
    _Before before,
    TextSpec spec,
    Rect box,
    List<WrapShape> blocked,
    WrapSide side,
    double top,
    double height,
    List<TextPart> parts,
    double scale) {
  var placed = <_Placed>[];
  for (var run in freeRuns(box, blocked, top, top + height, side)) {
    if (at >= text.length) break;
    var width = run.$2 - run.$1;
    // A word is broken only where it has the box's whole width, as a box
    // breaks only a word wider than its line.
    var (end, laid) = _fit(text, at, spec, width, parts, before, scale,
        breaks: width >= box.width - 0.5);
    // Not one word fits in this run; another may be wider.
    if (end <= at) continue;
    placed.add((left: run.$1, width: width, from: at, end: end, laid: laid));
    before = _past(before, text, at, end);
    at = end;

    // A hard break ends the line whatever room is left beside it.
    if (at < text.length && text[at] == "\n") {
      at++;
      break;
    }
  }

  var baseline = 0.0;
  for (var p in placed) {
    baseline = math.max(baseline, _baselineOf(p.laid));
  }
  var tall = height;
  for (var p in placed) {
    tall = math.max(tall, baseline - _baselineOf(p.laid) + p.laid.height);
  }
  return (placed: placed, next: at, height: tall, baseline: baseline);
}

/// _baselineOf is how far down a line laid out on its own its baseline is.
double _baselineOf(LaidOutWords line) =>
    line.lines.isEmpty ? 0 : line.lines.first.baseline;

/// _fit is the longest run of words from [at] that fits in [width], and its
/// paragraph. Word by word, not bisection: the answer is usually a few
/// words in, and measurements are cached. A first word wider than [width]
/// waits for a wider run, or with [breaks] is broken (_broken).
(int, LaidOutWords) _fit(String text, int at, TextSpec spec, double width,
    List<TextPart> parts, _Before before, double scale,
    {bool breaks = false}) {
  var end = at;
  var best = at;
  LaidOutWords? bestLine;

  while (end < text.length) {
    var next = end;
    // A word at a time, as parts count them (isWordSpace); a line break
    // ends the line.
    while (
        next < text.length && text[next] != "\n" && isWordSpace(text[next])) {
      next++;
    }
    if (next < text.length && text[next] == "\n") break;
    while (next < text.length && !isWordSpace(text[next])) {
      next++;
    }
    if (next == end) break;

    var candidate = text.substring(at, next).trimRight();
    var line = _line(candidate, spec, parts, before, scale);
    if (line.width > width + 0.5) {
      if (best > at || !breaks) break;
      return _broken(text, at, next, spec, width, parts, before, scale);
    }

    best = next;
    bestLine = line;
    end = next;
  }

  // Nothing fits: the run is narrower than the first word. The caller tries
  // the next run.
  if (bestLine == null) {
    return (at, _line("", spec, parts, before, scale));
  }
  return (best, bestLine);
}

/// _broken is as much of the word from [at] to [end] as fits in [width],
/// and at least its first letter: a word wider than the box broken across
/// lines, as a box breaks one wider than its line.
(int, LaidOutWords) _broken(String text, int at, int end, TextSpec spec,
    double width, List<TextPart> parts, _Before before, double scale) {
  var cut = at;
  LaidOutWords? kept;
  while (cut < end) {
    // A letter at a time, never between the halves of a surrogate pair.
    var next = cut + 1;
    if (next < end && (text.codeUnitAt(cut) & 0xFC00) == 0xD800) next++;
    var line = _line(text.substring(at, next), spec, parts, before, scale);
    if (kept != null && line.width > width + 0.5) break;
    cut = next;
    kept = line;
  }
  return (cut, kept!);
}

/// _Before is how far into the text a line starts, as parts count it: in
/// words and in letters.
typedef _Before = ({int words, int letters});

/// _past is [before] moved on past [text] from [from] to [end]. A word
/// broken at [end] is counted once it ends, on the line that ends it.
_Before _past(_Before before, String text, int from, int end) {
  var slice = text.substring(from, end);
  var words = wordsIn(slice);
  var broken = end < text.length &&
      end > from &&
      !isWordSpace(text[end]) &&
      !isWordSpace(text[end - 1]);
  return (
    words: before.words + words - (broken ? 1 : 0),
    letters: before.letters + lettersIn(slice)
  );
}

/// _line lays one line out, with whatever styled runs fall inside it.
LaidOutWords _line(String text, TextSpec spec, List<TextPart> parts,
        _Before before, double scale,
        {WordsPass pass = WordsPass.letters, Rect? over}) =>
    layOutWords(text, spec,
        parts: parts.isEmpty
            ? const []
            : partsFrom(parts, before.words, before.letters),
        maxWidth: double.infinity,
        scale: scale,
        pass: pass,
        over: over);

/// paintWrapped draws what layoutWrapped worked out.
///
/// [align] applies inside each run, so a centred paragraph beside a picture
/// centres in its room. [phase] is which half of the drawing this pass is
/// (see TextDrawPhase). [written] is how much of the pen's work is done,
/// line by line, and [fillAlpha] how far the letters have come up behind
/// it: both for Draw the outline, null in every other preset.
void paintWrapped(ui.Canvas canvas, WrappedText wrapped, TextSpec spec,
    {TextDrawPhase phase = TextDrawPhase.all,
    double? written,
    double? fillAlpha}) {
  /// half draws one of the two at its own opacity, through a layer if
  /// needed.
  void half(Rect room, double alpha, void Function() what) {
    if (alpha <= 0) return;
    if (alpha >= 1) {
      what();
      return;
    }
    canvas.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    what();
    canvas.restore();
  }

  for (var (i, line) in wrapped.lines.indexed) {
    var at = _lineAt(line, spec);
    var layerRoom = line.box.inflate(line.box.height);

    /// pen clips to how much of this line has been written.
    bool pen(double go) {
      if (go >= 1) return true;
      var share = (go * wrapped.lines.length - i).clamp(0.0, 1.0).toDouble();
      if (share <= 0) return false;
      canvas.clipRect(Rect.fromLTRB(
          layerRoom.left,
          layerRoom.top,
          at.dx + (line.words.width + line.box.height) * share,
          layerRoom.bottom));
      return true;
    }

    /// stroke draws as much of the outline as is written: each line
    /// uncovered left to right by a clip, as every line is its own paragraph.
    void stroke() {
      if (!phase.drawsOutline || line.outline == null) return;
      var go = written ?? 1;
      if (go <= 0) return;
      canvas.save();
      if (pen(go)) line.outline!.paint(canvas, at);
      canvas.restore();
    }

    // The outline goes behind the letters when it is simply the type's
    // outline, and on top while it is being drawn on.
    if (phase.drawsOutline) line.soft?.paint(canvas, at);
    if (written == null) stroke();
    if (phase.drawsLetters) {
      // The words stay put while the stroke is drawn on, unless told to
      // arrive with it (TextDrawStart).
      half(layerRoom, fillAlpha ?? 1, () => line.words.paint(canvas, at));
    }
    if (written != null) stroke();
  }
}

/// _lineAt is where [line] is drawn: [TextSpec.align] applies inside each
/// run, so a centred paragraph beside a picture centres in its room.
Offset _lineAt(WrappedLine line, TextSpec spec) {
  var room = line.box.width - line.words.width;
  var dx = switch (spec.align) {
    TextAlignSpec.left => 0.0,
    TextAlignSpec.justify => 0.0,
    TextAlignSpec.center => math.max(0.0, room / 2),
    TextAlignSpec.right => math.max(0.0, room),
  };
  return Offset(line.box.left + dx, line.box.top + line.drop);
}

/// paintWrappedMarks draws the highlights ([behind]) or underlines of
/// [parts] on what layoutWrapped set of [text], line by line: each line is
/// its own paragraph, its parts counted from its first word (partsFrom) and
/// [timings] kept beside them.
void paintWrappedMarks(ui.Canvas canvas, WrappedText wrapped, String text,
    TextSpec spec, List<TextPart> parts,
    {required bool behind, List<PartTiming> timings = const []}) {
  if (parts.isEmpty) return;
  for (var line in wrapped.lines) {
    var before = text.substring(0, line.from);
    var lineParts = <TextPart>[];
    var lineTimings = <PartTiming>[];
    for (var (i, part) in parts.indexed) {
      for (var moved in partsFrom([part], wordsIn(before), lettersIn(before))) {
        lineParts.add(moved);
        lineTimings.add(i < timings.length ? timings[i] : PartTiming.there);
      }
    }
    paintPartMarks(canvas, line.words, lineParts, spec, _lineAt(line, spec),
        behind: behind, timings: lineTimings);
  }
}
