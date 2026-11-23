import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// Exported so that importing table_element.dart brings the sort too.
export 'package:bruig/plugin_system/canvas/model/elements/table_sort.dart';

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_sort.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

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

/// TableTurn is how a table's arrival brings it in: whole, or a row or a
/// column at a time, each with the arrival's own movement.
enum TableTurn {
  together("Together"),
  rows("Row by row"),
  columns("Column by column");

  final String label;
  const TableTurn(this.label);

  static TableTurn fromName(String? name) => values
      .firstWhere((t) => t.name == name, orElse: () => TableTurn.together);

  /// revealOf is how far piece [index] of [count] is in when the arrival is
  /// [through] in: a cascade, each starting before the one before ends.
  static double revealOf(double through, int index, int count) {
    if (count <= 1) return through.clamp(0.0, 1.0).toDouble();
    var length = math.min(1.0, 2 / (count + 1));
    var start = index * (1 - length) / (count - 1);
    return ((through - start) / length).clamp(0.0, 1.0).toDouble();
  }
}

/// TableCellStyle is a look one rule paints onto the cells it matches.
/// Every field has a "leave it alone" value: a rule is an exception.
class TableCellStyle {
  /// background is painted behind the cell; transparent keeps the row's fill.
  final Color background;

  /// textColor is transparent to keep the type's own colour.
  final Color textColor;

  /// fontScale multiplies the cell's font size. 1 leaves it.
  final double fontScale;

  /// weight is 0 to keep the type's own, and 100..900 to override it.
  final int weight;

  /// letterWidth sets the characters on a fixed pitch so letter boxes line
  /// up; zero is natural. Only a rule about the whole cell may set it.
  final double letterWidth;

  /// letterSpacing is 0 to keep the type's own.
  final double letterSpacing;

  /// align and verticalAlign are null to keep the type's own.
  final TextAlignSpec? align;
  final VerticalAlignSpec? verticalAlign;

  final Color borderColor;
  final double borderWidth;

  /// sides is which edges the border is drawn on: top, right, bottom, left.
  final List<bool> sides;

  final double radius;

  /// inset shrinks the painted box inside its cell, making a chip.
  final double inset;

  /// textPad is extra room either side of the words, beyond cell padding.
  final double textPad;

  /// minWidth and minHeight are the least a hugging box may be, so chips
  /// round letters of different widths come out the same size.
  final double minWidth;
  final double minHeight;

  /// nudgeX and nudgeY move the letter, not its box, for a glyph whose ink
  /// is not centred on its advance: the text engine cannot measure ink.
  final double nudgeX;
  final double nudgeY;

  /// hug fits the box to the words (a chip) rather than filling the cell.
  final bool hug;

  /// redact draws a bar over each line of the words, which stay in the cell.
  /// Only a rule about the whole cell may set it (see [TableElement.lookAt]).
  final bool redact;

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
    this.redact = false,
    this.textPad = 0,
    this.nudgeX = 0,
    this.nudgeY = 0,
    this.minWidth = 0,
    this.minHeight = 0,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TableCellStyle();

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
    bool? redact,
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
        redact: redact ?? this.redact,
        textPad: textPad ?? this.textPad,
        minWidth: minWidth ?? this.minWidth,
        minHeight: minHeight ?? this.minHeight,
        nudgeX: nudgeX ?? this.nudgeX,
        nudgeY: nudgeY ?? this.nudgeY,
      );

  /// mapColours maps the cell's fill, words and border colours, each
  /// transparent one hidden (as it is saved: transparent is "the table's
  /// own").
  TableCellStyle mapColours(ColourMap f) {
    var p = ColourPass(f);
    var background = p(this.background, shown: this.background.a > 0);
    var textColor = p(this.textColor, shown: this.textColor.a > 0);
    var borderColor = p(this.borderColor, shown: this.borderColor.a > 0);
    if (!p.changed) return this;
    return copyWith(
        background: background, textColor: textColor, borderColor: borderColor);
  }

  /// scaledBy scales the measurements only, not fontScale, which multiplies
  /// a size that is scaled already.
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
        if (fontScale != _defaults.fontScale) "scale": fontScale,
        if (weight != _defaults.weight) "weight": weight,
        if (letterSpacing != _defaults.letterSpacing) "ls": letterSpacing,
        if (letterWidth != _defaults.letterWidth) "lw": letterWidth,
        if (align != null) "align": align!.name,
        if (verticalAlign != null) "valign": verticalAlign!.name,
        if (borderColor.a > 0) "bc": colorToJson(borderColor),
        if (borderWidth != _defaults.borderWidth) "bw": borderWidth,
        if (!allSides) "sides": sides,
        if (radius != _defaults.radius) "r": radius,
        if (inset != _defaults.inset) "inset": inset,
        if (!hug) "fill": true,
        if (redact) "redact": true,
        if (textPad != _defaults.textPad) "pad": textPad,
        if (minWidth != _defaults.minWidth) "minw": minWidth,
        if (minHeight != _defaults.minHeight) "minh": minHeight,
        if (nudgeX != _defaults.nudgeX) "nx": nudgeX,
        if (nudgeY != _defaults.nudgeY) "ny": nudgeY,
      };

  factory TableCellStyle.fromJson(Map<String, dynamic> json) => TableCellStyle(
        background: colorFromJson(json["bg"], _defaults.background),
        textColor: colorFromJson(json["fg"], _defaults.textColor),
        fontScale:
            jsonDouble(json["scale"], _defaults.fontScale).clamp(0.2, 6.0),
        weight: jsonInt(json["weight"], _defaults.weight),
        letterSpacing: jsonDouble(json["ls"], _defaults.letterSpacing),
        letterWidth: jsonDouble(json["lw"], _defaults.letterWidth),
        align: json["align"] is String
            ? TextAlignSpec.fromName(jsonStr(json["align"]))
            : null,
        verticalAlign: json["valign"] is String
            ? VerticalAlignSpec.fromName(jsonStr(json["valign"]))
            : null,
        borderColor: colorFromJson(json["bc"], _defaults.borderColor),
        borderWidth: jsonDouble(json["bw"], _defaults.borderWidth),
        sides: json["sides"] is List && (json["sides"] as List).length == 4
            ? [for (var v in json["sides"] as List) v == true]
            : const [true, true, true, true],
        radius: jsonDouble(json["r"], _defaults.radius),
        inset: jsonDouble(json["inset"], _defaults.inset),
        hug: !jsonBool(json["fill"], false),
        redact: jsonBool(json["redact"], false),
        textPad: jsonDouble(json["pad"], _defaults.textPad),
        minWidth: jsonDouble(json["minw"], _defaults.minWidth),
        minHeight: jsonDouble(json["minh"], _defaults.minHeight),
        nudgeX: jsonDouble(json["nx"], _defaults.nudgeX),
        nudgeY: jsonDouble(json["ny"], _defaults.nudgeY),
      );
}

/// _Span is a parsed range: "", "3", "2:4", ">1", "<4".
class _Span {
  final int from;
  final int to;
  const _Span(this.from, this.to);

  /// any is the empty spec; none, an unreadable one, matches nothing.
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

enum TableMatch {
  /// cell wants the whole cell: "W" finds neither "Won" nor "--- W".
  cell("The whole cell"),

  anywhere("Anywhere in it"),

  /// word finds it as a word of its own ("--- W", not "Won"), and the chip is
  /// drawn round that word rather than the whole cell.
  word("A whole word");

  final String label;
  const TableMatch(this.label);

  static TableMatch fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => TableMatch.cell);
}

/// TableWhen is a number a row must have for a rule to reach it: "Points 9
/// or more". [column] is a heading or a number counting from one.
class TableWhen {
  final String column;

  /// op is one of ">=", "<=", ">", "<" and "=".
  final String op;
  final double value;
  const TableWhen(this.column, this.op, this.value);

  static const ops = [">=", "<=", ">", "<", "="];

  bool holds(double n) => switch (op) {
        ">=" => n >= value,
        "<=" => n <= value,
        ">" => n > value,
        "<" => n < value,
        _ => n == value,
      };

  TableWhen copyWith({String? column, String? op, double? value}) =>
      TableWhen(column ?? this.column, op ?? this.op, value ?? this.value);

  Map<String, dynamic> toJson() => {"col": column, "op": op, "v": value};

  static TableWhen? fromJson(dynamic json) {
    if (json is! Map) return null;
    var op = json["op"];
    var v = json["v"];
    return TableWhen(jsonString(json["col"], ""),
        ops.contains(op) ? op as String : ">=", v is num ? v.toDouble() : 0);
  }

  @override
  bool operator ==(Object other) =>
      other is TableWhen &&
      other.column == column &&
      other.op == op &&
      other.value == value;

  @override
  int get hashCode => Object.hash(column, op, value);
}

/// TableRule is "these cells look like that": a column, rows and text to
/// match, each meaning "any" when blank.
class TableRule {
  /// column is a heading or a range of column numbers (see [spanMatches]).
  final String column;

  /// rows counts from one, including the header (see [spanMatches]).
  final String rows;

  /// match is the text to look for; empty matches every cell.
  final String match;

  final TableMatch how;

  final TableCellStyle style;

  /// name is what the Data Studio's Table tab calls this rule; empty is
  /// named from what it reaches (see table_design.dart).
  final String name;

  /// off keeps the rule without drawing it (the Table tab's eye).
  final bool off;

  /// keys are rows this rule follows by what they say in [keyColumn], so a
  /// style stays with its team as the team moves. Empty is rows by place
  /// only; both apply if both are set.
  final List<String> keys;
  final String keyColumn;

  final TableWhen? when;

  const TableRule({
    this.column = "",
    this.rows = "",
    this.match = "",
    this.how = TableMatch.cell,
    this.style = const TableCellStyle(),
    this.name = "",
    this.off = false,
    this.keys = const [],
    this.keyColumn = "",
    this.when,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TableRule();

  /// banded is a rule with no text: one box round all it picks out rather
  /// than a chip round each match.
  bool get banded => match.isEmpty;

  /// matchesRow reads the range language; [index] counts from zero.
  bool matchesRow(int index) => spanMatches(rows, index);

  /// readsRows is whether reaching a row needs what the row says.
  bool get readsRows => keys.isNotEmpty || when != null;

  /// reachesRow is [matchesRow] asking the row's words too: [cellAt] gives
  /// column [col].
  bool reachesRow(
      int index, List<String> header, String Function(int col) cellAt) {
    if (!matchesRow(index)) return false;
    if (keys.isNotEmpty) {
      var k = columnIndexOf(keyColumn, header);
      if (k < 0) return false;
      var said = cellAt(k).trim().toLowerCase();
      if (!keys.any((x) => x.trim().toLowerCase() == said)) return false;
    }
    var w = when;
    if (w != null) {
      var k = columnIndexOf(w.column, header);
      if (k < 0) return false;
      var n = cellNumber(cellAt(k));
      if (n == null || !w.holds(n)) return false;
    }
    return true;
  }

  /// columnIndexOf finds a column by heading or number from one; -1 if none.
  static int columnIndexOf(String spec, List<String> header) {
    var s = spec.trim();
    if (s.isEmpty) return -1;
    var byName =
        header.indexWhere((h) => h.trim().toLowerCase() == s.toLowerCase());
    if (byName >= 0) return byName;
    var n = int.tryParse(s);
    return n == null ? -1 : n - 1;
  }

  /// _spans caches parsed ranges: read once per cell per rule per frame, and
  /// only a handful are distinct.
  static final Map<String, _Span> _spans = {};

  /// _spanOf parses [spec], clearing the cache past a few hundred entries.
  static _Span _spanOf(String spec) {
    if (_spans.length > 256) _spans.clear();
    return _Span.parse(spec);
  }

  /// spanMatches is the range language shared by rows and columns: empty is
  /// any, "3" one (from one), "2:4" a block, `>1` after, `<4` before. An
  /// unreadable range matches nothing, so a typo does not paint the table.
  static bool spanMatches(String spec, int index) =>
      (_spans[spec] ??= _spanOf(spec)).covers(index + 1);

  /// matchesColumn checks by heading first, else as a range.
  bool matchesColumn(int index, List<String> header) {
    var spec = column.trim();
    if (spec.isEmpty) return true;

    var byName =
        header.indexWhere((h) => h.trim().toLowerCase() == spec.toLowerCase());
    if (byName >= 0) return byName == index;
    return spanMatches(spec, index);
  }

  bool matches(String cell) => match.isEmpty || runsIn(cell).isNotEmpty;

  (int, int)? runIn(String cell) {
    var all = runsIn(cell);
    return all.isEmpty ? null : all.first;
  }

  /// _lowered caches each rule text lowered, kept to a few hundred entries:
  /// every keystroke in a rule is a new key.
  static final Map<String, String> _lowered = {};

  /// runsIn is every character range the match falls in, each getting its
  /// own chip. [lowered] is [cell] lowered, if the caller has it.
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
    String? name,
    bool? off,
    List<String>? keys,
    String? keyColumn,
    TableWhen? when,
    bool noWhen = false,
  }) =>
      TableRule(
        column: column ?? this.column,
        rows: rows ?? this.rows,
        match: match ?? this.match,
        how: how ?? this.how,
        style: style ?? this.style,
        name: name ?? this.name,
        off: off ?? this.off,
        keys: keys ?? this.keys,
        keyColumn: keyColumn ?? this.keyColumn,
        when: noWhen ? null : when ?? this.when,
      );

  /// mapColours maps the rule's style, hidden while the rule is off.
  TableRule mapColours(ColourMap f) {
    var next = style.mapColours(f.shownOnlyIf(!off));
    return identical(next, style) ? this : copyWith(style: next);
  }

  Map<String, dynamic> toJson() => {
        if (column.isNotEmpty) "col": column,
        if (rows.isNotEmpty) "rows": rows,
        if (match.isNotEmpty) "match": match,
        if (how != _defaults.how) "how": how.name,
        "style": style.toJson(),
        if (name.isNotEmpty) "name": name,
        if (off) "off": true,
        if (keys.isNotEmpty) "keys": keys,
        if (keys.isNotEmpty) "keyCol": keyColumn,
        if (when != null) "when": when!.toJson(),
      };

  factory TableRule.fromJson(Map<String, dynamic> json) => TableRule(
        column: jsonString(json["col"], _defaults.column),
        rows: jsonString(json["rows"], _defaults.rows),
        match: jsonString(json["match"], _defaults.match),
        how: TableMatch.fromName(jsonStr(json["how"])),
        style:
            jsonSpec(json["style"], TableCellStyle.fromJson, _defaults.style),
        name: jsonString(json["name"], _defaults.name),
        off: json["off"] == true,
        keys: [
          if (json["keys"] is List)
            for (var k in json["keys"] as List)
              if (k is String) k
        ],
        keyColumn: jsonString(json["keyCol"], _defaults.keyColumn),
        when: TableWhen.fromJson(json["when"]),
      );
}

/// TableCellLook is all the rules say about one cell, worked out in one
/// walk so the painter's several questions share it.
class TableCellLook {
  final TableCellStyle? style;

  /// words are the rules that named a word, with where they found it, in
  /// written order so a later one draws over an earlier.
  final List<(TableRule, List<(int, int)>)> words;

  const TableCellLook(this.style, this.words);

  static const nothing = TableCellLook(null, []);

  bool get isEmpty => style == null && words.isEmpty;

  /// ruleAt is the rule that claims character [index]; a later rule wins.
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
/// the rest of the canvas. No formulas or column types.
class TableElement extends CanvasElement {
  /// rows is the whole grid including any header; ragged rows are padded.
  final List<List<String>> rows;

  final bool headerRow;
  final bool headerColumn;

  /// hiddenHeaders are columns whose header is not drawn; the text stays as
  /// the column's name for the data mapping and the sort.
  final List<int> hiddenHeaders;

  /// showOutline is the rule round the table, apart from [grid].
  final bool showOutline;

  final TextSpec cellSpec;
  final TextSpec headerSpec;

  final Color headerFill;
  final Color cellFill;

  /// headerFade and cellFade are second colours to fade to, or null for flat,
  /// running across the whole table.
  final GradientSpec? headerFade;
  final GradientSpec? cellFade;

  final bool zebra;
  final Color zebraFill;

  final DataSource source;

  /// sort is the order last applied, kept to reapply after the data changes.
  final TableSort sort;

  final TableGrid grid;
  final double gridWidth;
  final Color gridColor;

  /// cellPadding is the room round a cell's words on sides with no own figure.
  final double cellPadding;

  /// padTop, padRight, padBottom and padLeft are null to follow [cellPadding].
  final double? padTop;
  final double? padRight;
  final double? padBottom;
  final double? padLeft;

  final double cornerRadius;

  /// pictureScale is how much of its padded cell a picture fills.
  final double pictureScale;

  /// columnWidths are each column's share of the width (normalised by their
  /// sum), or empty for columns sized to their contents.
  final List<double> columnWidths;

  final double headerHeightRatio;

  final List<TableRule> rules;

  final ElementAnimation animation;

  /// turn is how the arrival brings it in; leaving is always whole.
  final TableTurn turn;

  /// style is the name of the style last given (data_styles.dart), or empty.
  /// A name, whose colours are the app's: not put through mapColours.
  final String style;

  /// columnKinds is how some columns' cells are drawn rather than written:
  /// "spark" a small line of the cell's numbers ("3, 5, 4, 8"); "ticks" a
  /// tick or cross; "harvey" a part-filled circle (0-4, or a share); "change"
  /// an arrow and size; "merge" a run of one value as one tall cell. See
  /// tableCellKinds.
  final Map<int, String> columnKinds;

  /// groupRows draws a row with only its first cell filled as a heading.
  final bool groupRows;

  /// cards draws each column after the first as a card of its own; [picked]
  /// is the column raised above the rest (-1 for none), with [ribbon]'s
  /// words on a band across its top.
  final bool cards;
  final int picked;
  final String ribbon;

  /// sheet is the canvas sheet range this table shows (data_sheet.dart), kept
  /// in step both ways (data_sync.dart). Null only until it gets a sheet.
  final SheetLink? sheet;

  /// sheetLooks is what its sheet's colour rules make of each cell, row by
  /// row: made with the rows (data_sync.dart), not saved. Not put through
  /// mapColours: it follows the sheet's rules, whose colours are mapped.
  final List<List<SheetCellLook?>> sheetLooks;

  SheetCellLook? sheetLookAt(int r, int c) =>
      r < sheetLooks.length && c < sheetLooks[r].length
          ? sheetLooks[r][c]
          : null;

  double get topPad => padTop ?? cellPadding;
  double get rightPad => padRight ?? cellPadding;
  double get bottomPad => padBottom ?? cellPadding;
  double get leftPad => padLeft ?? cellPadding;

  /// evenPadding is whether every side is [cellPadding] (one panel field).
  bool get evenPadding =>
      padTop == null &&
      padRight == null &&
      padBottom == null &&
      padLeft == null;

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
    this.turn = TableTurn.together,
    this.style = "",
    this.columnKinds = const {},
    this.groupRows = false,
    this.cards = false,
    this.picked = -1,
    this.ribbon = "",
    this.sheet,
    this.sheetLooks = const [],
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TableElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.table;

  int get columnCount => rows.fold(0, (n, r) => r.length > n ? r.length : n);

  @override
  Set<String> get assetIds => {
        for (var row in rows)
          for (var cell in row)
            if (pictureIn(cell) case var asset?) asset,
      };

  /// pictureCell is the prefix that makes a cell a picture. Kept in the cell's
  /// text, not a map of positions, so it moves with the cell.
  static const String pictureCell = "img:";

  static String? pictureIn(String cell) {
    var text = cell.trim();
    return text.startsWith(pictureCell) && text.length > pictureCell.length
        ? text.substring(pictureCell.length)
        : null;
  }

  List<String> get header =>
      headerRow && rows.isNotEmpty ? rows.first : const [];

  /// columnName is the header's text, or the column number when it is empty.
  /// Shared by the settings and the charts so they agree.
  String columnName(int column) {
    var names = header;
    var name = column < names.length ? names[column].trim() : "";
    return name.isEmpty ? "Column ${column + 1}" : name;
  }

  TableCellLook lookAt(int row, int col) {
    if (rules.isEmpty) return TableCellLook.nothing;

    var head = header;
    var text = cell(row, col);
    String? lower;
    TableCellStyle? style;
    var words = <(TableRule, List<(int, int)>)>[];

    for (var rule in rules) {
      if (rule.off) continue;
      if (!rule.matchesRow(row)) continue;
      if (rule.readsRows && !rule.reachesRow(row, head, (c) => cell(row, c))) {
        continue;
      }
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
                  redact: false,
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
              redact: (rule.match.isEmpty && rule.style.redact) || style.redact,
            );
    }

    return style == null && words.isEmpty
        ? TableCellLook.nothing
        : TableCellLook(style, words);
  }

  TableCellStyle? styleFor(int row, int col) => lookAt(row, col).style;

  /// runStyleFor is a word-naming rule's style for the character at [index].
  TableCellStyle? runStyleFor(int row, int col, int index) {
    var rule = lookAt(row, col).ruleAt(index);
    return rule != null && rule.style.changesType ? rule.style : null;
  }

  /// shows is false only for a header in [hiddenHeaders]. Its width, rules
  /// and background still apply.
  bool shows(int row, int col) =>
      !(headerRow && row == 0 && hiddenHeaders.contains(col));

  /// cell is the string at a position, or "" past a ragged row's end.
  String cell(int row, int col) {
    if (row < 0 || row >= rows.length) return "";
    var r = rows[row];
    return col >= 0 && col < r.length ? r[col] : "";
  }

  /// asText and parseRows are the quick-entry round trip (see joinTable).
  String asText() => joinTable(rows);

  static List<List<String>> parseRows(String text) => splitTable(text);

  @override
  CanvasElement rebase(ElementBase base) => _copy(base);

  @override
  bool get scalesInside => true;

  /// scaledBy scales the type, padding and rules. Columns and rows are
  /// fractions of the box and follow it on their own.
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
    TableTurn? turn,
    String? style,
    Map<int, String>? columnKinds,
    bool? groupRows,
    bool? cards,
    int? picked,
    String? ribbon,
    SheetLink? sheet,
    bool clearSheet = false,
    List<List<SheetCellLook?>>? sheetLooks,
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
          animation: animation,
          turn: turn,
          style: style,
          columnKinds: columnKinds,
          groupRows: groupRows,
          cards: cards,
          picked: picked,
          ribbon: ribbon,
          sheet: sheet,
          clearSheet: clearSheet,
          sheetLooks: sheetLooks);

  /// mapOwnColours maps the table's type, fills, fades, grid and rules: the
  /// header's fill and type hidden without a header, the stripes' fill
  /// without stripes, the grid's colour without a grid.
  @override
  TableElement mapOwnColours(ColourMap f) {
    var headed = headerRow || headerColumn;
    var p = ColourPass(f);
    var cellSpec = p.part(this.cellSpec, (s) => s.mapColours(f));
    var headerSpec =
        p.part(this.headerSpec, (s) => s.mapColours(f.shownOnlyIf(headed)));
    var headerFill = p(this.headerFill, shown: headed);
    var cellFill = p(this.cellFill);
    var headerFade = p.partOrNone(
        this.headerFade, (g) => g.mapColours(f.shownOnlyIf(headed)));
    var cellFade = p.partOrNone(this.cellFade, (g) => g.mapColours(f));
    var zebraFill = p(this.zebraFill, shown: zebra);
    var gridColor =
        p(this.gridColor, shown: grid != TableGrid.none && gridWidth > 0);
    var rules = p.list(this.rules, (r) => r.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      cellSpec: cellSpec,
      headerSpec: headerSpec,
      headerFill: headerFill,
      cellFill: cellFill,
      headerFade: headerFade,
      cellFade: cellFade,
      zebraFill: zebraFill,
      gridColor: gridColor,
      rules: rules,
      animation: animation,
    );
  }

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
    TableTurn? turn,
    String? style,
    Map<int, String>? columnKinds,
    bool? groupRows,
    bool? cards,
    int? picked,
    String? ribbon,
    SheetLink? sheet,
    bool clearSheet = false,
    List<List<SheetCellLook?>>? sheetLooks,
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
          animation: animation ?? this.animation,
          turn: turn ?? this.turn,
          style: style ?? this.style,
          columnKinds: columnKinds ?? this.columnKinds,
          groupRows: groupRows ?? this.groupRows,
          cards: cards ?? this.cards,
          picked: picked ?? this.picked,
          ribbon: ribbon ?? this.ribbon,
          sheet: clearSheet ? null : sheet ?? this.sheet,
          sheetLooks: sheetLooks ?? this.sheetLooks);

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
        if (pictureScale != _defaults.pictureScale) "picScale": pictureScale,
        if (columnWidths.isNotEmpty) "cols": columnWidths,
        "headerRatio": headerHeightRatio,
        if (rules.isNotEmpty) "rules": [for (var rule in rules) rule.toJson()],
        if (sort.on || !sort.pinFirstColumn) "sort": sort.toJson(),
        if (source.on) "source": source.toJson(),
        if (hiddenHeaders.isNotEmpty) "hiddenHeaders": hiddenHeaders,
        if (animation.any) "anim": animation.toJson(),
        if (turn != _defaults.turn) "turn": turn.name,
        if (style.isNotEmpty) "style": style,
        if (columnKinds.isNotEmpty)
          "columnKinds": {
            for (var MapEntry(:key, :value) in columnKinds.entries)
              "$key": value
          },
        if (groupRows) "groupRows": true,
        if (cards) "cards": true,
        if (picked >= 0) "picked": picked,
        if (ribbon.isNotEmpty) "ribbon": ribbon,
        if (sheet != null) "sheet": sheet!.toJson(),
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
        cellSpec:
            jsonSpec(json["cellSpec"], TextSpec.fromJson, _defaults.cellSpec),
        headerSpec: jsonSpec(
            json["headerSpec"], TextSpec.fromJson, _defaults.headerSpec),
        headerFill: colorFromJson(json["headerFill"], _defaults.headerFill),
        cellFill: colorFromJson(json["cellFill"], _defaults.cellFill),
        headerFade: json["headerFade"] is Map
            ? GradientSpec.fromJson(
                (json["headerFade"] as Map).cast<String, dynamic>())
            : null,
        cellFade: json["cellFade"] is Map
            ? GradientSpec.fromJson(
                (json["cellFade"] as Map).cast<String, dynamic>())
            : null,
        zebra: jsonBool(json["zebra"], true),
        zebraFill: colorFromJson(json["zebraFill"], _defaults.zebraFill),
        grid: TableGrid.fromName(jsonStr(json["grid"])),
        gridWidth: jsonDouble(json["gridWidth"], _defaults.gridWidth),
        gridColor: colorFromJson(json["gridColor"], _defaults.gridColor),
        cellPadding: jsonDouble(json["pad"], _defaults.cellPadding),
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
        cornerRadius: jsonDouble(json["cr"], _defaults.cornerRadius),
        pictureScale: jsonDouble(json["picScale"], _defaults.pictureScale)
            .clamp(0.05, 1.0),
        columnWidths: cols is List
            ? [for (var c in cols) c is num ? c.toDouble() : 1.0]
            : const [],
        headerHeightRatio:
            jsonDouble(json["headerRatio"], _defaults.headerHeightRatio),
        rules: [
          if (json["rules"] case List raw)
            for (var rule in raw)
              if (rule is Map<String, dynamic>) TableRule.fromJson(rule),
        ],
        sort: jsonSpec(json["sort"], TableSort.fromJson, _defaults.sort),
        source: jsonSpec(json["source"], DataSource.fromJson, _defaults.source),
        hiddenHeaders: [
          if (json["hiddenHeaders"] case List raw)
            for (var c in raw)
              if (c is num) c.toInt(),
        ],
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, _defaults.animation),
        turn: TableTurn.fromName(jsonStr(json["turn"])),
        style: jsonStr(json["style"]) ?? "",
        columnKinds: {
          if (json["columnKinds"] case Map m)
            for (var MapEntry(:key, :value) in m.entries)
              if (int.tryParse("$key") case var c? when value is String)
                c: value,
        },
        groupRows: json["groupRows"] == true,
        cards: json["cards"] == true,
        picked: json["picked"] is int ? json["picked"] as int : -1,
        ribbon: jsonString(json["ribbon"], _defaults.ribbon),
        sheet: SheetLink.fromJson(json["sheet"]));
  }

  /// sorted is this table in [sort]'s order, or this same table when there
  /// is nothing to do, so it can be applied unconditionally.
  TableElement sorted() {
    if (!sort.on) return this;
    var next = sortTableRows(rows, sort, headerRow: headerRow);
    return identical(next, rows) ? this : copyWith(rows: next);
  }
}

/// tableCellKinds is the ways a column's cells can be drawn (see
/// TableElement.columnKinds), as (name, label); "" writes them.
const tableCellKinds = [
  ("", "Words"),
  ("spark", "A small line"),
  ("ticks", "Ticks and crosses"),
  ("harvey", "Part-filled circles"),
  ("change", "Up or down"),
  ("merge", "Repeats as one"),
  ("heat", "Shaded by size"),
];
