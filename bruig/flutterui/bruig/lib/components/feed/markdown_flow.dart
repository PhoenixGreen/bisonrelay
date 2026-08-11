import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/components/feed/image_header.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// markdown_flow.dart divides one run of markdown between columns.
//
// All of it is arithmetic on text: no widgets, nothing to lay out, nothing
// that needs a BuildContext. It sits apart from the rendering for that
// reason -- the hard part of columns is deciding where the breaks fall, and
// that decision is worth being able to read, test and argue with on its own.
//
// What it cannot do is know how tall anything is. columnWeigher closes that
// gap by measuring the text at the width it is about to be drawn at and
// reading a picture's proportions out of its header, so the balance is struck
// against the real page rather than against a guess at one.

/// flowColumns divides one run of markdown between [count] columns so that
/// each holds roughly as much as the others.
///
/// Balanced in the order it was written: reading the columns left to right
/// gives back the post as it was typed. That is what makes a narrow window
/// safe -- when there is no room for columns they stack, and stacked they
/// read in the right order.
///
/// A break falls between two blocks where it can and through a paragraph
/// where it must. A run written as one long paragraph has no break to fall
/// between, and would otherwise sit entirely in the first column with the
/// rest empty -- which is what "it flows if I put paragraph breaks in but
/// does not if I do not" was. Splitting one is done at a sentence, and the
/// head finishes a column while the tail starts the next, so the two read as
/// prose carrying on rather than as a paragraph with a hole in it. Lists,
/// quotations, tables, code and pictures are never split.
///
/// [weigh] says how much of a column a block is expected to fill. The
/// default counts characters, which is all that can be known without a page
/// to lay them out on; the renderer passes one that estimates real heights
/// against the column width it is about to use.
List<String> flowColumns(String markdown, int count,
    {double Function(String)? weigh}) {
  if (count <= 1) return [markdown];
  var weight = weigh ?? _weigh;
  var queue = _topLevelBlocks(markdown);
  if (queue.isEmpty) return [for (var i = 0; i < count; i++) ""];

  var remaining = queue.fold<double>(0, (a, b) => a + weight(b));
  var out = <List<String>>[];
  var at = 0;

  for (var column = 0; column < count; column++) {
    var columnsLeft = count - column;
    // The last column takes what is left rather than measuring: whatever
    // rounding has done along the way ends up here, not on the floor.
    if (columnsLeft == 1) {
      out.add(queue.sublist(at));
      at = queue.length;
      break;
    }

    var target = remaining / columnsLeft;
    var taken = <String>[];
    var filled = 0.0;
    while (at < queue.length) {
      var next = queue[at];
      var nextWeight = weight(next);

      // Every remaining column needs something, or the run comes out as one
      // full column and the rest empty.
      //
      // Asked here rather than acted on here. A block that can be cut in
      // two satisfies this by being cut -- and stopping on the question
      // before ever reaching the cut is what left a picture alone in one
      // column with the whole of the post in the other: one block left, one
      // column still to fill, so it stopped, and the block it was saving was
      // the only writing there was.
      var mustLeaveSome =
          queue.length - at <= columnsLeft - 1 && taken.isNotEmpty;

      if (!mustLeaveSome && filled + nextWeight <= target) {
        taken.add(next);
        filled += nextWeight;
        at++;
        continue;
      }

      // The block does not fit. There are three things that can be done with
      // it -- stop before it, take the whole of it, or cut it -- and the one
      // that leaves this column nearest the size it was aiming for wins.
      //
      // Judged on the result rather than on the block. Asking whether the
      // block was oversized, which is what this did, said no for a paragraph
      // sitting beside a picture that had already half filled the column --
      // so the picture stayed alone with every word of the post beside it.
      // What matters is how far off the column ends up, and cutting always
      // lands on the mark.
      var room = target - filled;
      var errorStop = room.abs();
      var errorTake = mustLeaveSome
          ? double.infinity
          : (filled + nextWeight - target).abs();

      if (room > 0 && math.min(errorStop, errorTake) > target * _cutWhenOffBy) {
        var split = _splitParagraph(next, room / nextWeight);
        if (split != null) {
          taken.add(split.$1);
          queue[at] = split.$2;
          filled += weight(split.$1);
          break;
        }
      }

      // It could not be cut, so it goes whole into one column or the other.
      if (mustLeaveSome) break;

      if (taken.isEmpty || errorTake <= errorStop) {
        taken.add(next);
        filled += nextWeight;
        at++;
      }
      break;
    }

    // A heading belongs with what it heads. Left at the foot of a column it
    // announces the next one, which reads as a mistake -- so it goes back
    // and starts the column it belongs to.
    while (taken.length > 1 &&
        at > 0 &&
        at < queue.length &&
        identical(taken.last, queue[at - 1]) &&
        _headingLine.hasMatch(taken.last)) {
      filled -= weight(taken.removeLast());
      at--;
    }

    remaining -= filled;
    out.add(taken);
  }

  // Anything rounding has left over goes at the end rather than nowhere.
  while (at < queue.length) {
    out.last.add(queue[at]);
    at++;
  }
  return [for (var c in out) c.join("\n\n")];
}

/// _cutWhenOffBy is how far off the mark the best whole-block answer has to
/// be before a paragraph is cut instead, as a share of what the column was
/// aiming for.
///
/// A tenth. Nearer than that and the writing is left exactly as it was
/// written, which is why a run already broken into paragraphs is never
/// touched: stopping between two of them lands close enough by itself.
const _cutWhenOffBy = 0.1;

/// _sentences is where a paragraph may be broken.
final _sentences = RegExp(r'(?<=[.!?])\s+');

/// _unsplittable are the blocks a column break may not fall through: a
/// heading, a list item, a quotation, a table row and a fenced block.
final _unsplittable = RegExp(r'^\s*(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|\||```)');

/// _splitParagraph cuts one paragraph at the sentence nearest [fraction] of
/// the way through it, or returns null when the block may not be cut.
///
/// The head and the tail are each a whole paragraph, so the break lands at
/// the foot of one column and the top of the next. Cutting at a sentence
/// rather than at a word is the difference between a column that ends and a
/// column that stops.
(String, String)? _splitParagraph(String block, double fraction) {
  if (_unsplittable.hasMatch(block)) return null;
  if (block.contains("--embed[")) return null;

  var parts = block.split(_sentences);
  if (parts.length < 2) return null;

  var wanted = block.length * fraction.clamp(0.0, 1.0);
  var head = <String>[];
  var length = 0;
  // The last sentence is never offered: a split that keeps everything is
  // not a split.
  for (var i = 0; i < parts.length - 1; i++) {
    if (head.isNotEmpty && length + parts[i].length / 2 > wanted) break;
    head.add(parts[i]);
    length += parts[i].length + 1;
  }
  if (head.isEmpty) return null;
  return (head.join(" "), parts.sublist(head.length).join(" "));
}

/// _headingLine is a heading, which is a block of its own however it was
/// written.
final _headingLine = RegExp(r'^\s*#{1,6}\s');

/// _aloneOnALine are the things that are a block by themselves when they
/// have a line to themselves: a picture and a horizontal rule.
final _embedLine = RegExp(r'^\s*(--embed\[.*?\]--\s*)+$', dotAll: true);
final _ruleLine = RegExp(r'^\s*([-*_])\1{2,}\s*$');

/// _topLevelBlocks cuts markdown into the pieces a column break may fall
/// between.
///
/// A blank line is the obvious boundary, and for a long time it was the only
/// one -- which meant a heading written straight above its paragraph, or a
/// picture with a line of text under it, was one indivisible lump. A column
/// cannot be balanced against a lump: a heading with three paragraphs stuck
/// to it goes in whole or not at all, and that is what "a subtitle breaks
/// the flow" and "a picture in a column does not work" both were.
///
/// So a heading is a block, a picture on a line of its own is a block, and a
/// rule is a block, blank lines or no. A fenced code block is the opposite
/// case and is kept whole however many blank lines are inside it.
List<String> _topLevelBlocks(String markdown) {
  var out = <String>[];
  var current = <String>[];
  var fenced = false;
  void flush() {
    var block = current.join("\n").trim();
    if (block.isNotEmpty) out.add(block);
    current = [];
  }

  for (var line in markdown.split("\n")) {
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      current.add(line);
      if (!fenced) {
        flush();
      }
      continue;
    }
    if (fenced) {
      current.add(line);
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    if (_headingLine.hasMatch(line) ||
        _embedLine.hasMatch(line) ||
        _ruleLine.hasMatch(line)) {
      flush();
      current.add(line);
      flush();
      continue;
    }
    current.add(line);
  }
  flush();
  return out;
}

/// _embedRe finds an embed and its parameters.
final _embedRe = RegExp(r'--embed\[(.*?)\]--', dotAll: true);

/// _weigh is the fallback measure of a block: the characters in it.
///
/// All that can be known without a page to lay the block out on, and what
/// the model's own tests use. An embedded picture is the exception and has
/// to be: it carries its bytes as base64, tens of thousands of characters of
/// which none are on the page.
double _weigh(String block) {
  var embeds = _embedRe.allMatches(block).length;
  var text = block.replaceAll(_embedRe, "");
  return text.length + embeds * 600;
}

/// _embedShapes remembers the proportions of each picture that has been
/// weighed, keyed by the base64 it arrived as.
///
/// Reading them means decoding that base64, and the flow is worked out again
/// every time the column width changes -- which, while a window is being
/// dragged, is every frame.
final Map<String, double> _embedShapes = {};

/// _embedAspect is a picture's height as a share of its width, or a plain
/// guess when there is nothing to read it from.
double _embedAspect(String params) {
  var data = "";
  for (var part in params.split(",")) {
    var at = part.indexOf("=");
    if (at > 0 && part.substring(0, at) == "data") {
      data = part.substring(at + 1);
    }
  }
  if (data.isEmpty) return 0.6;
  var known = _embedShapes[data];
  if (known != null) return known;

  var aspect = 0.6;
  try {
    var size = imageDimensions(base64Decode(data));
    if (size != null && size.width > 0) aspect = size.height / size.width;
  } catch (_) {
    // Half-typed base64 in a post being written is ordinary.
  }
  if (_embedShapes.length > 32) _embedShapes.clear();
  _embedShapes[data] = aspect;
  return aspect;
}

/// _textHeights remembers what a block measured, keyed by the block and the
/// width it was measured at.
///
/// Laying text out is the expensive part of this, and the flow is worked out
/// again every time the column width changes -- which, while a window is
/// being dragged, is every frame.
final Map<String, double> _textHeights = {};

/// _markup is the characters that are instructions rather than words, and so
/// take no room on the page.
final _markup =
    RegExp(r'(^\s*#{1,6}\s*)|(^\s*>\s?)|(\*\*|__|~~|`)', multiLine: true);

/// columnWeigher measures a block by how tall it will actually be drawn in a
/// column [width] wide.
///
/// The text is laid out and measured rather than estimated. Guessing it from
/// a character count is fine while every column holds the same kind of thing
/// -- an error shared equally by both sides cancels out -- and stops being
/// fine the moment one column holds a picture. A picture's height is known
/// exactly, so any error in the text estimate lands entirely on the other
/// column: guessing sixty characters to a line where forty-two fit made a
/// column of prose read as two thirds of its real height, and the column
/// with the picture in it came out short by the difference.
///
/// [body] is the style the run is set in and [headingScales] the size of each
/// heading level as a share of it, which is how a style guide states them.
double Function(String) columnWeigher({
  required double width,
  required TextStyle body,
  required double gap,
  List<double> headingScales = const [1.7, 1.6, 1.15, 1.15, 1.0, 0.9],
  ImageRule image = const ImageRule(),
}) {
  // A picture is drawn at its share of the column, not always at the whole
  // of it, and with the guide's own space above and below. Weighed as though
  // it filled the column, one set to 60% counted for nearly twice the space
  // it takes.
  var pictureWidth = width * image.boundedWidth / 100;
  var bodySize = body.fontSize ?? 14;

  double measure(String text, TextStyle style) {
    var key = "${width.round()}|${style.fontSize}|${style.fontFamily}|"
        "${style.height}|$text";
    var known = _textHeights[key];
    if (known != null) return known;

    var painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    var height = painter.height;
    painter.dispose();

    if (_textHeights.length > 256) _textHeights.clear();
    _textHeights[key] = height;
    return height;
  }

  return (block) {
    var height = gap;
    for (var m in _embedRe.allMatches(block)) {
      height += pictureWidth * _embedAspect(m.group(1) ?? "") + image.gap * 2;
    }

    var text = block.replaceAll(_embedRe, "").trim();
    if (text.isEmpty) return height;

    // A heading is set larger than the body, and the hashes that say so are
    // not on the page.
    var level = RegExp(r'^\s*(#{1,6})\s').firstMatch(text)?.group(1)?.length;
    var style = level == null
        ? body
        : body.copyWith(
            fontSize: bodySize * headingScales[level - 1],
            fontWeight: FontWeight.w700);

    return height + measure(text.replaceAll(_markup, ""), style);
  };
}

/// CardsBlockSyntax reads a callout, or a grid of them.
///
/// A callout and a card are the same thing with a different amount filled in,
/// so there is one syntax for both:
///
///     --card--
///     icon: announce
///     title: Stay Updated
///     text: Subscribe and get the latest.
///     button: Subscribe Now
///     link: https://decred.org
///     --/card--
///
/// Every field is optional and unknown ones are ignored, so a card is never
/// broken by a field this app has not heard of -- which is what lets the set
/// grow later without old posts breaking. A line that begins with a space
/// continues the field above it, so a long description can be wrapped in the
/// source the way any other paragraph is.
///
/// Several of them go in a grid, at most two across:
///
///     --cards[2]--
///     --card-- ... --/card--
///     --card-- ... --/card--
///     --/cards--
///
/// Fielded rather than markdown-inside-the-card, because a card's parts are
/// named things -- this is the title, this is the button -- and a heading
/// somebody happened to write is not a title. It also degrades honestly: a
/// reader whose app does not know the syntax sees labelled lines in the order
/// they were written, which is still the card, just not drawn.
