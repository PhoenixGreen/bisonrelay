import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// The order a table's rows go in is its own file, and is exported so that
// "import table_element.dart" still brings a whole table.
export 'package:bruig/plugin_system/canvas/model/elements/table_sort.dart';

import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_sort.dart';

/// TableGrid is which rules a table draws between its cells.
enum TableGrid {
  all("All"),
  horizontal("Rows only"),
  vertical("Columns only"),
  outer("Outline only"),
  none("None");

  final String label;
  const TableGrid(this.label);

  static TableGrid fromName(String? name) => values
      .firstWhere((g) => g.name == name, orElse: () => TableGrid.horizontal);

  bool get drawsHorizontal => this == all || this == horizontal;
  bool get drawsVertical => this == all || this == vertical;
  bool get drawsOuter => this != none;
}

/// TableCellStyle is a look one rule paints onto the cells it matches.
///
/// Every field has a "leave it alone" value, because a rule is an exception
/// rather than a complete description: "the W column is green" should not also
/// decide the font, the weight and the colour of the words, and a style that
/// had to say all of them would be a style nobody could write.
class TableCellStyle {
  /// background is painted behind the cell. Transparent leaves whatever the
  /// row already had -- the header's fill, the zebra tint, or nothing.
  final Color background;

  /// textColor is transparent to keep the type's own colour.
  final Color textColor;

  /// fontScale multiplies the cell's font size. 1 leaves it.
  final double fontScale;

  /// weight is 0 to keep the type's own, and 100..900 to override it.
  final int weight;

  /// letterWidth lays the cell's characters out on a fixed pitch.
  ///
  /// Zero is the natural widths, which is what words want. A number is what a
  /// row of boxes wants: a W is wider than an L, so however carefully the
  /// spacing is set the boxes come out at different places, and lining them
  /// up by eye is a job that cannot be finished. Every character gets a slot
  /// of this width, and [letterSpacing] is the gap between the slots.
  ///
  /// It belongs to a rule about a *cell* rather than one about a word, and
  /// [TableElement.styleFor] enforces that. The pitch is how the whole cell
  /// is laid out, so a rule that named the letter D and set a width was
  /// silently respacing the Ls and Ws beside it -- one letter's rule deciding
  /// the layout of the rest.
  final double letterWidth;

  /// letterSpacing is 0 to keep the type's own.
  ///
  /// On a rule because that is where it is needed: a form guide reading
  /// "W D L" wants its letters far enough apart that their boxes do not
  /// touch, and the cell type's own spacing is one number for the whole
  /// table -- spacing the form column out would space the team names out
  /// with it.
  final double letterSpacing;

  /// align and verticalAlign are null to keep the type's own.
  ///
  /// Worth having on a rule rather than only on the table's type: a column of
  /// numbers wants to be right-aligned and the column of names beside it does
  /// not, and one alignment for the whole table cannot say that.
  final TextAlignSpec? align;
  final VerticalAlignSpec? verticalAlign;

  final Color borderColor;
  final double borderWidth;

  /// sides is which edges the border is drawn on, in the order top, right,
  /// bottom, left.
  ///
  /// A list of four rather than four fields because that is how it is read
  /// and written -- and because the common wants are "all of them" and "the
  /// top and the bottom", neither of which is improved by four named
  /// booleans.
  final List<bool> sides;

  final double radius;

  /// inset shrinks the painted box inside its cell, which is what turns a
  /// background into a chip rather than a filled cell.
  final double inset;

  /// textPad is extra room either side of the words, on top of the table's
  /// own cell padding.
  ///
  /// What alignment needs to be usable: pushed to the left or the right, the
  /// words sit against the edge of the cell, and the table's padding is one
  /// number for every cell in it -- so there was no way to give one column a
  /// margin without giving all of them one.
  final double textPad;

  /// minWidth and minHeight are the least a hugging box may be.
  ///
  /// What makes a row of chips a row of chips. Hugging the letters exactly is
  /// right for the box and wrong for a set of them: a W is wider than an L, so
  /// a form guide came out as boxes of three different sizes. A minimum makes
  /// them all the same, and a minimum equal to the height makes them square.
  final double minWidth;
  final double minHeight;

  /// nudgeX and nudgeY move the *letter* inside its box.
  ///
  /// The box is centred on the letter's advance -- the room the font says the
  /// letter takes -- and a letter's ink is not always centred in that. A W
  /// can sit a pixel right of its advance while the L beside it is fine, so a
  /// box that is arithmetically centred still looks wrong, and no amount of
  /// padding fixes it because padding is symmetric.
  ///
  /// The letter and not the box, because the boxes are the slots and the
  /// slots being in line is the whole point of a fixed pitch: moving one of
  /// them to centre a letter would take that letter's box out of the row it
  /// was put there to join.
  ///
  /// A nudge rather than measuring the ink: what a glyph actually covers is
  /// not something the text engine will say, and working it out from the
  /// outline would be writing a font renderer.
  final double nudgeX;
  final double nudgeY;

  /// hug fits the box to the words rather than to the cell.
  ///
  /// On, because the thing anybody asks for by naming a word is a chip round
  /// that word -- a green box behind the W, not a green cell with a W in it.
  /// Off fills the cell, which is what a rule about a whole column wants.
  final bool hug;

  const TableCellStyle({
    this.background = const Color(0x00000000),
    this.textColor = const Color(0x00000000),
    this.fontScale = 1,
    this.weight = 0,
    this.letterSpacing = 0,
    this.letterWidth = 0,
    this.align,
    this.verticalAlign,
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.sides = const [true, true, true, true],
    this.radius = 4,
    this.inset = 6,
    this.hug = true,
    this.textPad = 0,
    this.nudgeX = 0,
    this.nudgeY = 0,
    this.minWidth = 0,
    this.minHeight = 0,
  });

  bool get allSides => !sides.contains(false);

  bool get paintsBox =>
      background.a > 0 || (borderColor.a > 0 && borderWidth > 0);

  bool get changesType =>
      textColor.a > 0 ||
      fontScale != 1 ||
      weight != 0 ||
      letterSpacing != 0 ||
      align != null ||
      verticalAlign != null;

  TableCellStyle copyWith({
    Color? background,
    Color? textColor,
    double? fontScale,
    int? weight,
    double? letterSpacing,
    double? letterWidth,
    TextAlignSpec? align,
    VerticalAlignSpec? verticalAlign,
    bool clearAlign = false,
    bool clearVerticalAlign = false,
    Color? borderColor,
    double? borderWidth,
    List<bool>? sides,
    double? radius,
    double? inset,
    bool? hug,
    double? textPad,
    double? minWidth,
    double? minHeight,
    double? nudgeX,
    double? nudgeY,
  }) =>
      TableCellStyle(
        background: background ?? this.background,
        textColor: textColor ?? this.textColor,
        fontScale: fontScale ?? this.fontScale,
        weight: weight ?? this.weight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        letterWidth: letterWidth ?? this.letterWidth,
        align: clearAlign ? null : (align ?? this.align),
        verticalAlign:
            clearVerticalAlign ? null : (verticalAlign ?? this.verticalAlign),
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        sides: sides ?? this.sides,
        radius: radius ?? this.radius,
        inset: inset ?? this.inset,
        hug: hug ?? this.hug,
        textPad: textPad ?? this.textPad,
        minWidth: minWidth ?? this.minWidth,
        minHeight: minHeight ?? this.minHeight,
        nudgeX: nudgeX ?? this.nudgeX,
        nudgeY: nudgeY ?? this.nudgeY,
      );

  Map<String, dynamic> toJson() => {
        if (background.a > 0) "bg": colorToJson(background),
        if (textColor.a > 0) "fg": colorToJson(textColor),
        if (fontScale != 1) "scale": fontScale,
        if (weight != 0) "weight": weight,
        if (letterSpacing != 0) "ls": letterSpacing,
        if (letterWidth != 0) "lw": letterWidth,
        if (align != null) "align": align!.name,
        if (verticalAlign != null) "valign": verticalAlign!.name,
        if (borderColor.a > 0) "bc": colorToJson(borderColor),
        if (borderWidth != 0) "bw": borderWidth,
        if (!allSides) "sides": sides,
        if (radius != 4) "r": radius,
        if (inset != 6) "inset": inset,
        if (!hug) "fill": true,
        if (textPad != 0) "pad": textPad,
        if (minWidth != 0) "minw": minWidth,
        if (minHeight != 0) "minh": minHeight,
        if (nudgeX != 0) "nx": nudgeX,
        if (nudgeY != 0) "ny": nudgeY,
      };

  factory TableCellStyle.fromJson(Map<String, dynamic> json) => TableCellStyle(
        background: colorFromJson(json["bg"], const Color(0x00000000)),
        textColor: colorFromJson(json["fg"], const Color(0x00000000)),
        fontScale: jsonDouble(json["scale"], 1).clamp(0.2, 6.0),
        weight: jsonInt(json["weight"], 0),
        letterSpacing: jsonDouble(json["ls"], 0),
        letterWidth: jsonDouble(json["lw"], 0),
        align: json["align"] is String
            ? TextAlignSpec.fromName(json["align"] as String?)
            : null,
        verticalAlign: json["valign"] is String
            ? VerticalAlignSpec.fromName(json["valign"] as String?)
            : null,
        borderColor: colorFromJson(json["bc"], const Color(0x00000000)),
        borderWidth: jsonDouble(json["bw"], 0),
        sides: json["sides"] is List && (json["sides"] as List).length == 4
            ? [for (var v in json["sides"] as List) v == true]
            : const [true, true, true, true],
        radius: jsonDouble(json["r"], 4),
        inset: jsonDouble(json["inset"], 6),
        hug: !jsonBool(json["fill"], false),
        textPad: jsonDouble(json["pad"], 0),
        minWidth: jsonDouble(json["minw"], 0),
        minHeight: jsonDouble(json["minh"], 0),
        nudgeX: jsonDouble(json["nx"], 0),
        nudgeY: jsonDouble(json["ny"], 0),
      );
}

/// _Span is a parsed range: "", "3", "2:4", ">1", "<4".
///
/// Read once and kept, because the same handful of strings are asked the same
/// question thousands of times a frame -- see TableRule._spans.
class _Span {
  final int from;
  final int to;
  const _Span(this.from, this.to);

  /// any is the empty spec, and none is one that could not be read -- which
  /// matches nothing rather than everything, so a typo shows up as a rule
  /// that does nothing rather than a table painted entirely green.
  static const any = _Span(1, 1 << 30);
  static const none = _Span(1, 0);

  bool covers(int at) => at >= from && at <= to;

  factory _Span.parse(String spec) {
    var text = spec.trim();
    if (text.isEmpty) return any;

    if (text.startsWith(">")) {
      var from = int.tryParse(text.substring(1).trim());
      return from == null ? none : _Span(from + 1, 1 << 30);
    }
    if (text.startsWith("<")) {
      var to = int.tryParse(text.substring(1).trim());
      return to == null ? none : _Span(1, to - 1);
    }
    if (text.contains(":")) {
      var parts = text.split(":");
      var from = int.tryParse(parts.first.trim());
      var to = int.tryParse(parts.last.trim());
      if (from == null || to == null) return none;
      return _Span(math.min(from, to), math.max(from, to));
    }
    var one = int.tryParse(text);
    return one == null ? none : _Span(one, one);
  }
}

/// TableMatch is how a rule's text is looked for.
enum TableMatch {
  /// cell wants the whole cell. "W" does not find the W in "Won", and does
  /// not find the W in "--- W" either.
  cell("The whole cell"),

  /// anywhere finds it inside anything, "Won" included.
  anywhere("Anywhere in it"),

  /// word finds it as a word of its own, so "W" finds the W in "--- W" and
  /// not the W in "Won" -- and a chip is drawn round that word rather than
  /// round the whole cell.
  word("A whole word");

  final String label;
  const TableMatch(this.label);

  static TableMatch fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => TableMatch.cell);
}

/// TableRule is "these cells look like that".
///
/// One mechanism for three things that were asked for separately, and they
/// really are one: a green chip wherever a column says W is a rule about a
/// column and a word; a highlighted row is a rule about a row; a points
/// column set slightly larger is a rule about a column. Three settings pages
/// would have been three ways to write the same sentence.
///
/// Whatever is left blank means "any". A rule with nothing filled in is a
/// rule about the whole table, which is a legitimate if blunt thing to want.
class TableRule {
  /// column is a heading -- "Points" -- or a number counting from one.
  ///
  /// A heading, because that is what somebody looking at the table can see;
  /// the number is there for a table with no header row, and for the case
  /// where two columns share a name.
  final String column;

  /// rows is which rows, counting from one and including the header.
  ///
  /// A little language rather than a number, because the three things people
  /// want are one row, every row after the header, and a block of them -- and
  /// "2", ">1" and "2:4" say those in the space a number took. Empty is any
  /// row, which is what a rule about a column means.
  final String rows;

  /// match is the text to look for. Empty matches every cell.
  final String match;

  /// how the text is looked for. See [TableMatch].
  final TableMatch how;

  final TableCellStyle style;

  const TableRule({
    this.column = "",
    this.rows = "",
    this.match = "",
    this.how = TableMatch.cell,
    this.style = const TableCellStyle(),
  });

  /// banded is a rule with no text to look for, which is the case drawn as
  /// one box around everything it picks out rather than a box per cell.
  ///
  /// A rule naming a row is a band across the table; one naming a column is a
  /// band down it; one naming both is the cell where they cross. A rule
  /// naming a *word* is not a band at all -- it is a chip round that word,
  /// wherever the word happens to be.
  bool get banded => match.isEmpty;

  /// matchesRow reads the range language. [index] counts from zero.
  bool matchesRow(int index) => spanMatches(rows, index);

  /// _spans remembers what a range string means.
  ///
  /// The strings are read once per cell per rule per frame -- a league table
  /// with eight rules is two thousand reads a frame -- and there are only ever
  /// a handful of distinct ones, so parsing them again each time is work done
  /// for an answer already known.
  static final Map<String, _Span> _spans = {};

  /// spanMatches is the little range language, shared by the rows and the
  /// columns because they are asking the same question.
  ///
  /// Empty is any. "3" is one, counting from one. "2:4" is a block, "&gt;1"
  /// everything after, "&lt;4" everything before.
  ///
  /// An unreadable range matches nothing rather than everything, for the same
  /// reason an unknown column name does: a typo should show up as a rule that
  /// does nothing, not as a table painted entirely green.
  static bool spanMatches(String spec, int index) =>
      (_spans[spec] ??= _Span.parse(spec)).covers(index + 1);

  /// matchesColumn is whether [index] is one of the columns this rule is
  /// about.
  ///
  /// A heading first, because that is what somebody looking at the table can
  /// see. Failing that it is read as a range, the same little language the
  /// rows use -- 3, 2:4, >1 -- so a rule can cover a block of columns without
  /// naming each of them, and so a table with no header row can still be
  /// picked apart.
  bool matchesColumn(int index, List<String> header) {
    var spec = column.trim();
    if (spec.isEmpty) return true;

    var byName =
        header.indexWhere((h) => h.trim().toLowerCase() == spec.toLowerCase());
    if (byName >= 0) return byName == index;
    return spanMatches(spec, index);
  }

  /// spansColumns is whether the rule names more than one column, which is
  /// what tells a band how wide to be.
  bool get spansColumns => column.trim().isEmpty || !_isOne(column.trim());

  static bool _isOne(String spec) => int.tryParse(spec) != null;

  bool matches(String cell) => match.isEmpty || runsIn(cell).isNotEmpty;

  /// runIn is the first place the match falls inside [cell].
  (int, int)? runIn(String cell) {
    var all = runsIn(cell);
    return all.isEmpty ? null : all.first;
  }

  /// runsIn is every place the match falls inside [cell].
  ///
  /// Every place, not the first: a form guide reading "- - W | W" has two of
  /// them and wants two chips, and a rule that stopped at the first was a
  /// rule that highlighted half the answer.
  ///
  /// Ranges rather than a yes or no, because a chip round a word has to know
  /// which part of the cell the word is -- "--- W" wants a box round the W
  /// and not round the dashes.
  static final Map<String, String> _lowered = {};

  List<(int, int)> runsIn(String cell, [String? lowered]) {
    var wanted = _lowered[match] ??= match.trim().toLowerCase();
    if (wanted.isEmpty) return const [];
    // The caller may already have lowered it. A cell with three rules looking
    // at it was lowering the same string three times a frame.
    var lower = lowered ?? cell.toLowerCase();

    switch (how) {
      case TableMatch.cell:
        return cell.trim().toLowerCase() == wanted
            ? [(0, cell.length)]
            : const [];
      case TableMatch.anywhere:
      case TableMatch.word:
        // A whole word is bounded by anything that is not a letter or a
        // digit, which is what a word ends at everywhere anybody would expect
        // it to.
        var out = <(int, int)>[];
        for (var at = lower.indexOf(wanted);
            at >= 0;
            at = lower.indexOf(wanted, at + 1)) {
          var end = at + wanted.length;
          if (how == TableMatch.word) {
            var before = at == 0 ? "" : lower[at - 1];
            var after = end >= lower.length ? "" : lower[end];
            if (_wordish(before) || _wordish(after)) continue;
          }
          out.add((at, end));
        }
        return out;
    }
  }

  static bool _wordish(String c) =>
      c.isNotEmpty && RegExp(r"[a-z0-9]").hasMatch(c);

  TableRule copyWith({
    String? column,
    String? rows,
    String? match,
    TableMatch? how,
    TableCellStyle? style,
  }) =>
      TableRule(
        column: column ?? this.column,
        rows: rows ?? this.rows,
        match: match ?? this.match,
        how: how ?? this.how,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() => {
        if (column.isNotEmpty) "col": column,
        if (rows.isNotEmpty) "rows": rows,
        if (match.isNotEmpty) "match": match,
        if (how != TableMatch.cell) "how": how.name,
        "style": style.toJson(),
      };

  factory TableRule.fromJson(Map<String, dynamic> json) => TableRule(
        column: jsonString(json["col"], ""),
        // "row" is the number this used to be, kept readable so a table saved
        // before the range language still highlights the row it was told to.
        rows: jsonString(json["rows"],
            json["row"] is num ? "${(json["row"] as num).toInt()}" : ""),
        match: jsonString(json["match"], ""),
        // "loose" is what the two-way version wrote, so a table saved before
        // whole-word matching still finds what it was told to.
        how: json["how"] is String
            ? TableMatch.fromName(json["how"] as String?)
            : (jsonBool(json["loose"], false)
                ? TableMatch.anywhere
                : TableMatch.cell),
        style: jsonSpec(
            json["style"], TableCellStyle.fromJson, const TableCellStyle()),
      );
}

/// TableCellLook is everything the rules say about one cell, worked out once.
///
/// Once, because four different questions were being asked of the same rules
/// for every cell of every frame -- what the cell's type is, where the chips
/// go, what type each stretch of it is, and how far each letter is nudged --
/// and each walked every rule and searched the text again. A league table is
/// two hundred cells and eight rules, so the same search was being run
/// thousands of times a frame for an answer that had not changed.
class TableCellLook {
  /// style is the cell's own look: what a rule about the whole cell says.
  final TableCellStyle? style;

  /// words are the rules that named a word, with the places they found it.
  /// In the order they were written, so a later one draws over an earlier.
  final List<(TableRule, List<(int, int)>)> words;

  const TableCellLook(this.style, this.words);

  static const nothing = TableCellLook(null, []);

  bool get isEmpty => style == null && words.isEmpty;

  /// ruleAt is the rule that claims the character at [index], latest first --
  /// a list of exceptions is read in the order it was written.
  TableRule? ruleAt(int index) {
    for (var i = words.length - 1; i >= 0; i--) {
      for (var (from, to) in words[i].$2) {
        if (index >= from && index < to) return words[i].$1;
      }
    }
    return null;
  }
}

/// TableElement is a grid of strings, drawn rather than laid out as widgets.
///
/// The same reasoning as the chart next door: a Flutter Table renders to the
/// screen and stops there, while this has to export at 2400px, rotate with the
/// rest of the canvas and animate. So it is a painter, and everything about
/// how it looks is a number in here.
///
/// Rows of strings and nothing else. No formulas, no sorting, no column types
/// -- a table on a canvas is something you show, and the place to compute it
/// is wherever the numbers came from.
class TableElement extends CanvasElement {
  /// rows is the whole grid including the header, if there is one. Ragged
  /// rows are tolerated and padded out at paint time.
  final List<List<String>> rows;

  final bool headerRow;
  final bool headerColumn;

  /// showOutline is the rule round the outside of the table.
  ///
  /// Its own switch rather than another entry in [TableGrid], because it is a
  /// separate decision: "rules between the rows" and "a line round the whole
  /// thing" are two things anybody might want either of, and folding them
  /// into one list means an entry for every combination.
  final bool showOutline;

  final TextSpec cellSpec;
  final TextSpec headerSpec;

  final Color headerFill;
  final Color cellFill;

  /// zebra tints alternate rows, and is the single most effective thing for
  /// making a wide table readable.
  final bool zebra;
  final Color zebraFill;

  /// source is where the rows came from, when they came from somewhere. See
  /// DataSource; a table whose cells were typed has the default and never
  /// thinks about it again.
  final DataSource source;

  /// sort is the order the rows were last put in, kept so that the same order
  /// can be applied again after the data underneath changes.
  final TableSort sort;

  final TableGrid grid;
  final double gridWidth;
  final Color gridColor;

  final double cellPadding;
  final double cornerRadius;

  /// pictureScale is how much of its cell a picture fills, on top of the
  /// cell's own padding.
  ///
  /// One for the whole cell, less for room round the outside. A badge that
  /// touches the rules either side of it reads as a mistake, and the cell
  /// padding cannot be used for this -- it is the words' margin as well, and
  /// a table with room enough round its pictures would have its text a long
  /// way from the rules.
  final double pictureScale;

  /// columnWidths are fractions of the table's width and must sum to
  /// something; an empty list means equal columns, which is the default and
  /// covers most tables.
  final List<double> columnWidths;

  /// rowHeight is a fraction of the table's height per row, or 0 for equal
  /// rows. Header rows commonly want to be a little taller, and that is the
  /// only reason this is adjustable at all.
  final double headerHeightRatio;

  /// rules are the exceptions: which cells look different, and how. See
  /// [TableRule].
  final List<TableRule> rules;

  const TableElement(
    super.base, {
    this.rows = const [],
    this.headerRow = true,
    this.headerColumn = false,
    this.showOutline = true,
    this.cellSpec =
        const TextSpec(fontSize: 18, weight: 400, align: TextAlignSpec.left),
    this.headerSpec =
        const TextSpec(fontSize: 18, weight: 700, align: TextAlignSpec.left),
    this.headerFill = const Color(0xFF1D2733),
    this.cellFill = const Color(0x00000000),
    this.zebra = true,
    this.zebraFill = const Color(0x0DFFFFFF),
    this.grid = TableGrid.horizontal,
    this.gridWidth = 1,
    this.gridColor = const Color(0x33FFFFFF),
    this.cellPadding = 10,
    this.cornerRadius = 6,
    this.pictureScale = 1,
    this.columnWidths = const [],
    this.headerHeightRatio = 1.15,
    this.rules = const [],
    this.sort = const TableSort(),
    this.source = const DataSource(),
  });

  @override
  ElementKind get kind => ElementKind.table;

  int get columnCount => rows.fold(0, (n, r) => r.length > n ? r.length : n);

  @override
  Set<String> get assetIds => {
        for (var row in rows)
          for (var cell in row)
            if (pictureIn(cell) case var asset?) asset,
      };

  /// pictureCell is the prefix that turns a cell into a picture.
  ///
  /// Kept in the cell's own text rather than in a map of positions beside the
  /// grid. A map has to be renumbered every time a row is inserted or a
  /// column removed, and one missed renumbering puts a badge against the
  /// wrong team; text is carried by the cell it belongs to, whatever happens
  /// to the rows around it. It also survives the round trip through the
  /// pasted-text box for free.
  static const String pictureCell = "img:";

  /// pictureIn is the asset a cell names, or null when it is words.
  static String? pictureIn(String cell) {
    var text = cell.trim();
    return text.startsWith(pictureCell) && text.length > pictureCell.length
        ? text.substring(pictureCell.length)
        : null;
  }

  /// header is the first row when there is one, for resolving a rule's column
  /// by name. Empty otherwise, which makes every name fail to match and every
  /// number still work.
  List<String> get header =>
      headerRow && rows.isNotEmpty ? rows.first : const [];

  /// lookAt is what the rules say about one cell.
  ///
  /// One walk of the rules rather than four, and one search of the cell's
  /// text rather than one per question -- see [TableCellLook].
  TableCellLook lookAt(int row, int col) {
    if (rules.isEmpty) return TableCellLook.nothing;

    var head = header;
    var text = cell(row, col);
    String? lower;
    TableCellStyle? style;
    var words = <(TableRule, List<(int, int)>)>[];

    for (var rule in rules) {
      if (!rule.matchesRow(row)) continue;
      if (!rule.matchesColumn(col, head)) continue;

      if (rule.match.isNotEmpty) {
        var runs = rule.runsIn(text, lower ??= text.toLowerCase());
        if (runs.isEmpty) continue;
        words.add((rule, runs));
      }

      style = style == null
          ? (rule.match.isEmpty
              ? rule.style
              // A rule that names a word describes that word: its type and
              // the cell's pitch are not the cell's to take. Same treatment
              // for the first matching rule as for every one after it, or a
              // cell whose only rule names a letter would take both.
              : rule.style.copyWith(
                  letterWidth: 0,
                  letterSpacing: 0,
                  fontScale: 1,
                  weight: 0,
                  textColor: const Color(0x00000000)))
          : style.copyWith(
              background: rule.style.background.a > 0
                  ? rule.style.background
                  : style.background,
              borderColor: rule.style.borderColor.a > 0
                  ? rule.style.borderColor
                  : style.borderColor,
              borderWidth: rule.style.borderWidth != 0
                  ? rule.style.borderWidth
                  : style.borderWidth,
              sides: rule.style.allSides ? style.sides : rule.style.sides,
              radius: rule.style.radius,
              inset: rule.style.inset,
              hug: rule.style.hug,
              textPad:
                  rule.style.textPad != 0 ? rule.style.textPad : style.textPad,
              minWidth: rule.style.minWidth != 0
                  ? rule.style.minWidth
                  : style.minWidth,
              minHeight: rule.style.minHeight != 0
                  ? rule.style.minHeight
                  : style.minHeight,
              nudgeX: rule.style.nudgeX != 0 ? rule.style.nudgeX : style.nudgeX,
              nudgeY: rule.style.nudgeY != 0 ? rule.style.nudgeY : style.nudgeY,
              align: rule.style.align ?? style.align,
              verticalAlign: rule.style.verticalAlign ?? style.verticalAlign,
              // The type and the pitch only from a rule about the whole cell.
              textColor: rule.match.isEmpty && rule.style.textColor.a > 0
                  ? rule.style.textColor
                  : style.textColor,
              fontScale: rule.match.isEmpty && rule.style.fontScale != 1
                  ? rule.style.fontScale
                  : style.fontScale,
              weight: rule.match.isEmpty && rule.style.weight != 0
                  ? rule.style.weight
                  : style.weight,
              letterSpacing: rule.match.isEmpty && rule.style.letterSpacing != 0
                  ? rule.style.letterSpacing
                  : style.letterSpacing,
              letterWidth: rule.match.isEmpty && rule.style.letterWidth != 0
                  ? rule.style.letterWidth
                  : style.letterWidth,
            );
    }

    return style == null && words.isEmpty
        ? TableCellLook.nothing
        : TableCellLook(style, words);
  }

  /// styleFor is the cell's own look. See [lookAt], which is the one to reach
  /// for when more than one of these questions is being asked.
  TableCellStyle? styleFor(int row, int col) => lookAt(row, col).style;

  /// runStyleFor is the type change that belongs to the character at [index],
  /// from whichever rule that names a word claims it.
  TableCellStyle? runStyleFor(int row, int col, int index) {
    var rule = lookAt(row, col).ruleAt(index);
    return rule != null && rule.style.changesType ? rule.style : null;
  }

  /// cell is the string at a position, padding out ragged rows rather than
  /// throwing. See TableElement's note on ragged data.
  String cell(int row, int col) {
    if (row < 0 || row >= rows.length) return "";
    var r = rows[row];
    return col >= 0 && col < r.length ? r[col] : "";
  }

  /// asText and parse are the quick-entry round trip. Comma separated, with
  /// quoting for the cells that need it -- see joinTable.
  String asText() => joinTable(rows);

  static List<List<String>> parseRows(String text) => splitTable(text);

  @override
  CanvasElement rebase(ElementBase base) => _copy(base);

  TableElement copyWith({
    List<List<String>>? rows,
    bool? headerRow,
    bool? headerColumn,
    bool? showOutline,
    TextSpec? cellSpec,
    TextSpec? headerSpec,
    Color? headerFill,
    Color? cellFill,
    bool? zebra,
    Color? zebraFill,
    TableGrid? grid,
    double? gridWidth,
    Color? gridColor,
    double? cellPadding,
    double? cornerRadius,
    double? pictureScale,
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
    TableSort? sort,
    DataSource? source,
  }) =>
      _copy(base,
          rows: rows,
          headerRow: headerRow,
          headerColumn: headerColumn,
          showOutline: showOutline,
          cellSpec: cellSpec,
          headerSpec: headerSpec,
          headerFill: headerFill,
          cellFill: cellFill,
          zebra: zebra,
          zebraFill: zebraFill,
          grid: grid,
          gridWidth: gridWidth,
          gridColor: gridColor,
          cellPadding: cellPadding,
          cornerRadius: cornerRadius,
          pictureScale: pictureScale,
          columnWidths: columnWidths,
          headerHeightRatio: headerHeightRatio,
          rules: rules,
          sort: sort,
          source: source);

  TableElement _copy(
    ElementBase newBase, {
    List<List<String>>? rows,
    bool? headerRow,
    bool? headerColumn,
    bool? showOutline,
    TextSpec? cellSpec,
    TextSpec? headerSpec,
    Color? headerFill,
    Color? cellFill,
    bool? zebra,
    Color? zebraFill,
    TableGrid? grid,
    double? gridWidth,
    Color? gridColor,
    double? cellPadding,
    double? cornerRadius,
    double? pictureScale,
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
    TableSort? sort,
    DataSource? source,
  }) =>
      TableElement(newBase,
          rows: rows ?? this.rows,
          headerRow: headerRow ?? this.headerRow,
          headerColumn: headerColumn ?? this.headerColumn,
          showOutline: showOutline ?? this.showOutline,
          cellSpec: cellSpec ?? this.cellSpec,
          headerSpec: headerSpec ?? this.headerSpec,
          headerFill: headerFill ?? this.headerFill,
          cellFill: cellFill ?? this.cellFill,
          zebra: zebra ?? this.zebra,
          zebraFill: zebraFill ?? this.zebraFill,
          grid: grid ?? this.grid,
          gridWidth: gridWidth ?? this.gridWidth,
          gridColor: gridColor ?? this.gridColor,
          cellPadding: cellPadding ?? this.cellPadding,
          cornerRadius: cornerRadius ?? this.cornerRadius,
          pictureScale: pictureScale ?? this.pictureScale,
          columnWidths: columnWidths ?? this.columnWidths,
          headerHeightRatio: headerHeightRatio ?? this.headerHeightRatio,
          rules: rules ?? this.rules,
          sort: sort ?? this.sort,
          source: source ?? this.source);

  @override
  Map<String, dynamic> props() => {
        "rows": rows,
        "headerRow": headerRow,
        if (headerColumn) "headerCol": true,
        if (!showOutline) "noOutline": true,
        "cellSpec": cellSpec.toJson(),
        "headerSpec": headerSpec.toJson(),
        "headerFill": colorToJson(headerFill),
        "cellFill": colorToJson(cellFill),
        "zebra": zebra,
        "zebraFill": colorToJson(zebraFill),
        "grid": grid.name,
        "gridWidth": gridWidth,
        "gridColor": colorToJson(gridColor),
        "pad": cellPadding,
        "cr": cornerRadius,
        if (pictureScale != 1) "picScale": pictureScale,
        if (columnWidths.isNotEmpty) "cols": columnWidths,
        "headerRatio": headerHeightRatio,
        if (rules.isNotEmpty) "rules": [for (var rule in rules) rule.toJson()],
        if (sort.on || !sort.pinFirstColumn) "sort": sort.toJson(),
        if (source.on) "source": source.toJson(),
      };

  factory TableElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["rows"];
    var cols = json["cols"];
    return TableElement(b,
        rows: raw is List
            ? [
                for (var r in raw)
                  if (r is List) [for (var c in r) "$c"],
              ]
            : const [],
        headerRow: jsonBool(json["headerRow"], true),
        headerColumn: jsonBool(json["headerCol"], false),
        showOutline: !jsonBool(json["noOutline"], false),
        cellSpec: jsonSpec(
            json["cellSpec"],
            TextSpec.fromJson,
            const TextSpec(
                fontSize: 18, weight: 400, align: TextAlignSpec.left)),
        headerSpec: jsonSpec(
            json["headerSpec"],
            TextSpec.fromJson,
            const TextSpec(
                fontSize: 18, weight: 700, align: TextAlignSpec.left)),
        headerFill: colorFromJson(json["headerFill"], const Color(0xFF1D2733)),
        cellFill: colorFromJson(json["cellFill"], const Color(0x00000000)),
        zebra: jsonBool(json["zebra"], true),
        zebraFill: colorFromJson(json["zebraFill"], const Color(0x0DFFFFFF)),
        grid: TableGrid.fromName(json["grid"] as String?),
        gridWidth: jsonDouble(json["gridWidth"], 1),
        gridColor: colorFromJson(json["gridColor"], const Color(0x33FFFFFF)),
        cellPadding: jsonDouble(json["pad"], 10),
        cornerRadius: jsonDouble(json["cr"], 6),
        pictureScale: jsonDouble(json["picScale"], 1).clamp(0.05, 1.0),
        columnWidths: cols is List
            ? [for (var c in cols) c is num ? c.toDouble() : 1.0]
            : const [],
        headerHeightRatio: jsonDouble(json["headerRatio"], 1.15),
        rules: [
          if (json["rules"] case List raw)
            for (var rule in raw)
              if (rule is Map<String, dynamic>) TableRule.fromJson(rule),
        ],
        sort: jsonSpec(json["sort"], TableSort.fromJson, const TableSort()),
        source:
            jsonSpec(json["source"], DataSource.fromJson, const DataSource()));
  }

  /// sorted is this table with its rows in the order [sort] asks for.
  ///
  /// Returns the same table when there is nothing to do, so a caller can apply
  /// it unconditionally -- after a refresh, say -- without producing an undo
  /// step for a table that was never sorted.
  TableElement sorted() {
    if (!sort.on) return this;
    var next = sortTableRows(rows, sort, headerRow: headerRow);
    return identical(next, rows) ? this : copyWith(rows: next);
  }
}
