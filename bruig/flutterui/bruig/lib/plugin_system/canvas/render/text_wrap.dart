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
  final TextPainter painter;

  /// outline is the line laid out as an outline, where the type has one.
  /// Laid out here because a line's styled runs depend on the words before
  /// it, a fact of setting, not painting.
  final TextPainter? outline;

  /// soft is this line's shadow and glow, laid out on their own: drawn
  /// behind everything and never written on by the pen (see softFor).
  final TextPainter? soft;

  const WrappedLine(this.from, this.to, this.box, this.painter,
      {this.outline, this.soft});
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
  if (doc == null || !e.wrap.on) return const [];

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
      if (at.flowTo.isEmpty) return false;
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

/// wrapFits is whether wrapping round these obstacles leaves anywhere to
/// put the text. Where not, it is laid out the ordinary way and drawn over
/// the obstacle: visibly wrong rather than silently deleted.
bool wrapFits(String text, TextSpec spec, Rect box, List<WrapShape> blocked,
        TextWrap wrap) =>
    text.trim().isEmpty ||
    layoutWrapped(text, spec, box, blocked, wrap).lines.isNotEmpty;

/// layoutWrapped sets [text] inside [box] around [blocked], greedily a line
/// at a time with Flutter's line-breaking rule, so a box with nothing in
/// its way sets identically to one that never asked to wrap.
WrappedText layoutWrapped(
  String text,
  TextSpec spec,
  Rect box,
  List<WrapShape> blocked,
  TextWrap wrap, {
  List<TextPart> parts = const [],
  double scale = 1,

  /// outlineSpec is the type the outline is drawn in, or null for none (see
  /// outlineSpecFor).
  TextSpec? outlineSpec,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) {
    return const WrappedText([], 0, 0);
  }

  // A line's height, measured once: every line shares it, the words on a
  // line sharing one baseline.
  var probe = layoutText("Ag", spec, maxWidth: double.infinity, scale: scale);
  var lineHeight = math.max(1.0, probe.height);

  var lines = <WrappedLine>[];
  var at = 0;
  var y = box.top;
  var words = 0;

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

    var runs = freeRuns(box, blocked, y, y + lineHeight, wrap.side);
    if (runs.isEmpty) {
      y += lineHeight;
      continue;
    }

    var placedOnLine = false;
    for (var run in runs) {
      if (at >= text.length) break;
      var width = run.$2 - run.$1;

      var (end, painter) = _fit(text, at, spec, width, parts, words, scale);
      if (end <= at) {
        // Not one word fits in this run. Another run may be wider; if none
        // is, the line is skipped, which is how words get past a picture
        // reaching the edge.
        continue;
      }

      lines.add(WrappedLine(
          at, end, Rect.fromLTWH(run.$1, y, width, lineHeight), painter,
          outline: outlineSpec == null
              ? null
              : _line(text.substring(at, end).trimRight(), outlineSpec, parts,
                  words, scale, outline: true),
          soft: !spec.softPasses
              ? null
              : _line(text.substring(at, end).trimRight(), spec, parts, words,
                  scale,
                  soft: true)));
      words += wordsIn(text.substring(at, end));
      at = end;
      placedOnLine = true;

      // A hard break ends the line whatever room is left beside it.
      if (at < text.length && text[at] == "\n") {
        at++;
        break;
      }
    }

    y += lineHeight;
    if (!placedOnLine &&
        runs.length == 1 &&
        runs.first.$2 - runs.first.$1 <= 4) {
      continue;
    }
  }

  return WrappedText(lines, at, lines.isEmpty ? 0 : y - box.top);
}

/// _fit is the longest run of words from [at] that fits in [width], and its
/// paragraph. Word by word, not bisection: the answer is usually a few
/// words in, and measurements are cached.
(int, TextPainter) _fit(String text, int at, TextSpec spec, double width,
    List<TextPart> parts, int wordsBefore, double scale) {
  var end = at;
  var best = at;
  TextPainter? bestPainter;

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
    var painter = _line(candidate, spec, parts, wordsBefore, scale);
    if (painter.width > width + 0.5 && best > at) break;

    best = next;
    bestPainter = painter;
    end = next;
    if (painter.width > width + 0.5) break;
  }

  // Nothing fits: the run is narrower than the first word. The caller tries
  // the next run.
  if (bestPainter == null) {
    return (at, _line("", spec, parts, wordsBefore, scale));
  }
  return (best, bestPainter);
}

/// _line lays one line out, with whatever styled runs fall inside it.
TextPainter _line(String text, TextSpec spec, List<TextPart> parts,
        int wordsBefore, double scale,
        {bool outline = false, bool soft = false}) =>
    layoutText(text, spec,
        maxWidth: double.infinity,
        scale: scale,
        outline: outline,
        soft: soft,
        parts: parts.isEmpty ? const [] : partsFrom(parts, wordsBefore));

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
          at.dx + (line.painter.width + line.box.height) * share,
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
      half(layerRoom, fillAlpha ?? 1, () => line.painter.paint(canvas, at));
    }
    if (written != null) stroke();
  }
}

/// _lineAt is where [line] is drawn: [TextSpec.align] applies inside each
/// run, so a centred paragraph beside a picture centres in its room.
Offset _lineAt(WrappedLine line, TextSpec spec) {
  var room = line.box.width - line.painter.width;
  var dx = switch (spec.align) {
    TextAlignSpec.left => 0.0,
    TextAlignSpec.justify => 0.0,
    TextAlignSpec.center => math.max(0.0, room / 2),
    TextAlignSpec.right => math.max(0.0, room),
  };
  return Offset(line.box.left + dx, line.box.top);
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
    var words = wordsIn(text.substring(0, line.from));
    var lineParts = <TextPart>[];
    var lineTimings = <PartTiming>[];
    for (var (i, part) in parts.indexed) {
      for (var moved in partsFrom([part], words)) {
        lineParts.add(moved);
        lineTimings.add(i < timings.length ? timings[i] : PartTiming.there);
      }
    }
    paintPartMarks(
        canvas,
        line.painter,
        text.substring(line.from, line.to).trimRight(),
        lineParts,
        spec,
        _lineAt(line, spec),
        behind: behind,
        timings: lineTimings);
  }
}
