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
// The words belong to the head of the chain. Every box after it draws the part
// that would not fit in the one before, so making a box smaller pushes words
// down the line and making it bigger pulls them back -- which is what a chain
// of boxes is for.
//
// Worked out at drawing time rather than stored, and deliberately: where the
// words break depends on the box's width, its height, its type, its columns
// and its padding, all of which change while somebody is dragging a handle.
// A stored answer would be wrong for the whole of that drag.

/// TextFlow is one box's share of a chain.
class TextFlow {
  /// text is what this box draws -- the whole of it for a box on its own.
  final String text;

  /// overflows is whether there are words this box could not show.
  ///
  /// What turns the overflow grip red, and the reason it is worth computing
  /// even for a box with nothing after it: hidden text with no sign that it
  /// is hidden is the thing people lose work to.
  final bool overflows;

  /// receiving is whether these words came from another box.
  final bool receiving;

  /// head is the element the words belong to, which is this one for a box at
  /// the start of a chain or on its own.
  final String head;

  /// parts are the styled runs that apply to the words this box draws,
  /// counted from its own first word.
  ///
  /// The head's, moved: a document's markdown belongs to the whole text, and
  /// the second box in a chain is drawing that text further along. Without
  /// this a chain showed the headings and the bold of the first box only, and
  /// the rest arrived as plain words.
  final List<TextPart> parts;

  /// tidyStart is whether a blank line at the top of this box -- or of one of
  /// its columns -- is passed over.
  ///
  /// The head of the chain's answer, for every box in it. The words are one
  /// paragraph flowing through several boxes, and how it is broken is a fact
  /// about the words rather than about each box it lands in: two boxes that
  /// disagreed would tidy the top of one column and not the next.
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

/// flowFor is what [e] actually draws.
///
/// [inner] is the room the words have -- the element's box less its padding
/// and whatever an icon has taken -- and [spec] the type they are drawn in.
/// Both are the *drawn* values, so a box in a chain and the painter agree
/// about where the words break.
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
  // rest on. The boxes are different widths and different types, so there is
  // nothing to do but lay each one out in turn.
  // How the words are broken is the head's business, for every box the chain
  // passes through.
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

/// wouldLoop is whether pointing [from] at [to] would make a ring of boxes.
///
/// A ring has no first box, so there is nowhere to start reading and no way
/// to say what any box in it should show. Refused rather than resolved.
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
  // Back to the head first. The guard is not paranoia: a document written by
  // a build that allowed a ring, or edited by hand, would otherwise hang the
  // painter rather than draw something wrong.
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

/// _roomOf is where a box's words go: its bounds, less its padding and
/// whatever its icon has taken.
Rect _roomOf(TextElement e) {
  var inner = e.box.inner(e.bounds);
  return iconRoom(inner, e.icon).$2;
}

/// _specOf is the type a box draws in.
///
/// Its own, and not the fitted one: Fit to box sizes the type so that
/// everything fits, which is the opposite of what a box that passes its
/// overflow on is for.
TextSpec _specOf(TextElement e) => e.textSpec;

/// _blankRun is how many characters of empty lines [text] opens with.
///
/// What a box that must not start on a blank line skips: the gap between two
/// paragraphs is a line like any other, and a box that begins with one begins
/// with an empty row and its words sitting lower than the box beside it.
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

  // Wrapped, the room a box has is not its rectangle: it is what is left of
  // it once the things in the way are taken out. Measured the same way it is
  // drawn -- see layoutWrapped -- so what the grip says and what is on the
  // canvas cannot disagree.
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

  // Whitespace at the break belongs to the line that broke, not to the one
  // that starts after it -- a box beginning with a space is a box with a
  // crooked first line.
  while (end < text.length && text[end].trim().isEmpty && text[end] != "\n") {
    end++;
  }
  if (end < text.length && text[end] == "\n") end++;
  return math.min(end, text.length);
}
