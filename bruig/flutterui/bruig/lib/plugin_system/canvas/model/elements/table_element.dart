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

  final Color borderColor;
  final double borderWidth;
  final double radius;

  /// inset shrinks the painted box inside its cell, which is what turns a
  /// background into a chip rather than a filled cell.
  final double inset;

  const TableCellStyle({
    this.background = const Color(0x00000000),
    this.textColor = const Color(0x00000000),
    this.fontScale = 1,
    this.weight = 0,
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.radius = 4,
    this.inset = 3,
  });

  bool get paintsBox => background.a > 0 || (borderColor.a > 0 && borderWidth > 0);

  bool get changesType => textColor.a > 0 || fontScale != 1 || weight != 0;

  TableCellStyle copyWith({
    Color? background,
    Color? textColor,
    double? fontScale,
    int? weight,
    Color? borderColor,
    double? borderWidth,
    double? radius,
    double? inset,
  }) =>
      TableCellStyle(
        background: background ?? this.background,
        textColor: textColor ?? this.textColor,
        fontScale: fontScale ?? this.fontScale,
        weight: weight ?? this.weight,
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        radius: radius ?? this.radius,
        inset: inset ?? this.inset,
      );

  Map<String, dynamic> toJson() => {
        if (background.a > 0) "bg": colorToJson(background),
        if (textColor.a > 0) "fg": colorToJson(textColor),
        if (fontScale != 1) "scale": fontScale,
        if (weight != 0) "weight": weight,
        if (borderColor.a > 0) "bc": colorToJson(borderColor),
        if (borderWidth != 0) "bw": borderWidth,
        if (radius != 4) "r": radius,
        if (inset != 3) "inset": inset,
      };

  factory TableCellStyle.fromJson(Map<String, dynamic> json) => TableCellStyle(
        background: colorFromJson(json["bg"], const Color(0x00000000)),
        textColor: colorFromJson(json["fg"], const Color(0x00000000)),
        fontScale: jsonDouble(json["scale"], 1).clamp(0.2, 6.0),
        weight: jsonInt(json["weight"], 0),
        borderColor: colorFromJson(json["bc"], const Color(0x00000000)),
        borderWidth: jsonDouble(json["bw"], 0),
        radius: jsonDouble(json["r"], 4),
        inset: jsonDouble(json["inset"], 3),
      );
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

  /// row counts from one and includes the header. -1 is any row.
  final int row;

  /// match is the text to look for. Empty matches every cell.
  final String match;

  /// exact wants the whole cell rather than a cell containing it. On by
  /// default: "W" appearing inside "Won" is not what anybody typing W means.
  final bool exact;

  final TableCellStyle style;

  const TableRule({
    this.column = "",
    this.row = -1,
    this.match = "",
    this.exact = true,
    this.style = const TableCellStyle(),
  });

  /// wholeRow is a rule that picks out a row and nothing narrower, which is
  /// the one case drawn as a band across the table rather than cell by cell.
  bool get wholeRow => row >= 1 && column.isEmpty && match.isEmpty;

  /// columnIndex resolves [column] against a header row. -1 means any.
  int columnIndex(List<String> header) {
    if (column.trim().isEmpty) return -1;
    var byName = header.indexWhere(
        (h) => h.trim().toLowerCase() == column.trim().toLowerCase());
    if (byName >= 0) return byName;
    var byNumber = int.tryParse(column.trim());
    return byNumber == null ? -2 : byNumber - 1;
  }

  bool matches(String cell) {
    if (match.isEmpty) return true;
    return exact
        ? cell.trim().toLowerCase() == match.trim().toLowerCase()
        : cell.toLowerCase().contains(match.trim().toLowerCase());
  }

  TableRule copyWith({
    String? column,
    int? row,
    String? match,
    bool? exact,
    TableCellStyle? style,
  }) =>
      TableRule(
        column: column ?? this.column,
        row: row ?? this.row,
        match: match ?? this.match,
        exact: exact ?? this.exact,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() => {
        if (column.isNotEmpty) "col": column,
        if (row >= 0) "row": row,
        if (match.isNotEmpty) "match": match,
        if (!exact) "loose": true,
        "style": style.toJson(),
      };

  factory TableRule.fromJson(Map<String, dynamic> json) => TableRule(
        column: jsonString(json["col"], ""),
        row: jsonInt(json["row"], -1),
        match: jsonString(json["match"], ""),
        exact: !jsonBool(json["loose"], false),
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
      if (rule.row >= 1 && rule.row - 1 != row) continue;
      var wanted = rule.columnIndex(head);
      if (wanted == -2 || (wanted >= 0 && wanted != col)) continue;
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
              borderColor: rule.style.borderColor.a > 0
                  ? rule.style.borderColor
                  : out.borderColor,
              borderWidth: rule.style.borderWidth != 0
                  ? rule.style.borderWidth
                  : out.borderWidth,
              radius: rule.style.radius,
              inset: rule.style.inset,
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
