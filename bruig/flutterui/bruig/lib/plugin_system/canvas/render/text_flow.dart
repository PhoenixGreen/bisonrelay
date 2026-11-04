import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:flutter/painting.dart';

// text_flow.dart runs one piece of text through a line of boxes.
//
// The words belong to the head of the chain; every box after it draws what
// would not fit in the one before. Worked out at drawing time rather than
// stored, because where the words break depends on the box's size, type,
// columns and padding, all of which change during a drag.

/// TextFlow is one box's share of a chain.
class TextFlow {
  /// text is what this box draws -- the whole of it for a box on its own.
  final String text;

  /// overflows is whether there are words this box could not show: what
  /// turns the overflow grip red, worked out even for a box with nothing
  /// after it, so hidden text is never silent.
  final bool overflows;

  /// receiving is whether these words came from another box.
  final bool receiving;

  /// head is the element the words belong to, which is this one for a box at
  /// the start of a chain or on its own.
  final String head;

  /// parts are the styled runs that apply to the words this box draws,
  /// counted from its own first word: the head's, moved, so later boxes keep
  /// the document's headings and bold.
  final List<TextPart> parts;

  /// tidyStart is whether a blank line at the top of this box, or of one of
  /// its columns, is passed over. The head's answer, for every box in the
  /// chain, so all its columns are tidied alike.
  final bool tidyStart;

  const TextFlow({
    required this.text,
    this.overflows = false,
    this.receiving = false,
    this.head = "",
    this.tidyStart = false,
    this.parts = const [],
  });
}

/// flowFor is what [e] actually draws. [inner] is the room the words have
/// (the box less its padding and any icon) and [spec] the type; both are the
/// *drawn* values, so the chain and the painter agree where words break.
TextFlow flowFor(TextElement e, CanvasDocument? doc, Rect inner, TextSpec spec,
    {int frame = 0, CanvasImageSource? images}) {
  var mine = e.displayText;
  var blocked = wrapObstacles(e, doc, frame, inner, images: images);

  // A box on its own: everything it has, and whether all of it is showing.
  if (doc == null || (e.flowTo.isEmpty && !_isTarget(e, doc))) {
    return TextFlow(
      text: mine,
      overflows: _consumed(mine, e, inner, spec, tidy: e.columns.noBlankStart) <
          mine.length,
      head: e.id,
      tidyStart: e.columns.noBlankStart,
      parts: e.documentParts,
    );
  }

  var chain = _chainTo(e, doc);
  var head = chain.first;
  var text = head.displayText;

  // Walk the chain from the head, each box taking what fits and passing the
  // rest on; the boxes differ in width and type, so each is laid out in turn.
  // How the words are broken is the head's business for every box.
  var tidy = head.columns.noBlankStart;

  var at = 0;
  for (var box in chain) {
    if (box.id == e.id) break;
    if (at >= text.length) break;
    // A blank line the box before it broke on belongs to neither of them.
    if (tidy && box.id != head.id) at += _blankRun(text.substring(at));
    if (at >= text.length) break;
    var room = _roomOf(box);
    at += _consumed(text.substring(at), box, room, _specOf(box),
        tidy: tidy,
        blocked: wrapObstacles(box, doc, frame, room, images: images));
  }

  var receiving = !identical(head, e) && head.id != e.id;
  if (tidy && receiving && at < text.length) {
    at += _blankRun(text.substring(at));
  }

  var rest = at >= text.length ? "" : text.substring(at);
  var took = _consumed(rest, e, inner, spec, tidy: tidy, blocked: blocked);
  return TextFlow(
    text: rest,
    overflows: took < rest.length,
    receiving: receiving,
    head: head.id,
    tidyStart: tidy,
    // The head's styled runs, counted from this box's own first word.
    parts: receiving
        ? partsFrom(head.documentParts, wordsIn(text.substring(0, at)))
        : head.documentParts,
  );
}

/// wouldLoop is whether pointing [from] at [to] would make a ring of boxes,
/// which has no first box to start reading from. Refused rather than
/// resolved.
bool wouldLoop(TextElement from, String to, CanvasDocument doc) {
  if (to == from.id) return true;
  var seen = <String>{from.id};
  var next = doc.elementById(to);
  while (next is TextElement) {
    if (!seen.add(next.id)) return true;
    if (next.flowTo.isEmpty) return false;
    if (next.flowTo == from.id) return true;
    next = doc.elementById(next.flowTo);
  }
  return false;
}

/// flowSourceOf is the element whose words land in [e], if any.
TextElement? flowSourceOf(TextElement e, CanvasDocument? doc) {
  if (doc == null) return null;
  for (var other in doc.elements) {
    if (other is TextElement && other.flowTo == e.id) return other;
  }
  return null;
}

/// _isTarget is whether anything flows into this box.
bool _isTarget(TextElement e, CanvasDocument doc) =>
    flowSourceOf(e, doc) != null;

/// _chainTo is every box from the head of the chain up to and including [e].
List<TextElement> _chainTo(TextElement e, CanvasDocument doc) {
  // Back to the head first. The guard is needed: a document with a ring
  // (from an older build, or edited by hand) would otherwise hang the painter.
  var head = e;
  var seen = <String>{e.id};
  while (true) {
    var before = flowSourceOf(head, doc);
    if (before == null || !seen.add(before.id)) break;
    head = before;
  }

  var chain = <TextElement>[head];
  var at = head;
  while (at.flowTo.isNotEmpty && at.id != e.id) {
    var next = doc.elementById(at.flowTo);
    if (next is! TextElement) break;
    if (chain.any((b) => b.id == next.id)) break;
    chain.add(next);
    at = next;
  }
  return chain;
}

/// _roomOf is where a box's words go: its bounds, less its padding.
Rect _roomOf(TextElement e) => e.box.inner(e.bounds);

/// _specOf is the type a box draws in: its own, not the fitted one, since
/// Fit to box sizes type so everything fits, the opposite of passing the
/// overflow on.
TextSpec _specOf(TextElement e) => e.textSpec;

/// _blankRun is how many characters of empty lines [text] opens with: what a
/// box that must not start on a blank line skips, so its words do not sit
/// lower than the box beside it.
int _blankRun(String text) {
  var at = 0;
  while (at < text.length) {
    var end = text.indexOf("\n", at);
    if (end < 0) break;
    if (text.substring(at, end).trim().isNotEmpty) break;
    at = end + 1;
  }
  return at;
}

/// _consumed is how many characters of [text] this box can show.
int _consumed(String text, TextElement e, Rect inner, TextSpec spec,
    {bool tidy = false, List<WrapShape> blocked = const []}) {
  if (text.isEmpty || inner.width <= 0 || inner.height <= 0) return 0;

  // Wrapped, the room a box has is what is left once the things in the way
  // are taken out. Measured as it is drawn (see layoutWrapped), so the grip
  // and the canvas agree.
  if (e.wrap.on &&
      blocked.isNotEmpty &&
      wrapFits(text, spec, inner, blocked, e.wrap)) {
    return layoutWrapped(text, spec, inner, blocked, e.wrap).consumed;
  }

  var width =
      e.columns.isSingle ? inner.width : e.columns.columnWidth(inner.width);
  if (width <= 0) return 0;

  var painter = layoutText(text, spec, maxWidth: width, fillWidth: true);
  var metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return 0;

  // How many lines fit: the same packing the columns use, so a box with three
  // columns passes on what would not fit in the third rather than what would
  // not fit in one.
  var runs = columnRuns(metrics, inner.height, math.max(1, e.columns.count),
      noBlankStart: tidy);
  var lines = runs.isEmpty ? 0 : runs.last.$2;
  if (lines >= metrics.length) return text.length;
  if (lines <= 0) return 0;

  // The character the last line drawn ends at. Asked of the paragraph rather
  // than counted, because where a line breaks is the paragraph's business.
  var last = metrics[lines - 1];
  var end = painter
      .getPositionForOffset(ui.Offset(width + 1000, last.baseline))
      .offset;
  if (end <= 0) return 0;

  // Whitespace at the break belongs to the line that broke, or the next box
  // starts with a crooked first line.
  while (end < text.length && text[end].trim().isEmpty && text[end] != "\n") {
    end++;
  }
  if (end < text.length && text[end] == "\n") end++;
  return math.min(end, text.length);
}
