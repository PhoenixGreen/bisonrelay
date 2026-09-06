import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// data_source.dart is where a table's or a chart's numbers came from, when
// they came from somewhere rather than being typed.
//
// The shape of the problem is that nobody wants to type a league table twice a
// week, and nobody wants to learn a query language either. So this is two
// things: a general mapping from JSON to rows, which is a handful of paths,
// and a small set of presets that fill those paths in for a source somebody is
// actually likely to use. The general part is what makes it usable with
// anything; the presets are what make it usable at all.
//
// What is deliberately not here is a credential. An API key is kept outside
// the document -- see storage/canvas_api_keys.dart -- because a canvas is a
// thing people send each other, and a key in the file would be a key posted to
// a chat the first time somebody shared their table. The document holds the
// URL and the paths; the key is the reader's, on their machine.

/// DataKind is where the numbers come from.
enum DataKind {
  /// typed is the ordinary case: the cells are the data.
  typed("Typed in"),

  /// file is a JSON file on this machine, re-read on demand.
  ///
  /// The one that costs nothing and answers most of the need: whatever fetches
  /// the data -- a browser, curl, something on a schedule -- writes a file,
  /// and the canvas reads it. No network from the app at all.
  file("A JSON file"),

  /// url is fetched over the internet, and is off unless the reader has turned
  /// it on. See CanvasPreferences.allowFetching for why that is a decision
  /// rather than a default.
  url("A web address");

  final String label;
  const DataKind(this.label);
}

/// SourceColumn is one column of the table: what it is called, and where to
/// find it in each record.
///
/// Not DataColumn, which is what it wants to be called and is already the name
/// of a Material widget -- every file showing one of these in the interface
/// would have to hide half an import to say it.
class SourceColumn {
  final String header;

  /// path is a dotted route into one record -- "team.name", "points",
  /// "team.crest". Empty means the record itself, which is what a list of
  /// plain values needs.
  final String path;

  /// picture marks a column whose value is the address of an image -- a club
  /// crest, a flag -- rather than something to write in the cell.
  ///
  /// Only honoured when fetching is on, because collecting the pictures means
  /// one request each. Off, the address is written into the cell as text,
  /// which is ugly but truthful and can be seen to be a URL.
  final bool picture;

  /// keep leaves whatever is already in this column alone.
  ///
  /// For a column somebody has filled in themselves -- club badges chosen by
  /// hand, a note against each row -- in a table whose other columns come from
  /// an API. Without it a refresh is all or nothing: either the numbers stay
  /// stale or the hand-made column is wiped twice a week.
  ///
  /// What is kept is matched by [DataSource.matchColumn] rather than by row
  /// number, because the rows move: a team that climbs two places must bring
  /// its badge with it.
  final bool keep;

  /// spread lays a comma-separated value out as a row of results.
  ///
  /// Written for a form guide. football-data.org sends "D,W,W,W,W" -- oldest
  /// first, and fewer than five early in a season -- which as a cell reads
  /// "D,W,W,W,W" and is not what anybody wants to look at. Set to a number, it
  /// becomes that many slots wide, padded on the left with an em dash so the
  /// letters line up down the table whether a club has played five games or
  /// two.
  ///
  /// Zero leaves the value alone, which is every other column.
  final int spread;

  /// divider goes before the last result, where a form guide usually marks
  /// the most recent game off from the ones before it.
  final String divider;

  const SourceColumn({
    this.header = "",
    this.path = "",
    this.picture = false,
    this.keep = false,
    this.spread = 0,
    this.divider = "",
  });

  SourceColumn copyWith({
    String? header,
    String? path,
    bool? picture,
    bool? keep,
    int? spread,
    String? divider,
  }) =>
      SourceColumn(
        header: header ?? this.header,
        path: path ?? this.path,
        picture: picture ?? this.picture,
        keep: keep ?? this.keep,
        spread: spread ?? this.spread,
        divider: divider ?? this.divider,
      );

  Map<String, dynamic> toJson() => {
        "h": header,
        "p": path,
        if (picture) "pic": true,
        if (keep) "keep": true,
        if (spread > 0) "spread": spread,
        if (divider.isNotEmpty) "div": divider,
      };

  factory SourceColumn.fromJson(Map<String, dynamic> json) => SourceColumn(
        header: jsonString(json["h"], ""),
        path: jsonString(json["p"], ""),
        picture: jsonBool(json["pic"], false),
        keep: jsonBool(json["keep"], false),
        spread: jsonInt(json["spread"], 0),
        divider: jsonString(json["div"], ""),
      );
}

/// DataSource is the whole recipe.
class DataSource {
  final DataKind kind;

  /// where is the file path or the web address, depending on [kind].
  final String where;

  /// rowsPath is the route to the list of records inside the document --
  /// "standings.0.table" for the source below. Empty means the document is
  /// itself the list.
  final String rowsPath;

  final List<SourceColumn> columns;

  /// matchColumn is the column that says which row is which across a refresh
  /// -- the team's name, usually.
  ///
  /// Needed only by the columns marked [SourceColumn.keep]. Rows arrive in
  /// whatever order the source sends them and are then sorted, so a badge kept
  /// by row number would be handed to whoever finished in that position this
  /// week. Minus one falls back to the row number, which is right for a source
  /// whose order never changes and wrong for a league table.
  final int matchColumn;

  /// preset is which named recipe filled the paths in, kept so the settings
  /// panel can show it and offer to fill them in again. Empty for a mapping
  /// somebody wrote themselves.
  final String preset;

  /// fetchedAt is when the numbers last arrived, so a table can say how old it
  /// is rather than looking equally current whether it was refreshed a minute
  /// or a season ago.
  final DateTime? fetchedAt;

  const DataSource({
    this.kind = DataKind.typed,
    this.where = "",
    this.rowsPath = "",
    this.columns = const [],
    this.matchColumn = -1,
    this.preset = "",
    this.fetchedAt,
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
    String? preset,
    DateTime? fetchedAt,
  }) =>
      DataSource(
        kind: kind ?? this.kind,
        where: where ?? this.where,
        rowsPath: rowsPath ?? this.rowsPath,
        columns: columns ?? this.columns,
        matchColumn: matchColumn ?? this.matchColumn,
        preset: preset ?? this.preset,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "where": where,
        if (rowsPath.isNotEmpty) "rows": rowsPath,
        if (columns.isNotEmpty) "cols": [for (var c in columns) c.toJson()],
        if (matchColumn >= 0) "match": matchColumn,
        if (preset.isNotEmpty) "preset": preset,
        if (fetchedAt != null) "at": fetchedAt!.toIso8601String(),
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
        preset: jsonString(json["preset"], ""),
        fetchedAt: DateTime.tryParse(jsonString(json["at"], "")),
      );
}

/// valueAtPath walks a dotted path into decoded JSON.
///
/// "standings.0.table" is a map, then the first item of a list, then a map
/// again. Numbers are list indices; everything else is a key. Missing anything
/// gives null rather than throwing -- an API that has changed shape, or a
/// record with a field the others have, is a blank cell and not a broken
/// canvas.
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
/// Returns an empty list when the path does not lead to a list, which is what
/// a caller shows as "nothing came back" -- there is nothing useful to do with
/// half a table, and replacing good rows with rubbish is worse than refusing.
List<List<String>> rowsFromJson(dynamic json, DataSource source) {
  var records = valueAtPath(json, source.rowsPath);
  if (records is! List || source.columns.isEmpty) return const [];

  return [
    [for (var column in source.columns) column.header],
    for (var record in records)
      [
        for (var column in source.columns)
          _spread(_text(valueAtPath(record, column.path)), column)
      ],
  ];
}

/// _spread lays a comma-separated value out as a row of results. See
/// [SourceColumn.spread].
///
/// The newest entries are kept when there are more than there is room for,
/// because a form guide is about how a club is playing now.
String _spread(String value, SourceColumn column) {
  if (column.spread <= 0) return value;
  var results = [for (var part in value.split(",")) part.trim()]
    ..removeWhere((p) => p.isEmpty);

  if (results.length > column.spread) {
    results = results.sublist(results.length - column.spread);
  }
  // Padded on the left, so the most recent game is in the same place in every
  // row whatever a club has played.
  while (results.length < column.spread) {
    results.insert(0, "\u2014");
  }
  if (column.divider.isNotEmpty && results.length > 1) {
    results.insert(results.length - 1, column.divider);
  }
  return results.join(" ");
}

/// _text is a JSON value as a cell.
///
/// Whole numbers lose their ".0": a points column that read "6.0" all the way
/// down would be a table nobody would keep. Anything that is not a scalar
/// becomes empty rather than the word "Instance of ...", which is what a
/// default toString would put in the cell.
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

/// TableLink is a chart taking its numbers from a table on the same canvas.
///
/// The alternative was giving the chart its own DataSource and letting it
/// fetch too, which is worse in every way that matters: two requests for one
/// set of numbers, two things to keep in step, and a chart that could quietly
/// disagree with the table beside it. A canvas showing a league table and a
/// chart of the same league should be showing one set of figures, and this is
/// what makes that structurally true rather than a thing to be careful about.
class TableLink {
  /// tableId is the element it reads. Empty when the chart's numbers are its
  /// own, which is the default.
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
/// just arrived. Rows are matched on [DataSource.matchColumn] -- the team's
/// name -- so a badge follows its team up and down the table rather than
/// staying at the position it was put in.
///
/// A row with no match keeps whatever the source sent for it, which for a
/// picture column is nothing: a newly promoted club has no badge until
/// somebody gives it one, and that is the truth rather than another club's
/// badge inherited by position.
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
/// A rule that colours cells names its column -- "Points", "GD" -- so a
/// refresh that renamed the headers quietly switched every one of those off.
/// The reader named these columns and the source did not, so the reader wins:
/// what arrives is the numbers, not the vocabulary.
///
/// Columns the table did not have before take the source's name, which is the
/// only name they have.
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
