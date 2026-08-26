import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/markdown_title.dart';
import 'package:bruig/components/feed/page_image.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_header.dart is the banner across the top of a page.
//
// A banner is rows, and a row is one or two cells. Deliberately no more than
// that: the shapes people actually build -- a logo beside a title, a bar of
// links under them -- all fit, and every shape past it is one that has to be
// made to work at a width its author never saw.
//
// Each row is a fixed height, given in its own marker, and everything in it
// is sized to that. That is what makes a banner resize predictably: a logo
// is as tall as its row, a title is set to fill its row, and neither changes
// the height of anything when the window does.

/// HeaderRowMode is how a row divides its width.
///
/// split is a different layout from the rest rather than a setting on it:
/// two cells pushed to opposite edges, against cells sitting together
/// somewhere. Trying to express both as alignments of one row is what made
/// the old header's gaps grow with the window.
///
/// The other three take one cell or two. Two sit together in the order they
/// were written, a fixed gap apart -- which is a logo and the title beside
/// it, the commonest thing a banner holds and the one shape split cannot
/// make.
enum HeaderRowMode {
  split,
  center,
  left,
  right;

  static HeaderRowMode parse(String? raw) {
    var t = (raw ?? "").trim().toLowerCase();
    for (var m in HeaderRowMode.values) {
      if (m.name == t) return m;
    }
    if (t == "centre") return HeaderRowMode.center;
    return HeaderRowMode.left;
  }

  Alignment get alignment => switch (this) {
        HeaderRowMode.center => Alignment.center,
        HeaderRowMode.right => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };
}

/// HeaderRow is one row of a banner.
@immutable
class HeaderRow {
  final double height;
  final HeaderRowMode mode;

  /// cells is one cell, or two in [HeaderRowMode.split].
  final List<String> cells;

  /// flush takes the banner's padding away from this row, so what is in it
  /// runs edge to edge and, at the top or bottom, sits hard against that
  /// edge.
  ///
  /// Which is what a bar of links along the top of a banner is: a strip the
  /// full width of it, not a row of words inset from it like the rest.
  final bool flush;

  /// group keeps two cells together as one thing and places the pair, in
  /// place of the second taking whatever the first leaves.
  ///
  /// Two different layouts, not a setting on one. Without it a row is a
  /// logo and a title that runs on to the far edge; with it the two sit
  /// beside each other and the pair goes where the mode says -- which is
  /// what centring a logo and its title means, and cannot be had from a
  /// second cell that fills the rest of the row.
  final bool group;

  const HeaderRow({
    required this.height,
    required this.mode,
    required this.cells,
    this.flush = false,
    this.group = false,
  });

  /// maxHeight is the tallest a single row may be. Past this it is not a
  /// banner on a page, it is the page.
  static const maxHeight = 400.0;
  static const defaultHeight = 96.0;
}

/// maxHeaderRows is how many rows a banner may have.
const int maxHeaderRows = 2;

/// maxRowCells is how many cells a row may have.
const int maxRowCells = 2;

/// HeaderBlockSyntax reads a page's banner.
///
///     --header--
///     background: --embed[type=image/png,data=...]--
///     --row[96,split]--
///     left: ![](logo)
///     right: # My Site
///     --/row--
///     --row[44,center]--
///     --include[navigation]--
///     --/row--
///     --/header--
///
/// A row's marker carries its height and how it divides. A row that names
/// neither is [HeaderRow.defaultHeight] and left-aligned.
///
/// A bar of links is a fragment in a row, with nothing special about it.
/// That is the point of rows: what used to be a "nav" field with a "navat"
/// beside it is now a row like any other, placed the way any other row is.
class HeaderBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--header--\s*$');
  static final _close = RegExp(r'^\s*--/header--\s*$');
  static final _rowOpen = RegExp(r'^\s*--row(?:\[([^\]]*)\])?--\s*$');
  static final _rowClose = RegExp(r'^\s*--/row--\s*$');
  static final _field = RegExp(r'^\s*(\w+)\s*:\s*(.*)$');

  /// _cellFields are the two halves of a split row.
  static const cellFields = ["left", "right"];

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();

    var fields = <String, List<String>>{};
    var rows = <HeaderRow>[];
    String? current;

    while (!parser.isDone) {
      var at = parser.current.content;
      if (_close.hasMatch(at)) {
        parser.advance();
        break;
      }
      var rowMatch = _rowOpen.firstMatch(at);
      if (rowMatch != null) {
        var row = _parseRow(parser, rowMatch.group(1));
        if (rows.length < maxHeaderRows) rows.add(row);
        current = null;
        continue;
      }

      // A field of the banner itself, whose value runs to the next field --
      // a background is an embed, which is one very long line, but anything
      // included here is not.
      var m = _field.firstMatch(at);
      var key = m?.group(1)?.toLowerCase();
      if (m != null && key != null && headerFields.contains(key)) {
        current = key;
        fields[current] = [m.group(2)!.trim()];
      } else if (current != null) {
        fields[current]!.add(at);
      }
      parser.advance();
    }

    var element = md.Element.text("header", "");
    fields.forEach((k, lines) {
      var value = lines.join("\n").trim();
      if (value.isNotEmpty) element.attributes[k] = value;
    });
    element.attributes["rows"] = "${rows.length}";
    for (var i = 0; i < rows.length; i++) {
      element.attributes["r${i}h"] = "${rows[i].height}";
      element.attributes["r${i}m"] = rows[i].mode.name;
      if (rows[i].flush) element.attributes["r${i}f"] = "1";
      if (rows[i].group) element.attributes["r${i}g"] = "1";
      for (var c = 0; c < rows[i].cells.length; c++) {
        element.attributes["r${i}c$c"] = rows[i].cells[c];
      }
    }
    // Wrapped in a paragraph for the same reason a run of columns is: the
    // builder that draws this is reached through flutter_markdown's inline
    // path, which expects to be inside a block.
    return md.Element("p", [element]);
  }

  /// _parseRow reads one row, from its marker to its close.
  HeaderRow _parseRow(md.BlockParser parser, String? args) {
    var height = HeaderRow.defaultHeight;
    var mode = HeaderRowMode.left;
    var flush = false;
    var group = false;
    for (var arg in (args ?? "").split(",")) {
      var t = arg.trim();
      var n = double.tryParse(t);
      if (n != null) {
        height = n.clamp(16, HeaderRow.maxHeight);
      } else if (t.toLowerCase() == "flush") {
        flush = true;
      } else if (t.toLowerCase() == "group") {
        group = true;
      } else if (t.isNotEmpty) {
        mode = HeaderRowMode.parse(t);
      }
    }
    parser.advance();

    var cells = <String, List<String>>{};
    var loose = <String>[];
    String? current;
    while (!parser.isDone) {
      var at = parser.current.content;
      if (_rowClose.hasMatch(at)) {
        parser.advance();
        break;
      }
      var m = _field.firstMatch(at);
      var key = m?.group(1)?.toLowerCase();
      if (m != null && key != null && cellFields.contains(key)) {
        current = key;
        cells[current] = [m.group(2)!.trim()];
      } else if (current != null) {
        cells[current]!.add(at);
      } else {
        // Not a named cell: the row holds one thing, which is what a bar of
        // links in a row looks like.
        loose.add(at);
      }
      parser.advance();
    }

    List<String> out;
    if (cells.isEmpty) {
      var one = loose.join("\n").trim();
      out = one.isEmpty ? const [] : [one];
    } else {
      out = [
        for (var f in cellFields)
          if (cells[f] != null) cells[f]!.join("\n").trim(),
      ].where((c) => c.isNotEmpty).toList();
      if (out.length > maxRowCells) out = out.sublist(0, maxRowCells);
    }
    return HeaderRow(
        height: height, mode: mode, cells: out, flush: flush, group: group);
  }
}

/// headerFields is every field the banner itself understands, as opposed to
/// its rows. A closed list, because it is what tells a field from a line
/// that happens to have a colon in it.
const List<String> headerFields = [
  "background",
  ...titleStyleFields,
];

/// headerRowSpaces says where a banner puts a space, reading down: before
/// each row, and one more for after the last.
///
/// A space goes at the banner's own edge unless the row there is flush, and
/// between two rows when one of them is flush and the other is not. So a
/// strip along an edge loses only its own inset, and the row beside it keeps
/// as much room below as it has above -- which it did not when a flush row
/// took the space between them with it.
///
/// Two ordinary rows have nothing between them, as before: rows are stacked
/// and their heights are what a writer set.
List<bool> headerRowSpaces(List<HeaderRow> rows) {
  if (rows.isEmpty) return const [];
  return [
    !rows.first.flush,
    for (var i = 1; i < rows.length; i++) rows[i].flush != rows[i - 1].flush,
    !rows.last.flush,
  ];
}

/// headerRowsOf reads the rows back out of a parsed element.
List<HeaderRow> headerRowsOf(Map<String, String> a) {
  var count = int.tryParse(a["rows"] ?? "") ?? 0;
  return [
    for (var i = 0; i < count; i++)
      HeaderRow(
        height: double.tryParse(a["r${i}h"] ?? "") ?? HeaderRow.defaultHeight,
        mode: HeaderRowMode.parse(a["r${i}m"]),
        flush: a["r${i}f"] == "1",
        group: a["r${i}g"] == "1",
        cells: [
          for (var c = 0; c < maxRowCells; c++)
            if (a["r${i}c$c"] != null) a["r${i}c$c"]!,
        ],
      ),
  ];
}

/// embedImage pulls the picture out of an --embed[...]-- string.
///
/// The background and a logo are drawn rather than rendered: they have to
/// fill a box and be cropped or scaled to it, which is a decision about the
/// box and not something the markdown renderer can be asked for. Returns
/// null for anything that is not an inline image, which is then not drawn.
({Uint8List bytes, String mime})? embedImage(String? value) {
  if (value == null) return null;
  var m = RegExp(r'--embed\[(.*?)\]--').firstMatch(value);
  if (m == null) return null;

  var parms = <String, String>{};
  for (var part in (m.group(1) ?? "").split(",")) {
    var at = part.indexOf("=");
    if (at == -1) continue;
    parms[part.substring(0, at)] = part.substring(at + 1);
  }
  var mime = parms["type"] ?? "";
  if (!mime.startsWith("image/")) return null;
  var data = parms["data"];
  if (data == null || data.isEmpty) return null;
  try {
    return (bytes: base64Decode(data), mime: mime);
  } catch (_) {
    // A truncated embed, or one still holding the "[content abc]" reference
    // a document carries while it is being written. Neither is a picture.
    return null;
  }
}

/// HeaderCellAlign tells whatever is drawn inside a banner's cell which way
/// the row it is in runs.
///
/// A block fills the width it is given, so a bar of links in a centred row
/// would start at the left of it and look nothing like centred. The bar
/// reads this and lays its links out the same way -- see markdown_nav.dart.
/// An InheritedWidget rather than an argument because what is between the
/// two is the markdown renderer, which knows nothing about banners.
class HeaderCellAlign extends InheritedWidget {
  final Alignment alignment;
  const HeaderCellAlign(
      {required this.alignment, required super.child, super.key});

  static Alignment? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderCellAlign>()?.alignment;

  @override
  bool updateShouldNotify(HeaderCellAlign old) => old.alignment != alignment;
}

/// HeaderCellRoom tells whatever is drawn inside a banner's cell how much
/// height that cell actually has.
///
/// A block in a cell is drawn at its own size and clipped to the row -- see
/// _cell, where that is the deliberate choice: shrinking a bar of links to
/// fit a short row would set its writing at a different size from everything
/// else in the banner.
///
/// But a banner drawn in a narrow window scales its rows down, and a block
/// that cannot know that goes on drawing itself full size into a row half its
/// height. What is left is a strip through the middle of some words. So the
/// room is told rather than implied: the cell's own constraints cannot carry
/// it, because the block is deliberately given all the height it asks for.
class HeaderCellRoom extends InheritedWidget {
  final double height;
  const HeaderCellRoom({required this.height, required super.child, super.key});

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderCellRoom>()?.height;

  @override
  bool updateShouldNotify(HeaderCellRoom old) => old.height != height;
}

/// headerPicture is the picture a banner field names, whichever way it names
/// one.
///
/// Two ways, because a banner takes its pictures from wherever the page took
/// them. An --embed[...]-- carries its own bytes and is what a post uses. A
/// site keeps its pictures as files instead, so a page names one by path --
/// ![](assets/banner.jpg) -- and that is what the Pictures list hands over
/// to paste in. Understanding only the first meant a background set from the
/// site's own pictures silently drew nothing: the file was there, served,
/// and named correctly, and the banner behaved as though the line were
/// blank.
({Uint8List bytes, String mime})? headerPicture(
    BuildContext context, String? value) {
  if (value == null) return null;

  var embedded = embedImage(value);
  if (embedded != null) return embedded;

  var m = RegExp(r'!\[[^\]]*\]\(([^)\s]+)\)').firstMatch(value);
  var path = m?.group(1);
  if (path == null || !isPageAssetPath(path)) return null;

  var bytes = pageAssetBytes(context, path);
  if (bytes == null) return null;
  return (bytes: bytes, mime: pageAssetMime(path));
}

/// headerImage draws a picture sized to the room it has.
Widget headerImage(({Uint8List bytes, String mime}) image) =>
    isSvgMime(image.mime)
        ? SvgPicture.memory(image.bytes, fit: BoxFit.contain)
        : Image.memory(image.bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox.shrink());

class HeaderMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      _MarkdownHeader(fields: element.attributes);
}

class _MarkdownHeader extends StatelessWidget {
  final Map<String, String> fields;
  const _MarkdownHeader({required this.fields});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.headerOf(context) ?? const HeaderRule();
    var rows = headerRowsOf(fields);
    if (rows.isEmpty) return const SizedBox.shrink();

    var titleStyle = HeaderTextStyle.parse(fields);
    var background = headerPicture(context, fields["background"]);
    // The whole banner scales together in a narrow window, rather than each
    // thing in it coping alone.
    //
    // Everything is sized from the rows, so scaling the rows scales the
    // writing and the pictures with them and the proportions hold. Left to
    // themselves the rows stayed the height they were written at whatever
    // room there was, and the title absorbed the entire difference by
    // condensing -- which is why a logo and a title looked too big for the
    // banner on a small screen, and why the writing was cut on a smaller
    // one.
    return LayoutBuilder(builder: (context, constraints) {
      var scale = rule.scaleFor(constraints.maxWidth);
      var padding = rule.boundedPadding * scale;
      var gap = rule.boundedGap * scale;
      // Where the vertical spaces go. A flush row gives up its own inset
      // from the banner's edge and nothing else -- the row beside it keeps
      // the space between them, so it still sits with as much room below as
      // above. Taking that away as well was what left the writing crowded
      // against a strip along the bottom.
      var spaces = headerRowSpaces(rows);
      var total = rows.fold<double>(0, (t, r) => t + r.height * scale) +
          spaces.where((s) => s).length * padding;

      // No room of its own above or below. The gap separates the rows
      // inside a banner -- that is what it says it is, and it is what it
      // does at the rows below -- and using it out here as well gave the
      // banner a second, undocumented margin. Nothing showed until a page
      // took a background, at which point it read as a band above the
      // banner that no padding or margin on the page could reach.
      //
      // What separates a banner from what follows it is what separates any
      // two blocks: the renderer puts that between them already.
      return ClipRRect(
        borderRadius: BorderRadius.circular(rule.boundedRadius),
        // As tall as its rows and no taller. The rows are what a writer
        // sets, so the banner follows them rather than the other way about.
        child: SizedBox(
          height: total,
          child: Stack(fit: StackFit.expand, children: [
            if (background != null)
              Positioned.fill(
                // Cover, not contain: a banner fills its space and is
                // cropped to it, which is what a background is.
                child: isSvgMime(background.mime)
                    ? SvgPicture.memory(background.bytes, fit: BoxFit.cover)
                    : Image.memory(background.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink()),
              ),
            // A wash over the picture, so writing stays readable on top of
            // whatever was chosen. Skipped where there is no picture, since
            // it would only mute the page's own background.
            if (background != null && rule.scrim > 0)
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colors.surface
                      .withValues(alpha: rule.scrim.clamp(0, 1)),
                ),
              ),
            // The padding goes on each row rather than round the lot, so
            // a flush row can go without it and run edge to edge. The
            // space above the first row and below the last goes the same
            // way: a strip along the top of a banner has nothing above it.
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (spaces[i]) SizedBox(height: padding),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: rows[i].flush ? 0 : padding),
                    child: _HeaderRow(
                        row: rows[i],
                        style: titleStyle,
                        rule: rule,
                        scale: scale,
                        gap: gap),
                  ),
                ],
                if (spaces.last) SizedBox(height: padding),
              ],
            ),
          ]),
        ),
      );
    });
  }
}

/// _HeaderRow draws one row at the height it was given.
class _HeaderRow extends StatelessWidget {
  final HeaderRow row;
  final HeaderTextStyle style;
  final HeaderRule rule;

  /// scale is how much of its written size the banner is being drawn at.
  final double scale;

  /// gap is the space between two cells, already scaled.
  final double gap;

  const _HeaderRow({
    required this.row,
    required this.style,
    required this.rule,
    required this.scale,
    required this.gap,
  });

  double get height => row.height * scale;

  /// _isMarkdown is whether a cell holds a block rather than a title.
  ///
  /// A title is one line of words; anything on several lines, or opening
  /// with a marker, is a block -- a bar of links, most often, since a
  /// fragment is replaced with the whole of itself before this is read.
  /// Told apart because they are drawn by different things: a title is set
  /// to the row and condensed to fit, a block is rendered.
  static bool _isMarkdown(String value) =>
      value.contains("\n") || RegExp(r'^\s*--\w').hasMatch(value);

  Widget _cell(BuildContext context, String value, Alignment within) {
    var image = headerPicture(context, value);
    if (image != null) return headerImage(image);

    if (_isMarkdown(value)) {
      // Clipped rather than scaled: a block has its own sizes, and shrinking
      // a bar of links to fit a short row would make its writing a different
      // size from everything else in the banner. The row's height wins, and
      // what does not fit is not shown.
      return HeaderCellRoom(
        height: height,
        child: HeaderCellAlign(
          alignment: within,
          child: ClipRect(
            child: OverflowBox(
              alignment: within,
              maxHeight: double.infinity,
              child: MarkdownArea(value, false),
            ),
          ),
        ),
      );
    }

    return HeaderText(
      text: value,
      style: style,
      // The row's height is what the writing is set to, which is what makes
      // a title sit level with the logo beside it without either being told
      // about the other.
      fitTo: height,
      within: within,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (row.cells.isEmpty) {
      content = const SizedBox.shrink();
    } else if (row.mode == HeaderRowMode.split && row.cells.length > 1) {
      // Two cells at opposite edges. Each takes half, so a long title
      // condenses within its half rather than crowding the other out --
      // see HeaderText.
      content = Row(children: [
        Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: _cell(context, row.cells[0], Alignment.centerLeft))),
        SizedBox(width: gap),
        Expanded(
            child: Align(
                alignment: Alignment.centerRight,
                child: _cell(context, row.cells[1], Alignment.centerRight))),
      ]);
    } else if (row.cells.length > 1) {
      // Two cells together, in the order they were written, a fixed gap
      // apart. The gap is fixed rather than shared out, or a logo and the
      // title beside it would drift apart as the window widened -- which is
      // what split is for when that is wanted.
      //
      // The second takes what the first leaves, whichever way the row runs.
      // Holding each to half meant a title in a centred row was cropped
      // while the room it needed sat empty on the other side of it, and a
      // row's alignment is about where its writing sits, not how much of
      // the banner it may use.
      var first = _cell(context, row.cells[0], Alignment.centerLeft);
      var second = _cell(context, row.cells[1], row.mode.alignment);

      content = LayoutBuilder(builder: (context, constraints) {
        var room = constraints.maxWidth - gap;

        if (row.group) {
          // Sized to what is in them and placed as one thing, so a logo and
          // its title can sit together in the middle of a banner.
          //
          // The room is divided rather than one taking what the other
          // leaves: a pair meant to be seen together has neither of them
          // running off to an edge, and a third to the first keeps a logo a
          // logo.
          return Align(
            alignment: row.mode.alignment,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: room / 3),
                child: first,
              ),
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: room * 2 / 3),
                child: second,
              ),
            ]),
          );
        }

        return Row(children: [
          // The first is still bounded, or a wide logo would leave the
          // second nothing.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: room / 2),
            child: first,
          ),
          SizedBox(width: gap),
          Expanded(child: Align(alignment: row.mode.alignment, child: second)),
        ]);
      });
    } else {
      content = Align(
        alignment: row.mode.alignment,
        child: _cell(context, row.cells.first, row.mode.alignment),
      );
    }

    return SizedBox(height: height, child: content);
  }
}
