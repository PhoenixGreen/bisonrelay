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
// A second way of setting type, and a switch rather than the default: a
// paragraph is normally laid out once by Flutter against a rectangle. Here
// the lines are worked out one at a time (what is in the way at this
// height, what room that leaves, how many words fit), one measurement per
// word, though the layout cache absorbs most of it. So this runs only for a
// text element that asks for it, and only while something overlaps.

/// WrappedLine is one line of wrapped text: which characters, where they go,
/// and the paragraph they were measured as.
class WrappedLine {
  final int from;
  final int to;
  final Rect box;
  final TextPainter painter;

  /// outline is the same line laid out as an outline, where the type has one.
  /// Laid out here because a line's styled runs depend on how many words came
  /// before it, a fact about the setting rather than the painting.
  final TextPainter? outline;

  /// soft is the shadow and the glow for this line, laid out on their own.
  /// Drawn behind everything else and never written on by the pen: what
  /// falls behind the words is there because the words are. See softFor.
  final TextPainter? soft;

  const WrappedLine(this.from, this.to, this.box, this.painter,
      {this.outline, this.soft});
}

/// WrappedText is a paragraph set around its obstacles.
class WrappedText {
  final List<WrappedLine> lines;

  /// consumed is how many characters were set, which is what tells a box in a
  /// chain what to pass on and an overflow grip whether to be red.
  final int consumed;

  final double height;

  const WrappedText(this.lines, this.consumed, this.height);
}

/// WrapShape is one thing the words have to go around: a rectangle and,
/// where the element has one, its own outline, so words can go into the
/// corners of a circle's box.
class WrapShape {
  /// bounds is the element's box, spread by the gap. What the outline is
  /// tested against, and the answer on its own where there is no outline.
  final Rect bounds;

  /// path is the element's own shape in document space, turned if the element
  /// is turned, and *not* spread -- the gap is added to the span it gives, so
  /// that a shape is not distorted by being outset.
  final Path? path;

  /// silhouette is where a picture's ink actually is, with [drawn] the
  /// rectangle it is drawn into and [shown] the part of the picture that is
  /// in it, so text wraps a cut-out's ink rather than its box.
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

  /// spanIn is the horizontal room this takes out of a line between [top] and
  /// [bottom], or null where it takes none. Asked per line, which is what
  /// makes a wrap tight round a curved shape.
  (double, double)? spanIn(double top, double bottom) {
    if (bounds.bottom <= top || bounds.top >= bottom) return null;

    // A picture's ink, where it has been read. The band is widened by the gap
    // the same way an outline's is.
    if (silhouette case var ink?) {
      var span = ink.spanIn(drawn, shown, picture, top - gap, bottom + gap);
      if (span == null) return null;
      return (span.$1 - gap, span.$2 + gap);
    }

    var outline = path;
    if (outline == null) return (bounds.left, bounds.right);

    // The band this line covers, given the room asked for above and below.
    var band = Path()
      ..addRect(Rect.fromLTRB(
          bounds.left - 1, top - gap, bounds.right + 1, bottom + gap));
    var hit = Path.combine(PathOperation.intersect, outline, band);
    var box = hit.getBounds();
    if (box.width <= 0 || box.height <= 0) return null;
    return (box.left - gap, box.right + gap);
  }
}

/// wrapObstacles is what a text element has to set its words around.
///
/// Everything visible that overlaps its box, less the element itself, the
/// line it may be riding, backgrounds, and anything covering the whole box
/// (a panel behind a headline is a background). The rectangles come back in
/// document space, already spread by the element's gap.
///
/// Nothing is left out for being tall: a picture beside a column is usually
/// taller than it. A thing that really covers the words is caught by
/// wrapFits instead.
///
/// [images] is where a picture's ink is read from; without one (a model
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
    // Never the boxes this one shares its words with: they are one paragraph
    // in several places, often overlapping while a chain is arranged, and
    // going around them would squeeze the words out of sight.
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

/// _pictureShape is a picture as something to go around: its ink where that
/// has been read, and its box until then, or for good if it is turned (the
/// profile is rows of the unturned picture).
WrapShape _pictureShape(
    ImageElement e, Rect at, Rect box, double gap, CanvasImageSource? images) {
  var ink = images?.resolveOutline(e.assetId, e.removal);
  var image = images?.resolve(e.assetId, e.removal);
  if (ink == null || image == null || e.rotationRadians != 0) {
    return WrapShape(box, gap: gap);
  }

  // Where the picture is drawn inside its element, and which part of it that
  // is: a crop and a cover fit both mean the two are not the same picture.
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var placed = placeImage(size, at, e.fit, crop: e.crop, framing: e.framing);
  return WrapShape(box,
      silhouette: ink,
      drawn: placed.dst,
      shown: placed.src,
      picture: size,
      gap: gap);
}

/// _outlineOf is an element's own shape in document space, or null for the
/// ones whose shape is their box. A shape element knows its outline exactly
/// (see shapePath); pictures are handled by _pictureShape.
Path? _outlineOf(CanvasElement e, Rect at) {
  if (e is! ShapeElement) return null;
  var path = shapePath(e.shape, at,
      points: e.points,
      cornerRadius: e.cornerRadius,
      corners: e.corners,
      bubble: e.bubble);
  if (e.rotationRadians == 0) return path;

  // Turned about its own centre, the way it is drawn: one rotation about one
  // point, written out.
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

/// _sameChain is whether [other] is one of the boxes [e] shares its words
/// with, in either direction. Walked here because text_flow imports this
/// file.
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

/// freeRuns is the room left on a line between [top] and [bottom]: the box's
/// width less every obstacle reaching into that band, overlapping obstacles
/// merged into one hole.
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

  // A run too narrow to hold anything is not room, it is a sliver.
  runs = [
    for (var run in runs)
      if (run.$2 - run.$1 > 4) run,
  ];
  if (runs.isEmpty || side == WrapSide.both) return runs;
  return [side == WrapSide.left ? runs.first : runs.last];
}

/// wrapFits is whether wrapping this text round these obstacles leaves
/// anywhere to put it. Where it does not, the words are laid out the
/// ordinary way and drawn over what is in the way: visibly wrong rather than
/// silently deleted.
bool wrapFits(String text, TextSpec spec, Rect box, List<WrapShape> blocked,
        TextWrap wrap) =>
    text.trim().isEmpty ||
    layoutWrapped(text, spec, box, blocked, wrap).lines.isNotEmpty;

/// layoutWrapped sets [text] inside [box], going around [blocked]. Greedy, a
/// line at a time: words are added while they fit, the same rule Flutter's
/// line breaker uses, so a box with nothing in its way sets identically to
/// one that never asked to wrap.
WrappedText layoutWrapped(
  String text,
  TextSpec spec,
  Rect box,
  List<WrapShape> blocked,
  TextWrap wrap, {
  List<TextPart> parts = const [],
  double scale = 1,

  /// outlineSpec is the type the outline is drawn in, or null where there is
  /// none to draw. See outlineSpecFor, which is what decides it -- the type's
  /// own outline, a part's, or the one Draw the outline invents.
  TextSpec? outlineSpec,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) {
    return const WrappedText([], 0, 0);
  }

  // The height of a line of this type, measured once: every line is the same
  // height, the words on a line sharing one baseline.
  var probe = layoutText("Ag", spec, maxWidth: double.infinity, scale: scale);
  var lineHeight = math.max(1.0, probe.height);

  var lines = <WrappedLine>[];
  var at = 0;
  var y = box.top;
  var words = 0;

  while (at < text.length && y + lineHeight <= box.bottom + 0.5) {
    // A line of its own with nothing on it: the gap between two paragraphs.
    // Taken here, because the word-fitting below cannot advance past a break
    // and would stall on it.
    if (text[at] == "\n") {
      at++;
      y += lineHeight;
      continue;
    }
    // The space a line broke on belongs to the line that broke, not to this
    // one.
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
        // Not even one word fits in this run. Another run on the same line
        // may be wider; if none is, the line is skipped and the next one
        // tried, which is how words get past a picture that reaches the edge.
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

/// _fit is the longest run of words from [at] that fits in [width], and the
/// paragraph it was measured as. Word by word rather than by bisection: the
/// answer is usually a handful of words in, and measurements are cached.
(int, TextPainter) _fit(String text, int at, TextSpec spec, double width,
    List<TextPart> parts, int wordsBefore, double scale) {
  var end = at;
  var best = at;
  TextPainter? bestPainter;

  while (end < text.length) {
    // The next word, and the spaces before it.
    var next = end;
    while (
        next < text.length && text[next] != "\n" && text[next].trim().isEmpty) {
      next++;
    }
    if (next < text.length && text[next] == "\n") break;
    while (next < text.length &&
        text[next].trim().isNotEmpty &&
        text[next] != "\n") {
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

  // Nothing fits and nothing was measured: the run is narrower than the first
  // word. The caller tries the next run.
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
/// [align] is the element's own, applied inside each run, so a centred
/// paragraph beside a picture is centred in the room it has. [phase] is
/// which half of the drawing this pass is for (see TextDrawPhase). [written]
/// is how much of the pen's work is done, line by line and left to right,
/// and [fillAlpha] how far the letters have come up behind it: together,
/// Draw the outline. The pen writes the outline where the type has one and
/// the words where it has not. Null for both in every other preset.
void paintWrapped(ui.Canvas canvas, WrappedText wrapped, TextSpec spec,
    {TextDrawPhase phase = TextDrawPhase.all,
    double? written,
    double? fillAlpha}) {
  /// half draws one of the two at its own opacity, through a layer where it
  /// needs one.
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
    var room = line.box.width - line.painter.width;
    var dx = switch (spec.align) {
      TextAlignSpec.left => 0.0,
      TextAlignSpec.justify => 0.0,
      TextAlignSpec.center => math.max(0.0, room / 2),
      TextAlignSpec.right => math.max(0.0, room),
    };
    var at = Offset(line.box.left + dx, line.box.top);
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

    /// stroke draws the outline, or as much of it as has been written: each
    /// line uncovered left to right in its share of the time, by a clip,
    /// since every line is its own paragraph.
    void stroke() {
      if (!phase.drawsOutline || line.outline == null) return;
      var go = written ?? 1;
      if (go <= 0) return;
      canvas.save();
      if (pen(go)) line.outline!.paint(canvas, at);
      canvas.restore();
    }

    // Behind the letters when it is simply the type's outline (a centred
    // stroke with the fill over it, see layoutText), and on top while it is
    // being drawn on, since that is what is being watched.
    if (phase.drawsOutline) line.soft?.paint(canvas, at);
    if (written == null) stroke();
    if (phase.drawsLetters) {
      // The words stay where they are while the stroke is drawn onto them,
      // unless they have been told to arrive with it. See TextDrawStart.
      half(layerRoom, fillAlpha ?? 1, () => line.painter.paint(canvas, at));
    }
    if (written != null) stroke();
  }
}
