import 'dart:math' as math;

import 'package:bruig/components/feed/markdown_flow.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_blocks.dart is columns and callout cards: two block syntaxes this
// app adds, and the widgets that draw them.
//
// Markdown has neither in any dialect worth following, so both are written in
// the shape the app already uses for what Markdown has no word for -- a
// marker on a line of its own, matching --form-- next door. A reader whose
// client does not know them sees the markers as ordinary lines with the
// writing still in the right order underneath, which is the most a format
// nobody else implements can promise.
//
// Where the breaks fall is worked out in markdown_flow.dart. This file is
// only the drawing.

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

/// GridBlockSyntax reads a picture gallery.
///
/// Imported from Decred Pulse, which added it to the page format Bison Relay
/// serves. A run of pictures with a caption after each one:
///
///     --grid--
///     --embed[type=image/png,data=...]--
///     ### The first one
///     What it is.
///     --embed[type=image/png,data=...]--
///     ### The second one
///     --/grid--
///
/// Every picture starts a cell and takes the writing after it as its caption,
/// so a gallery is written the way it reads -- picture, words, picture, words
/// -- with no separator to keep in step. Anything before the first picture is
/// a cell of its own, which is where a heading over the gallery goes.
///
/// --grid[n]-- sets how many across, matching --columns[n]-- and --cards[n]--
/// next door. Decred Pulse spells the one-across case --grid2-- and gives it
/// a separate implementation; here it is --grid[1]--, since that is what it
/// is, and it comes out for free.
///
/// --grid2-- is still read, and means --grid[1]--, so a page written for
/// Decred Pulse renders here as its author laid it out. Importing a format
/// and then not reading what is already written in it would be a poor
/// import.
///
/// Cells hold markdown, not text: each is rendered by a MarkdownArea of its
/// own, so a heading, a list or a link inside a cell is the same as outside
/// one. A reader whose client does not know the markers sees them as
/// ordinary lines with the pictures and writing still in order underneath.
class GridBlockSyntax extends md.BlockSyntax {
  /// The settings in the brackets: how many across, and anything written
  /// key=value after it -- --grid[3, gap=6]--.
  ///
  /// The count is still a bare number, which is what every gallery written
  /// before this says, and what a writer wanting three across should have to
  /// type. The rest is for the one thing a page cannot otherwise reach: how
  /// far apart the cells are, which the reader's guide decides. A shop front
  /// is a grid of cards laid out by a page rather than a gallery of
  /// photographs read by a person, and the two do not want the same gap.
  static final _open = RegExp(r'^\s*--grid(2)?(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/grid2?--\s*$');

  /// _picture is what starts a new cell: an image embed, or a markdown
  /// image. A download embed of something that is not a picture does not --
  /// it belongs in the caption of the cell it is written in.
  static final _picture = RegExp(r'--embed\[[^\]]*type=image/|!\[[^\]]*\]\(');

  /// _cell is a cell said out loud: --cell-- starts one, whatever is in it.
  ///
  /// Dividing at each picture is right for a gallery, which is what this
  /// block was written for: the pictures are the cells and the writing under
  /// one is its caption. It is wrong for anything where the picture is not
  /// first -- a shop front whose cards put the picture under the writing, or
  /// behind all of it -- because there the writing of one cell runs into the
  /// end of the last.
  ///
  /// So a writer can say where a cell starts instead. The marker is consumed
  /// rather than drawn, the way --col-- is in a run of columns.
  static final _cell = RegExp(r'^\s*--cell--\s*$');

  /// The most a grid may hold across, matching ColumnsBlockSyntax. Past four
  /// a cell in a chat-width window is a word wide.
  static const maxColumns = 4;

  @override
  RegExp get pattern => _open;

  static bool startsCell(String line) => _picture.hasMatch(line);

  /// _count is how many across was asked for: the bare number at the front
  /// of the settings, if there is one.
  static String _count(String settings) {
    var first = settings.split(",").first.trim();
    return int.tryParse(first) == null ? "" : first;
  }

  /// _gap is the room between cells, or null to take the reader's guide's.
  static double? _gap(String settings) {
    for (var part in settings.split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      if (part.substring(0, at).trim().toLowerCase() != "gap") continue;
      var got = double.tryParse(part.substring(at + 1).trim());
      if (got == null || got < 0 || got > 200) return null;
      return got;
    }
    return null;
  }

  /// splitCells divides a run into cells at each picture.
  ///
  /// Separate from parse so the division can be tested without a parser.
  static List<String> splitCells(List<String> lines) {
    var cells = <String>[];
    var current = <String>[];

    void flush() {
      var text = current.join("\n").trim();
      if (text.isNotEmpty) cells.add(text);
      current = [];
    }

    // A run holding any marker at all is divided by the markers alone.
    // Mixing the two would divide a card that has a picture in it in half,
    // and a writer who has said where the cells are has answered the
    // question this was guessing at.
    var said = lines.any(_cell.hasMatch);

    for (var line in lines) {
      if (said) {
        if (_cell.hasMatch(line)) {
          flush();
          continue;
        }
        current.add(line);
        continue;
      }

      // A picture opens a cell, but only once there is something to close:
      // a leading picture would otherwise emit an empty cell before itself.
      if (startsCell(line) && current.any((l) => l.trim().isNotEmpty)) {
        flush();
      }
      current.add(line);
    }
    flush();
    return cells;
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    var line = parser.current.content;
    var match = _open.firstMatch(line);
    var settings = match?.group(2) ?? "";

    // --grid2-- is one across by definition, and takes no count of its own.
    // A bare --grid-- carries no count at all: it is left for the builder to
    // fill from the guide, since how many across a gallery should be is a
    // decision about the page rather than about the writing.
    var count = match?.group(1) != null ? "1" : _count(settings);
    var gap = _gap(settings);
    parser.advance();

    var lines = <String>[];
    while (!parser.isDone) {
      if (_close.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    var cells = splitCells(lines);
    var element = md.Element.text("grid", "");
    if (count.isNotEmpty) {
      element.attributes["columns"] =
          "${(int.tryParse(count) ?? 2).clamp(1, maxColumns)}";
    }
    if (gap != null) element.attributes["gap"] = "$gap";
    element.attributes["count"] = "${cells.length}";
    for (var i = 0; i < cells.length; i++) {
      element.attributes["cell$i"] = cells[i];
    }
    // Wrapped in a paragraph for the same reason a run of columns is: the
    // builder that draws this is reached through flutter_markdown's inline
    // path, which expects to be inside a block.
    return md.Element("p", [element]);
  }
}

/// GridMarkdownElementBuilder draws a gallery.
class GridMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var count = int.tryParse(element.attributes["count"] ?? "") ?? 0;
    var cells = <String>[];
    for (var i = 0; i < count; i++) {
      cells.add(element.attributes["cell$i"] ?? "");
    }
    return _MarkdownGrid(
      cells: cells,
      // Null when the writer wrote a bare --grid--, which the guide answers.
      columns: int.tryParse(element.attributes["columns"] ?? ""),
      gap: double.tryParse(element.attributes["gap"] ?? ""),
    );
  }
}

/// _MarkdownGrid lays the cells out in rows.
class _MarkdownGrid extends StatelessWidget {
  final List<String> cells;

  /// columns is what the writer asked for, or null to take the guide's.
  final int? columns;

  /// gap is the room the writer asked for between cells, or null for the
  /// guide's.
  final double? gap;
  const _MarkdownGrid({required this.cells, required this.columns, this.gap});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    // Shares the columns guard: a gallery inside a gallery inside a gallery
    // is a way to hang the renderer, not a layout.
    var depth = _ColumnDepth.of(context);
    if (depth >= _ColumnDepth._maxDepth) {
      return Text(cells.join("\n\n"));
    }

    var rule = MarkdownGuideScope.gridOf(context) ?? const GridRule();
    var gap = this.gap ?? rule.boundedGap;
    var asked = columns ?? rule.boundedColumns;

    return LayoutBuilder(builder: (context, constraints) {
      // Narrow enough and a gallery stops being one: four pictures across a
      // phone-width window are thumbnails in a row, and the captions under
      // them are a word wide. Below the guide's width they stack, which is
      // what they would have been without the markup.
      var available = constraints.maxWidth;
      var across = asked;
      while (across > 1 &&
          (available - gap * (across - 1)) / across < rule.boundedStackBelow) {
        across--;
      }
      return _rows(context, across, gap, depth);
    });
  }

  Widget _rows(BuildContext context, int across, double gap, int depth) {
    // One across is a stack of blocks, not a layout -- drawing it as a Row
    // of one would stretch a child where a plain block belongs. This is also
    // Decred Pulse's --grid2--.
    if (across <= 1) {
      return _ColumnDepth(
        depth: depth + 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              MarkdownArea(cells[i], false),
            ],
          ],
        ),
      );
    }

    // Laid out in rows rather than a Wrap so cells line up across as well as
    // down: a Wrap gives each cell its own height and the grid stops being
    // one. A short last row keeps its cells at column width rather than
    // spreading them, by padding the row with blanks.
    var rows = <Widget>[];
    for (var start = 0; start < cells.length; start += across) {
      var row = <Widget>[];
      for (var i = start; i < start + across; i++) {
        if (i > start) row.add(SizedBox(width: gap));
        row.add(Expanded(
          child: i < cells.length
              ? MarkdownArea(cells[i], false)
              : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      // Deliberately not wrapped in IntrinsicHeight to even the cells up: a
      // cell is a MarkdownArea, which lays out through a LayoutBuilder, and
      // LayoutBuilder cannot be dry-laid-out -- asking for the intrinsic
      // height of a row of them throws. Cells hang from a common top
      // instead, which is what a gallery of unequal captions wants anyway.
      rows.add(
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: row));
    }

    return _ColumnDepth(
      depth: depth + 1,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
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
          Text(titleText, style: theme.markdownTextStyle(rule.title, body)),
        if (titleText.isNotEmpty && text.isNotEmpty) const SizedBox(height: 6),
        if (text.isNotEmpty)
          Text(text, style: theme.markdownTextStyle(rule.text, body)),
        if (buttonText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            // The app's own button, so a card's button is the same button as
            // every other button in the app and follows the Buttons area --
            // in whichever of the five designs the guide asks for (see
            // CardRule.button). The style carries the fill, the border and
            // the label colour for every role, so one widget draws all five
            // rather than the card having to pick a widget class per role.
            child: ElevatedButton(
              style: theme.buttonStyle(rule.button),
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

    var iconInk = theme.markdownInk(rule.iconInk) ?? theme.colors.primary;
    var iconBack = theme.markdownInk(rule.iconBackground);
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
            color: theme.markdownInk(rule.borderInk) ??
                theme.colors.outlineVariant,
            width: rule.boundedBorder);

    return Container(
      padding: rule.paddings.isZero ? null : rule.paddings.insets,
      decoration: BoxDecoration(
        color: theme.markdownInk(rule.background),
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

  var ink = theme.markdownInk(rule.borderInk) ?? theme.colors.outlineVariant;

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
    var dividerInk =
        theme.markdownInk(rule.dividerInk) ?? theme.colors.outlineVariant;

    // The style the run is set in, which is what every block below is
    // measured in. Built the same way applyGuide builds the paragraph style,
    // so what is measured is what will be drawn.
    var guide = theme.markdownGuide;
    var bodyStyle = theme.markdownTextStyle(
        guide.body,
        Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 14));

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
