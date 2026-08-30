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
  });

  @override
  ElementKind get kind => ElementKind.table;

  int get columnCount =>
      rows.fold(0, (n, r) => r.length > n ? r.length : n);

  /// cell is the string at a position, padding out ragged rows rather than
  /// throwing. See TableElement's note on ragged data.
  String cell(int row, int col) {
    if (row < 0 || row >= rows.length) return "";
    var r = rows[row];
    return col >= 0 && col < r.length ? r[col] : "";
  }

  /// asText and parse are the quick-entry round trip, in the same tab or
  /// comma separated form the chart uses -- one habit to learn, not two.
  String asText() => rows.map((r) => r.join("\t")).join("\n");

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
          headerHeightRatio: headerHeightRatio);

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
          headerHeightRatio: headerHeightRatio ?? this.headerHeightRatio);

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
        headerHeightRatio: jsonDouble(json["headerRatio"], 1.15));
  }
}
