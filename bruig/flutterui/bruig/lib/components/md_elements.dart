import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
// import 'package:dart_vlc/dart_vlc.dart' as vlc;
import 'package:bruig/components/context_menu.dart';
import 'package:bruig/components/feed/image_header.dart';
import 'package:bruig/components/pages/forms.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text_dialog.dart';
import 'package:bruig/components/audio_element.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/screens/feed.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/util.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/components/image_dialog.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_avif/flutter_avif.dart';

class DownloadSource {
  final String uid;

  DownloadSource(this.uid);
}

class PagesSource {
  final String uid;
  final int sessionID;
  final int pageID;

  PagesSource(this.uid, this.sessionID, this.pageID);
}

class VideoInlineSyntax extends md.InlineSyntax {
  /// This is a primitive example pattern
  VideoInlineSyntax({
    String pattern = r'--video\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final videoURL = match.group(1);

    md.Element el = md.Element.text("video", videoURL!.toString());

    parser.addNode(el);
    return true;
  }
}

class ImageInlineSyntax extends md.InlineSyntax {
  /// This is a primitive example pattern
  ImageInlineSyntax({
    String pattern = r'--image\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final imageURL = match.group(1);

    md.Element el = md.Element.text("image", imageURL!.toString());

    parser.addNode(el);
    return true;
  }
}

class LnpayURLSyntax extends md.InlineSyntax {
  LnpayURLSyntax({
    String pattern = r'lnpay:\/\/(ln[td]?\w*)',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match.group(1) ?? "";

    md.Element el = md.Element.text("lnpay", url);

    parser.addNode(el);
    return true;
  }
}

/// Matches bare (not already markdown-linked) http(s) URLs so the "Pretty
/// Links" plugin can offer a native preview card for known domains. Because
/// user-supplied inline syntaxes are tried before flutter_markdown's
/// built-in link/autolink syntaxes, this only ever fires on genuinely bare
/// URLs in the source text -- an explicit `[text](url)` markdown link is
/// fully consumed by the built-in LinkSyntax before the parser's cursor
/// ever reaches the URL text on its own.
class BareLinkSyntax extends md.InlineSyntax {
  /// The element tag matched URLs are emitted as, for whichever
  /// MarkdownExtension registered this syntax to render.
  final String tag;

  BareLinkSyntax({
    required this.tag,
    String pattern = r'https?:\/\/\S+',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(tag, match.group(0) ?? ""));
    return true;
  }
}

/// ColumnsBlockSyntax reads a run of columns.
///
/// Markdown has no columns of its own -- there is no syntax for them in any
/// dialect worth following -- so this is one Bison Relay adds, in the shape
/// the app already uses for the things markdown has no word for:
///
///     --columns--
///     What goes on the left.
///     --col--
///     What goes on the right.
///     --/columns--
///
/// Two markers and a separator, matching --form--/--/form-- next door. A
/// reader whose client does not know them sees the markers as ordinary
/// lines with the writing still in the right order underneath, which is the
/// most a format nobody else implements can promise.
///
/// The columns hold markdown, not text: each one is rendered by a
/// MarkdownArea of its own, so a heading, a list or a picture inside a
/// column is the same heading, list or picture it would be outside one.
class ColumnsBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--columns(?:\[(\d+)\])?--\s*$');
  static final _separator = RegExp(r'^\s*--col--\s*$');
  static final _close = RegExp(r'^\s*--/columns--\s*$');

  /// The most columns one run may hold.
  ///
  /// Four is past the point where a column in a chat-width window is a word
  /// wide. Separators past it fold into the last column rather than being
  /// dropped, so nothing a writer typed disappears.
  static const maxColumns = 4;

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    // The count, when one was asked for: --columns[2]-- flows the writing
    // into two rather than expecting it to be divided by hand.
    var asked =
        int.tryParse(_open.firstMatch(parser.current.content)?.group(1) ?? "");
    parser.advance();

    var columns = <List<String>>[[]];
    while (!parser.isDone) {
      var line = parser.current.content;
      if (_close.hasMatch(line)) {
        parser.advance();
        break;
      }
      if (_separator.hasMatch(line)) {
        if (columns.length < maxColumns) columns.add([]);
        parser.advance();
        continue;
      }
      columns.last.add(line);
      parser.advance();
    }

    var parts = [for (var c in columns) c.join("\n").trim()];

    // The columns travel as attributes rather than as parsed children: each
    // is a whole document in its own right, and the renderer hands it to a
    // MarkdownArea instead of trying to lay out somebody else's nodes.
    var element = md.Element.text("columns", "");

    // A count with no separators is a run to be flowed, and it is passed on
    // whole for the renderer to divide. Dividing it here is too early: how
    // much of a column a block fills depends on how wide the column is and
    // on the shape of any picture in it, and neither is known until there is
    // a page to put it on. Weighed by characters alone a photograph counted
    // for six hundred of them whatever its proportions, and a column with
    // one at the top came out half empty.
    //
    // Separators are a decision the writer already made, so where there are
    // any they win -- one of them is how a break is forced in a run that
    // would otherwise be balanced.
    if (asked != null && parts.length == 1) {
      element.attributes["flow"] = parts.first;
      element.attributes["count"] = "${asked.clamp(1, maxColumns)}";
      return md.Element("p", [element]);
    }

    for (var i = 0; i < parts.length; i++) {
      element.attributes["col$i"] = parts[i];
    }

    // Wrapped in a paragraph. The builder that draws this is reached through
    // flutter_markdown's inline path, which expects to be inside a block --
    // at the top level of a document there is no block tag to inherit and it
    // fails on the way in.
    return md.Element("p", [element]);
  }
}

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
      if (!fenced) flush();
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
    if (at > 0 && part.substring(0, at) == "data")
      data = part.substring(at + 1);
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
class CardsBlockSyntax extends md.BlockSyntax {
  static final _openGrid = RegExp(r'^\s*--cards(?:\[(\d+)\])?--\s*$');
  static final _closeGrid = RegExp(r'^\s*--/cards--\s*$');
  static final _openCard = RegExp(r'^\s*--card--\s*$');
  static final _closeCard = RegExp(r'^\s*--/card--\s*$');
  static final _field = RegExp(r'^\s*(\w+)\s*:\s*(.*)$');

  /// The most a grid may hold: two across and three down.
  static const maxColumns = 2;
  static const maxRows = 3;
  static const maxCards = maxColumns * maxRows;

  @override
  RegExp get pattern => RegExp(r'^\s*--cards?(?:\[\d+\])?--\s*$');

  @override
  md.Node? parse(md.BlockParser parser) {
    var line = parser.current.content;
    var grid = _openGrid.hasMatch(line);
    var columns = grid
        ? (int.tryParse(_openGrid.firstMatch(line)?.group(1) ?? "") ?? 2)
            .clamp(1, maxColumns)
        : 1;

    var cards = <Map<String, String>>[];
    if (grid) {
      parser.advance();
      while (!parser.isDone) {
        var at = parser.current.content;
        if (_closeGrid.hasMatch(at)) {
          parser.advance();
          break;
        }
        if (_openCard.hasMatch(at)) {
          var card = _readCard(parser);
          if (cards.length < maxCards) cards.add(card);
          continue;
        }
        // Anything between the cards is not part of one. Skipped rather than
        // shown, since a grid is a grid of cards.
        parser.advance();
      }
    } else {
      cards.add(_readCard(parser));
    }

    var element = md.Element.text("cards", "");
    element.attributes["columns"] = "$columns";
    element.attributes["count"] = "${cards.length}";
    for (var i = 0; i < cards.length; i++) {
      cards[i].forEach((key, value) {
        element.attributes["$i.$key"] = value;
      });
    }
    // Wrapped in a paragraph for the same reason a run of columns is: the
    // builder that draws this is reached through flutter_markdown's inline
    // path, which expects to be inside a block.
    return md.Element("p", [element]);
  }

  /// _readCard reads one --card-- block, starting on its opening marker.
  Map<String, String> _readCard(md.BlockParser parser) {
    parser.advance();
    var fields = <String, String>{};
    String? last;
    while (!parser.isDone) {
      var line = parser.current.content;
      if (_closeCard.hasMatch(line) || _closeGrid.hasMatch(line)) {
        // A grid's closing marker is left for the caller: it ends the grid,
        // not only this card, and a card left unclosed must not swallow it.
        if (_closeCard.hasMatch(line)) parser.advance();
        break;
      }
      if (_openCard.hasMatch(line)) break;

      // A line beginning with a space continues the field above it, so a
      // description can be wrapped in the source like any other paragraph.
      if (last != null &&
          line.startsWith(RegExp(r'\s')) &&
          line.trim().isNotEmpty) {
        fields[last] = "${fields[last]} ${line.trim()}";
        parser.advance();
        continue;
      }

      var field = _field.firstMatch(line);
      if (field != null) {
        last = field.group(1)!.toLowerCase();
        fields[last] = field.group(2)!.trim();
      }
      parser.advance();
    }
    return fields;
  }
}

class EmbedInlineSyntax extends md.InlineSyntax {
  final String dbRoot;

  /// This is a primitive example pattern
  EmbedInlineSyntax(
    this.dbRoot, {
    String pattern = r'--embed\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final Map<String, String> parms = {};
    final rawParms = match.group(1) ?? "";
    rawParms.split(",").forEach((element) {
      var p = element.indexOf("=");
      if (p == -1) return;
      parms[element.substring(0, p)] = element.substring(p + 1);
    });

    // Quote embed: a reference to another post (rendered as a nested
    // card). Only ever produced by the feed's Quote Post action, which is
    // gated behind AreaStyle.feedCardActions.
    if (parms["type"] == "quote") {
      var el = md.Element.text("quote", "");
      el.attributes["from"] = parms["from"] ?? "";
      el.attributes["post"] = parms["post"] ?? "";
      parser.addNode(el);
      return true;
    }

    // Only accept valid download FIDs.
    var download = parms["download"] ?? "";
    if (!RegExp(r"^[0-9a-fA-F]{64}$").hasMatch(download)) {
      download = "";
    }

    // URL-decode alt text.
    var alt = parms["alt"] ?? "";
    if (alt != "") {
      try {
        alt = Uri.decodeComponent(alt);
      } catch (exception) {
        // Ignore decoding errors and just print a debug msg.
        debugPrint("Unable to decode alt: $exception");
      }
    }

    var data = parms["data"] ?? "";
    var localFilename = parms["localfilename"] ?? "";

    // Bare link without embedded data.
    if ((data == "" && localFilename == "") && download != "") {
      var el = md.Element.text(
          "download", alt != "" ? alt : "Download file $download");
      el.attributes["fid"] = download;
      parser.addNode(el);
      return true;
    }

    // Otherwise, we need data.
    if (data == "" && localFilename == "") {
      return true;
    }

    var tag = "";

    // If localFilename is specified, load from saved embedded dir.
    if (localFilename != "") {
      var filePath = path.join(dbRoot, localFilename);
      try {
        // Encode back to base64 becase ImageBuilder decodes it itself.
        data = base64Encode(File(filePath).readAsBytesSync());
      } catch (exception) {
        tag = "text";
        data = "Error opening embedded file '$filePath': $exception";
      }
    }

    if (tag == "") {
      switch (parms["type"]) {
        case "image/bmp":
        case "image/gif":
        case "image/jpeg":
        case "image/jxl":
        case "image/png":
        case "image/webp":
          tag = "image";
          break;
        case "image/avif":
          tag = "avif";
          break;
        case "text/plain":
          // Decode plain text directly.
          //
          // Its own tag, not "pre". A fenced code block parses to <pre>
          // too, so registering a builder for "pre" -- which is what an
          // attached text file needed -- took over every code block in
          // every post as well: they lost the monospaced face and the block
          // background, and each one grew a "View" button belonging to a
          // file that was not there. See MarkdownAreaModel.builders.
          tag = "embedtext";
          try {
            data = utf8.fuse(base64).decode(data);
          } catch (exception) {
            data = "Unable to decode plain text contents: $exception";
          }
          break;
        case "application/pdf":
          tag = "pdf";
          break;
        case "audio/ogg":
          tag = "audio";
          break;
        default:
          return true;
      }
    }
    md.Element el = md.Element.text(tag, data);

    if (download != "") {
      el.attributes["fid"] = download;
    }
    if (alt != "") {
      el.attributes["alt"] = alt;
    }

    if (parms["type"] != "") {
      el.attributes["type"] = parms["type"]!;
    }

    if (parms.containsKey("filename") && parms["filename"] != "") {
      el.attributes["filename"] = parms["filename"]!;
    }

    var name = parms["name"] ?? "";
    if (name != "") {
      el.attributes["name"] = name;
    }

    parser.addNode(el);
    return true;
  }
}

/*
class _VideoMarkdownDesktopElement extends StatefulWidget {
  final String filename;
  _VideoMarkdownDesktopElement(this.filename, {Key? key}) : super(key: key);

  @override
  __VideoMarkdownDesktopElementState createState() =>
      __VideoMarkdownDesktopElementState();
}


class __VideoMarkdownDesktopElementState
    extends State<_VideoMarkdownDesktopElement> {
  vlc.Player player = vlc.Player(id: 69420);
  vlc.Media? media;

  @override
  void initState() {
    super.initState();
    media = vlc.Media.file(File(widget.filename));
    if (media != null) {
      player.open(media!);
    }
  }

  @override
  void dispose() {
    player.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return vlc.Video(
      player: player,
      width: 320,
      height: 200,
    );
  }
}

class _VideoMarkdownMobileElement extends StatefulWidget {
  final String filename;
  _VideoMarkdownMobileElement(this.filename, {Key? key}) : super(key: key);

  @override
  __VideoMarkdownMobileElementState createState() =>
      __VideoMarkdownMobileElementState();
}

class __VideoMarkdownMobileElementState
    extends State<_VideoMarkdownMobileElement> {
  mbv.VideoPlayerController? controller;

  void initController() async {
    var f = File(widget.filename);
    var newController = await mbv.VideoPlayerController.file(f);
    await newController.initialize();
    mounted
        ? setState(() {
            controller = newController;
            controller?.play();
          })
        : null;
  }

  @override
  void initState() {
    super.initState();
    initController();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    if (controller == null) {
      return Container(
        color: theme.cardColor,
        child: Center(
          child: Text("Loading..."),
        ),
      );
    }

    return AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: mbv.VideoPlayer(controller!));
  }
}

class VideoMarkdownElementBuilder extends MarkdownElementBuilder {
  final String basedir;
  VideoMarkdownElementBuilder(this.basedir);

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final bool useVLC =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // Protect against trying to fetch from !basedir.
    String filename = p.canonicalize(p.join(this.basedir, element.textContent));
    if (!p.isWithin(basedir, filename)) {
      return Container(color: Colors.amber, width: 100, height: 100);
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: useVLC
              ? _VideoMarkdownDesktopElement(filename)
              : _VideoMarkdownMobileElement(filename)),
    );
  }
}
*/

class MarkdownAreaModel extends ChangeNotifier {
  final extensionSet = md.ExtensionSet(
      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes]);

  final Map<String, MarkdownElementBuilder> builders = {
    // An attached text file, which EmbedInlineSyntax emits as "embedtext".
    // Deliberately not "pre": that is what a fenced code block parses to,
    // and a builder registered there renders every code block in the app as
    // a scrolling box with a "View" button, in the body face rather than the
    // code one -- flutter_markdown asks the builder for the block's tag
    // before it reaches its own code-block rendering.
    "embedtext": PreformattedElementBuilder(),
    "pdf": PDFMarkdownElementBuilder(),
    "audio": AudioElementBuilder(),
    //"video": VideoMarkdownElementBuilder(basedir),
    "codeblock": CodeblockMarkdownElementBuilder(),
    "image": ImageMarkdownElementBuilder(),
    "download": DownloadLinkElementBuilder(),
    "form": FormElementBuilder(),
    "lnpay": _LNPayURLElementBuilder(),
    "avif": AVIFElementBuilder(),
    "quote": QuoteMarkdownElementBuilder(),
    "columns": ColumnsMarkdownElementBuilder(),
    "cards": CardsMarkdownElementBuilder(),
  };

  final List<md.InlineSyntax> inlineSyntaxes = [
    LnpayURLSyntax(),
  ];
  final List<md.BlockSyntax> blockSyntaxes = [
    FormBlockSyntax(),
    ColumnsBlockSyntax(),
    CardsBlockSyntax(),
  ];

  // _pluginExtensions is whatever the last setPluginExtensions call added,
  // kept so the next one can remove exactly those again.
  List<MarkdownExtension> _pluginExtensions = const [];

  MarkdownAreaModel(String dbroot) {
    inlineSyntaxes.add(EmbedInlineSyntax(dbroot));
  }

  /// setPluginExtensions replaces the markdown renderers contributed from
  /// outside this file -- see lib/plugin_system, which is the only caller.
  /// The built-in builders and syntaxes declared above are never touched by
  /// it, so a plugin can add a rendering but never remove or replace one of
  /// Bison Relay's own.
  ///
  /// Called whenever the set of enabled plugins changes. Markdown already
  /// rendered on screen keeps its old rendering until it rebuilds.
  void setPluginExtensions(List<MarkdownExtension> extensions) {
    var sameTags = _pluginExtensions.length == extensions.length &&
        _pluginExtensions.every((e) => extensions.any((n) => n.tag == e.tag));
    if (sameTags) return;

    for (var e in _pluginExtensions) {
      builders.remove(e.tag);
      if (e.inlineSyntax != null) inlineSyntaxes.remove(e.inlineSyntax);
    }
    _pluginExtensions = extensions;
    for (var e in extensions) {
      builders[e.tag] = e.builder;
      if (e.inlineSyntax != null) inlineSyntaxes.add(e.inlineSyntax!);
    }
    notifyListeners();
  }
}

/// MarkdownExtension is one markdown rendering contributed from outside this
/// file. It is the whole of the app's markdown extension point: a tag to
/// render, the builder that renders it, and optionally an inline syntax that
/// produces that tag in the first place.
class MarkdownExtension {
  /// The markdown element tag [builder] renders.
  final String tag;
  final MarkdownElementBuilder builder;

  /// An optional syntax that emits [tag]. Needed when the extension renders
  /// something the markdown source doesn't already mark up -- a bare URL,
  /// say, which is otherwise just text.
  final md.InlineSyntax? inlineSyntax;

  const MarkdownExtension({
    required this.tag,
    required this.builder,
    this.inlineSyntax,
  });
}

/// MarkdownGuideScope carries a style guide's picture rules down to the
/// embeds inside one piece of markdown.
///
/// An InheritedWidget rather than a parameter because the widget that draws
/// an embed is built by flutter_markdown from a builder, several layers
/// below whoever chose the guide, and there is no argument to thread down.
///
/// Absent means "as it was". Chat installs no scope, so a picture in a
/// message is drawn exactly as it was before guides existed -- which is what
/// keeps this a posts-only feature.
class MarkdownGuideScope extends InheritedWidget {
  final ImageRule image;
  final ColumnRule columns;
  final CardRule cards;

  const MarkdownGuideScope(
      {required this.image,
      this.columns = const ColumnRule(),
      this.cards = const CardRule(),
      required super.child,
      super.key});

  static ImageRule? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.image;

  static ColumnRule? columnsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.columns;

  static CardRule? cardsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.cards;

  @override
  bool updateShouldNotify(MarkdownGuideScope old) =>
      old.image != image || old.columns != columns || old.cards != cards;
}

/// _ColumnDepth is how many runs of columns a piece of markdown is already
/// inside.
///
/// Each column is rendered by a MarkdownArea of its own, and that MarkdownArea
/// reads columns too -- so a post whose columns contain columns nests one
/// widget tree inside another for as deep as it is written. A post arrives
/// from somebody else, and a few hundred lines of nothing but opening markers
/// would be a way to exhaust the stack of whoever reads it. Past [_maxDepth]
/// the markers are shown as the text they are instead.
class _ColumnDepth extends InheritedWidget {
  final int depth;
  const _ColumnDepth({required this.depth, required super.child});

  static const _maxDepth = 3;

  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnDepth>()?.depth ?? 0;

  @override
  bool updateShouldNotify(_ColumnDepth old) => old.depth != depth;
}

class ColumnsMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // A run to be flowed arrives whole, with the number of columns it is to
    // be flowed into: dividing it needs the width of a column and the shape
    // of any picture in it, neither of which the parser can know.
    var flow = element.attributes["flow"];
    if (flow != null) {
      return _MarkdownColumns(const [],
          flow: flow,
          count: int.tryParse(element.attributes["count"] ?? "") ?? 2);
    }

    var columns = <String>[];
    for (var i = 0;; i++) {
      var text = element.attributes["col$i"];
      if (text == null) break;
      columns.add(text);
    }
    return _MarkdownColumns(columns);
  }
}

/// CardsMarkdownElementBuilder draws a callout, or a grid of them.
class CardsMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var count = int.tryParse(element.attributes["count"] ?? "") ?? 0;
    var columns = int.tryParse(element.attributes["columns"] ?? "") ?? 1;
    var cards = <Map<String, String>>[];
    for (var i = 0; i < count; i++) {
      var fields = <String, String>{};
      element.attributes.forEach((key, value) {
        if (key.startsWith("$i.")) fields[key.substring("$i.".length)] = value;
      });
      cards.add(fields);
    }
    return _MarkdownCards(cards: cards, columns: columns);
  }
}

/// _MarkdownCards lays the cards out and draws each one.
class _MarkdownCards extends StatelessWidget {
  final List<Map<String, String>> cards;
  final int columns;
  const _MarkdownCards({required this.cards, required this.columns});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.cardsOf(context) ?? const CardRule();
    var gap = rule.boundedGap;

    if (cards.length == 1 || columns <= 1) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: gap / 2),
        child: _card(context, theme, rule, cards.first),
      );
    }

    // Laid out in rows of [columns] rather than in a Wrap, so the cards in a
    // row are equal shares of the width and line up with the row above --
    // which is the whole reason for saying how many columns there are.
    var rows = <Widget>[];
    for (var at = 0; at < cards.length; at += columns) {
      var row = cards.sublist(at, math.min(at + columns, cards.length));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) SizedBox(width: gap),
              // The empty slot on a short last row keeps its share, so two
              // cards over two rows do not become one wide and one narrow.
              Expanded(
                child: i < row.length
                    ? _card(context, theme, rule, row[i])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap / 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// _card draws one: the icon beside the writing, and the button under it.
  Widget _card(BuildContext context, ThemeNotifier theme, CardRule rule,
      Map<String, String> fields) {
    Color? ink(MarkdownInk i) => i.resolve(theme.markdownRoleColor,
        paletteColor: theme.markdownPaletteColor);

    var body =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    var titleText = fields["title"] ?? "";
    var text = fields["text"] ?? fields["description"] ?? "";
    var buttonText = fields["button"] ?? "";
    var link = fields["link"] ?? "";
    var icon = MarkdownCardIcon.named(fields["icon"] ?? "");

    var writing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titleText.isNotEmpty)
          Text(titleText,
              style: rule.title.applyTo(body, theme.markdownRoleColor,
                  paletteColor: theme.markdownPaletteColor)),
        if (titleText.isNotEmpty && text.isNotEmpty) const SizedBox(height: 6),
        if (text.isNotEmpty)
          Text(text,
              style: rule.text.applyTo(body, theme.markdownRoleColor,
                  paletteColor: theme.markdownPaletteColor)),
        if (buttonText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            // The app's own button, so a card's button is the same button as
            // every other button in the app and follows the Buttons area.
            child: ElevatedButton(
              onPressed: link.isEmpty
                  ? null
                  : () async {
                      var url = Uri.tryParse(link);
                      if (url == null) return;
                      if (!await launchUrl(url) && context.mounted) {
                        SnackBarModel.of(context).error("Could not open $link");
                      }
                    },
              child: Text(buttonText),
            ),
          ),
        ],
      ],
    );

    var iconInk = ink(rule.iconInk) ?? theme.colors.primary;
    var iconBack = ink(rule.iconBackground);
    Widget? drawn = icon == null
        ? null
        : Container(
            padding: EdgeInsets.all(
                iconBack == null ? 0 : rule.boundedIconSize * 0.4),
            decoration: iconBack == null
                ? null
                : BoxDecoration(color: iconBack, shape: BoxShape.circle),
            child: Icon(icon.icon, size: rule.boundedIconSize, color: iconInk),
          );

    var border = rule.boundedBorder == 0
        ? null
        : Border.all(
            color: ink(rule.borderInk) ?? theme.colors.outlineVariant,
            width: rule.boundedBorder);

    return Container(
      padding: rule.paddings.isZero ? null : rule.paddings.insets,
      decoration: BoxDecoration(
        color: ink(rule.background),
        border: border,
        borderRadius: BorderRadius.circular(rule.boundedRadius),
      ),
      child: drawn == null
          ? writing
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                drawn,
                SizedBox(width: rule.boundedIconSize * 0.6),
                Expanded(child: writing),
              ],
            ),
    );
  }
}

/// _runBox draws the box round a run of columns: its margin, border, corners
/// and the padding between that border and the writing.
///
/// Round the run, not round each column. A border on every column is a row of
/// boxes with a channel down the middle of every gap; a border round the
/// outside is a block that happens to be set in columns. What separates one
/// column from the next is the divider, which is its own setting -- see
/// _ColumnDividers.
///
/// Flutter will not paint a border whose sides differ together with rounded
/// corners -- Border.paint refuses outright -- so a per-side border loses the
/// rounding, exactly as the theme's own areas do on their flat path.
Widget _runBox(ThemeNotifier theme, ColumnRule rule, Widget child) {
  var padding = rule.paddings;
  var margin = rule.margins;
  var widths = rule.borderWidths;
  var radii = rule.radii;

  var ink = rule.borderInk.resolve(theme.markdownRoleColor,
          paletteColor: theme.markdownPaletteColor) ??
      theme.colors.outlineVariant;

  Border? border;
  if (!widths.isZero) {
    border = widths.isUniform
        ? Border.all(color: ink, width: widths.left)
        : Border(
            left: BorderSide(color: ink, width: widths.left),
            top: BorderSide(color: ink, width: widths.top),
            right: BorderSide(color: ink, width: widths.right),
            bottom: BorderSide(color: ink, width: widths.bottom),
          );
  }
  var corners = radii.isZero || (border != null && !widths.isUniform)
      ? null
      : radii.radius;

  // Nothing set at all is nothing drawn: a run with no box of its own stays
  // the plain block it was before these settings existed.
  if (border == null && corners == null && padding.isZero && margin.isZero) {
    return child;
  }

  // Clipped to its own corners, so a picture filling a column does not square
  // off the rounding underneath it.
  if (corners != null) {
    child = ClipRRect(borderRadius: corners, child: child);
  }

  return Container(
    margin: margin.isZero ? null : margin.insets,
    padding: padding.isZero ? null : padding.insets,
    decoration: border == null && corners == null
        ? null
        : BoxDecoration(border: border, borderRadius: corners),
    child: child,
  );
}

/// _ColumnDividers draws one line down the middle of each gap.
///
/// Painted over the columns rather than placed between them, because a line
/// between two children of a Row has to be told how tall to be and the only
/// widget that answers that -- IntrinsicHeight -- cannot measure a column
/// holding a picture. (ImageMd sizes itself with a LayoutBuilder, and
/// LayoutBuilder refuses intrinsic measurement outright.) Painting needs no
/// measurement: the columns are equal shares of a known width, so where the
/// gaps fall is arithmetic, and the canvas is already exactly as tall as the
/// tallest column.
class _ColumnDividers extends CustomPainter {
  final int count;
  final double gap;
  final double width;
  final Color color;

  const _ColumnDividers(
      {required this.count,
      required this.gap,
      required this.width,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2 || width <= 0) return;
    var each = (size.width - gap * (count - 1)) / count;
    if (each <= 0) return;
    var paint = Paint()..color = color;
    for (var i = 1; i < count; i++) {
      // The middle of the i-th gap, which starts where the i-th column ends.
      var centre = i * (each + gap) - gap / 2;
      canvas.drawRect(
          Rect.fromLTWH(centre - width / 2, 0, width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ColumnDividers old) =>
      old.count != count ||
      old.gap != gap ||
      old.width != width ||
      old.color != color;
}

/// _MarkdownColumns lays a run of columns out side by side, or one above
/// another when there is not the width for them.
class _MarkdownColumns extends StatelessWidget {
  /// columns are the columns as the writer divided them, when they did.
  final List<String> columns;

  /// flow is the whole run, for a --columns[n]-- that is to be divided here
  /// rather than by hand, and [count] is how many columns to divide it into.
  ///
  /// Divided here rather than in the parser because how much of a column a
  /// block fills depends on how wide the column is and on the shape of any
  /// picture in it, and neither is known until there is a page to put it on.
  final String? flow;
  final int count;

  const _MarkdownColumns(this.columns, {this.flow, this.count = 2});

  @override
  Widget build(BuildContext context) {
    if (flow == null && columns.isEmpty) return const SizedBox.shrink();

    var depth = _ColumnDepth.of(context);
    if (depth >= _ColumnDepth._maxDepth) {
      return Text(flow ?? columns.join("\n\n"));
    }

    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.columnsOf(context) ?? const ColumnRule();
    var gap = rule.boundedGap;
    var dividerWidth = rule.boundedDivider;
    var dividerInk = rule.dividerInk.resolve(theme.markdownRoleColor,
            paletteColor: theme.markdownPaletteColor) ??
        theme.colors.outlineVariant;

    // The style the run is set in, which is what every block below is
    // measured in. Built the same way applyGuide builds the paragraph style,
    // so what is measured is what will be drawn.
    var guide = theme.markdownGuide;
    var bodyStyle = guide.body.applyTo(
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14),
        theme.markdownRoleColor,
        paletteColor: theme.markdownPaletteColor);

    Widget column(String text) => MarkdownArea(text, false);

    // A single column is not a layout, and drawing it as a Row of one would
    // put a stretched child where a plain block belongs.
    if (flow == null && columns.length == 1) {
      return _ColumnDepth(
        depth: depth + 1,
        child: _runBox(theme, rule, column(columns.first)),
      );
    }
    if (flow != null && count <= 1) {
      return _ColumnDepth(
        depth: depth + 1,
        child: _runBox(theme, rule, column(flow!)),
      );
    }

    return _ColumnDepth(
      depth: depth + 1,
      child: _runBox(
        theme,
        rule,
        LayoutBuilder(
          builder: (context, constraints) {
            var wanted = flow != null ? count : this.columns.length;

            // Stacked whenever a column would come out narrower than the
            // guide allows -- a phone, a narrow window, or simply too many
            // columns. Unbounded width has no share to divide, so it stacks
            // too.
            var each = constraints.maxWidth.isFinite
                ? (constraints.maxWidth - gap * (wanted - 1)) / wanted
                : 0.0;

            // Divided against the width it is about to be drawn at, so a
            // picture counts for the space it will actually take and a
            // column is balanced against the real page rather than against
            // a guess at one. Stacked, every column is the full width.
            var stacked = each < rule.boundedStackBelow;
            var columns = flow == null
                ? this.columns
                : flowColumns(flow!, wanted,
                    weigh: columnWeigher(
                      width: stacked
                          ? (constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : 320)
                          : each,
                      body: bodyStyle,
                      headingScales: [for (var h in guide.headings) h.scale],
                      gap: guide.blockGap,
                      image: MarkdownGuideScope.of(context) ?? guide.image,
                    ));

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    // Stacked, the divider lies across the gap rather than
                    // down it -- the same line doing the same job the other
                    // way round.
                    if (i > 0)
                      dividerWidth > 0
                          ? Container(
                              height: dividerWidth,
                              margin: EdgeInsets.symmetric(
                                  vertical: (gap - dividerWidth) / 2),
                              color: dividerInk,
                            )
                          : SizedBox(height: gap),
                    column(columns[i]),
                  ],
                ],
              );
            }

            var row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  // Equal shares. A picture set to 100% inside one fills its
                  // column, because the column is the width it is given.
                  Expanded(child: column(columns[i])),
                ],
              ],
            );

            if (dividerWidth <= 0) return row;
            // The Stack takes its size from the Row, and the painter fills
            // it -- so the lines are exactly as tall as the tallest column
            // without anything having to measure one.
            return Stack(children: [
              row,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ColumnDividers(
                      count: columns.length,
                      gap: gap,
                      width: dividerWidth,
                      color: dividerInk,
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class MarkdownArea extends StatelessWidget {
  static final _startTagBugRe = RegExp(r'^\s*(<[^>\s]+\s*>)$');

  static String _cleanupSrcText(String text) {
    // This renderer has a bug where a raw text "<foo>" needs escaping, otherwise
    // its not rendered.
    return text.replaceFirstMapped(_startTagBugRe, (m) => "\\${m[1]}");
  }

  final String text;
  final bool hasNick;
  // When true, links render with their normal styling but don't navigate on
  // tap. Used by the Feed page's AreaStyle.feedHideLinks toggle -- only
  // affects this MarkdownArea instance, not markdown rendering elsewhere
  // (chat, pages, etc).
  final bool disableLinks;
  // When true, headers/bold/italic/strikethrough all render with normal
  // body text styling instead of their usual formatting -- the markdown is
  // still parsed (embeds/links/etc still work), only the *visual*
  // formatting is flattened. Used by the Feed page's
  // AreaStyle.feedStripMarkdown toggle -- only affects this MarkdownArea
  // instance, not markdown rendering elsewhere (chat, pages, etc).
  final bool plainText;

  /// guide is the style guide to set this text in, or null for whichever
  /// the reader's theme is using.
  ///
  /// A guide rather than the name of one, which is what this used to take.
  /// Naming it meant looking it up among the built-ins, and a reader who had
  /// edited theirs has a guide that is not among them -- so every change
  /// made in Settings was saved correctly and then rendered by the built-in
  /// it had been forked from. Nothing the editor did appeared to work.
  ///
  /// Passed in only by the composer, which shows the writer the guide the
  /// post will carry rather than the one the reader happens to use.
  final MarkdownStyleGuide? guide;

  MarkdownArea(srcText, this.hasNick,
      {this.disableLinks = false,
      this.plainText = false,
      this.guide,
      super.key})
      : text = MarkdownArea._cleanupSrcText(srcText);

  Future<void> launchUrlAwait(context, url) async {
    var parsed = Uri.parse(url);
    var downSource = Provider.of<DownloadSource?>(context, listen: false);
    var pageSource = Provider.of<PagesSource?>(context, listen: false);
    var uid = downSource?.uid ?? pageSource?.uid ?? "";
    var snackbar = SnackBarModel.of(context);

    if (parsed.scheme != "" && parsed.scheme != "br") {
      if (!await launchUrl(Uri.parse(url))) {
        snackbar.error("Could not launch $url");
      }
      return;
    }

    // Handle absolute br:// link.
    if (parsed.host != "") {
      uid = parsed.host;
    }

    if (uid == "") {
      throw "Cannot follow br:// link without target UID";
    }

    var resources = Provider.of<ResourcesModel>(context, listen: false);
    var sessionID = pageSource?.sessionID ?? 0;
    var parentPageID = pageSource?.pageID ?? 0;
    try {
      await resources.fetchPage(
          uid, parsed.pathSegments, sessionID, parentPageID, null, "");
    } catch (exception) {
      snackbar.error("Unable to fetch page: $exception");
    }
  }

  // Flattens header/bold/italic/strikethrough styles down to plain body
  // text, leaving everything else (code, blockquote, links, etc) alone.
  MarkdownStyleSheet _plainStyleSheet(
      MarkdownStyleSheet base, BuildContext context) {
    final plain = DefaultTextStyle.of(context).style;
    return base.copyWith(
      h1: plain,
      h2: plain,
      h3: plain,
      h4: plain,
      h5: plain,
      h6: plain,
      strong: plain,
      em: plain,
      del: plain,
    );
  }

  /// _guidedStyleSheet is the theme's own stylesheet with the style guide
  /// folded onto it.
  ///
  /// The theme's is returned untouched for Default, which is not an
  /// optimisation but the definition of it: Default is the guide that says
  /// nothing, so folding it on is a no-op with extra steps.
  MarkdownStyleSheet _guidedStyleSheet(
      ThemeNotifier theme, BuildContext context) {
    var guide = this.guide ?? theme.markdownGuide;
    if (guide.id == defaultGuideId && !_saysAnything(guide)) {
      return theme.mdStyleSheet;
    }

    // Folded onto the *effective* sheet, not the app's sparse one.
    //
    // The app's sheet names only the few things it overrides and leaves the
    // rest null, and MarkdownBody fills those in from the Material theme --
    // "fallbackStyleSheet.merge(widget.styleSheet)". A guide that writes
    // into a null field therefore replaces a value that had not been worked
    // out yet, and whatever it worked from becomes the answer.
    //
    // The first version worked from DefaultTextStyle, which is near-black
    // with a purple cast while the theme's own text is near-white -- so
    // every guide but Default rendered its paragraphs in dark purple, and
    // links lost the theme's styling the same way. Merging first means the
    // guide adjusts colours and sizes that are already right.
    var effective = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .merge(theme.mdStyleSheet);
    return applyGuide(
      effective,
      guide,
      (role) => theme.markdownRoleColor(role),
      paletteColor: theme.markdownPaletteColor,
    );
  }

  /// _saysAnything reports whether a guide differs from the plain one.
  ///
  /// Default is the guide that changes nothing, so it can be skipped -- but
  /// only while it really is unchanged. A reader who edited Default has a
  /// guide still carrying its id, and skipping that would throw their work
  /// away every time a post was drawn.
  ///
  /// Compared against the built-in Default rather than against an empty
  /// guide. Default is not empty -- it states the heading ladder the app has
  /// always drawn, because a size in a guide is a share of the body and an
  /// unsaid one would mean "the same size as the body". An empty guide is no
  /// longer any guide the app can be using, so comparing with one made this
  /// answer yes every time.
  static bool _saysAnything(MarkdownStyleGuide guide) =>
      guide.toJson().toString() !=
      builtInGuideFor(defaultGuideId)!.toJson().toString();

  @override
  Widget build(BuildContext context) {
    return Consumer3<ThemeNotifier, PaymentsModel, MarkdownAreaModel>(
        builder: (context, theme, payments, mk, _) => _withGuide(
              theme,
              MarkdownBody(
                codeBlockMaxHeight: 200,
                // Plain text wins over a guide: it is the Feed's "strip
                // markdown" setting, which is a decision not to show
                // formatting at all, and a guide is only ever about how
                // formatting looks.
                styleSheet: plainText
                    ? _plainStyleSheet(theme.mdStyleSheet, context)
                    : _guidedStyleSheet(theme, context),
                data: text.trim(),
                extensionSet: mk.extensionSet,
                builders: mk.builders,
                onTapLink: (text, url, _) {
                  if (disableLinks) return;
                  launchUrlAwait(context, url);
                },
                inlineSyntaxes: mk.inlineSyntaxes,
                blockSyntaxes: mk.blockSyntaxes,
              ),
            ));
  }

  /// _withGuide puts the guide's picture rules where the embeds can see
  /// them, and nothing at all around text that has no guide.
  Widget _withGuide(ThemeNotifier theme, Widget child) {
    var guide = this.guide ?? theme.markdownGuide;
    // Default with nothing changed is the app as it was, so it gets no scope
    // at all rather than one that happens to match.
    if (guide.id == defaultGuideId &&
        guide.image == const ImageRule() &&
        guide.columns == const ColumnRule() &&
        guide.cards == const CardRule()) {
      return child;
    }
    return MarkdownGuideScope(
        image: guide.image,
        columns: guide.columns,
        cards: guide.cards,
        child: child);
  }
}

class Downloadable extends StatelessWidget {
  final String tip;
  final String fid;
  final Widget child;
  const Downloadable(this.tip, this.fid, this.child, {super.key});

  void download(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    try {
      var downloads = Provider.of<DownloadsModel>(context, listen: false);
      var source = Provider.of<DownloadSource?>(context, listen: false);
      var page = Provider.of<PagesSource?>(context, listen: false);
      var uid = source?.uid ?? page?.uid ?? "";
      if (uid == "") {
        throw "UID in parent DownloadsSource/PagesSource not found";
      }
      await downloads.getUnknownUserFile(uid, fid);
      snackbar.success("Added $fid to download queue");
    } catch (exception) {
      snackbar.error("Unable to start download: $exception");
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: fid != "" ? () => download(context) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: child,
          ),
        ),
      );
}

// chatImageConstraints resolves the configured chat image size setting into
// concrete BoxConstraints, given the width available to the image within its
// chat bubble (as reported by an enclosing LayoutBuilder).
BoxConstraints chatImageConstraints(String size, double availableWidth) {
  switch (size) {
    case "half":
      return BoxConstraints(
          maxWidth: availableWidth.isFinite ? availableWidth * 0.5 : 250);
    case "full":
      return BoxConstraints(
          maxWidth: availableWidth.isFinite ? availableWidth : 250);
    default:
      return const BoxConstraints(maxHeight: 250, maxWidth: 250);
  }
}

class ImageMd extends StatelessWidget {
  final String tip;
  final Uint8List imgContent;
  final String type;
  final String? name;
  const ImageMd(this.tip, this.imgContent, this.type, {this.name, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var chatImageSize = theme.chatImageSize;
    // The style guide's picture rules, when this markdown has one. Null is
    // every other case -- chat, and posts read under Default -- and keeps
    // the sizes and corners this drew before guides existed.
    var rule = MarkdownGuideScope.of(context);

    var image = Image.memory(
      imgContent,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        debugPrint("ImageMd unable to decode image: $error");
        return const SizedBox.shrink();
      },
    );

    var corners = BorderRadius.all(
        Radius.circular(rule == null ? 8.0 : rule.boundedRadius));
    var border = rule == null || rule.boundedBorder == 0
        ? null
        : Border.all(
            color: rule.borderInk.resolve(theme.markdownRoleColor,
                    paletteColor: theme.markdownPaletteColor) ??
                theme.colors.outlineVariant,
            width: rule.boundedBorder);

    Widget sized = LayoutBuilder(
      builder: (context, constraints) {
        // Chat, which has no guide: a bound on how large a picture may be
        // drawn, exactly as it always was.
        if (rule == null) {
          return ConstrainedBox(
            constraints:
                chatImageConstraints(chatImageSize, constraints.maxWidth),
            child: ClipRRect(borderRadius: corners, child: image),
          );
        }

        // The guide's share of the column it is in, so a picture keeps its
        // proportion of the page at any window size.
        //
        // A width, not a maximum width. As a maximum it was only ever a cap:
        // an Image set to contain draws at its natural size whenever that
        // fits, so a picture narrower than the column ignored the setting
        // entirely and 100% did not fill the post -- it meant "up to the
        // full width", which every picture smaller than the column was
        // already under. The height follows from the width, the aspect
        // ratio being the picture's own.
        //
        // Unbounded width has no share to take, so the picture is left at
        // its natural size rather than given an infinite one.
        return SizedBox(
          width: constraints.maxWidth.isFinite
              ? constraints.maxWidth * rule.boundedWidth / 100
              : null,
          child: ClipRRect(borderRadius: corners, child: image),
        );
      },
    );

    if (border != null) {
      sized = Container(
        decoration: BoxDecoration(border: border, borderRadius: corners),
        child: sized,
      );
    }

    // A gesture rather than an InkWell: the picture is the thing you are
    // looking at, and it needs no highlight drawn under it to say so.
    //
    // The highlight was drawn over the whole tappable area, which includes
    // the space above and below the picture that the style guide's Gap
    // setting puts there -- so it stood off the picture by the gap at the
    // top and bottom and by two pixels at the sides, a lopsided box that
    // grew as the gap was widened. The pointer still turns to a hand, which
    // is what actually says the picture can be opened.
    return Tooltip(
      message: tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            showDialog(
                context: context,
                builder: (_) => ImageDialog(imgContent, type, name: name));
          },
          child: Container(
            margin: rule == null
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
                : EdgeInsets.symmetric(horizontal: 2, vertical: rule.gap),
            alignment: rule == null ? null : _alignOf(rule.align),
            child: sized,
          ),
        ),
      ),
    );
  }

  static Alignment _alignOf(MarkdownAlign align) => switch (align) {
        MarkdownAlign.center => Alignment.topCenter,
        MarkdownAlign.right => Alignment.topRight,
        MarkdownAlign.left || MarkdownAlign.inherit => Alignment.topLeft,
      };
}

class AvifMd extends StatelessWidget {
  final String tip;
  final Uint8List imgContent;
  const AvifMd(this.tip, this.imgContent, {super.key});

  @override
  Widget build(BuildContext context) {
    var chatImageSize = ThemeNotifier.of(context).chatImageSize;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(30)),
        onTap: () {
          showDialog(context: context, builder: (_) => AvifDialog(imgContent));
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
            child: LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints:
                    chatImageConstraints(chatImageSize, constraints.maxWidth),
                child: Image(
                  image: AvifImage.memory(imgContent).image,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint("AvifMd unable to decode image: $error");
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PreformattedElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
            controller: ScrollController(keepScrollOffset: false),
            child: Consumer<ThemeNotifier>(
                builder: (context, theme, child) => Text.rich(
                      TextSpan(text: text.text),

                      // Overwrite <pre> style to use the same as code
                      // (Markdown component uses same as <p> by default).
                      style: theme.mdStyleSheet.code,
                    ))),
      ),
      const SizedBox(height: 10),
      Builder(
          builder: (context) => TextButton(
              onPressed: () => showDialog(
                  context: context,
                  builder: (context) => TextDialog(text.text)),
              child: const Text("View"))),
    ]);
  }
}

class CodeblockMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(text: text.text),
      style: preferredStyle,
    );
  }
}

class PDFMarkdownElementBuilder extends MarkdownElementBuilder {
  Future<String> _tempPDFDir() async {
    bool isMobile = Platform.isIOS || Platform.isAndroid;
    String base = isMobile
        ? (await getApplicationCacheDirectory()).path
        : (await getDownloadsDirectory())?.path ?? "";
    return path.join(base, "feedimages");
  }

  void _handleItemTap(BuildContext context, String value, Uint8List pdfBytes,
      String filename) async {
    switch (value) {
      case "save":
        var fname = await FilePicker.platform.saveFile(
              dialogTitle: "Select filename",
              fileName: filename != "" ? filename : "document.pdf",
            ) ??
            "";

        if (fname == "") {
          return;
        }

        File(fname).writeAsBytesSync(pdfBytes);
        context.mounted
            ? showSuccessSnackbar(context, "Written PDF file $fname")
            : null;
        break;

      case "share":
        var fname = filename != "" ? filename : "document.pdf";
        var dir = await _tempPDFDir();
        if (!Directory(dir).existsSync()) {
          Directory(dir).createSync(recursive: true);
        }
        fname = path.join(dir, fname);
        File(fname).writeAsBytesSync(pdfBytes);
        Share.shareXFiles([XFile(fname)], text: "Pdf");
        break;
    }
  }

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List pdfBytes;
    String filename = element.attributes["filename"] ?? "";
    try {
      pdfBytes = const Base64Decoder().convert(element.textContent);
      if (pdfBytes.isEmpty) throw "Empty PDF";
    } catch (exception) {
      return Text("Unable to decode pdf: $exception");
    }

    try {
      return Builder(
          builder: (context) => ContextMenu(
              handleItemTap: (value) {
                _handleItemTap(context, value, pdfBytes, filename);
              },
              items: [
                if (!Platform.isAndroid)
                  const PopupMenuItem(
                      value: "save", child: Text("Save to file")),
                if (Platform.isAndroid || Platform.isIOS)
                  const PopupMenuItem(value: "share", child: Text("Share")),
              ],
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 400, maxHeight: 400),
                  child: PdfViewer(
                    PdfDocumentRefData(pdfBytes, sourceName: "data"),
                  ))));
    } catch (exception) {
      debugPrint("Unable to decode pdf: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class AudioElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List audioBytes;
    try {
      audioBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode pdf: $exception");
    }

    // return Text("Audio bytes ${audioBytes.length}");
    return Consumer<AudioModel>(
        builder: (context, audio, child) => AudioElement(
            mimeType: element.attributes["type"] ?? "audio/ogg",
            audioBytes: audioBytes,
            audio: audio));
  }
}

class DownloadLinkElementBuilder extends MarkdownElementBuilder {
  DownloadLinkElementBuilder();

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var download = element.attributes["fid"] ?? "";
    var tip = "Click to download file $download";
    // Set as the link it is. With no style of its own it fell through to
    // Material's stock text colour -- the seed purple, which is not in the
    // palette and appears nowhere else in the app on purpose.
    return Downloadable(
      tip,
      download,
      Builder(
        builder: (context) => Text(
          element.textContent,
          style: ThemeNotifier.of(context).markdownLinkStyle(preferredStyle),
        ),
      ),
    );
  }
}

class QuoteMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _QuotedPostCard(
      from: element.attributes["from"] ?? "",
      postId: element.attributes["post"] ?? "",
    );
  }
}

class _QuotedPostCard extends StatefulWidget {
  final String from;
  final String postId;
  const _QuotedPostCard({required this.from, required this.postId});
  @override
  State<_QuotedPostCard> createState() => _QuotedPostCardState();
}

class _QuotedPostCardState extends State<_QuotedPostCard> {
  bool _requested = false;

  Widget _shell(BuildContext context, Widget child, VoidCallback? onTap) {
    final theme = ThemeNotifier.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: theme.surfaceColor(SurfaceColor.surfaceContainer),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.surfaceColor(SurfaceColor.surfaceContainerHigh)),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = Provider.of<FeedModel>(context);
    final client = Provider.of<ClientModel>(context, listen: false);
    final post = feed.getPost(widget.from, widget.postId);
    final theme = ThemeNotifier.of(context);

    if (post == null) {
      if (!_requested && widget.from.isNotEmpty && widget.postId.isNotEmpty) {
        _requested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          feed.getUserPost(widget.from, widget.postId);
        });
      }
      return _shell(
        context,
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text("Loading quoted post...",
              style: TextStyle(
                  fontSize: 13,
                  color: theme.textColor(TextColor.onSurfaceVariant))),
        ),
        null,
      );
    }

    var nick = client.getNick(widget.from);
    if (nick == "") nick = post.summ.authorNick;
    if (nick == "") nick = widget.from;

    return _shell(
      context,
      Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SizedBox(
                  width: 22,
                  height: 22,
                  child: UserAvatarFromID(client, widget.from, nick: nick)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(nick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textColor(TextColor.onSurface))),
              ),
            ]),
            const SizedBox(height: 6),
            Provider<DownloadSource>(
              create: (_) => DownloadSource(widget.from),
              child: MarkdownArea(post.content, false),
            ),
          ],
        ),
      ),
      () => FeedScreen.showPost(context, post),
    );
  }
}

class ImageMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List imgBytes;
    try {
      imgBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode image: $exception");
    }

    var alt = element.attributes["alt"] ?? "";
    var download = element.attributes["fid"] ?? "";
    var tip = "";
    if (alt != "") {
      tip = alt;
      if (download != "") {
        tip += "\n\n";
      }
    }
    if (download != "") {
      tip += "Click to download file $download";
    }
    var type = element.attributes["type"] ?? "";
    var name = element.attributes["name"];

    try {
      return ImageMd(tip, imgBytes, type, name: name);
    } catch (exception) {
      debugPrint("Unable to decode image: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class AVIFElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List imgBytes;
    try {
      imgBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode avif: $exception");
    }

    var alt = element.attributes["alt"] ?? "";
    var download = element.attributes["fid"] ?? "";
    var tip = "";
    if (alt != "") {
      tip = alt;
      if (download != "") {
        tip += "\n\n";
      }
    }
    if (download != "") {
      tip += "Click to download file $download";
    }

    try {
      return AvifMd(tip, imgBytes);
    } catch (exception) {
      debugPrint("Unable to decode avif: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class _PayReqBtn extends StatefulWidget {
  final PaymentsModel payments;
  final String invoice;
  const _PayReqBtn(this.payments, this.invoice);

  @override
  State<_PayReqBtn> createState() => __PayReqBtnState();
}

class __PayReqBtnState extends State<_PayReqBtn> {
  late PaymentInfo info;

  void payInfoChanged() {
    setState(() {});
  }

  void attemptPayment() {
    info.attemptPayment();
  }

  @override
  void initState() {
    super.initState();
    info = widget.payments.decodedInvoice(widget.invoice);
    info.addListener(payInfoChanged);
  }

  @override
  void dispose() {
    info.removeListener(payInfoChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (info.decoded == null) {
      return const ElevatedButton(
          onPressed: null, child: Text("Decoding invoice..."));
    }

    String amt = formatDCR(info.decoded?.amount ?? 0);

    if (info.status == PaymentStatus.succeeded) {
      return ElevatedButton(
          onPressed: null, child: Text("Succeeded paying $amt"));
    }

    if (info.status == PaymentStatus.errored) {
      return ElevatedButton(
          onPressed: null, child: Text("Errored paying $amt: ${info.err}"));
    }

    if (info.status == PaymentStatus.inflight) {
      return ElevatedButton(onPressed: null, child: Text("Paying $amt"));
    }

    if (info.decoded?.expired ?? false) {
      return ElevatedButton(
          onPressed: null, child: Text("Invoice $amt expired"));
    }

    return ElevatedButton(onPressed: attemptPayment, child: Text("Pay $amt"));
  }
}

class _LNPayURLElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Consumer<PaymentsModel>(
        builder: (context, payments, child) =>
            _PayReqBtn(payments, element.textContent));
  }
}
