import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:intl/intl.dart';

// data_source.dart is where a table's or a chart's numbers came from, when
// they were not typed: a general mapping from JSON to rows (a handful of
// paths), filled in by the presets in data_presets.dart.
//
// No credential is kept here. A canvas is shared, so an API key stays on the
// reader's machine (storage/canvas_api_keys.dart); the document holds only
// the URL and the paths.

/// DataKind is where the numbers come from.
enum DataKind {
  /// typed is the ordinary case: the cells are the data.
  typed("Typed in"),

  /// file is a JSON file on this machine, re-read on demand. The app makes
  /// no network request for it.
  file("A JSON file"),

  /// url is fetched over the internet, and is off unless the reader has turned
  /// it on. See CanvasPreferences.allowFetching.
  url("A web address");

  final String label;
  const DataKind(this.label);
}

/// DataShape is how the response is laid out: a list of records (one object
/// per row, as a league table arrives), or parallel arrays where row i is the
/// i-th of each (as dcrdata sends a chain's history).
enum DataShape {
  records("A list of records"),
  columns("Parallel arrays");

  final String label;
  const DataShape(this.label);

  static DataShape fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => records);
}

/// SourceColumn is one column of the table: what it is called, and where to
/// find it in each record. (Not DataColumn, which is a Material widget.)
class SourceColumn {
  final String header;

  /// path is a dotted route into one record -- "team.name", "points",
  /// "team.crest". Empty means the record itself, for a list of plain values.
  final String path;

  /// picture marks a column whose value is the address of an image -- a club
  /// crest, a flag -- rather than something to write in the cell. Only
  /// honoured when fetching is on, since each picture is a request; off, the
  /// address is written into the cell as text.
  final bool picture;

  /// keep leaves whatever is already in this column alone, for a hand-filled
  /// column in a table whose other columns come from an API. Kept values are
  /// matched by [DataSource.matchColumn], not by row number, because the rows
  /// move.
  final bool keep;

  /// spread lays a comma-separated value ("D,W,W,W,W", a form guide) out as
  /// that many slots, padded on the left with an em dash so the letters line
  /// up down the table. Zero leaves the value alone.
  final int spread;

  /// divider goes before the last result, where a form guide usually marks
  /// the most recent game off from the ones before it.
  final String divider;

  /// template builds a cell out of other fields instead of taking one.
  ///
  /// Anything in braces is a path into the record and is replaced by what is
  /// there: "{team.tla} ({points})" gives "MCI (6)". Everything outside the
  /// braces is written as it stands. Substitution only: no arithmetic or
  /// conditions. [path] is ignored when this is set.
  final String template;

  /// divide scales a number on the way in, such as atoms to DCR. The scaled
  /// figure is what lands in the cell and what the chart draws. One, the
  /// default, leaves it alone, as does a value that is not a number.
  final double divide;

  /// date reads the value as a time (see [asDate]) and writes it out in this
  /// DateFormat pattern. Empty leaves it alone.
  final String date;

  const SourceColumn({
    this.header = "",
    this.path = "",
    this.picture = false,
    this.keep = false,
    this.spread = 0,
    this.divider = "",
    this.template = "",
    this.divide = 1,
    this.date = "",
  });

  SourceColumn copyWith({
    String? header,
    String? path,
    bool? picture,
    bool? keep,
    int? spread,
    String? divider,
    String? template,
    double? divide,
    String? date,
  }) =>
      SourceColumn(
        header: header ?? this.header,
        path: path ?? this.path,
        picture: picture ?? this.picture,
        keep: keep ?? this.keep,
        spread: spread ?? this.spread,
        divider: divider ?? this.divider,
        template: template ?? this.template,
        divide: divide ?? this.divide,
        date: date ?? this.date,
      );

  Map<String, dynamic> toJson() => {
        "h": header,
        "p": path,
        if (picture) "pic": true,
        if (keep) "keep": true,
        if (spread > 0) "spread": spread,
        if (divider.isNotEmpty) "div": divider,
        if (template.isNotEmpty) "tpl": template,
        if (divide != 1) "div10": divide,
        if (date.isNotEmpty) "date": date,
      };

  factory SourceColumn.fromJson(Map<String, dynamic> json) => SourceColumn(
        header: jsonString(json["h"], ""),
        path: jsonString(json["p"], ""),
        picture: jsonBool(json["pic"], false),
        keep: jsonBool(json["keep"], false),
        spread: jsonInt(json["spread"], 0),
        divider: jsonString(json["div"], ""),
        template: jsonString(json["tpl"], ""),
        divide: jsonDouble(json["div10"], 1),
        date: jsonString(json["date"], ""),
      );
}

/// DataSource is the whole recipe for filling a table from JSON.
class DataSource {
  final DataKind kind;

  /// where is the file path or the web address, depending on [kind].
  final String where;

  /// rowsPath is the route to the list of records inside the document, such
  /// as "standings.0.table". Empty means the document is itself the list.
  final String rowsPath;

  final List<SourceColumn> columns;

  /// matchColumn is the column that says which row is which across a refresh
  /// (the team's name, usually), for the columns marked [SourceColumn.keep].
  /// Minus one matches by row number, which is only right for a source whose
  /// order never changes.
  final int matchColumn;

  /// shape is how the response is laid out. See [DataShape].
  final DataShape shape;

  /// preset is which named recipe filled the paths in, kept so the settings
  /// panel can show it and offer to fill them in again. Empty for a mapping
  /// somebody wrote themselves.
  final String preset;

  /// fetchedAt is when the numbers last arrived, so a table can say how old it
  /// is.
  final DateTime? fetchedAt;

  /// fromRows asks the source for whatever the element already has rows for,
  /// instead of a fixed choice: a refresh reads the match column and asks for
  /// those (the coins already in a coin comparison, say). Only for a preset
  /// whose choice is a list of rows; see DataPreset.choiceFromRows.
  final bool fromRows;

  const DataSource({
    this.kind = DataKind.typed,
    this.where = "",
    this.rowsPath = "",
    this.columns = const [],
    this.matchColumn = -1,
    this.shape = DataShape.records,
    this.preset = "",
    this.fetchedAt,
    this.fromRows = false,
  });

  bool get on => kind != DataKind.typed && where.isNotEmpty;

  /// host is the address's host, which is what an API key is filed under.
  String get host =>
      kind == DataKind.url ? (Uri.tryParse(where)?.host ?? "") : "";

  DataSource copyWith({
    DataKind? kind,
    String? where,
    String? rowsPath,
    List<SourceColumn>? columns,
    int? matchColumn,
    DataShape? shape,
    String? preset,
    DateTime? fetchedAt,
    bool? fromRows,
  }) =>
      DataSource(
        kind: kind ?? this.kind,
        where: where ?? this.where,
        rowsPath: rowsPath ?? this.rowsPath,
        columns: columns ?? this.columns,
        matchColumn: matchColumn ?? this.matchColumn,
        shape: shape ?? this.shape,
        preset: preset ?? this.preset,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        fromRows: fromRows ?? this.fromRows,
      );

  /// withColumnMoved is this source with one column shifted along the row;
  /// the order of the columns is the order of the table.
  DataSource withColumnMoved(int from, int to) {
    if (from == to || from < 0 || to < 0) return this;
    if (from >= columns.length || to >= columns.length) return this;
    var next = [...columns];
    next.insert(to, next.removeAt(from));
    return copyWith(
      columns: next,
      matchColumn:
          matchColumn < 0 ? matchColumn : movedIndex(matchColumn, from, to),
    );
  }

  /// withoutColumn is this source with one column taken out, and whatever
  /// referred to the columns by number moved up behind it.
  DataSource withoutColumn(int at) {
    if (at < 0 || at >= columns.length) return this;
    return copyWith(
      columns: [
        for (var i = 0; i < columns.length; i++)
          if (i != at) columns[i],
      ],
      matchColumn: matchColumn < 0
          ? matchColumn
          : (indexAfterRemoval(matchColumn, at) ?? -1),
    );
  }

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "where": where,
        if (rowsPath.isNotEmpty) "rows": rowsPath,
        if (columns.isNotEmpty) "cols": [for (var c in columns) c.toJson()],
        if (matchColumn >= 0) "match": matchColumn,
        if (shape != DataShape.records) "shape": shape.name,
        if (preset.isNotEmpty) "preset": preset,
        if (fetchedAt != null) "at": fetchedAt!.toIso8601String(),
        if (fromRows) "fromRows": true,
      };

  factory DataSource.fromJson(Map<String, dynamic> json) => DataSource(
        kind: DataKind.values.firstWhere((k) => k.name == json["kind"],
            orElse: () => DataKind.typed),
        where: jsonString(json["where"], ""),
        rowsPath: jsonString(json["rows"], ""),
        columns: [
          if (json["cols"] case List raw)
            for (var c in raw)
              if (c is Map<String, dynamic>) SourceColumn.fromJson(c),
        ],
        matchColumn: jsonInt(json["match"], -1),
        shape: DataShape.fromName(jsonString(json["shape"], "")),
        preset: jsonString(json["preset"], ""),
        fetchedAt: DateTime.tryParse(jsonString(json["at"], "")),
        fromRows: jsonBool(json["fromRows"], false),
      );
}

/// asRowKey turns what is written in a cell into something an address can ask
/// for: lower case, hyphens for spaces, nothing else.
///
/// "Bitcoin Cash" becomes bitcoin-cash, CoinGecko's id. It is a guess: the
/// few it gets wrong (BNB is binancecoin, XRP is ripple) come back missing
/// rather than wrong, and the refresh says which.
String asRowKey(String cell) {
  var out = StringBuffer();
  for (var rune in cell.trim().toLowerCase().runes) {
    var c = String.fromCharCode(rune);
    if (_letterOrDigit.hasMatch(c)) {
      out.write(c);
    } else if (c == " " || c == "-" || c == "_" || c == ".") {
      if (out.isNotEmpty && !out.toString().endsWith("-")) out.write("-");
    }
  }
  return out.toString().replaceAll(_trailingDashes, "");
}

// Compiled once: asRowKey tests every character of every cell.
final RegExp _letterOrDigit = RegExp(r"[a-z0-9]");
final RegExp _trailingDashes = RegExp(r"-+$");

/// movedIndex is where the thing at [index] ends up when the column at
/// [from] is moved to [to].
///
/// Anything that refers to a column by number (which column a chart draws,
/// which identifies a row, which headings are hidden) must go through this
/// when the columns move, or it silently points at a different column.
int movedIndex(int index, int from, int to) {
  if (index == from) return to;
  if (from < to) return index > from && index <= to ? index - 1 : index;
  return index >= to && index < from ? index + 1 : index;
}

/// indexAfterRemoval is where the thing at [index] ends up when the column at
/// [removed] is taken out, or null if it was that column.
int? indexAfterRemoval(int index, int removed) {
  if (index == removed) return null;
  return index > removed ? index - 1 : index;
}

/// valueAtPath walks a dotted path into decoded JSON.
///
/// Numbers are list indices; everything else is a key. Anything missing
/// gives null rather than throwing, so a changed API is a blank cell, not a
/// broken canvas.
dynamic valueAtPath(dynamic json, String path) {
  if (path.isEmpty) return json;
  dynamic at = json;
  for (var step in path.split(".")) {
    if (at == null) return null;
    var index = int.tryParse(step);
    if (index != null && at is List) {
      at = index >= 0 && index < at.length ? at[index] : null;
    } else if (at is Map) {
      at = at[step];
    } else {
      return null;
    }
  }
  return at;
}

/// rowsFromJson turns a decoded document into table rows, header first.
///
/// Returns an empty list when the path does not lead to a list, which a
/// caller shows as "nothing came back" rather than replacing good rows.
///
/// [raw] leaves date columns as the timestamps they arrived as, for a chart
/// that picks points by date: a formatted date such as "Feb 26" cannot be
/// parsed back. The raw rows are used immediately and never stored.
List<List<String>> rowsFromJson(dynamic json, DataSource source,
    {bool raw = false}) {
  if (source.columns.isEmpty) return const [];
  if (raw) {
    source = source.copyWith(columns: [
      for (var c in source.columns) c.copyWith(date: ""),
    ]);
  }
  if (source.shape == DataShape.columns) return _rowsFromColumns(json, source);

  var records = valueAtPath(json, source.rowsPath);
  if (records is! List) return const [];

  return [
    [for (var column in source.columns) column.header],
    for (var record in records)
      [
        for (var column in source.columns)
          spreadValue(_cell(record, column), column)
      ],
  ];
}

/// _rowsFromColumns reads parallel arrays: one array per column, row i being
/// the i-th of each.
///
/// The length is the shortest array's: a source read mid-write (dcrdata's
/// timestamps one ahead of its values) would otherwise end on an empty value.
List<List<String>> _rowsFromColumns(dynamic json, DataSource source) {
  var at = valueAtPath(json, source.rowsPath);
  var arrays = <List>[];
  for (var column in source.columns) {
    var found = valueAtPath(at, column.path);
    if (found is! List) return const [];
    arrays.add(found);
  }
  if (arrays.isEmpty) return const [];

  var length = arrays.first.length;
  for (var array in arrays) {
    if (array.length < length) length = array.length;
  }

  return [
    [for (var column in source.columns) column.header],
    for (var i = 0; i < length; i++)
      [
        for (var (c, column) in source.columns.indexed)
          spreadValue(_scaled(arrays[c][i], column), column)
      ],
  ];
}

/// _cell is one column's value out of one record: a field, or a template
/// built from several.
String _cell(dynamic record, SourceColumn column) => column.template.isEmpty
    ? _scaled(valueAtPath(record, column.path), column)
    : fillTemplate(column.template, record);

/// _scaled is one value as a cell, with the column's conversions applied: a
/// number brought into the units the chart is drawn in, or a timestamp
/// written out as a date. See [SourceColumn.divide] and [SourceColumn.date].
String _scaled(dynamic value, SourceColumn column) {
  if (column.date.isNotEmpty) {
    var when = asDate(value);
    if (when != null) return DateFormat(column.date).format(when);
  }
  if (column.divide != 1 && column.divide != 0) {
    var number = value is num
        ? value.toDouble()
        : value is String
            ? double.tryParse(value)
            : null;
    if (number != null) return _text(number / column.divide);
  }
  return _text(value);
}

/// asDate reads a timestamp however it was sent.
///
/// Seconds and milliseconds since the epoch are told apart by size: seconds
/// do not reach 1e11 until the year 5138, and milliseconds passed it in 1973.
/// Anything else is left to DateTime.parse, which covers ISO strings.
DateTime? asDate(dynamic value) {
  if (value is num) {
    var n = value.toDouble();
    if (n <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        (n >= 1e11 ? n : n * 1000).round());
  }
  if (value is String) {
    var n = double.tryParse(value);
    if (n != null) return asDate(n);
    return DateTime.tryParse(value);
  }
  return null;
}

/// fillTemplate replaces every {path} in [template] with what the record has
/// there. See [SourceColumn.template].
///
/// A path that leads nowhere becomes empty rather than being left as braces.
String fillTemplate(String template, dynamic record) =>
    template.replaceAllMapped(RegExp(r"\{([^{}]*)\}"),
        (m) => _text(valueAtPath(record, m.group(1)!.trim())));

/// spreadValue lays a comma-separated value out as a row of results. See
/// [SourceColumn.spread].
///
/// Public so football_form.dart lays out a form guide built from fixtures
/// exactly as one from the response. The newest entries are kept when there
/// are too many.
String spreadValue(String value, SourceColumn column) {
  if (column.spread <= 0) return value;
  var results = [for (var part in value.split(",")) part.trim()]
    ..removeWhere((p) => p.isEmpty);

  if (results.length > column.spread) {
    results = results.sublist(results.length - column.spread);
  }
  while (results.length < column.spread) {
    results.insert(0, "\u2014");
  }
  if (column.divider.isNotEmpty && results.length > 1) {
    results.insert(results.length - 1, column.divider);
  }
  return results.join(" ");
}

/// _text is a JSON value as a cell. Whole numbers lose their ".0", and
/// anything that is not a scalar becomes empty.
String _text(dynamic value) {
  if (value == null) return "";
  if (value is num) {
    return value == value.roundToDouble() && value.abs() < 1e15
        ? "${value.toInt()}"
        : "$value";
  }
  if (value is String || value is bool) return "$value";
  return "";
}

/// TableLink is a chart taking its numbers from a table on the same canvas,
/// rather than fetching its own, so the two can never disagree.
class TableLink {
  /// tableId is the element it reads. Empty, the default, when the chart's
  /// numbers are its own.
  final String tableId;

  /// categoryColumn is the column the labels come from -- the team's name.
  final int categoryColumn;

  /// valueColumns are the columns that become series, in order. More than one
  /// is a chart comparing two figures per row.
  final List<int> valueColumns;

  const TableLink({
    this.tableId = "",
    this.categoryColumn = 0,
    this.valueColumns = const [],
  });

  bool get on => tableId.isNotEmpty && valueColumns.isNotEmpty;

  TableLink copyWith({
    String? tableId,
    int? categoryColumn,
    List<int>? valueColumns,
  }) =>
      TableLink(
        tableId: tableId ?? this.tableId,
        categoryColumn: categoryColumn ?? this.categoryColumn,
        valueColumns: valueColumns ?? this.valueColumns,
      );

  Map<String, dynamic> toJson() => {
        "id": tableId,
        "cat": categoryColumn,
        "vals": valueColumns,
      };

  factory TableLink.fromJson(Map<String, dynamic> json) => TableLink(
        tableId: jsonString(json["id"], ""),
        categoryColumn: jsonInt(json["cat"], 0),
        valueColumns: [
          if (json["vals"] case List raw)
            for (var v in raw)
              if (v is num) v.toInt(),
        ],
      );
}

/// keepColumns puts back the columns marked [SourceColumn.keep] from the rows
/// that were there before.
///
/// [before] is the table as it stood, header included; [after] is what has
/// just arrived. Rows are matched on [DataSource.matchColumn], so a badge
/// follows its team. A row with no match keeps whatever the source sent.
List<List<String>> keepColumns(
  List<List<String>> before,
  List<List<String>> after,
  DataSource source, {
  bool headerRow = true,
}) {
  var kept = <int>[
    for (var i = 0; i < source.columns.length; i++)
      if (source.columns[i].keep) i,
  ];
  if (kept.isEmpty || before.length < 2 || after.length < 2) return after;

  var skip = headerRow ? 1 : 0;
  var match = source.matchColumn;
  var out = [
    for (var row in after) [...row]
  ];

  // What was there, by whatever identifies a row.
  var was = <String, List<String>>{};
  for (var i = skip; i < before.length; i++) {
    var key = match >= 0 && match < before[i].length
        ? before[i][match].trim().toLowerCase()
        : "#${i - skip}";
    if (key.isNotEmpty) was[key] = before[i];
  }

  for (var i = skip; i < out.length; i++) {
    var key = match >= 0 && match < out[i].length
        ? out[i][match].trim().toLowerCase()
        : "#${i - skip}";
    var old = was[key];
    if (old == null) continue;
    for (var c in kept) {
      if (c < out[i].length && c < old.length) out[i][c] = old[c];
    }
  }
  return out;
}

/// keepHeaders puts the table's existing column names back over the ones the
/// source supplied.
///
/// Rules that colour cells name their column, so renamed headers would
/// switch them off. Columns the table did not have before take the source's
/// name.
List<List<String>> keepHeaders(
  List<List<String>> before,
  List<List<String>> after, {
  bool headerRow = true,
}) {
  if (!headerRow || before.isEmpty || after.isEmpty) return after;
  var was = before.first;
  var out = [
    for (var row in after) [...row]
  ];
  for (var c = 0; c < out.first.length && c < was.length; c++) {
    out.first[c] = was[c];
  }
  return out;
}
