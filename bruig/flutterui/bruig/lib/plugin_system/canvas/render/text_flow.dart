import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:flutter/painting.dart';

// text_flow.dart runs one piece of text through a line of boxes. The words
// belong to the head of the chain; each later box draws what would not fit
// in the one before. Worked out when drawn rather than stored, since where
// words break depends on size, type, columns and padding, which change
// during a drag.

/// TextFlow is one box's share of a chain.
class TextFlow {
  /// text is what this box draws: all of it for a box on its own.
  final String text;

  /// overflows is whether there are words this box could not show: what
  /// turns the overflow grip red, worked out even for a box with nothing
  /// after it, so hidden text is never silent.
  final bool overflows;

  final bool receiving;

  /// head is the element the words belong to: this one at the start of a
  /// chain or on its own.
  final String head;

  /// parts are the styled runs that apply to the words this box draws,
  /// counted from its own first word: the head's, moved, so later boxes keep
  /// the document's headings and bold.
  final List<TextPart> parts;

  /// tidyStart is whether a blank line at the top of this box, or of one of
  /// its columns, is passed over. The head's answer, for every box in the
  /// chain, so all its columns are tidied alike.
  final bool tidyStart;

  /// blocked is what the words go round in this box (wrapObstacles), as
  /// worked out for the flow, so the painter need not work it out again.
  final List<WrapShape> blocked;

  const TextFlow({
    this.blocked = const [],
    required this.text,
    this.overflows = false,
    this.receiving = false,
    this.head = "",
    this.tidyStart = false,
    this.parts = const [],
  });
}

/// flowFor is what [e] actually draws. [inner] is the room the words have
/// (the box less its padding) and [spec] the type; both are the
/// *drawn* values, so the chain and the painter agree where words break.
TextFlow flowFor(TextElement e, CanvasDocument? doc, Rect inner, TextSpec spec,
    {int frame = 0, CanvasImageSource? images}) {
  var mine = e.displayText;
  var blocked = wrapObstacles(e, doc, frame, inner, images: images);

  // A box on its own: everything it has, and whether all of it is showing.
  if (doc == null || (!e.flowsOnIn(doc) && !_isTarget(e, doc))) {
    return TextFlow(
      text: mine,
      overflows: _consumed(mine, e, doc, inner, spec,
              tidy: e.columns.noBlankStart,
              parts: e.drawnPartsWith(e.documentParts)) <
          mine.length,
      head: e.id,
      tidyStart: e.columns.noBlankStart,
      parts: e.documentParts,
      blocked: blocked,
    );
  }

  var chain = _chainTo(e, doc);
  var head = chain.first;
  var text = head.displayText;

  // Walk the chain from the head, each box taking what fits and passing on
  // the rest; boxes differ in width and type, so each is laid out in turn.
  // How words break is the head's business for every box.
  var tidy = head.columns.noBlankStart;

  var at = 0;
  for (var box in chain) {
    if (box.id == e.id) break;
    if (at >= text.length) break;
    // A blank line the box before it broke on belongs to neither of them.
    if (tidy && box.id != head.id) at += _blankRun(text.substring(at));
    if (at >= text.length) break;
    var room = _roomOf(box);
    at += _consumed(text.substring(at), box, doc, room, _specOf(box),
        tidy: tidy,
        blocked: wrapObstacles(box, doc, frame, room, images: images),
        parts: box.drawnPartsWith(_partsAt(head, text, at)));
  }

  var receiving = !identical(head, e) && head.id != e.id;
  if (tidy && receiving && at < text.length) {
    at += _blankRun(text.substring(at));
  }

  var rest = at >= text.length ? "" : text.substring(at);
  // The head's styled runs, counted from this box's own first word.
  var parts = receiving ? _partsAt(head, text, at) : head.documentParts;
  var took = _consumed(rest, e, doc, inner, spec,
      tidy: tidy, blocked: blocked, parts: e.drawnPartsWith(parts));
  return TextFlow(
    text: rest,
    overflows: took < rest.length,
    receiving: receiving,
    head: head.id,
    tidyStart: tidy,
    blocked: blocked,
    parts: parts,
  );
}

/// wouldLoop is whether pointing [from] at [to] would make a ring of boxes,
/// which has no first box to read from. Refused rather than resolved.
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

/// flowSourceOf is the element whose words land in [e], if any: one that
/// flows on into it (TextElement.flowsOnIn).
TextElement? flowSourceOf(TextElement e, CanvasDocument? doc) {
  if (doc == null) return null;
  var list = doc.elements;
  var sources = _sources[list] ??= () {
    var out = <String, TextElement>{};
    for (var other in list) {
      if (other is TextElement && other.flowsOnIn(doc)) {
        out.putIfAbsent(other.flowTo, () => other);
      }
    }
    return out;
  }();
  return sources[e.id];
}

/// _sources is, per list of elements, each text box by the box its words
/// go on to. Every text box drawn asks whether it is a target, and walking
/// the elements for each made a page of text boxes cost the square of
/// their number. Lists of elements are replaced, never changed, so one per
/// list holds (as elementById's index does).
final _sources = Expando<Map<String, TextElement>>("flowSources");

bool _isTarget(TextElement e, CanvasDocument doc) =>
    flowSourceOf(e, doc) != null;

/// _chainTo is every box from the head of the chain up to and including [e].
List<TextElement> _chainTo(TextElement e, CanvasDocument doc) {
  // Back to the head first, guarded: a document with a ring (edited by
  // hand, say) must not hang the painter.
  var head = e;
  var seen = <String>{e.id};
  while (true) {
    var before = flowSourceOf(head, doc);
    if (before == null || !seen.add(before.id)) break;
    head = before;
  }

  var chain = <TextElement>[head];
  var at = head;
  while (at.flowsOnIn(doc) && at.id != e.id) {
    var next = doc.elementById(at.flowTo);
    if (next is! TextElement) break;
    if (chain.any((b) => b.id == next.id)) break;
    chain.add(next);
    at = next;
  }
  return chain;
}

/// _partsAt is [head]'s styled runs for the words from character [at] of
/// [text] on, counted from the first of them.
List<TextPart> _partsAt(TextElement head, String text, int at) {
  if (at <= 0) return head.documentParts;
  var before = text.substring(0, at);
  return partsFrom(head.documentParts, wordsIn(before), lettersIn(before));
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

/// _consumed is how many characters of [text] this box can show on a page of
/// [doc], laid out with the [parts] it is drawn with, since a part may
/// change the size.
int _consumed(
    String text, TextElement e, CanvasDocument? doc, Rect inner, TextSpec spec,
    {bool tidy = false,
    List<WrapShape> blocked = const [],
    required List<TextPart> parts}) {
  if (text.isEmpty) return 0;
  double width;
  switch (wordsSetRound(e, doc, text, spec, inner, blocked, parts: parts)) {
    // A line draws every word it has, however long.
    case WordsSet.onLine:
      return text.length;
    // Wrapped, the room a box has is what is left once the things in the
    // way are taken out. Measured as it is drawn (see layoutWrapped), so the
    // grip and the canvas agree.
    case WordsSet.wrapped:
      return layoutWrapped(text, spec, inner, blocked, e.wrap, parts: parts)
          .consumed;
    case WordsSet.inBox:
      width = inner.width;
    case WordsSet.inColumns:
      width = e.columns.columnWidth(inner.width);
  }
  if (width <= 0 || inner.height <= 0) return 0;

  // How many lines fit: the same packing the columns use, so a box with three
  // columns passes on what would not fit in the third rather than what would
  // not fit in one.
  return layOutWords(text, spec, parts: parts, maxWidth: width, fillWidth: true)
      .charactersIn(inner.height, columns: e.columns.count, tidy: tidy);
}
