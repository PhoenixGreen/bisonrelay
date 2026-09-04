import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// TableGrid is which rules a table draws between its cells.
enum TableGrid {
  all("All"),
  horizontal("Rows only"),
  vertical("Columns only"),
  outer("Outline only"),
  none("None");

  final String label;
  const TableGrid(this.label);

  static TableGrid fromName(String? name) =>
      values.firstWhere((g) => g.name == name, orElse: () => TableGrid.horizontal);

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
    this.align,
    this.verticalAlign,
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.sides = const [true, true, true, true],
    this.radius = 4,
    this.inset = 6,
    this.hug = true,
  });

  bool get allSides => !sides.contains(false);

  bool get paintsBox => background.a > 0 || (borderColor.a > 0 && borderWidth > 0);

  bool get changesType =>
      textColor.a > 0 ||
      fontScale != 1 ||
      weight != 0 ||
      align != null ||
      verticalAlign != null;

  TableCellStyle copyWith({
    Color? background,
    Color? textColor,
    double? fontScale,
    int? weight,
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
  }) =>
      TableCellStyle(
        background: background ?? this.background,
        textColor: textColor ?? this.textColor,
        fontScale: fontScale ?? this.fontScale,
        weight: weight ?? this.weight,
        align: clearAlign ? null : (align ?? this.align),
        verticalAlign:
            clearVerticalAlign ? null : (verticalAlign ?? this.verticalAlign),
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        sides: sides ?? this.sides,
        radius: radius ?? this.radius,
        inset: inset ?? this.inset,
        hug: hug ?? this.hug,
      );

  Map<String, dynamic> toJson() => {
        if (background.a > 0) "bg": colorToJson(background),
        if (textColor.a > 0) "fg": colorToJson(textColor),
        if (fontScale != 1) "scale": fontScale,
        if (weight != 0) "weight": weight,
        if (align != null) "align": align!.name,
        if (verticalAlign != null) "valign": verticalAlign!.name,
        if (borderColor.a > 0) "bc": colorToJson(borderColor),
        if (borderWidth != 0) "bw": borderWidth,
        if (!allSides) "sides": sides,
        if (radius != 4) "r": radius,
        if (inset != 6) "inset": inset,
        if (!hug) "fill": true,
      };

  factory TableCellStyle.fromJson(Map<String, dynamic> json) => TableCellStyle(
        background: colorFromJson(json["bg"], const Color(0x00000000)),
        textColor: colorFromJson(json["fg"], const Color(0x00000000)),
        fontScale: jsonDouble(json["scale"], 1).clamp(0.2, 6.0),
        weight: jsonInt(json["weight"], 0),
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
      );
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

  /// spanMatches is the little range language, shared by the rows and the
  /// columns because they are asking the same question.
  ///
  /// Empty is any. "3" is one, counting from one. "2:4" is a block, "&gt;1"
  /// everything after, "&lt;4" everything before.
  ///
  /// An unreadable range matches nothing rather than everything, for the same
  /// reason an unknown column name does: a typo should show up as a rule that
  /// does nothing, not as a table painted entirely green.
  static bool spanMatches(String spec, int index) {
    var text = spec.trim();
    if (text.isEmpty) return true;
    var at = index + 1;

    if (text.startsWith(">")) {
      var from = int.tryParse(text.substring(1).trim());
      return from == null ? false : at > from;
    }
    if (text.startsWith("<")) {
      var to = int.tryParse(text.substring(1).trim());
      return to == null ? false : at < to;
    }
    if (text.contains(":")) {
      var parts = text.split(":");
      var from = int.tryParse(parts.first.trim());
      var to = int.tryParse(parts.last.trim());
      if (from == null || to == null) return false;
      return at >= math.min(from, to) && at <= math.max(from, to);
    }
    var one = int.tryParse(text);
    return one == null ? false : at == one;
  }

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

    var byName = header.indexWhere(
        (h) => h.trim().toLowerCase() == spec.toLowerCase());
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
  List<(int, int)> runsIn(String cell) {
    var wanted = match.trim().toLowerCase();
    if (wanted.isEmpty) return const [];
    var lower = cell.toLowerCase();

    switch (how) {
      case TableMatch.cell:
        return cell.trim().toLowerCase() == wanted ? [(0, cell.length)] : const [];
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
        style: jsonSpec(json["style"], TableCellStyle.fromJson,
            const TableCellStyle()),
      );
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

  final TextSpec cellSpec;
  final TextSpec headerSpec;

  final Color headerFill;
  final Color cellFill;

  /// zebra tints alternate rows, and is the single most effective thing for
  /// making a wide table readable.
  final bool zebra;
  final Color zebraFill;

  final TableGrid grid;
  final double gridWidth;
  final Color gridColor;

  final double cellPadding;
  final double cornerRadius;

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
    this.cellSpec = const TextSpec(
        fontSize: 18, weight: 400, align: TextAlignSpec.left),
    this.headerSpec = const TextSpec(
        fontSize: 18, weight: 700, align: TextAlignSpec.left),
    this.headerFill = const Color(0xFF1D2733),
    this.cellFill = const Color(0x00000000),
    this.zebra = true,
    this.zebraFill = const Color(0x0DFFFFFF),
    this.grid = TableGrid.horizontal,
    this.gridWidth = 1,
    this.gridColor = const Color(0x33FFFFFF),
    this.cellPadding = 10,
    this.cornerRadius = 6,
    this.columnWidths = const [],
    this.headerHeightRatio = 1.15,
    this.rules = const [],
  });

  @override
  ElementKind get kind => ElementKind.table;

  int get columnCount =>
      rows.fold(0, (n, r) => r.length > n ? r.length : n);

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
  List<String> get header => headerRow && rows.isNotEmpty ? rows.first : const [];

  /// styleFor is the look of one cell: every rule that matches it, later ones
  /// winning, or null when none do.
  ///
  /// Later wins because that is what a list of exceptions means -- the one
  /// written last is the one thought of last.
  TableCellStyle? styleFor(int row, int col) {
    TableCellStyle? out;
    var head = header;
    for (var rule in rules) {
      if (!rule.matchesRow(row)) continue;
      if (!rule.matchesColumn(col, head)) continue;
      if (!rule.matches(cell(row, col))) continue;
      out = out == null
          ? rule.style
          : out.copyWith(
              background: rule.style.background.a > 0
                  ? rule.style.background
                  : out.background,
              textColor:
                  rule.style.textColor.a > 0 ? rule.style.textColor : out.textColor,
              fontScale:
                  rule.style.fontScale != 1 ? rule.style.fontScale : out.fontScale,
              weight: rule.style.weight != 0 ? rule.style.weight : out.weight,
              align: rule.style.align ?? out.align,
              verticalAlign: rule.style.verticalAlign ?? out.verticalAlign,
              borderColor: rule.style.borderColor.a > 0
                  ? rule.style.borderColor
                  : out.borderColor,
              borderWidth: rule.style.borderWidth != 0
                  ? rule.style.borderWidth
                  : out.borderWidth,
              sides: rule.style.allSides ? out.sides : rule.style.sides,
              radius: rule.style.radius,
              inset: rule.style.inset,
              hug: rule.style.hug,
            );
    }
    return out;
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
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
  }) =>
      _copy(base,
          rows: rows,
          headerRow: headerRow,
          headerColumn: headerColumn,
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
          columnWidths: columnWidths,
          headerHeightRatio: headerHeightRatio,
          rules: rules);

  TableElement _copy(
    ElementBase newBase, {
    List<List<String>>? rows,
    bool? headerRow,
    bool? headerColumn,
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
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
  }) =>
      TableElement(newBase,
          rows: rows ?? this.rows,
          headerRow: headerRow ?? this.headerRow,
          headerColumn: headerColumn ?? this.headerColumn,
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
          columnWidths: columnWidths ?? this.columnWidths,
          headerHeightRatio: headerHeightRatio ?? this.headerHeightRatio,
          rules: rules ?? this.rules);

  @override
  Map<String, dynamic> props() => {
        "rows": rows,
        "headerRow": headerRow,
        if (headerColumn) "headerCol": true,
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
        if (columnWidths.isNotEmpty) "cols": columnWidths,
        "headerRatio": headerHeightRatio,
        if (rules.isNotEmpty)
          "rules": [for (var rule in rules) rule.toJson()],
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
        cellSpec: jsonSpec(json["cellSpec"], TextSpec.fromJson,
            const TextSpec(fontSize: 18, weight: 400, align: TextAlignSpec.left)),
        headerSpec: jsonSpec(json["headerSpec"], TextSpec.fromJson,
            const TextSpec(fontSize: 18, weight: 700, align: TextAlignSpec.left)),
        headerFill: colorFromJson(json["headerFill"], const Color(0xFF1D2733)),
        cellFill: colorFromJson(json["cellFill"], const Color(0x00000000)),
        zebra: jsonBool(json["zebra"], true),
        zebraFill: colorFromJson(json["zebraFill"], const Color(0x0DFFFFFF)),
        grid: TableGrid.fromName(json["grid"] as String?),
        gridWidth: jsonDouble(json["gridWidth"], 1),
        gridColor: colorFromJson(json["gridColor"], const Color(0x33FFFFFF)),
        cellPadding: jsonDouble(json["pad"], 10),
        cornerRadius: jsonDouble(json["cr"], 6),
        columnWidths: cols is List
            ? [for (var c in cols) c is num ? c.toDouble() : 1.0]
            : const [],
        headerHeightRatio: jsonDouble(json["headerRatio"], 1.15),
        rules: [
          if (json["rules"] case List raw)
            for (var rule in raw)
              if (rule is Map<String, dynamic>) TableRule.fromJson(rule),
        ]);
  }
}
