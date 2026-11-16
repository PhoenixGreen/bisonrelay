import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:flutter/foundation.dart';

// sheet_reshape.dart is a sheet made from another (Ken, 2026-11-17, the
// improvements report's second item): the same numbers in another shape,
// so one sheet feeds any chart without being typed again. The Charts canvas
// found Line's "Small charts" needing its own long copy of a wide sheet.
//
// - long: a column a club becomes a row a club a season (wide → long);
// - wide: a row a club a season becomes a column a club (a pivot);
// - group: rows with the same word brought together, their numbers added
//   up, averaged, counted, or the most or least;
// - join: another sheet's columns beside each row, matched on a column.
//
// A made sheet keeps its recipe (DataSheet.made) and is made again whenever
// what it is made from changes, so a refresh flows through to its tables
// and charts (sheetsMade, before the views follow their sheets).

enum ReshapeKind {
  long("Long: a row a value"),
  wide("Wide: a column a word"),
  group("Grouped: totals by a column"),
  join("Joined with another sheet");

  final String label;
  const ReshapeKind(this.label);

  static ReshapeKind fromName(String? n) =>
      values.firstWhere((k) => k.name == n, orElse: () => long);
}

/// SheetMade is how a sheet is made from sheet [from]. Columns are counted
/// from the source's first; -1 is none.
@immutable
class SheetMade {
  final String from;
  final ReshapeKind kind;

  /// keep is, for long, the columns kept on every row (the club's name); the
  /// rest each become a row, their heading under [names], their value under
  /// [valuesName].
  final List<int> keep;
  final String names, valuesName;

  /// rows, columns and value are, for wide, the column naming each row, the
  /// one whose words become columns, and the one filling them.
  final int rows, columns, value;

  /// by and how are, for group, the column grouped by and what is made of
  /// each number column: "total", "average", "count", "most", "least".
  final int by;
  final String how;

  /// other, on and otherOn are, for join, the other sheet and the columns
  /// matched in each.
  final String other;
  final int on, otherOn;

  const SheetMade(this.from, this.kind,
      {this.keep = const [0],
      this.names = "Series",
      this.valuesName = "Value",
      this.rows = 0,
      this.columns = 1,
      this.value = 2,
      this.by = 0,
      this.how = "total",
      this.other = "",
      this.on = 0,
      this.otherOn = 0});

  Map<String, dynamic> toJson() => {
        "from": from,
        "kind": kind.name,
        if (kind == ReshapeKind.long) ...{
          "keep": keep,
          "names": names,
          "valuesName": valuesName,
        },
        if (kind == ReshapeKind.wide) ...{
          "rows": rows,
          "columns": columns,
          "value": value,
          "how": how,
        },
        if (kind == ReshapeKind.group) ...{"by": by, "how": how},
        if (kind == ReshapeKind.join) ...{
          "other": other,
          "on": on,
          "otherOn": otherOn,
        },
      };

  static SheetMade? fromJson(Object? j) {
    if (j is! Map || j["from"] is! String) return null;
    int n(String k, int or) => j[k] is num ? (j[k] as num).toInt() : or;
    String s(String k, String or) => j[k] is String ? j[k] as String : or;
    return SheetMade(j["from"] as String, ReshapeKind.fromName(j["kind"]),
        keep: [
          if (j["keep"] case List k)
            for (var c in k)
              if (c is num) c.toInt(),
        ],
        names: s("names", "Series"),
        valuesName: s("valuesName", "Value"),
        rows: n("rows", 0),
        columns: n("columns", 1),
        value: n("value", 2),
        by: n("by", 0),
        how: s("how", "total"),
        other: s("other", ""),
        on: n("on", 0),
        otherOn: n("otherOn", 0));
  }

  @override
  bool operator ==(Object other) =>
      other is SheetMade &&
      mapEquals(other.toJson().map((k, v) => MapEntry(k, "$v")),
          toJson().map((k, v) => MapEntry(k, "$v")));

  @override
  int get hashCode => "${toJson()}".hashCode;

  /// says is what it is, in a few words, for the Studio.
  String says(DataSheet source, DataSheet? with_) => switch (kind) {
        ReshapeKind.long => "${source.name}, a row a value",
        ReshapeKind.wide => "${source.name}, a column a "
            "${_head(source, columns).toLowerCase()}",
        ReshapeKind.group =>
          "${source.name}, ${how == "count" ? "counted" : how} "
              "by ${_head(source, by).toLowerCase()}",
        ReshapeKind.join => "${source.name} with ${with_?.name ?? "another"}",
      };
}

String _head(DataSheet s, int c) =>
    s.cells.isNotEmpty && c >= 0 && c < s.cells.first.length
        ? s.cells.first[c].trim()
        : "column ${c + 1}";

/// _grid is [s]'s used cells as shown (formulas worked out), header first.
List<List<String>> _grid(DataSheet s) {
  var g = s.used;
  return [
    for (var r = g.r0; r <= g.r1; r++)
      [for (var c = g.c0; c <= g.c1; c++) sheetShown(s, r, c)],
  ];
}

double? _number(String v) {
  var t = v.trim().replaceAll(RegExp(r"[,£$€%\s]"), "").replaceAll("−", "-");
  return t.isEmpty ? null : double.tryParse(t);
}

String _plain(double v) => v == v.roundToDouble()
    ? v.round().toString()
    : v.toStringAsFixed(2).replaceAll(RegExp(r"0+$"), "");

double _aggregate(String how, List<double> v) => switch (how) {
      "count" => v.length.toDouble(),
      "average" => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length,
      "most" => v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b),
      "least" => v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b),
      _ => v.fold(0.0, (a, b) => a + b),
    };

/// reshaped is the cells [m] makes from [from] (and, for a join, [other]),
/// header first.
List<List<String>> reshaped(SheetMade m, DataSheet from, [DataSheet? other]) {
  var g = _grid(from);
  if (g.isEmpty) return const [];
  var head = g.first, body = g.skip(1).toList();
  String at(List<String> row, int c) => c >= 0 && c < row.length ? row[c] : "";
  switch (m.kind) {
    case ReshapeKind.long:
      var keep = [
        for (var c in m.keep)
          if (c >= 0 && c < head.length) c
      ];
      return [
        [for (var c in keep) head[c], m.names, m.valuesName],
        for (var row in body)
          for (var c = 0; c < head.length; c++)
            if (!keep.contains(c) && at(row, c).trim().isNotEmpty)
              [for (var k in keep) at(row, k), head[c], at(row, c)],
      ];
    case ReshapeKind.wide:
      var keys = <String>[], cols = <String>[];
      var cells = <String, List<String>>{};
      for (var row in body) {
        var k = at(row, m.rows), c = at(row, m.columns);
        if (k.trim().isEmpty || c.trim().isEmpty) continue;
        if (!keys.contains(k)) keys.add(k);
        if (!cols.contains(c)) cols.add(c);
        (cells["$k\u0000$c"] ??= []).add(at(row, m.value));
      }
      String one(List<String>? vs) {
        if (vs == null || vs.isEmpty) return "";
        if (vs.length == 1) return vs.single;
        var n = [for (var v in vs) _number(v)].whereType<double>().toList();
        return n.length == vs.length ? _plain(_aggregate(m.how, n)) : vs.last;
      }
      return [
        [at(head, m.rows), ...cols],
        for (var k in keys) [k, for (var c in cols) one(cells["$k\u0000$c"])],
      ];
    case ReshapeKind.group:
      var numbers = [
        for (var c = 0; c < head.length; c++)
          if (c != m.by &&
              body.isNotEmpty &&
              body.every(
                  (r) => at(r, c).trim().isEmpty || _number(at(r, c)) != null))
            c
      ];
      var keys = <String>[];
      var groups = <String, List<List<String>>>{};
      for (var row in body) {
        var k = at(row, m.by);
        if (k.trim().isEmpty) continue;
        if (!keys.contains(k)) keys.add(k);
        (groups[k] ??= []).add(row);
      }
      return [
        [
          at(head, m.by),
          if (m.how == "count")
            "Count"
          else ...[for (var c in numbers) head[c]],
        ],
        for (var k in keys)
          [
            k,
            if (m.how == "count")
              "${groups[k]!.length}"
            else
              for (var c in numbers)
                _plain(_aggregate(m.how, [
                  for (var r in groups[k]!)
                    if (_number(at(r, c)) case var v?) v
                ])),
          ],
      ];
    case ReshapeKind.join:
      if (other == null) return g;
      var o = _grid(other);
      if (o.isEmpty) return g;
      var oHead = o.first;
      var extra = [
        for (var c = 0; c < oHead.length; c++)
          if (c != m.otherOn) c
      ];
      String key(String v) => v.trim().toLowerCase();
      var match = {for (var r in o.skip(1)) key(at(r, m.otherOn)): r};
      return [
        [...head, for (var c in extra) oHead[c]],
        for (var row in body)
          [
            ...row,
            for (var c in extra) at(match[key(at(row, m.on))] ?? const [], c),
          ],
      ];
  }
}

/// sheetsMade is [next] with every made sheet made again where what it is
/// made from changed since [was] (or it is new, or its recipe changed): a
/// chain of them settles in as many passes as it is long.
CanvasDocument sheetsMade(CanvasDocument was, CanvasDocument next) {
  if (!next.sheets.any((s) => s.made != null)) return next;
  var before = {for (var s in was.sheets) s.id: s};
  var sheets = [...next.sheets];
  var changed = <String>{
    for (var s in sheets)
      if (!identical(before[s.id], s)) s.id,
  };
  var any = false;
  for (var pass = 0; pass < 4; pass++) {
    var byId = {for (var s in sheets) s.id: s};
    var again = false;
    for (var (i, s) in sheets.indexed) {
      var m = s.made;
      if (m == null) continue;
      var from = byId[m.from];
      if (from == null) continue; // its source gone: kept as it was
      var other = m.kind == ReshapeKind.join ? byId[m.other] : null;
      var stale = changed.contains(m.from) ||
          (other != null && changed.contains(m.other)) ||
          before[s.id] == null ||
          before[s.id]!.made != m;
      if (!stale) continue;
      var cells = reshaped(m, from, other);
      if (listEquals([for (var r in s.cells) r.join("\u0001")],
          [for (var r in cells) r.join("\u0001")])) {
        continue;
      }
      sheets[i] = s.copyWith(cells: cells);
      changed.add(s.id);
      again = true;
      any = true;
    }
    if (!again) break;
  }
  return any ? next.copyWith(sheets: sheets) : next;
}
