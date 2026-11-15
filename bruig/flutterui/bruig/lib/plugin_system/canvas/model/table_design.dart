import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:flutter/painting.dart';

// table_design.dart is what the Data Studio's Table tab says about a
// table's rules, which it calls styles (Ken, 2026-11-15: designing a table
// through the settings was "very painful"): what part of the table was
// clicked, what each style reaches, what to call it, and whether it changes
// anything you can see. Words rather than the rule language, so "Points
// column · bold" stands for {col: "Points", style: {weight: 700}}.

/// TablePartKind is what was clicked in the Table tab.
enum TablePartKind { table, header, column, row, cell, style }

/// TablePart is one part of a table: the whole of it, its header row, a
/// column, a row, a cell, or one of its styles. Rows count as the table's
/// own rows do, the header (if it has one) being row 0.
class TablePart {
  final TablePartKind kind;
  final int row, col, style;
  const TablePart._(this.kind, {this.row = -1, this.col = -1, this.style = -1});

  static const table = TablePart._(TablePartKind.table);
  static const header = TablePart._(TablePartKind.header);
  const TablePart.column(int col) : this._(TablePartKind.column, col: col);
  const TablePart.row(int row) : this._(TablePartKind.row, row: row);
  const TablePart.cell(int row, int col)
      : this._(TablePartKind.cell, row: row, col: col);
  const TablePart.style(int style) : this._(TablePartKind.style, style: style);

  @override
  bool operator ==(Object other) =>
      other is TablePart &&
      other.kind == kind &&
      other.row == row &&
      other.col == col &&
      other.style == style;

  @override
  int get hashCode => Object.hash(kind, row, col, style);

  @override
  String toString() => "TablePart($kind, $row, $col, $style)";
}

/// styleShows is whether a style changes anything you would see: a fill, a
/// border, its words' colour, size, weight, spacing or place, or hiding
/// them. Corners, insets and nudges change nothing on their own.
bool styleShows(TableCellStyle s) =>
    s.paintsBox ||
    s.changesType ||
    s.letterWidth != 0 ||
    s.textPad != 0 ||
    s.redact;

/// styleCells is every cell [rule] reaches in [t], switched off or not, as
/// (row, column) pairs.
List<(int, int)> styleCells(TableElement t, TableRule rule) {
  var head = t.header;
  var out = <(int, int)>[];
  for (var r = 0; r < t.rows.length; r++) {
    if (!rule.matchesRow(r)) continue;
    if (rule.readsRows && !rule.reachesRow(r, head, (c) => t.cell(r, c))) {
      continue;
    }
    for (var c = 0; c < t.columnCount; c++) {
      if (!rule.matchesColumn(c, head)) continue;
      if (rule.match.isNotEmpty && rule.runsIn(t.cell(r, c)).isEmpty) {
        continue;
      }
      out.add((r, c));
    }
  }
  return out;
}

/// styleIdle says why a style does nothing, or null when it does something:
/// it finds no cell (its words are nowhere in the table, or its rows or
/// column are not there), or nothing about its look shows.
String? styleIdle(TableElement t, TableRule rule) {
  if (styleCells(t, rule).isEmpty) {
    return rule.match.isNotEmpty
        ? "“${rule.match}” is nowhere it looks"
        : "It reaches no cells";
  }
  if (!styleShows(rule.style)) return "It changes nothing you can see";
  return null;
}

/// stylesAt is the styles on one cell, in the order they apply: a later one
/// wins where two say different things.
List<int> stylesAt(TableElement t, int row, int col) => [
      for (var (i, rule) in t.rules.indexed)
        if (rule.matchesRow(row) &&
            (!rule.readsRows ||
                rule.reachesRow(row, t.header, (c) => t.cell(row, c))) &&
            rule.matchesColumn(col, t.header) &&
            (rule.match.isEmpty || rule.runsIn(t.cell(row, col)).isNotEmpty))
          i
    ];

/// stylesOnColumn and stylesOnRow are the styles reaching any cell of a
/// column or a row.
List<int> stylesOnColumn(TableElement t, int col) => [
      for (var (i, rule) in t.rules.indexed)
        if (styleCells(t, rule).any((p) => p.$2 == col)) i
    ];
List<int> stylesOnRow(TableElement t, int row) => [
      for (var (i, rule) in t.rules.indexed)
        if (styleCells(t, rule).any((p) => p.$1 == row)) i
    ];

/// spanWords says a range in the rule language as words. [what] is "row" or
/// "column"; [header] is whether row 1 is the header.
String spanWords(String spec, String what, {bool header = false}) {
  var text = spec.trim();
  if (text.isEmpty) return "every $what";
  String one(int n) => header && what == "row"
      ? (n == 1 ? "the header" : ordinal(n - 1))
      : "$what $n";
  if (text.startsWith(">")) {
    var n = int.tryParse(text.substring(1).trim());
    if (n == null) return "no ${what}s (“$text” can't be read)";
    if (header && what == "row" && n == 1) return "every row but the header";
    return "${what}s after ${one(n)}";
  }
  if (text.startsWith("<")) {
    var n = int.tryParse(text.substring(1).trim());
    if (n == null) return "no ${what}s (“$text” can't be read)";
    return "${what}s before ${one(n)}";
  }
  if (text.contains(":")) {
    var parts = text.split(":");
    var a = int.tryParse(parts.first.trim()),
        b = int.tryParse(parts.last.trim());
    if (a == null || b == null) return "no ${what}s (“$text” can't be read)";
    if (header && what == "row") {
      return "${ordinal(math.min(a, b) - 1)} to ${ordinal(math.max(a, b) - 1)}";
    }
    return "${what}s ${math.min(a, b)}–${math.max(a, b)}";
  }
  var n = int.tryParse(text);
  return n == null ? "no ${what}s (“$text” can't be read)" : one(n);
}

/// ordinal is 1st, 2nd, 3rd, 4th, 11th, 21st.
String ordinal(int n) {
  if (n <= 0) return "$n";
  var teen = (n % 100) >= 11 && (n % 100) <= 13;
  var end = teen
      ? "th"
      : switch (n % 10) { 1 => "st", 2 => "nd", 3 => "rd", _ => "th" };
  return "$n$end";
}

/// styleReach says what [rule] reaches: its column, its rows and its words.
String styleReach(TableElement t, TableRule rule) {
  var col = rule.column.trim();
  var head = t.header;
  var colWords = col.isEmpty
      ? "every column"
      : head.any((h) => h.trim().toLowerCase() == col.toLowerCase())
          ? "$col column"
          : spanWords(col, "column");
  var rowWords = spanWords(rule.rows, "row", header: t.headerRow);
  if (t.headerRow && rule.rows.trim() == ">1") rowWords = "every row";
  if (rule.keys.isNotEmpty) {
    rowWords = rule.rows.trim().isEmpty || rule.rows.trim() == ">1"
        ? "${keysWords(rule.keys)}, wherever ${rule.keys.length == 1 ? "it is" : "they are"}"
        : "${keysWords(rule.keys)} in $rowWords";
  }
  var parts = [colWords, rowWords];
  var w = rule.when;
  if (w != null) parts.add("where ${whenWords(w)}");
  if (rule.match.isNotEmpty) {
    parts.add(switch (rule.how) {
      TableMatch.cell => "“${rule.match}”",
      TableMatch.word => "the word “${rule.match}”",
      TableMatch.anywhere => "“${rule.match}” anywhere",
    });
  }
  return parts.join(" · ");
}

/// keysWords says the rows a style follows: "Arsenal", "Arsenal and
/// Chelsea", "Arsenal, Chelsea and 2 more".
String keysWords(List<String> keys) {
  if (keys.isEmpty) return "";
  if (keys.length == 1) return keys.first;
  if (keys.length == 2) return "${keys[0]} and ${keys[1]}";
  if (keys.length == 3) return "${keys[0]}, ${keys[1]} and ${keys[2]}";
  return "${keys[0]}, ${keys[1]} and ${keys.length - 2} more";
}

/// whenWords says a number condition: "Points is 9 or more".
String whenWords(TableWhen w) {
  var v =
      w.value == w.value.roundToDouble() ? "${w.value.round()}" : "${w.value}";
  return "${w.column} ${switch (w.op) {
    ">=" => "is $v or more",
    "<=" => "is $v or less",
    ">" => "is over $v",
    "<" => "is under $v",
    _ => "is $v",
  }}";
}

/// colourWord names a colour roughly, as you would say it.
String colourWord(Color c) {
  var hsl = HSLColor.fromColor(c.withValues(alpha: 1));
  var l = hsl.lightness, s = hsl.saturation, h = hsl.hue;
  if (s < 0.12 || l < 0.08 || l > 0.95) {
    if (l < 0.12) return "black";
    if (l > 0.9) return "white";
    return l < 0.4
        ? "dark grey"
        : l > 0.7
            ? "light grey"
            : "grey";
  }
  var name = h < 15 || h >= 345
      ? "red"
      : h < 36
          ? "orange"
          : h < 65
              ? "gold"
              : h < 165
                  ? "green"
                  : h < 195
                      ? "teal"
                      : h < 255
                          ? "blue"
                          : h < 290
                              ? "violet"
                              : "pink";
  return l < 0.3
      ? "dark $name"
      : l > 0.75
          ? "pale $name"
          : name;
}

/// styleLook says what [s] does, shortly: "green fill, bold, larger".
String styleLook(TableCellStyle s) {
  var out = <String>[];
  if (s.redact) out.add("words hidden");
  if (s.background.a > 0) {
    out.add(
        "${colourWord(s.background)} ${s.hug || s.inset > 0 ? "box" : "fill"}");
  }
  if (s.borderColor.a > 0 && s.borderWidth > 0) {
    var sides = s.sides;
    var where = s.allSides
        ? "border"
        : [
            if (sides[0]) "line above",
            if (sides[2]) "line under",
            if (sides[1] || sides[3]) "side lines",
          ].join(", ");
    out.add("${colourWord(s.borderColor)} $where");
  }
  if (s.textColor.a > 0) out.add("${colourWord(s.textColor)} words");
  if (s.weight >= 600) out.add("bold");
  if (s.weight > 0 && s.weight <= 300) out.add("light");
  if (s.fontScale > 1.01) out.add("larger");
  if (s.fontScale < 0.99) out.add("smaller");
  if (s.letterWidth != 0 || s.letterSpacing != 0) out.add("spaced");
  if (s.align != null) out.add("to the ${s.align!.name}");
  if (s.textPad != 0) out.add("margin");
  return out.isEmpty ? "no change" : out.join(", ");
}

/// styleName is what to call [t]'s style [index]: its own name, else what it
/// reaches and looks like.
String styleName(TableElement t, int index) {
  var rule = t.rules[index];
  if (rule.name.trim().isNotEmpty) return rule.name.trim();
  var look = styleLook(rule.style);
  if (rule.match.isNotEmpty) {
    var col = rule.column.trim();
    return "“${rule.match}”${col.isEmpty ? "" : " in ${_short(t, col)}"} · $look";
  }
  var w = rule.when;
  if (rule.keys.isNotEmpty) {
    var col = rule.column.trim();
    return "${keysWords(rule.keys)}${col.isEmpty ? "'s row" : "'s ${_short(t, col)}"} · $look";
  }
  if (w != null) {
    var col = rule.column.trim();
    return "${_capital(whenWords(w))}${col.isEmpty ? " (rows)" : col.toLowerCase() == w.column.toLowerCase() ? "" : " · ${_short(t, col)}"} · $look";
  }
  if (rule.column.trim().isEmpty) {
    return "${_capital(spanWords(rule.rows, "row", header: t.headerRow))} · $look";
  }
  return "${_capital(_short(t, rule.column.trim()))} · $look";
}

String _short(TableElement t, String col) =>
    t.header.any((h) => h.trim().toLowerCase() == col.toLowerCase())
        ? col
        : spanWords(col, "column");

String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// styleGroups puts [t]'s styles under headings, as the Table tab lists
/// them: those about whole rows; a group for each column with three or more;
/// the other columns together; then words. Each style once, in order.
List<(String, List<int>)> styleGroups(TableElement t) {
  var rows = <int>[], words = <int>[], byCol = <String, List<int>>{};
  for (var (i, rule) in t.rules.indexed) {
    if (rule.column.trim().isEmpty && rule.match.isEmpty) {
      rows.add(i);
    } else if (rule.column.trim().isEmpty) {
      words.add(i);
    } else {
      (byCol[rule.column.trim().toLowerCase()] ??= []).add(i);
    }
  }
  var other = <int>[];
  var out = <(String, List<int>)>[if (rows.isNotEmpty) ("Whole rows", rows)];
  for (var MapEntry(:key, :value) in byCol.entries) {
    if (value.length >= 3 && key.isNotEmpty) {
      out.add((
        "${_capital(_short(t, t.rules[value.first].column.trim()))}"
            "${t.header.any((h) => h.trim().toLowerCase() == key) ? " column" : ""}",
        value
      ));
    } else {
      other.addAll(value);
    }
  }
  other.sort();
  if (other.isNotEmpty) {
    out.add((
      out.length > (rows.isEmpty ? 0 : 1) ? "Other columns" : "Columns",
      other
    ));
  }
  if (words.isNotEmpty) out.add(("Words anywhere", words));
  return out;
}

/// keyColumnOf is the column that names a table's rows -- a team, a player,
/// a coin -- for styles that follow a row as it moves: one headed as names
/// are, else the column of the longest distinct words. -1 when none is.
int keyColumnOf(TableElement t) {
  var head = t.header;
  const named = ["team", "club", "name", "player", "country", "coin", "who"];
  for (var (i, h) in head.indexed) {
    if (named.contains(h.trim().toLowerCase())) return i;
  }
  var best = -1;
  var bestLength = 0.0;
  var start = t.headerRow ? 1 : 0;
  for (var c = 0; c < t.columnCount; c++) {
    var words = [
      for (var r = start; r < t.rows.length; r++) t.cell(r, c).trim()
    ];
    if (words.isEmpty || words.any((w) => w.isEmpty)) continue;
    if (words.any((w) => cellNumber(w) != null)) continue;
    if (words.toSet().length != words.length) continue;
    var length = words.fold(0, (a, w) => a + w.length) / words.length;
    if (length > bestLength) {
      best = c;
      bestLength = length;
    }
  }
  return best;
}

/// ReachOption is one answer to "what should the new style reach?", offered
/// from what was clicked: its words, and the rule it starts as.
class ReachOption {
  final String label;
  final TableRule rule;
  const ReachOption(this.label, this.rule);
}

/// columnKey is how a rule names column [col]: its heading, or its number.
String columnKey(TableElement t, int col) {
  var head = t.header;
  var name = col < head.length ? head[col].trim() : "";
  return name.isEmpty ? "${col + 1}" : name;
}

/// reachOptions is what a new style could reach, from a click on [from]
/// (prototype v3's reachOptions): a cell offers that team's cell or whole
/// row (following it), the row by place (staying put), the column, a number
/// condition from what the cell says, and each short word in it; a row tab,
/// the team's row or the place; a column tab, the column. [rows], picked
/// with shift, offers them by place or by who is in them.
List<ReachOption> reachOptions(TableElement t, TablePart from,
    {List<int> rows = const []}) {
  var out = <ReachOption>[];
  var k = keyColumnOf(t);
  var head = t.header;
  String keyAt(int row) => k < 0 ? "" : t.cell(row, k).trim();
  bool body(int row) => !(t.headerRow && row == 0);
  String place(int row) => t.headerRow ? ordinal(row) : "row ${row + 1}";

  if (rows.length > 1) {
    var sorted = [...rows]..sort();
    var runs = sorted.last - sorted.first + 1 == sorted.length;
    var spec = runs ? "${sorted.first + 1}:${sorted.last + 1}" : "";
    if (runs) {
      out.add(ReachOption(
          "${_capital(place(sorted.first))} to ${place(sorted.last)}, whoever is there",
          TableRule(rows: spec)));
    }
    if (k >= 0 && sorted.every(body)) {
      var keys = [for (var r in sorted) keyAt(r)];
      out.add(ReachOption("${keysWords(keys)}, wherever they are",
          TableRule(keys: keys, keyColumn: columnKey(t, k))));
    }
    return out;
  }

  switch (from.kind) {
    case TablePartKind.cell:
      var row = from.row, col = from.col;
      var colKey = columnKey(t, col), colName = t.columnName(col);
      if (!body(row)) {
        out.add(ReachOption(
            "The $colName heading", TableRule(column: colKey, rows: "1")));
        out.add(ReachOption("The header row", const TableRule(rows: "1")));
        break;
      }
      var who = keyAt(row);
      if (who.isNotEmpty && col != k) {
        out.add(ReachOption(
            "$who's $colName, wherever $who is",
            TableRule(
                column: colKey, keys: [who], keyColumn: columnKey(t, k))));
      }
      if (who.isNotEmpty) {
        out.add(ReachOption("$who's row, wherever $who is",
            TableRule(keys: [who], keyColumn: columnKey(t, k))));
      }
      out.add(ReachOption("The ${place(row)} row, whoever is there",
          TableRule(rows: "${row + 1}")));
      out.add(ReachOption("The $colName column",
          TableRule(column: colKey, rows: t.headerRow ? ">1" : "")));
      var n = cellNumber(t.cell(row, col));
      if (n != null && head.isNotEmpty) {
        var v = n == n.roundToDouble() ? "${n.round()}" : "$n";
        out.add(ReachOption("$colName $v or more",
            TableRule(column: colKey, when: TableWhen(colKey, ">=", n))));
        out.add(ReachOption("Rows where $colName is $v or more",
            TableRule(when: TableWhen(colKey, ">=", n))));
      }
      var words = t.cell(row, col).trim().split(RegExp(r"\s+"));
      if (words.length > 1) {
        var seen = <String>{};
        for (var w in words) {
          if (w.isEmpty || w.length > 3 || !seen.add(w)) continue;
          if (seen.length > 4) break;
          out.add(ReachOption("Every “$w” in $colName",
              TableRule(column: colKey, match: w, how: TableMatch.word)));
        }
      }
    case TablePartKind.row:
      var who = keyAt(from.row);
      if (who.isNotEmpty) {
        out.add(ReachOption("$who's row, wherever $who is",
            TableRule(keys: [who], keyColumn: columnKey(t, k))));
      }
      out.add(ReachOption("The ${place(from.row)} row, whoever is there",
          TableRule(rows: "${from.row + 1}")));
    case TablePartKind.column:
      out.add(ReachOption(
          "The ${t.columnName(from.col)} column",
          TableRule(
              column: columnKey(t, from.col), rows: t.headerRow ? ">1" : "")));
      if (t.headerRow) {
        out.add(ReachOption("Its heading",
            TableRule(column: columnKey(t, from.col), rows: "1")));
      }
    case TablePartKind.header:
      out.add(const ReachOption("The header row", TableRule(rows: "1")));
    case TablePartKind.table:
      out.add(ReachOption(
          t.headerRow ? "Every row but the header" : "Every row",
          TableRule(rows: t.headerRow ? ">1" : "")));
    case TablePartKind.style:
      break;
  }
  return out;
}

/// lookFor is the look a new style starts with, so it shows at once: a pale
/// gold fill for rows and cells, a gold box round words.
TableCellStyle lookFor(TableRule rule) => rule.match.isNotEmpty
    ? const TableCellStyle(background: Color(0xFFF2B33D), hug: true, inset: 2)
    : const TableCellStyle(
        background: Color(0x40F2B33D), hug: false, inset: 0, radius: 0);
