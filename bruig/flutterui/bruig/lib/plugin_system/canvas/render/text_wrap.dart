import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// text_wrap.dart sets words around the things in their way.
//
// It is a second way of setting type, and that is why it is a switch rather
// than the way everything works. A paragraph is normally laid out once by
// Flutter, which breaks lines against a rectangle -- fast, correctly shaped,
// and unable to know that there is a photograph in the middle of it. Here the
// lines are worked out one at a time: what is in the way at this height, what
// room that leaves, and how many words fit in it.
//
// The cost is real (one measurement per word rather than one per paragraph,
// though the layout cache absorbs most of it), so this runs only for a text
// element that has asked for it and only while something actually overlaps.

/// WrappedLine is one line of wrapped text: which characters, where they go,
/// and the paragraph they were measured as.
class WrappedLine {
  final int from;
  final int to;
  final Rect box;
  final TextPainter painter;
  const WrappedLine(this.from, this.to, this.box, this.painter);
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

/// wrapObstacles is what a text element has to set its words around.
///
/// Everything visible that overlaps its box, less a few things that would
/// make nonsense of it: the element itself, the line it may be riding, and
/// anything that covers the whole box -- a panel behind a headline is a
/// background, and a paragraph cannot go round it. Backgrounds proper are
/// left out for the same reason.
///
/// The rectangles come back in document space, already spread by the gap the
/// element asked for.
List<Rect> wrapObstacles(
    TextElement e, CanvasDocument? doc, int frame, Rect inner) {
  if (doc == null || !e.wrap.on) return const [];

  var out = <Rect>[];
  for (var other in doc.elements) {
    if (other.id == e.id || !other.visible) continue;
    if (other.kind == ElementKind.background) continue;
    if (e.curve?.elementId == other.id) continue;
    // Never the boxes this one shares its words with. They are one paragraph
    // in several places, they are routinely laid over each other while a
    // chain is being arranged, and treating the box the words come *from* as
    // something to go around squeezed them into whatever strip was left --
    // which read as the wrapping having deleted them.
    if (_sameChain(e, other, doc)) continue;

    var box = other.boundsAt(frame).inflate(e.wrap.gap);
    if (!box.overlaps(inner)) continue;
    // A thing that covers the words entirely is not something to go around.
    if (box.top <= inner.top && box.bottom >= inner.bottom) continue;
    out.add(box);
  }
  return out;
}

/// _sameChain is whether [other] is one of the boxes [e] shares its words
/// with, in either direction.
///
/// Walked rather than asked of text_flow, which is the other side of this
/// question and imports this file to answer it.
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

/// freeRuns is the room left on a line between [top] and [bottom].
///
/// The box's own width less every obstacle that reaches into that band,
/// merged so two overlapping pictures are one hole rather than two.
List<(double, double)> freeRuns(
    Rect box, List<Rect> blocked, double top, double bottom, WrapSide side) {
  var holes = <(double, double)>[];
  for (var it in blocked) {
    if (it.bottom <= top || it.top >= bottom) continue;
    var from = math.max(box.left, it.left);
    var to = math.min(box.right, it.right);
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
/// anywhere to put it.
///
/// Something covering the box from side to side leaves no room on any line,
/// and a paragraph set into no room is a paragraph nobody can see. Where that
/// happens the words are laid out the ordinary way and drawn over whatever is
/// in the way: that is wrong, and it is visibly wrong, which is what somebody
/// can act on. Silently deleting a page of text is neither.
bool wrapFits(String text, TextSpec spec, Rect box, List<Rect> blocked,
        TextWrap wrap) =>
    text.trim().isEmpty ||
    layoutWrapped(text, spec, box, blocked, wrap).lines.isNotEmpty;

/// layoutWrapped sets [text] inside [box], going around [blocked].
///
/// Greedy, a line at a time, which is what makes it able to answer the
/// question a paragraph layout cannot: the room on *this* line. Words are
/// added while they fit and the line ends when the next one does not -- the
/// same rule Flutter's own line breaker uses, so a box with nothing in its
/// way sets identically to one that never asked to wrap.
WrappedText layoutWrapped(
  String text,
  TextSpec spec,
  Rect box,
  List<Rect> blocked,
  TextWrap wrap, {
  List<TextPart> parts = const [],
  double scale = 1,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) {
    return const WrappedText([], 0, 0);
  }

  // The height of a line of this type, measured once. Every line is the same
  // height: the words on a line have to sit on one baseline, and a wrapped
  // paragraph is not the place to discover otherwise.
  var probe = layoutText("Ag", spec, maxWidth: double.infinity, scale: scale);
  var lineHeight = math.max(1.0, probe.height);

  var lines = <WrappedLine>[];
  var at = 0;
  var y = box.top;
  var words = 0;

  while (at < text.length && y + lineHeight <= box.bottom + 0.5) {
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
          at, end, Rect.fromLTWH(run.$1, y, width, lineHeight), painter));
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
/// paragraph it was measured as.
///
/// Word by word rather than by bisection: the answer is usually a handful of
/// words in, the measurements are cached, and a bisection would have to lay
/// out a candidate that is mostly wrong to find out that it is.
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
        int wordsBefore, double scale) =>
    layoutText(text, spec,
        maxWidth: double.infinity,
        scale: scale,
        parts: parts.isEmpty ? const [] : partsFrom(parts, wordsBefore));

/// paintWrapped draws what layoutWrapped worked out.
///
/// [align] is the element's own, applied inside each run: a centred paragraph
/// beside a picture is centred in the room it actually has, which is the only
/// reading of "centred" that means anything here.
void paintWrapped(ui.Canvas canvas, WrappedText wrapped, TextSpec spec) {
  for (var line in wrapped.lines) {
    var room = line.box.width - line.painter.width;
    var dx = switch (spec.align) {
      TextAlignSpec.left => 0.0,
      TextAlignSpec.justify => 0.0,
      TextAlignSpec.center => math.max(0.0, room / 2),
      TextAlignSpec.right => math.max(0.0, room),
    };
    line.painter.paint(canvas, Offset(line.box.left + dx, line.box.top));
  }
}
