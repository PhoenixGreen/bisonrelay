import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/chart_presets.dart'
    show ChartUse;
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/table_design.dart';

// table_presets.dart is the Table tab's gallery (Ken, 2026-11-17; prototype
// v7 and its research): ten kinds of table, each with starting designs. A
// design sets the table's layout -- its header, lines, stripes, which
// columns are drawn rather than written, headings across -- and its
// emphasis, as styles (TableRules) named "Design: ...", which the next
// design replaces; the cells, the user's own styles and the style's
// colours stay. Each design reads the table's own columns -- numbers, yes
// and no, W/D/L, lists of numbers, changes -- and says what it needs when
// they aren't there.

/// TableShape is what a table's columns hold, for its designs.
class TableShape {
  final TableElement t;
  TableShape(this.t);

  List<String> _body(int c) => [
        for (var r = t.headerRow ? 1 : 0; r < t.rows.length; r++)
          t.cell(r, c).trim(),
      ].where((v) => v.isNotEmpty).toList();

  bool _most(int c, bool Function(String) test) {
    var vs = _body(c);
    return vs.isNotEmpty && vs.where(test).length * 10 >= vs.length * 7;
  }

  static final _num = RegExp(r"^[−\-+£$€]?\d[\d,]*(\.\d+)?%?$");

  List<int> get numbers => [
        for (var c = 1; c < t.columnCount; c++)
          if (_most(c, (v) => _num.hasMatch(v))) c
      ];
  int? get lastNumber => numbers.isEmpty ? null : numbers.last;
  List<int> get yesNo => [
        for (var c = 1; c < t.columnCount; c++)
          if (_most(
              c,
              (v) => RegExp(r"^(y|yes|n|no|true|false|✓|✗|x|-)$",
                      caseSensitive: false)
                  .hasMatch(v)))
            c
      ];
  List<int> get results => [
        for (var c = 1; c < t.columnCount; c++)
          if (_most(c, (v) => RegExp(r"^[WDL][\sWDL]*$").hasMatch(v))) c
      ];
  List<int> get lists => [
        for (var c = 1; c < t.columnCount; c++)
          if (_most(
              c,
              (v) => RegExp(r"^-?\d+(\.\d+)?([,;\s]+-?\d+(\.\d+)?)+$")
                  .hasMatch(v)))
            c
      ];
  List<int> get changes => [
        for (var c = 1; c < t.columnCount; c++)
          if (RegExp(r"chang|moved|move|±|diff|vs|delta", caseSensitive: false)
                  .hasMatch(columnKey(t, c)) ||
              _most(c, (v) => RegExp(r"^[+\-−]\d").hasMatch(v) || v == "0"))
            c
      ];
  List<int> get smallSteps => [
        for (var c in numbers)
          if (_most(c, (v) => RegExp(r"^[0-4]$").hasMatch(v))) c
      ];

  /// lead is the first data row's key, for a design that lights one row.
  String get lead => t.rows.length > (t.headerRow ? 1 : 0)
      ? t.cell(t.headerRow ? 1 : 0, 0).trim()
      : "";
}

/// TablePreset is one starting design for a kind of table.
class TablePreset {
  final String name, says;
  final List<ChartUse> uses;

  /// needs, when set, says what the table lacks for it; null, it can.
  final String? Function(TableShape)? needs;
  final TableElement Function(TableElement t, TableShape s) apply;
  const TablePreset(this.name, this.says, this.uses, this.apply, {this.needs});
}

class TableKind {
  final String id, name, use;
  final List<TablePreset> presets;
  const TableKind(this.id, this.name, this.use, this.presets);
}

const _i = ChartUse.infographic, _v = ChartUse.video, _a = ChartUse.analysis;
const designPrefix = "Design: ";

/// _fresh is [t] with the last design's choices taken off: its styles
/// named "Design: ...", its drawn columns and headings across.
TableElement _fresh(TableElement t) => t.copyWith(
      rules: [
        for (var r in t.rules)
          if (!r.name.startsWith(designPrefix)) r
      ],
      columnKinds: const {},
      groupRows: false,
      headerRow: true,
      headerColumn: false,
      zebra: false,
      grid: TableGrid.horizontal,
      gridWidth: 1,
      showOutline: false,
    );

TableRule _rule(String name, TableRule r) =>
    r.copyWith(name: "$designPrefix$name");

TableElement _with(TableElement t, List<TableRule> rules,
        {Map<int, String> kinds = const {}}) =>
    t.copyWith(
        rules: [...t.rules, ...rules],
        columnKinds: {...t.columnKinds, ...kinds});

/// _boldLast is the last column of numbers in bold: a league's points.
List<TableRule> _boldLast(TableElement t, TableShape s) => s.lastNumber == null
    ? const []
    : [
        _rule(
            "${columnKey(t, s.lastNumber!)} in bold",
            TableRule(
                column: columnKey(t, s.lastNumber!),
                rows: ">1",
                style: const TableCellStyle(weight: 800))),
      ];

/// _lit is the first row picked out: tinted and bold, wherever it moves.
List<TableRule> _lit(TableElement t, TableShape s, Color tint) => s.lead.isEmpty
    ? const []
    : [
        _rule(
            "${s.lead} picked out",
            TableRule(
                keys: [s.lead],
                keyColumn: columnKey(t, 0),
                style: TableCellStyle(
                    background: tint,
                    weight: 700,
                    radius: 0,
                    inset: 0,
                    hug: false))),
      ];

/// _form is W, D and L as coloured boxes in a results column.
List<TableRule> _form(TableElement t, TableShape s) => [
      for (var c in s.results)
        for (var (w, colour) in const [
          ("W", Color(0xFF2EA44F)),
          ("D", Color(0xFF9AA4B2)),
          ("L", Color(0xFFE5534B)),
        ])
          _rule(
              "$w in ${columnKey(t, c)}",
              TableRule(
                  column: columnKey(t, c),
                  match: w,
                  how: TableMatch.word,
                  style: TableCellStyle(
                      background: colour,
                      textColor: const Color(0xFFFFFFFF),
                      weight: 700,
                      radius: 3,
                      inset: 2))),
    ];

/// _top is the first [n] rows larger and bold.
List<TableRule> _top(int n) => [
      _rule(
          "The first $n larger",
          TableRule(
              rows: "2:${n + 1}",
              style: const TableCellStyle(weight: 700, fontScale: 1.12))),
    ];

String? _needsResults(TableShape s) =>
    s.results.isEmpty ? "a column of results like W D L" : null;
String? _needsChanges(TableShape s) =>
    s.changes.isEmpty ? "a column of changes like +2 or −1" : null;
String? _needsLists(TableShape s) =>
    s.lists.isEmpty ? "a column of numbers like 3, 5, 8" : null;
String? _needsYesNo(TableShape s) =>
    s.yesNo.isEmpty ? "a column of yes and no" : null;
String? _needsSteps(TableShape s) =>
    s.smallSteps.isEmpty ? "a column of numbers 0 to 4" : null;
String? _needsNumbers(TableShape s) =>
    s.numbers.isEmpty ? "a column of numbers" : null;

const _tint = Color(0x33F2B33D);

final tableKinds = <TableKind>[
  TableKind(
      "league", "League table", "Standings: positions, results and points.", [
    TablePreset(
        "Broadcast standings",
        "Rounded panel, the top four marked, bold points, row by row.",
        [_v, _i], (t, s) {
      var f = _fresh(t).copyWith(cornerRadius: 10, turn: TableTurn.rows);
      return _with(f, [
        ..._boldLast(f, s),
        _rule(
            "The top four marked",
            TableRule(
                rows: "2:5",
                column: columnKey(f, 0),
                style: const TableCellStyle(
                    background: Color(0x552F6FDE),
                    radius: 0,
                    inset: 0,
                    hug: false))),
      ]);
    }),
    TablePreset("Newspaper", "Compact, hairlines only, bold points.", [_a],
        (t, s) => _with(_fresh(t).copyWith(gridWidth: 0.6), _boldLast(t, s))),
    TablePreset(
        "With form",
        "The results as W, D and L boxes; striped.",
        [_a, _i],
        (t, s) => _with(_fresh(t).copyWith(zebra: true),
            [..._boldLast(t, s), ..._form(t, s)]),
        needs: _needsResults),
    TablePreset(
        "Movers",
        "Places gained and lost as arrows.",
        [_v, _a],
        (t, s) => _with(_fresh(t), _boldLast(t, s),
            kinds: {for (var c in s.changes) c: "change"}),
        needs: _needsChanges),
    TablePreset(
        "One club lit",
        "The first club's row tinted and bold, wherever it goes.",
        [_a, _v],
        (t, s) => _with(_fresh(t), [..._boldLast(t, s), ..._lit(t, s, _tint)])),
  ]),
  TableKind(
      "leaderboard", "Leaderboard", "A ranked list: the top few stand out.", [
    TablePreset(
        "Podium",
        "The top three larger and bold; arriving one by one.",
        [_i, _v],
        (t, s) => _with(
            _fresh(t).copyWith(grid: TableGrid.none, turn: TableTurn.rows),
            _top(3))),
    TablePreset(
        "Striped",
        "Stripes for a long list, the last column bold.",
        [_a, _i],
        (t, s) => _with(_fresh(t).copyWith(zebra: true, grid: TableGrid.none),
            _boldLast(t, s))),
    TablePreset(
        "Results",
        "Changes up and down beside each.",
        [_a],
        (t, s) => _with(_fresh(t), _boldLast(t, s),
            kinds: {for (var c in s.changes) c: "change"}),
        needs: _needsChanges),
  ]),
  TableKind("plain", "Plain and clean",
      "Newspaper and report tables: few lines, numbers right.", [
    TablePreset(
        "Newsroom",
        "One rule under the header, hairlines, nothing else.",
        [_a],
        (t, s) => _fresh(t).copyWith(gridWidth: 0.6)),
    TablePreset(
        "Three rules",
        "No lines but under the header: the academic way.",
        [_a],
        (t, s) => _fresh(t).copyWith(grid: TableGrid.none)),
    TablePreset("One row lit", "The first row tinted and bold.", [_a, _v],
        (t, s) => _with(_fresh(t).copyWith(gridWidth: 0.6), _lit(t, s, _tint))),
    TablePreset(
        "In groups",
        "Rows with only a first cell become headings across.",
        [_a],
        (t, s) => _fresh(t).copyWith(groupRows: true)),
  ]),
  TableKind("heat", "Heatmap table", "Each number shaded by how high it is.", [
    TablePreset(
        "Shaded by column",
        "Every column of numbers shaded on its own scale.",
        [_a],
        (t, s) => _with(
            _fresh(t).copyWith(grid: TableGrid.all, gridWidth: 2), const [],
            kinds: {for (var c in s.numbers) c: "heat"}),
        needs: _needsNumbers),
    TablePreset(
        "Shaded, no lines",
        "The shades alone, no lines between.",
        [_i, _a],
        (t, s) => _with(_fresh(t).copyWith(grid: TableGrid.none), const [],
            kinds: {for (var c in s.numbers) c: "heat"}),
        needs: _needsNumbers),
    TablePreset(
        "Last column shaded",
        "Only the column that matters most.",
        [_a],
        (t, s) => _with(_fresh(t), const [],
            kinds: {if (s.lastNumber != null) s.lastNumber!: "heat"}),
        needs: _needsNumbers),
  ]),
  TableKind("charts", "Table with charts", "A small chart in the cells.", [
    TablePreset(
        "Sparklines",
        "Each row's numbers as a small line.",
        [_a],
        (t, s) => _with(_fresh(t), const [],
            kinds: {for (var c in s.lists) c: "spark"}),
        needs: _needsLists),
    TablePreset(
        "Up and down",
        "Changes as coloured arrows.",
        [_a, _v],
        (t, s) => _with(_fresh(t), const [],
            kinds: {for (var c in s.changes) c: "change"}),
        needs: _needsChanges),
  ]),
  TableKind("accounts", "Accounts", "Statements, budgets and price boards.", [
    TablePreset(
        "Statement",
        "Sections as headings across, the last column bold.",
        [_a],
        (t, s) => _with(_fresh(t).copyWith(groupRows: true, gridWidth: 0.6),
            _boldLast(t, s))),
    TablePreset(
        "Price board",
        "Changes in colour with arrows.",
        [_a, _v],
        (t, s) => _with(_fresh(t).copyWith(zebra: true), const [],
            kinds: {for (var c in s.changes) c: "change"}),
        needs: _needsChanges),
  ]),
  TableKind("compare", "Comparison", "Options against features.", [
    TablePreset(
        "Ticks",
        "Yes and no as ticks and crosses.",
        [_i, _a],
        (t, s) => _with(_fresh(t).copyWith(grid: TableGrid.all), const [],
            kinds: {for (var c in s.yesNo) c: "ticks"}),
        needs: _needsYesNo),
    TablePreset(
        "How much",
        "0 to 4 as part-filled circles.",
        [_a],
        (t, s) => _with(_fresh(t).copyWith(grid: TableGrid.all), const [],
            kinds: {for (var c in s.smallSteps) c: "harvey"}),
        needs: _needsSteps),
    TablePreset(
        "In groups",
        "Headings across for each group of features.",
        [_a],
        (t, s) => _with(
            _fresh(t).copyWith(groupRows: true, zebra: true), const [],
            kinds: {for (var c in s.yesNo) c: "ticks"})),
  ]),
  TableKind("scorecard", "Scorecard", "Measures against their targets.", [
    TablePreset(
        "Arrows",
        "Ahead or behind as arrows.",
        [_a, _v],
        (t, s) => _with(_fresh(t), const [],
            kinds: {for (var c in s.changes) c: "change"}),
        needs: _needsChanges),
    TablePreset(
        "How far along",
        "0 to 4 as part-filled circles.",
        [_i, _a],
        (t, s) => _with(_fresh(t), const [],
            kinds: {for (var c in s.smallSteps) c: "harvey"}),
        needs: _needsSteps),
  ]),
  TableKind("fixtures", "Fixtures", "Who plays whom, and when.", [
    TablePreset(
        "By date",
        "Dates as headings across, one row a match.",
        [_i, _v],
        (t, s) => _fresh(t)
            .copyWith(groupRows: true, grid: TableGrid.none, zebra: true)),
    TablePreset(
        "Repeats merged",
        "A repeated date or group as one tall cell.",
        [_a],
        (t, s) => _fresh(t)
            .copyWith(grid: TableGrid.all, columnKinds: const {0: "merge"})),
  ]),
  TableKind("plans", "Plans", "Tiers side by side.", [
    TablePreset(
        "Ticks, one lit",
        "Ticks for what each has; the first row bold.",
        [_i, _a],
        (t, s) => _with(
            _fresh(t).copyWith(grid: TableGrid.all, cornerRadius: 10), _top(1),
            kinds: {for (var c in s.yesNo) c: "ticks"}),
        needs: _needsYesNo),
  ]),
];

/// presetTable is [preset] on [t]: its design, the cells kept.
TableElement presetTable(TablePreset preset, TableElement t) =>
    preset.apply(t, TableShape(t));
