import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// Exported so that importing table_element.dart brings the sort too.
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

/// TableCellStyle is a look one rule paints onto the cells it matches. Every
/// field has a "leave it alone" value, since a rule is an exception rather
/// than a complete description.
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

  /// letterWidth lays the cell's characters out on a fixed pitch, so a row
  /// of letter boxes lines up; zero is natural widths. [letterSpacing] is the
  /// gap between the slots.
  ///
  /// Only a rule about the whole cell may set it ([TableElement.lookAt]
  /// enforces that), since the pitch lays out every letter in the cell.
  final double letterWidth;

  /// letterSpacing is 0 to keep the type's own.
  final double letterSpacing;

  /// align and verticalAlign are null to keep the type's own.
  final TextAlignSpec? align;
  final VerticalAlignSpec? verticalAlign;

  final Color borderColor;
  final double borderWidth;

  /// sides is which edges the border is drawn on, in the order top, right,
  /// bottom, left.
  final List<bool> sides;

  final double radius;

  /// inset shrinks the painted box inside its cell, which is what turns a
  /// background into a chip rather than a filled cell.
  final double inset;

  /// textPad is extra room either side of the words, on top of the table's
  /// own cell padding, so one column can have a margin.
  final double textPad;

  /// minWidth and minHeight are the least a hugging box may be, so a row of
  /// chips round letters of different widths comes out the same size.
  final double minWidth;
  final double minHeight;

  /// nudgeX and nudgeY move the *letter* inside its box, for a glyph whose
  /// ink is not centred on its advance. The letter rather than the box, so the
  /// boxes stay in line; a nudge because the text engine cannot measure ink.
  final double nudgeX;
  final double nudgeY;

  /// hug fits the box to the words (a chip, the default) rather than filling
  /// the cell.
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

  /// scaledBy is this style at [by] times the size: the measurements only, not
  /// fontScale, which multiplies a size that is scaled already.
  TableCellStyle scaledBy(double by) => copyWith(
        letterSpacing: letterSpacing * by,
        letterWidth: letterWidth * by,
        borderWidth: borderWidth * by,
        radius: radius * by,
        inset: inset * by,
        textPad: textPad * by,
        minWidth: minWidth * by,
        minHeight: minHeight * by,
        nudgeX: nudgeX * by,
        nudgeY: nudgeY * by,
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
            ? TextAlignSpec.fromName(jsonStr(json["align"]))
            : null,
        verticalAlign: json["valign"] is String
            ? VerticalAlignSpec.fromName(jsonStr(json["valign"]))
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

/// _Span is a parsed range: "", "3", "2:4", ">1", "<4". Cached in
/// TableRule._spans.
class _Span {
  final int from;
  final int to;
  const _Span(this.from, this.to);

  /// any is the empty spec, and none is one that could not be read, which
  /// matches nothing so a typo does not paint the whole table.
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

/// TableRule is "these cells look like that": a column, rows and text to
/// match, each meaning "any" when left blank.
class TableRule {
  /// column is a heading ("Points"), or a range of column numbers counting
  /// from one, in the [spanMatches] language.
  final String column;

  /// rows is which rows, counting from one and including the header, in the
  /// [spanMatches] language.
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

  /// banded is a rule with no text to look for, drawn as one box around
  /// everything it picks out (a band across or down the table) rather than a
  /// chip round each match.
  bool get banded => match.isEmpty;

  /// matchesRow reads the range language. [index] counts from zero.
  bool matchesRow(int index) => spanMatches(rows, index);

  /// _spans remembers what a range string means: they are read once per cell
  /// per rule per frame, and only a handful are distinct.
  static final Map<String, _Span> _spans = {};

  /// _spanOf parses [spec], keeping the map to the ranges a canvas has:
  /// cleared past a few hundred, as _lowered is.
  static _Span _spanOf(String spec) {
    if (_spans.length > 256) _spans.clear();
    return _Span.parse(spec);
  }

  /// spanMatches is the range language shared by rows and columns. Empty is
  /// any, "3" is one (counting from one), "2:4" a block, `>1` everything
  /// after, `<4` everything before. An unreadable range matches nothing.
  static bool spanMatches(String spec, int index) =>
      (_spans[spec] ??= _spanOf(spec)).covers(index + 1);

  /// matchesColumn is whether [index] is one of the columns this rule is
  /// about: by heading first, else as a range (see [spanMatches]).
  bool matchesColumn(int index, List<String> header) {
    var spec = column.trim();
    if (spec.isEmpty) return true;

    var byName =
        header.indexWhere((h) => h.trim().toLowerCase() == spec.toLowerCase());
    if (byName >= 0) return byName == index;
    return spanMatches(spec, index);
  }

  bool matches(String cell) => match.isEmpty || runsIn(cell).isNotEmpty;

  /// runIn is the first place the match falls inside [cell].
  (int, int)? runIn(String cell) {
    var all = runsIn(cell);
    return all.isEmpty ? null : all.first;
  }

  /// _lowered caches each rule text lowered. Kept to a few hundred: every
  /// keystroke in a rule is a new key.
  static final Map<String, String> _lowered = {};

  /// runsIn is every place the match falls inside [cell], as character
  /// ranges, so each gets its own chip. [lowered] is [cell] lowered, if the
  /// caller already has it.
  List<(int, int)> runsIn(String cell, [String? lowered]) {
    if (_lowered.length > 256) _lowered.clear();
    var wanted = _lowered[match] ??= match.trim().toLowerCase();
    if (wanted.isEmpty) return const [];
    var lower = lowered ?? cell.toLowerCase();

    switch (how) {
      case TableMatch.cell:
        return cell.trim().toLowerCase() == wanted
            ? [(0, cell.length)]
            : const [];
      case TableMatch.anywhere:
      case TableMatch.word:
        // A whole word is bounded by anything that is not a letter or digit.
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

  static bool _wordish(String c) => c.isNotEmpty && _letterOrDigit.hasMatch(c);
  static final RegExp _letterOrDigit = RegExp(r"[a-z0-9]");

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
        rows: jsonString(json["rows"], ""),
        match: jsonString(json["match"], ""),
        how: TableMatch.fromName(jsonStr(json["how"])),
        style: jsonSpec(
            json["style"], TableCellStyle.fromJson, const TableCellStyle()),
      );
}

/// TableCellLook is everything the rules say about one cell, worked out in
/// one walk of the rules so the painter's several questions share it.
class TableCellLook {
  /// style is the cell's own look: what a rule about the whole cell says.
  final TableCellStyle? style;

  /// words are the rules that named a word, with the places they found it.
  /// In the order they were written, so a later one draws over an earlier.
  final List<(TableRule, List<(int, int)>)> words;

  const TableCellLook(this.style, this.words);

  static const nothing = TableCellLook(null, []);

  bool get isEmpty => style == null && words.isEmpty;

  /// ruleAt is the rule that claims the character at [index]; a later rule
  /// wins.
  TableRule? ruleAt(int index) {
    for (var i = words.length - 1; i >= 0; i--) {
      for (var (from, to) in words[i].$2) {
        if (index >= from && index < to) return words[i].$1;
      }
    }
    return null;
  }
}

/// TableElement is a grid of strings, painted (render/table_painter.dart)
/// rather than laid out as widgets, so it exports, rotates and animates like
/// the rest of the canvas. No formulas or column types: the numbers are
/// computed wherever they came from.
class TableElement extends CanvasElement {
  /// rows is the whole grid including the header, if there is one. Ragged
  /// rows are tolerated and padded out at paint time.
  final List<List<String>> rows;

  final bool headerRow;
  final bool headerColumn;

  /// hiddenHeaders are the columns whose header text is not drawn, by index.
  /// The text is kept, so the column still has a name for the data mapping
  /// and the sort.
  final List<int> hiddenHeaders;

  /// showOutline is the rule round the outside of the table, separate from
  /// [grid] so any combination can be had.
  final bool showOutline;

  final TextSpec cellSpec;
  final TextSpec headerSpec;

  final Color headerFill;
  final Color cellFill;

  /// headerFade and cellFade are the second colours those two fade to, or
  /// null for flat ones. Both run across the whole table, not restarting on
  /// every row.
  final GradientSpec? headerFade;
  final GradientSpec? cellFade;

  /// zebra tints alternate rows.
  final bool zebra;
  final Color zebraFill;

  /// source is where the rows came from, when they came from somewhere. See
  /// DataSource.
  final DataSource source;

  /// sort is the order the rows were last put in, kept so that the same order
  /// can be applied again after the data underneath changes.
  final TableSort sort;

  final TableGrid grid;
  final double gridWidth;
  final Color gridColor;

  /// cellPadding is the room round the words in a cell, on every side that
  /// has not been given a figure of its own.
  final double cellPadding;

  /// padTop, padRight, padBottom and padLeft are those figures: one side's
  /// own padding, or null to follow [cellPadding].
  final double? padTop;
  final double? padRight;
  final double? padBottom;
  final double? padLeft;

  final double cornerRadius;

  /// pictureScale is how much of its cell a picture fills, on top of the
  /// cell's own padding: 1 for the whole cell, less for room round it.
  final double pictureScale;

  /// columnWidths are each column's share of the table's width (normalised
  /// by their sum), or empty for columns sized to their contents.
  final List<double> columnWidths;

  /// headerHeightRatio is how tall the header row is against a body row.
  final double headerHeightRatio;

  /// rules are the exceptions: which cells look different, and how. See
  /// [TableRule].
  final List<TableRule> rules;

  /// animation is how it arrives and leaves. See ElementAnimation.
  final ElementAnimation animation;

  /// topPad and the three beside it are what each side actually gets.
  double get topPad => padTop ?? cellPadding;
  double get rightPad => padRight ?? cellPadding;
  double get bottomPad => padBottom ?? cellPadding;
  double get leftPad => padLeft ?? cellPadding;

  /// evenPadding is whether every side is simply [cellPadding], which is what
  /// the settings panel offers as one field rather than four.
  bool get evenPadding =>
      padTop == null &&
      padRight == null &&
      padBottom == null &&
      padLeft == null;

  /// evenColumns is whether the columns are sized by their contents rather
  /// than by [columnWidths].
  bool get evenColumns => columnWidths.isEmpty;

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
    this.headerFade,
    this.cellFade,
    this.zebra = true,
    this.zebraFill = const Color(0x0DFFFFFF),
    this.grid = TableGrid.horizontal,
    this.gridWidth = 1,
    this.gridColor = const Color(0x33FFFFFF),
    this.cellPadding = 10,
    this.padTop,
    this.padRight,
    this.padBottom,
    this.padLeft,
    this.cornerRadius = 6,
    this.pictureScale = 1,
    this.columnWidths = const [],
    this.headerHeightRatio = 1.15,
    this.rules = const [],
    this.sort = const TableSort(),
    this.source = const DataSource(),
    this.hiddenHeaders = const [],
    this.animation = const ElementAnimation(),
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

  /// pictureCell is the prefix that turns a cell into a picture. Kept in the
  /// cell's own text rather than a map of positions, so it moves with the
  /// cell when rows and columns change.
  static const String pictureCell = "img:";

  /// pictureIn is the asset a cell names, or null when it is words.
  static String? pictureIn(String cell) {
    var text = cell.trim();
    return text.startsWith(pictureCell) && text.length > pictureCell.length
        ? text.substring(pictureCell.length)
        : null;
  }

  /// header is the first row when there is one, for resolving a rule's column
  /// by name; empty otherwise.
  List<String> get header =>
      headerRow && rows.isNotEmpty ? rows.first : const [];

  /// columnName is what to call a column: what its header says, or its number
  /// when it says nothing. Shared by the settings and the charts, so they
  /// agree.
  String columnName(int column) {
    var names = header;
    var name = column < names.length ? names[column].trim() : "";
    return name.isEmpty ? "Column ${column + 1}" : name;
  }

  /// lookAt is what the rules say about one cell. See [TableCellLook].
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
              // pitch are not the cell's to take, first rule or not.
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

  /// styleFor is the cell's own look. Use [lookAt] when asking more than one
  /// question of a cell.
  TableCellStyle? styleFor(int row, int col) => lookAt(row, col).style;

  /// runStyleFor is the type change that belongs to the character at [index],
  /// from whichever rule that names a word claims it.
  TableCellStyle? runStyleFor(int row, int col, int index) {
    var rule = lookAt(row, col).ruleAt(index);
    return rule != null && rule.style.changesType ? rule.style : null;
  }

  /// shows is whether a cell's text is drawn: false only for a header in
  /// [hiddenHeaders]. Its width, rules and background still apply.
  bool shows(int row, int col) =>
      !(headerRow && row == 0 && hiddenHeaders.contains(col));

  /// cell is the string at a position, or "" past the end of a ragged row.
  String cell(int row, int col) {
    if (row < 0 || row >= rows.length) return "";
    var r = rows[row];
    return col >= 0 && col < r.length ? r[col] : "";
  }

  /// asText and parseRows are the quick-entry round trip. See joinTable.
  String asText() => joinTable(rows);

  static List<List<String>> parseRows(String text) => splitTable(text);

  @override
  CanvasElement rebase(ElementBase base) => _copy(base);

  @override
  bool get scalesInside => true;

  /// scaledBy is the type, the room and the rules at [by] times the size.
  /// Columns and rows are fractions of the box and follow it on their own;
  /// these are measurements. See CanvasElement.scaledBy.
  @override
  CanvasElement scaledBy(double by) => copyWith(
        cellSpec: cellSpec.scaledBy(by),
        headerSpec: headerSpec.scaledBy(by),
        cellPadding: cellPadding * by,
        // Null sides follow cellPadding, so stay null.
        padTop: padTop == null ? null : padTop! * by,
        padRight: padRight == null ? null : padRight! * by,
        padBottom: padBottom == null ? null : padBottom! * by,
        padLeft: padLeft == null ? null : padLeft! * by,
        gridWidth: gridWidth * by,
        cornerRadius: cornerRadius * by,
        rules: [
          for (var rule in rules) rule.copyWith(style: rule.style.scaledBy(by))
        ],
      );

  TableElement copyWith({
    List<List<String>>? rows,
    bool? headerRow,
    bool? headerColumn,
    bool? showOutline,
    TextSpec? cellSpec,
    TextSpec? headerSpec,
    Color? headerFill,
    Color? cellFill,
    GradientSpec? headerFade,
    GradientSpec? cellFade,
    bool flatHeader = false,
    bool flatCells = false,
    bool? zebra,
    Color? zebraFill,
    TableGrid? grid,
    double? gridWidth,
    Color? gridColor,
    double? cellPadding,
    double? padTop,
    double? padRight,
    double? padBottom,
    double? padLeft,
    bool evenPadding = false,
    double? cornerRadius,
    double? pictureScale,
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
    TableSort? sort,
    DataSource? source,
    List<int>? hiddenHeaders,
    ElementAnimation? animation,
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
          headerFade: headerFade,
          cellFade: cellFade,
          flatHeader: flatHeader,
          flatCells: flatCells,
          zebra: zebra,
          zebraFill: zebraFill,
          grid: grid,
          gridWidth: gridWidth,
          gridColor: gridColor,
          cellPadding: cellPadding,
          padTop: padTop,
          padRight: padRight,
          padBottom: padBottom,
          padLeft: padLeft,
          evenPadding: evenPadding,
          cornerRadius: cornerRadius,
          pictureScale: pictureScale,
          columnWidths: columnWidths,
          headerHeightRatio: headerHeightRatio,
          rules: rules,
          sort: sort,
          source: source,
          hiddenHeaders: hiddenHeaders,
          animation: animation);

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
    GradientSpec? headerFade,
    GradientSpec? cellFade,
    bool flatHeader = false,
    bool flatCells = false,
    bool? zebra,
    Color? zebraFill,
    TableGrid? grid,
    double? gridWidth,
    Color? gridColor,
    double? cellPadding,
    double? padTop,
    double? padRight,
    double? padBottom,
    double? padLeft,
    bool evenPadding = false,
    double? cornerRadius,
    double? pictureScale,
    List<double>? columnWidths,
    double? headerHeightRatio,
    List<TableRule>? rules,
    TableSort? sort,
    DataSource? source,
    List<int>? hiddenHeaders,
    ElementAnimation? animation,
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
          headerFade: flatHeader ? null : (headerFade ?? this.headerFade),
          cellFade: flatCells ? null : (cellFade ?? this.cellFade),
          zebra: zebra ?? this.zebra,
          zebraFill: zebraFill ?? this.zebraFill,
          grid: grid ?? this.grid,
          gridWidth: gridWidth ?? this.gridWidth,
          gridColor: gridColor ?? this.gridColor,
          cellPadding: cellPadding ?? this.cellPadding,
          padTop: evenPadding ? null : (padTop ?? this.padTop),
          padRight: evenPadding ? null : (padRight ?? this.padRight),
          padBottom: evenPadding ? null : (padBottom ?? this.padBottom),
          padLeft: evenPadding ? null : (padLeft ?? this.padLeft),
          cornerRadius: cornerRadius ?? this.cornerRadius,
          pictureScale: pictureScale ?? this.pictureScale,
          columnWidths: columnWidths ?? this.columnWidths,
          headerHeightRatio: headerHeightRatio ?? this.headerHeightRatio,
          rules: rules ?? this.rules,
          sort: sort ?? this.sort,
          source: source ?? this.source,
          hiddenHeaders: hiddenHeaders ?? this.hiddenHeaders,
          animation: animation ?? this.animation);

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
        if (headerFade != null) "headerFade": headerFade!.toJson(),
        if (cellFade != null) "cellFade": cellFade!.toJson(),
        "zebra": zebra,
        "zebraFill": colorToJson(zebraFill),
        "grid": grid.name,
        "gridWidth": gridWidth,
        "gridColor": colorToJson(gridColor),
        "pad": cellPadding,
        if (padTop != null) "padTop": padTop,
        if (padRight != null) "padRight": padRight,
        if (padBottom != null) "padBottom": padBottom,
        if (padLeft != null) "padLeft": padLeft,
        "cr": cornerRadius,
        if (pictureScale != 1) "picScale": pictureScale,
        if (columnWidths.isNotEmpty) "cols": columnWidths,
        "headerRatio": headerHeightRatio,
        if (rules.isNotEmpty) "rules": [for (var rule in rules) rule.toJson()],
        if (sort.on || !sort.pinFirstColumn) "sort": sort.toJson(),
        if (source.on) "source": source.toJson(),
        if (hiddenHeaders.isNotEmpty) "hiddenHeaders": hiddenHeaders,
        if (animation.any) "anim": animation.toJson(),
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
        headerFade: json["headerFade"] is Map
            ? GradientSpec.fromJson(
                (json["headerFade"] as Map).cast<String, dynamic>())
            : null,
        cellFade: json["cellFade"] is Map
            ? GradientSpec.fromJson(
                (json["cellFade"] as Map).cast<String, dynamic>())
            : null,
        zebra: jsonBool(json["zebra"], true),
        zebraFill: colorFromJson(json["zebraFill"], const Color(0x0DFFFFFF)),
        grid: TableGrid.fromName(jsonStr(json["grid"])),
        gridWidth: jsonDouble(json["gridWidth"], 1),
        gridColor: colorFromJson(json["gridColor"], const Color(0x33FFFFFF)),
        cellPadding: jsonDouble(json["pad"], 10),
        padTop:
            json["padTop"] is num ? (json["padTop"] as num).toDouble() : null,
        padRight: json["padRight"] is num
            ? (json["padRight"] as num).toDouble()
            : null,
        padBottom: json["padBottom"] is num
            ? (json["padBottom"] as num).toDouble()
            : null,
        padLeft:
            json["padLeft"] is num ? (json["padLeft"] as num).toDouble() : null,
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
            jsonSpec(json["source"], DataSource.fromJson, const DataSource()),
        hiddenHeaders: [
          if (json["hiddenHeaders"] case List raw)
            for (var c in raw)
              if (c is num) c.toInt(),
        ],
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }

  /// sorted is this table with its rows in the order [sort] asks for, or
  /// this same table when there is nothing to do, so it can be applied
  /// unconditionally (after a refresh, say).
  TableElement sorted() {
    if (!sort.on) return this;
    var next = sortTableRows(rows, sort, headerRow: headerRow);
    return identical(next, rows) ? this : copyWith(rows: next);
  }
}
