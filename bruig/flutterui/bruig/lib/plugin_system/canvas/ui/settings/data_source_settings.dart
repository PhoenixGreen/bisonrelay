import 'dart:math' as math;
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// data_source_settings.dart is the "where do these numbers come from" panel.
//
// It is a table's, for now, and is its own file because it is about data
// rather than about how a table looks -- and because a chart pulling a table's
// numbers, next door, has to show some of the same things.
//
// The panel is arranged so the easy path is the short one: choose a preset,
// choose a competition, press Refresh. Everything under that -- the address,
// the path to the rows, the columns -- is the same mapping the preset filled
// in, left visible so anything the presets do not cover is still reachable.

/// dataSourceSection is the Data section of a table's settings.
///
/// The whole section is the panel, rather than the panel being its children,
/// because the Refresh button lives in the section's own heading -- pressing
/// it must work with the section shut, and it needs the state that knows
/// whether a refresh is already running.
Widget dataSourceSection(
        BuildContext context,
        CanvasController controller,
        TableElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    _DataSourcePanel(
      controller: controller,
      target: _TableTarget(e, controller, write, begin, commit),
      key: ValueKey("source-${e.id}"),
    );

/// sourceRefreshButton is the Refresh button on its own, for a section that
/// is not the data source's.
///
/// The Table section has one because that is where somebody is standing when
/// they want the numbers again: they are looking at the cells. Sending them
/// to another section to press the same button is asking them to know which
/// section owns the wire rather than which one shows the thing.
///
/// It is the same refresh -- see _runRefresh -- so the coin list, the derived
/// form guide and the message about what could not be found all behave the
/// same way from either button. Null where there is no source to read, so a
/// heading does not carry a button that could never do anything.
Widget? sourceRefreshButton(
    BuildContext context,
    CanvasController controller,
    CanvasElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var target = switch (e) {
    TableElement table => _TableTarget(table, controller, write, begin, commit),
    ChartElement chart => _ChartTarget(chart, controller, write, begin, commit),
    _ => null,
  };
  if (target == null || !target.source.on) return null;
  return _RefreshButton(target: target, key: ValueKey("refresh-${e.id}"));
}

class _RefreshButton extends StatefulWidget {
  final _Target target;

  const _RefreshButton({required this.target, super.key});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  /// _busy is a refresh in progress. A second press would make a second
  /// request and race the first one into the document.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    var source = widget.target.source;
    return CanvasIconButton(
      icon: _busy ? Icons.hourglass_empty : Icons.refresh,
      tooltip: source.fetchedAt == null
          ? "Read the data and put it in the ${widget.target.noun}"
          : "Read the data again — last updated "
              "${DateFormat("d MMM y, HH:mm").format(source.fetchedAt!.toLocal())}",
      onPressed: _busy
          ? null
          : () async {
              var allowed = context.read<CanvasPreferences>().allowFetching;
              setState(() => _busy = true);
              try {
                await _runRefresh(context, widget.target, allowed);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}

/// chartSourceSection is the same panel on a chart.
///
/// The same panel, deliberately. Choosing a preset, pasting an address,
/// keeping a key and mapping the columns are the same job whichever element
/// is asking, and the two answers people gave when this was a table's alone
/// -- write it twice, or make the chart borrow a table -- are how two things
/// that ought to agree stop agreeing.
///
/// What differs is what happens to what comes back, which is [_Target].
Widget chartSourceSection(
        BuildContext context,
        CanvasController controller,
        ChartElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    _DataSourcePanel(
      controller: controller,
      target: _ChartTarget(e, controller, write, begin, commit),
      key: ValueKey("source-${e.id}"),
    );

/// _Target is the element the panel is filling in.
///
/// Everything above it -- the presets, the address, the key, the mapping --
/// is the same for a table and for a chart. What is not the same is what
/// arriving rows are turned into: a table takes them as they are, keeps the
/// columns the reader filled in and re-sorts itself; a chart picks two of the
/// columns out of them and thins four thousand points down to something a
/// canvas can draw.
abstract class _Target {
  final CanvasController controller;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;

  _Target(this.controller, this.write, this.begin, this.commit);

  CanvasElement get element;
  DataSource get source;

  /// chart is which presets are offered and which extra controls are shown.
  bool get chart;

  /// remember prefixes the keys the open/shut sections are stored under, so a
  /// chart's Columns section is not opened by having opened a table's.
  String get remember;

  /// noun is what the tooltips call the thing being filled in.
  String get noun;

  /// label is the section's heading.
  ///
  /// A chart already has a Data section -- the numbers themselves, typed or
  /// pasted -- and two sections called Data on one panel is a panel nobody
  /// can navigate. This one is where they come from.
  String get label;

  /// setSource writes the recipe back, with nothing fetched.
  void setSource(DataSource next) {
    begin();
    write(withSource(next));
    commit();
  }

  CanvasElement withSource(DataSource next);

  /// choosePreset applies a whole recipe, including whatever else about the
  /// element it implies.
  /// [fromRows] is written along with the recipe where it is given, so that
  /// turning it off and choosing a basket is one change rather than two --
  /// see the Coins dropdown. Two writes read the *old* element for the
  /// second of them, and the flag came straight back on.
  void choosePreset(DataPreset preset, String choice, {bool? fromRows});

  /// receive puts what came back into the element, and says what happened.
  ///
  /// Async because a table collects its pictures on the way in, which is one
  /// request per badge.
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed,
      required bool proxied,
      List<List<String>> raw = const []});

  /// rowKeys is what the element already has a row for, in its own order:
  /// the cells of the match column.
  ///
  /// What DataSource.fromRows reads. A table's are its cells, a chart's are
  /// the labels along its axis -- which for a coin comparison is the coins,
  /// and is exactly the list to ask the API for.
  List<String> get rowKeys => const [];

  /// rowsFor is the element's own rows for the keys in [keys], as they stand
  /// now -- what a refresh puts back for a row the source did not send.
  List<List<String>> rowsFor(List<String> keys) => const [];

  /// picturesMatter is whether a column can hold a picture, and whether one
  /// can be kept across a refresh.
  ///
  /// Both are a table's: a cell can show a club badge, and a badge chosen by
  /// hand has to survive the next refresh. A chart draws numbers, so on one
  /// they are two switches that do nothing -- which is indistinguishable from
  /// two broken ones.
  bool get picturesMatter => true;

  /// moveColumn shifts a column along the row, carrying whatever refers to
  /// the columns by number with it.
  void moveColumn(int from, int to);

  /// removeColumn takes one out, likewise.
  void removeColumn(int at);

  /// extras are the controls this element adds -- which columns a chart
  /// draws, and how many points it keeps.
  ///
  /// [lastRows] is what the last refresh in this sitting returned, empty
  /// before there has been one. Handed in rather than kept in the document:
  /// four thousand rows saved into every canvas, so that one dropdown can
  /// change its mind without asking again, is not a trade worth making.
  List<Widget> extras(List<List<String>> lastRows,
          [List<List<String>> lastRaw = const [],
          List<String> fields = const []]) =>
      const [];
}

/// _TableTarget is a table filling itself in, which is where all of this
/// started.
class _TableTarget extends _Target {
  @override
  final TableElement element;

  _TableTarget(
      this.element, super.controller, super.write, super.begin, super.commit);

  @override
  DataSource get source => element.source;

  @override
  bool get chart => false;

  @override
  String get remember => "tableSource";

  @override
  String get noun => "table";

  @override
  String get label => "Data";

  @override
  CanvasElement withSource(DataSource next) => element.copyWith(source: next);

  @override
  List<String> get rowKeys {
    var at = source.matchColumn < 0 ? 0 : source.matchColumn;
    return [
      for (var (i, row) in element.rows.indexed)
        if (!(element.headerRow && i == 0) && at < row.length)
          if (row[at].trim().isNotEmpty) row[at],
    ];
  }

  @override
  List<List<String>> rowsFor(List<String> keys) {
    var at = source.matchColumn < 0 ? 0 : source.matchColumn;
    var want = keys.toSet();
    return [
      for (var (i, row) in element.rows.indexed)
        if (!(element.headerRow && i == 0) && at < row.length)
          if (want.contains(_keyOf(source, row[at]))) row,
    ];
  }

  @override
  void choosePreset(DataPreset preset, String choice, {bool? fromRows}) {
    // A preset brings its hidden headings with it. Its badge and position
    // columns are named so the mapping can refer to them and are not drawn,
    // and making the reader switch those off by hand after choosing a preset
    // would be a preset that half worked.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice).copyWith(fromRows: fromRows),
      hiddenHeaders: preset.hiddenHeaders,
    ));
    commit();
  }

  @override
  void moveColumn(int from, int to) {
    // The cells move with the mapping. Reordering the recipe and leaving the
    // table showing the old order until somebody refreshes is a button that
    // appears to do nothing.
    begin();
    write(element.copyWith(
      source: source.withColumnMoved(from, to),
      rows: [
        for (var row in element.rows) _cellsMoved(row, from, to),
      ],
      hiddenHeaders: [
        for (var h in element.hiddenHeaders) movedIndex(h, from, to),
      ],
    ));
    commit();
  }

  @override
  void removeColumn(int at) {
    begin();
    write(element.copyWith(
      source: source.withoutColumn(at),
      rows: [
        for (var row in element.rows)
          [
            for (var i = 0; i < row.length; i++)
              if (i != at) row[i],
          ],
      ],
      hiddenHeaders: [
        for (var h in element.hiddenHeaders)
          if (indexAfterRemoval(h, at) case var moved?) moved,
      ],
    ));
    commit();
  }

  /// _cellsMoved is one row with a cell shifted along it.
  ///
  /// A short row is left alone rather than padded: a ragged table is a table
  /// somebody is part way through typing, and filling it out to be moved is
  /// changing something they did not ask to change.
  static List<String> _cellsMoved(List<String> row, int from, int to) {
    if (from >= row.length || to >= row.length) return row;
    var next = [...row];
    next.insert(to, next.removeAt(from));
    return next;
  }

  @override
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed,
      required bool proxied,
      List<List<String>> raw = const []}) async {
    rows = await collectPictures(rows, next, allowFetching: allowed);

    // The columns the reader fills in themselves, put back from what was
    // there before -- matched by name, so a badge follows its team up and
    // down the table rather than staying at the position it was put in.
    rows = keepColumns(element.rows, rows, next, headerRow: element.headerRow);
    // And the column names the reader gave them. Rules pick their cells out
    // by column name, so a refresh that renamed the headers switched every
    // rule off -- the crest column's padding among them.
    rows = keepHeaders(element.rows, rows, headerRow: element.headerRow);

    // Sorted on the way in, so a refresh puts the rows back in the order the
    // table was already in rather than the order the source happened to send
    // them. A league table that re-sorted itself only when somebody
    // remembered to press Sort would be wrong twice a week.
    begin();
    var table = element.copyWith(rows: rows, source: next).sorted();
    write(table);

    // The charts reading this table come with it. Without this the two would
    // drift the moment anybody refreshed -- a table showing this week and a
    // chart of last week, side by side on one canvas, with nothing to say
    // which was which.
    var followers = 0;
    for (var other in controller.document.elements) {
      if (other is ChartElement && other.fromTable.tableId == table.id) {
        controller.replaceElement(
            other.copyWith(
                data: chartDataFromTable(table, other.fromTable,
                    keeping: other.data.series)),
            transient: true);
        followers++;
      }
    }
    commit();
    return followers == 0
        ? "${rows.length - 1} rows."
        : "${rows.length - 1} rows, and $followers chart"
            "${followers == 1 ? "" : "s"}.";
  }
}

/// _ChartTarget is a chart fetching its own numbers.
class _ChartTarget extends _Target {
  @override
  final ChartElement element;

  _ChartTarget(
      this.element, super.controller, super.write, super.begin, super.commit);

  @override
  DataSource get source => element.source;

  @override
  bool get chart => true;

  @override
  List<String> get rowKeys => [
        for (var name in element.data.categories)
          if (name.trim().isNotEmpty) name,
      ];

  @override
  List<List<String>> rowsFor(List<String> keys) {
    // A chart has no cells, only a label and its values -- so the row put
    // back is the label with nothing against it, which draws as a gap and is
    // the truth: nothing came back for it.
    var want = keys.toSet();
    var at = source.matchColumn < 0 ? 0 : source.matchColumn;
    var width = source.columns.isEmpty ? at + 1 : source.columns.length;
    return [
      for (var name in element.data.categories)
        if (want.contains(_keyOf(source, name)))
          [for (var c = 0; c < width; c++) c == at ? name : ""],
    ];
  }

  @override
  String get remember => "chartSource";

  @override
  String get noun => "chart";

  @override
  String get label => "Data source";

  @override
  CanvasElement withSource(DataSource next) => element.copyWith(source: next);

  @override
  bool get picturesMatter => false;

  @override
  void moveColumn(int from, int to) {
    begin();
    write(element.copyWith(
      source: source.withColumnMoved(from, to),
      fromSource: element.fromSource.afterMove(from, to),
    ));
    commit();
  }

  @override
  void removeColumn(int at) {
    begin();
    write(element.copyWith(
      source: source.withoutColumn(at),
      fromSource: element.fromSource.afterRemoval(at),
    ));
    commit();
  }

  @override
  void choosePreset(DataPreset preset, String choice, {bool? fromRows}) {
    // A chart preset brings its mapping with it: which column is the axis,
    // which are the series, and how many points are worth drawing. Without
    // that, choosing "Coin supply" leaves a chart that has fetched four
    // thousand rows and drawn none of them.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice).copyWith(fromRows: fromRows),
      fromSource: ChartSourceMap(
        categoryColumn: preset.chartCategory,
        valueColumns: preset.chartValues,
        maxPoints: preset.chartPoints,
      ),
      // And the drawing, where the recipe wants a particular one. Four
      // columns of open, high, low and close drawn as four lines is not what
      // anybody choosing an OHLC source was asking for.
      type: preset.chartType,
    ));
    commit();
  }

  @override
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed,
      required bool proxied,
      List<List<String>> raw = const []}) async {
    // Keeping what has been decided about how each series looks: a refresh
    // brings new values, it is not somebody asking for their colours back.
    var data = chartDataFromRows(rows, element.fromSource,
        when: datesIn(raw, element.fromSource.categoryColumn),
        keeping: element.data.series);
    begin();
    // The numbers land in the chart's own data, which is what every other
    // setting works on: once fetched they are edited, coloured and animated
    // exactly like numbers that were typed in.
    write(element.copyWith(data: data, source: next));
    commit();
    return data.isEmpty
        ? "Nothing to draw — check which columns the chart is using."
        : "${data.categories.length} points"
            "${data.series.length > 1 ? " in ${data.series.length} series" : ""}.";
  }

  @override
  List<Widget> extras(List<List<String>> lastRows,
      [List<List<String>> lastRaw = const [], List<String> fields = const []]) {
    var columns = element.source.columns;
    var link = element.fromTable;
    var tables = [
      for (var other in controller.document.elements)
        if (other is TableElement) other,
    ];
    TableElement? linked;
    for (var table in tables) {
      if (table.id == link.tableId) linked = table;
    }
    var linkedColumns = linked?.columnCount ?? 0;

    void setLink(TableLink next) {
      begin();
      write(element.copyWith(fromTable: next));
      commit();
    }

    var map = element.fromSource;
    (int, String) named(int c) =>
        (c, columns[c].header.isEmpty ? "Column ${c + 1}" : columns[c].header);

    // Whether the axis is a date, which is what makes an interval mean
    // anything. Taken from the column's own format rather than from the data,
    // so the control appears as soon as the mapping says the column is a
    // date and not only after a refresh.
    var axisIsDate = map.categoryColumn >= 0 &&
        map.categoryColumn < columns.length &&
        columns[map.categoryColumn].date.isNotEmpty;

    return [
      // Taking the numbers from a table on this canvas, which is the other
      // way a chart gets data and belongs in the section that answers where
      // the data comes from. Only offered when there is a table to take them
      // from: a control that reads something which does not exist reads as
      // broken.
      //
      // It is the right answer whenever both are on the page. One request,
      // one set of figures, and a table and a chart of the same league cannot
      // quietly disagree.
      if (tables.isNotEmpty) ...[
        CanvasControlGroup(label: "Table", children: [
          CanvasDropdown<String>(
            label: "Read from",
            value: link.tableId,
            width: 168,
            options: [
              ("", "Not linked"),
              for (var table in tables)
                (table.id, table.name.isEmpty ? "Table" : table.name),
            ],
            onChanged: (id) => setLink(link.copyWith(tableId: id)),
          ),
        ]),
        if (linked case var table?) ...[
          CanvasControlGroup(label: "Labels", children: [
            CanvasDropdown<int>(
              label: "From column",
              value: link.categoryColumn,
              width: 148,
              options: [
                for (var c = 0; c < linkedColumns; c++)
                  (c, table.columnName(c)),
              ],
              onChanged: (c) => setLink(link.copyWith(categoryColumn: c)),
            ),
          ]),
          CanvasControlGroup(label: "Values", children: [
            for (var c = 0; c < linkedColumns; c++)
              CanvasToggle(
                label: table.columnName(c),
                value: link.valueColumns.contains(c),
                onChanged: (v) => setLink(link.copyWith(valueColumns: [
                  for (var i = 0; i < linkedColumns; i++)
                    if (i == c ? v : link.valueColumns.contains(i)) i,
                ])),
              ),
            CanvasHint("Each column you choose becomes a series. The table's "
                "header names it, so a chart of the Points column is "
                "labelled Points without typing it."),
          ]),
          CanvasControlGroup(label: "Apply", children: [
            CanvasIconButton(
              icon: Icons.download_outlined,
              tooltip: link.on
                  ? "Take the numbers from the table now"
                  : "Choose at least one column of values",
              onPressed: link.on
                  ? () {
                      begin();
                      write(element.copyWith(
                          data: chartDataFromTable(table, link,
                              keeping: element.data.series)));
                      commit();
                    }
                  : null,
            ),
            CanvasHint("Refreshing the table brings the chart with it, so the "
                "two cannot drift apart."),
          ]),
        ],
      ],
      // A row per series, each saying where it comes from. This was a switch
      // per mapped column, which asked the question the wrong way round:
      // switches say "any number of these", the series were numbered
      // somewhere else, and nothing could be drawn that the mapping had not
      // already been given a column for. Now the chart's series are the list,
      // and every field the source turned out to hold is on offer against
      // each one -- picking a field that has no column yet adds it.
      CanvasControlGroup(label: "Series data", children: [
        CanvasDropdown<int>(
          key: const ValueKey("chartAxisColumn"),
          label: _axisLabel(element.type),
          value: map.categoryColumn,
          width: 168,
          options: [for (var c = 0; c < columns.length; c++) named(c)],
          onChanged: (v) =>
              _setMap(map.copyWith(categoryColumn: v), lastRows, lastRaw),
        ),
        for (var (i, c) in map.valueColumns.indexed) ...[
          const CanvasLineBreak(),
          // Narrow enough that the two of them and the button stay on one
          // line down a 240-pixel sidebar. Wrapped, a series was three lines
          // and four series were a wall: the row *is* the series, and it
          // reads as one when it is one line.
          seriesPicker(
            index: i,
            column: c,
            columns: columns,
            fields: fields,
            width: 94,
            onChanged: (next) =>
                _bindSeries(i, next, lastRows, lastRaw, fields),
          ),
          // How this series' figures are written, on the row that says where
          // they come from. Against the series rather than over the grid: a
          // dropdown per series along the top of the numbers was a third row
          // of controls above a table that already had two.
          CanvasDropdown<NumberStyle?>(
            key: ValueKey("chartSeriesNumbers$i"),
            label: "Shown as",
            value: i < element.data.series.length
                ? element.data.series[i].numbers?.style
                : null,
            width: 94,
            // The name alone, without the example beside it: at this width
            // "Millions — 1.0M" is "Millions…", which is the name with a
            // promise of something after it that can never be read.
            options: [
              (null, "As the chart"),
              for (var style in NumberStyle.values) (style, style.label),
            ],
            onChanged: (style) => _writeSeriesStyle(i, style),
          ),
          CanvasIconButton(
            key: ValueKey("chartSeriesRemove$i"),
            icon: Icons.close,
            tooltip: "Take this series off the chart",
            onPressed: map.valueColumns.length <= 1
                ? null
                : () => _setMap(
                    map.copyWith(valueColumns: [
                      for (var (j, v) in map.valueColumns.indexed)
                        if (j != i) v,
                    ]),
                    lastRows,
                    lastRaw),
          ),
        ],
        const CanvasLineBreak(),
        CanvasIconButton(
          key: const ValueKey("chartSeriesAdd"),
          icon: Icons.add,
          tooltip: "Draw another of the source's columns as a second series",
          onPressed: () => _bindSeries(map.valueColumns.length,
              _nextFree(map, columns), lastRows, lastRaw, fields),
        ),
        CanvasHint("One row per series. Each says which of the source's "
            "columns it is drawn from, and the column's name is the series' "
            "name — so a chart of Market cap is labelled Market cap without "
            "typing it. Anything the last refresh turned out to hold is "
            "offered even where the mapping has no column for it yet; "
            "choosing one adds the column."),
        const CanvasLineBreak(),
        // Readings on the dates asked for, rather than one point in every so
        // many. Only where the axis is a date: on a column of team names it
        // is a control that could not do anything.
        if (axisIsDate) ...[
          CanvasDropdown<IntervalUnit>(
            label: "A reading",
            value: map.interval.unit,
            width: 132,
            options: [for (var u in IntervalUnit.values) (u, u.label)],
            onChanged: (u) => _setMap(
                map.copyWith(interval: map.interval.copyWith(unit: u)),
                lastRows,
                lastRaw),
          ),
          if (map.interval.on) ...[
            CanvasNumberField(
              label: "Every",
              // The unit, so the pair reads as a sentence: "A reading —
              // Yearly. Every — 2 years." On its own the number said nothing
              // about what it was counting, and read as a number of readings,
              // which is not what it is.
              suffix: _unitWords(map.interval.unit, map.interval.every),
              value: map.interval.every.toDouble(),
              min: 1,
              max: 99,
              decimals: 0,
              width: 52,
              onChanged: (v) => _setMap(
                  map.copyWith(
                      interval: map.interval.copyWith(every: v.round())),
                  lastRows,
                  lastRaw),
              onCommit: commit,
            ),
            // The anchor, which is the whole point: a reading a year starting
            // wherever the data happens to begin lands on no date in
            // particular, and one on the seventh of February can be compared
            // with last year's.
            if (map.interval.unit.hasMonth)
              CanvasDropdown<int>(
                label: "In",
                value: map.interval.month,
                width: 112,
                options: const [
                  (1, "January"),
                  (2, "February"),
                  (3, "March"),
                  (4, "April"),
                  (5, "May"),
                  (6, "June"),
                  (7, "July"),
                  (8, "August"),
                  (9, "September"),
                  (10, "October"),
                  (11, "November"),
                  (12, "December"),
                ],
                onChanged: (v) => _setMap(
                    map.copyWith(interval: map.interval.copyWith(month: v)),
                    lastRows,
                    lastRaw),
              ),
            if (map.interval.unit.hasDay)
              CanvasNumberField(
                label: "On the",
                value: map.interval.day.toDouble(),
                min: 1,
                max: 31,
                decimals: 0,
                width: 52,
                onChanged: (v) => _setMap(
                    map.copyWith(
                        interval: map.interval.copyWith(day: v.round())),
                    lastRows,
                    lastRaw),
                onCommit: commit,
              ),
            if (map.interval.unit.hasWeekday)
              CanvasDropdown<int>(
                label: "On",
                value: map.interval.weekday,
                width: 112,
                options: const [
                  (DateTime.monday, "Monday"),
                  (DateTime.tuesday, "Tuesday"),
                  (DateTime.wednesday, "Wednesday"),
                  (DateTime.thursday, "Thursday"),
                  (DateTime.friday, "Friday"),
                  (DateTime.saturday, "Saturday"),
                  (DateTime.sunday, "Sunday"),
                ],
                onChanged: (v) => _setMap(
                    map.copyWith(interval: map.interval.copyWith(weekday: v)),
                    lastRows,
                    lastRaw),
              ),
            // What a reading is made of. Which of these is right is a fact
            // about the series rather than about the chart, and there is no
            // telling from the numbers: transactions a day added up over a
            // year is the year's transactions, and the seconds between blocks
            // added up over a year is a number that means nothing.
            CanvasDropdown<IntervalPick>(
              label: "Each one is",
              value: map.interval.how,
              width: 168,
              options: [for (var p in IntervalPick.values) (p, p.label)],
              onChanged: (p) => _setMap(
                  map.copyWith(interval: map.interval.copyWith(how: p)),
                  lastRows,
                  lastRaw),
            ),
            CanvasHint("${_intervalWords(map.interval)}. "
                "${map.interval.how.combines ? "Every row in the period goes "
                    "into it — added up suits a count, like transactions in a "
                    "day; averaged suits a rate or a level, like the time "
                    "between blocks or a price, where adding them up would "
                    "mean nothing." : "The row nearest each date is the "
                    "reading — a real one, not an average."} "
                "Nothing is drawn where the data has a gap."),
          ] else
            const CanvasHint(
                "Every point draws them all, thinned to Most points below if "
                "there are more of them than a canvas can show."),
        ],
        if (!map.interval.on)
          CanvasNumberField(
            label: "Most points",
            value: map.maxPoints.toDouble(),
            min: 0,
            max: 2000,
            decimals: 0,
            width: 66,
            onChanged: (v) =>
                _setMap(map.copyWith(maxPoints: v.round()), lastRows, lastRaw),
            onCommit: commit,
          ),
        if (!map.interval.on)
          const CanvasHint(
              "A daily series going back years is thousands of points, and a "
              "canvas is a few inches wide: drawn in full it is a grey smear. "
              "Most points keeps that many, evenly spread, ending on the "
              "latest — they are real readings, not an average. Zero draws "
              "every one."),
      ]),
    ];
  }

  /// _bindSeries points series [index] at [column], adding the series where
  /// there is not one there yet.
  ///
  /// [column] may be past the end of the mapping, which is what choosing a
  /// field the source has but the mapping has no column for means: the column
  /// is added first -- see seriesPicker, which offers those fields and hands
  /// back where the new column will be.
  void _bindSeries(int index, int column, List<List<String>> rows,
      [List<List<String>> raw = const [], List<String> fields = const []]) {
    var next = boundSeries(element, index, column, fields);
    begin();
    write(rows.isEmpty
        ? next
        : next.copyWith(
            data: chartDataFromRows(rows, next.fromSource,
                when: datesIn(raw, next.fromSource.categoryColumn),
                keeping: element.data.series)));
    commit();
  }

  /// _writeSeriesStyle writes one series' own way of showing a figure, or
  /// takes it back to the chart's.
  ///
  /// The chart's own decimals and grouping come with the style, so choosing
  /// one is choosing a style rather than inheriting nothing. Null forgets it
  /// altogether -- see ChartSeries.copyWith's writtenLikeChart, since the
  /// ordinary copyWith fills a null with what was there before.
  void _writeSeriesStyle(int index, NumberStyle? style) {
    if (index >= element.data.series.length) return;
    var out = [...element.data.series];
    out[index] = out[index].copyWith(
        numbers: style == null ? null : element.numbers.copyWith(style: style),
        writtenLikeChart: style == null);
    begin();
    write(element.copyWith(
        data: ChartData(categories: element.data.categories, series: out)));
    commit();
  }

  /// _nextFree is a column not already drawn, for a series being added. The
  /// first one is better than none: a new series pointed at a column that is
  /// already drawn is a second copy of a line somebody has to go and change.
  int _nextFree(ChartSourceMap map, List<SourceColumn> columns) {
    for (var c = 0; c < columns.length; c++) {
      if (c != map.categoryColumn && !map.valueColumns.contains(c)) return c;
    }
    return columns.isEmpty ? 0 : columns.length - 1;
  }

  /// _setMap changes what is drawn, and redraws it where it can.
  ///
  /// With the rows from this sitting's refresh in hand, changing which column
  /// is the axis is immediate. Without them -- a canvas opened this morning,
  /// nothing fetched yet -- the mapping is set and the chart keeps what it
  /// has until Refresh is pressed, which is honest: the column being asked
  /// for was never in the document to begin with.
  void _setMap(ChartSourceMap next, List<List<String>> rows,
      [List<List<String>> raw = const []]) {
    begin();
    write(rows.isEmpty
        ? element.copyWith(fromSource: next)
        : element.copyWith(
            fromSource: next,
            data: chartDataFromRows(rows, next,
                when: datesIn(raw, next.categoryColumn),
                keeping: element.data.series)));
    commit();
  }
}

String _summary(DataSource source) {
  if (!source.on) return "Typed in";
  var preset = presetById(source.preset);
  var name = preset?.label ?? source.kind.label;
  if (source.fetchedAt == null) return name;
  return "$name · ${DateFormat("d MMM, HH:mm").format(source.fetchedAt!.toLocal())}";
}

/// _runRefresh is the whole point of the panel: go and get it, map it, and
/// hand it to whatever asked for it.
///
/// A function rather than a method, because two things run it -- the button
/// in the Data section's heading and the one in the Table section's, which is
/// where somebody looking at the cells is when they want them again. Two
/// copies of this would be two things to keep in step, and the second copy is
/// exactly where the coin list or the derived form guide would get forgotten.
///
/// Returns null where nothing came back, having already said why.
Future<FetchedRows?> _runRefresh(
    BuildContext context, _Target target, bool allowed) async {
  var snackbar = SnackBarModel.of(context);
  var source = target.source;

  // What to ask for, where the element's own rows are what decides. Worked
  // out here rather than written into the address when the option was
  // chosen: the rows change, and an address saved from the rows as they were
  // that morning is an address that answers yesterday's question.
  var asking = source;
  var wanted = <String>[];
  var preset = presetById(source.preset);
  if (source.fromRows && preset != null && preset.choiceFromRows) {
    // What the source files each row under, which is not always what the row
    // says: XRP is filed as ripple. See CanvasRowNames.idFor.
    wanted = [
      for (var cell in target.rowKeys)
        if (CanvasRowNames.idFor(preset, cell).isNotEmpty)
          CanvasRowNames.idFor(preset, cell),
    ];
    if (wanted.isEmpty) {
      snackbar.error("There are no rows to ask about. Put a "
          "${preset.choiceLabel.toLowerCase()} in the first column first, "
          "one per row.");
      return null;
    }
    asking = source.copyWith(where: preset.address(wanted.join(",")));
  }

  var proxied = source.kind == DataKind.url ? await networkIsProxied() : false;
  var result = await loadData(asking, allowFetching: allowed, proxied: proxied);
  if (!context.mounted) return null;
  if (!result.worked) {
    snackbar.error(result.problem!);
    return null;
  }

  var rows = result.rows!;

  // A second look, for a source that cannot say everything in one answer.
  // The football preset works its form guide out from the fixtures, because
  // the plan that sends it as a field is a paid one and the results are free.
  if (preset?.derive != null) {
    rows = await preset!.derive!(rows, asking,
        (url) => fetchJsonAt(url, allowFetching: allowed, proxied: proxied));
    if (!context.mounted) return null;
  }

  // A row asked for and not sent back is kept rather than dropped. It is
  // almost always a name spelled some other way -- BNB is filed as
  // binancecoin -- and the row is where somebody would go to correct it. Cut
  // out of the table by the refresh, the typing goes with it and there is
  // nothing left to fix: the way to add a coin becomes the way to lose one.
  // Matched through the same mapping the request was built with, or a row
  // that came back as "XRP" would look like the ripple that was asked for
  // never arriving.
  var missing = rowsMissingFrom(wanted, rows, asking.matchColumn,
      idOf:
          preset == null ? null : (cell) => CanvasRowNames.idFor(preset, cell));
  if (missing.isNotEmpty) {
    rows = [...rows, ...target.rowsFor(missing)];
  }

  var said = await target.receive(
      rows, asking.copyWith(fetchedAt: DateTime.now()),
      allowed: allowed, proxied: proxied, raw: result.raw);
  if (!context.mounted) return null;
  snackbar.success(
      missing.isEmpty ? said : "$said Not found: ${missing.join(", ")}.");
  var got = FetchedRows(result.fields, rows, result.raw);
  target.controller.lastFetched[target.element.id] = got;
  return got;
}

class _DataSourcePanel extends StatefulWidget {
  final CanvasController controller;
  final _Target target;

  const _DataSourcePanel({
    required this.controller,
    required this.target,
    super.key,
  });

  @override
  State<_DataSourcePanel> createState() => _DataSourcePanelState();
}

class _DataSourcePanelState extends State<_DataSourcePanel> {
  /// _busy is a refresh in progress. A second press would make a second
  /// request and race the first one into the document.
  bool _busy = false;

  /// _fields is what the last refresh turned out to contain: every path that
  /// led to a value in the first record.
  ///
  /// Kept here rather than in the document, because it is a fact about what
  /// came back this morning and not about the design. It is empty until a
  /// refresh has happened, which is honest -- there is nothing to know about
  /// a source nobody has read yet.
  List<String> get _fields =>
      target.controller.lastFetched[target.element.id]?.fields ?? const [];

  /// _hasKey is whether a key has been saved for this address's host. The key
  /// itself is never read back into the interface -- there is nothing anybody
  /// needs to do with it except replace it.
  bool _hasKey = false;
  String _forHost = "";

  _Target get target => widget.target;
  DataSource get source => target.source;

  /// _rawRows is the same rows with the dates still in them, for a chart
  /// choosing its points by date. Empty unless a column is a date.
  List<List<String>> get _rawRows =>
      target.controller.lastFetched[target.element.id]?.raw ?? const [];

  /// _rows is what the last refresh in this sitting returned.
  ///
  /// Read from the controller rather than kept here, so a refresh run from the
  /// Table section's button -- which is not inside this panel -- leaves the
  /// mapping controls able to redraw from the rows it brought back.
  List<List<String>> get _rows =>
      target.controller.lastFetched[target.element.id]?.rows ?? const [];

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  @override
  void didUpdateWidget(_DataSourcePanel old) {
    super.didUpdateWidget(old);
    if (source.host != _forHost) _checkKey();
  }

  Future<void> _checkKey() async {
    var host = source.host;
    var has = await CanvasApiKeys.has(host);
    if (mounted) {
      setState(() {
        _hasKey = has;
        _forHost = host;
      });
    }
  }

  void _set(DataSource next) => target.setSource(next);

  /// _refresh reads the source and remembers what it turned out to hold, so
  /// the mapping controls can change their mind without asking again.
  Future<void> _refresh() async {
    var allowed = context.read<CanvasPreferences>().allowFetching;
    setState(() => _busy = true);
    try {
      await _runRefresh(context, target, allowed);
      if (!mounted) return;
      // _runRefresh has already put what came back on the controller, which
      // is where the mapping controls read it from. This only has to redraw.
      setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    var chosen = await FilePicker.platform.pickFiles(
      dialogTitle: "Choose a JSON file",
      type: FileType.custom,
      allowedExtensions: const ["json", "txt"],
    );
    var path = chosen?.files.firstOrNull?.path;
    if (path != null) _set(source.copyWith(kind: DataKind.file, where: path));
  }

  @override
  Widget build(BuildContext context) {
    var preset = presetById(source.preset);
    var allowed = context.watch<CanvasPreferences>().allowFetching;

    var where = boxed(
      context,
      CanvasExpander(
        label: target.label,
        remember: target.remember,
        trailing: _summary(source),
        // In the heading, so a table is refreshed with one press and without
        // opening anything. It is the thing this section is for.
        // The last-updated line lived at the bottom of the section, which is
        // the one place somebody checking how old a table is would not look.
        // It belongs on the button that changes it.
        action: CanvasIconButton(
          icon: _busy ? Icons.hourglass_empty : Icons.refresh,
          tooltip: !source.on
              ? "Choose where the data comes from first"
              : source.fetchedAt == null
                  ? "Read the data and put it in the ${target.noun}"
                  : "Read the data again — last updated "
                      "${DateFormat("d MMM y, HH:mm").format(source.fetchedAt!.toLocal())}",
          onPressed: source.on && !_busy ? _refresh : null,
        ),
        children: _sourceControls(context, preset, allowed),
      ),
    );

    // The mapping is its own pair of sections rather than two more layers
    // inside this one. Buried, they were three deep -- open Data, open
    // Columns, open the column -- and a reader who had opened the wrong one
    // had no way of telling from the outside.
    //
    // Hidden entirely while the numbers are typed in, because a mapping with
    // nothing to map is a section that only ever says nothing.
    if (source.kind == DataKind.typed && source.columns.isEmpty) {
      return where;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        where,
        boxed(
          context,
          CanvasExpander(
            label: "Columns",
            remember: "${target.remember}Columns",
            trailing: "${source.columns.length}",
            children: _columnControls(preset),
          ),
        ),
      ],
    );
  }

  /// _fieldsIn is what the last refresh turned out to contain and what the
  /// preset says a record carries, together.
  ///
  /// Together rather than one instead of the other. The discovery walks the
  /// first record, so a field only some records have -- or one the whole
  /// competition happens to be null on this week -- is invisible to it, and
  /// dropping the preset's list would mark a column that is mapped perfectly
  /// well as pointing at something that does not exist.
  List<String> _fieldNames(DataPreset? preset) => <String>{
        ...?preset?.fields,
        ..._fields,
      }.toList()
        ..sort();

  /// _sourceControls is where the numbers come from: the preset, the address
  /// or the file, and the key.
  List<Widget> _sourceControls(
      BuildContext context, DataPreset? preset, bool allowed) {
    return [
      CanvasControlGroup(label: "Source", children: [
        CanvasDropdown<String>(
          label: "Preset",
          value: source.preset,
          width: 168,
          options: [
            ("", "None — set it up myself"),
            for (var p in presetsFor(chart: target.chart)) (p.id, p.label),
          ],
          onChanged: (id) {
            var chosen = presetById(id);
            if (chosen == null) {
              _set(source.copyWith(preset: ""));
              return;
            }
            target.choosePreset(chosen, chosen.choices.first.$1);
          },
        ),
        if (preset != null)
          CanvasDropdown<String>(
            label: preset.choiceLabel,
            value: source.fromRows && preset.choiceFromRows
                ? _fromRows
                : _choiceOf(preset, source),
            width: 168,
            options: [
              ...preset.choices,
              // Whatever the element already has rows for, however many that
              // is. The three baskets above are somebody else's idea of an
              // interesting set; this one is the reader's own.
              if (preset.choiceFromRows)
                (
                  _fromRows,
                  "Choose ${preset.choiceLabel.toLowerCase()} "
                      "for the ${target.noun}"
                ),
            ],
            // Through the preset rather than the source, because the choice
            // decides the mapping as well as the address: dcrdata keeps every
            // series in an array named after itself.
            onChanged: (code) {
              if (code == _fromRows) {
                // The address is left as it is until a refresh, which is when
                // the rows are read. Written now it would go stale the moment
                // a row was added.
                _set(source.copyWith(fromRows: true));
                return;
              }
              // One write, not two: choosePreset reads the element as it
              // stands, so setting the flag first and then choosing left it
              // reading the element from before and turning the flag back on.
              target.choosePreset(preset, code, fromRows: false);
            },
          ),
        // Said where the choice is made, because renaming a row only changes
        // what is fetched when this is on -- and somebody who renames one and
        // refreshes, and gets the old name back, has no way of telling why.
        if (preset != null && !source.fromRows && preset.choiceFromRows)
          CanvasHint(
              "The ${preset.choiceLabel.toLowerCase()} above are fixed lists: "
              "a refresh asks for those, whatever the ${target.noun} says. To "
              "choose your own, pick “Whatever is in the ${target.noun}” — "
              "then the rows decide, and renaming one changes what is asked "
              "for."),
        // Ask the source what it has. The built-in list is short and was
        // written by hand, so it is both incomplete and occasionally wrong --
        // CoinGecko files Firo under "zcoin". One request replaces it with
        // the source's own answer, kept for next time.
        if (preset != null && preset.namesAddress.isNotEmpty && source.fromRows)
          _LookUpNames(preset: preset, noun: preset.choiceLabel.toLowerCase()),
        if (preset != null && source.fromRows && preset.choiceFromRows)
          CanvasHint(
              "The ${target.noun} says what to ask for: one ${preset.choiceLabel.toLowerCase().replaceAll(RegExp(r"s\$"), "")} per row, read from the "
              "first column. Add a row and refresh to add one, delete a row "
              "to drop it. Names are matched loosely — “Bitcoin Cash” finds "
              "bitcoin-cash — and anything that cannot be found is named "
              "rather than quietly left out."),
        CanvasDropdown<DataKind>(
          label: "From",
          value: source.kind,
          width: 128,
          options: [for (var k in DataKind.values) (k, k.label)],
          onChanged: (k) => _set(source.copyWith(kind: k)),
        ),
      ]),
      if (preset != null) CanvasHint(preset.note),

      // What this element does with what arrives. Empty for a table, which
      // takes the rows as they are.
      ...target.extras(_rows, _rawRows, _fieldNames(preset)),

      if (source.kind == DataKind.file)
        CanvasControlGroup(label: "File", children: [
          CanvasTextField(
            label: "Path",
            value: source.where,
            width: 240,
            onChanged: (v) => _set(source.copyWith(where: v)),
          ),
          CanvasIconButton(
            icon: Icons.folder_open_outlined,
            tooltip: "Choose a file",
            onPressed: _pickFile,
          ),
          CanvasHint("Whatever collects the data — a browser, curl, something "
              "on a schedule — writes JSON here, and Refresh reads it. No "
              "connection is made by this app."),
        ]),

      if (source.kind == DataKind.url) ...[
        CanvasControlGroup(label: "Address", children: [
          CanvasTextField(
            label: "URL",
            value: source.where,
            width: 240,
            onChanged: (v) => _set(source.copyWith(where: v)),
          ),
        ]),
        // The group's own caption says whether there is a key, so the field
        // does not caption itself as well. A box labelled "Key" over a
        // working table reads as something still to be done.
        CanvasControlGroup(label: _hasKey ? "Key active" : "Key", children: [
          _KeyField(host: source.host, saved: _hasKey, onSaved: _checkKey),
          CanvasHint(_hasKey
              ? "A key is saved for ${source.host}. It is kept on this "
                  "machine and never written into the canvas, so a canvas you "
                  "send carries the ${target.noun} and not your key."
              : "Kept on this machine, never written into the canvas."),
        ]),
        if (!allowed)
          CanvasHint("Fetching is switched off. Turn on \"Let a canvas fetch "
              "data\" in Settings > Plugins > Canvas — it is off because "
              "nothing else in this app connects out on its own, and a fetch "
              "from here would not go through the proxy in Settings."),
      ],
    ];
  }

  /// _columnControls is the mapping: which field lands in which column, and
  /// in what order.
  List<Widget> _columnControls(DataPreset? preset) {
    var fields = _fieldNames(preset);
    return [
      CanvasControlGroup(label: "Rows", children: [
        CanvasTextField(
          label: "Path to the list",
          value: source.rowsPath,
          width: 200,
          onChanged: (v) => _set(source.copyWith(rowsPath: v)),
        ),
        CanvasHint("A dotted route into the JSON — \"standings.0.table\" "
            "means the table of the first standings. Leave it empty when "
            "the document is itself a list."),
      ]),
      for (var i = 0; i < source.columns.length; i++)
        _oneColumn(i, source.columns[i], fields, preset),
      CanvasControlGroup(label: "Add", hideCaption: true, children: [
        CanvasIconButton(
          icon: Icons.add,
          tooltip: "Add a column to the mapping",
          onPressed: () => _set(source
              .copyWith(columns: [...source.columns, const SourceColumn()])),
        ),
        // A custom field is an ordinary column with a recipe instead of a
        // field, so it is added here rather than in a section of its own --
        // which is where it was, listing the same columns a second time.
        CanvasIconButton(
          icon: Icons.functions,
          tooltip: "Add a column built from other fields",
          onPressed: () => _set(source.copyWith(columns: [
            ...source.columns,
            SourceColumn(
                header: "New field",
                template: "{${fields.isEmpty ? "" : fields.first}}"),
          ])),
        ),
      ]),
      if (target.picturesMatter)
        CanvasControlGroup(label: "Keeping your own", children: [
          CanvasDropdown<int>(
            label: "Rows are matched by",
            value: source.matchColumn,
            width: 168,
            options: [
              (-1, "Their position"),
              for (var c = 0; c < source.columns.length; c++)
                (c, _columnName(c)),
            ],
            onChanged: (v) => _set(source.copyWith(matchColumn: v)),
          ),
          const CanvasHint(
              "\"Keep mine\" leaves a column exactly as you filled it in "
              "— club badges you chose yourself, a note against each row — "
              "while everything else is replaced. Match the rows by the "
              "team's name rather than by their position, or a club that "
              "climbs two places will inherit somebody else's badge."),
        ]),
    ];
  }

  /// _columnName is what a column is called in a list of them.
  String _columnName(int i) {
    if (i < 0 || i >= source.columns.length) return "Column ${i + 1}";
    var header = source.columns[i].header.trim();
    return header.isEmpty ? "Column ${i + 1}" : header;
  }

  /// _oneColumn is a single column, as a line that opens.
  ///
  /// A line rather than a block. A league table is a dozen columns and each
  /// of them has six or seven settings, so laid out in full the section was
  /// eighty rows of controls to change one heading -- and the one being
  /// looked for had to be found by counting. Closed, each column says its
  /// name and what it is mapped to, which is what somebody scanning the list
  /// is reading; open, it is everything about that column, custom fields
  /// included.
  ///
  /// Remembered by name rather than by number, so the one left open stays
  /// open when a column is moved past it.
  Widget _oneColumn(
      int i, SourceColumn column, List<String> fields, DataPreset? preset) {
    // Two different questions. "builds" is whether the cell is a recipe
    // instead of a field, which decides whether there is a field to choose.
    // "custom" is whether it is laid out as one -- which includes a column
    // the preset fills in itself, carrying a spread and no template: the form
    // guide is exactly that, and hiding its slots because it has no braces in
    // it is how its settings went missing once already.
    var builds = column.template.isNotEmpty;
    var custom = _isCustom(column, preset);
    return CanvasExpander(
      label: _columnName(i),
      remember: "${target.remember}Col:"
          "${column.header.isEmpty ? "$i" : column.header}",
      trailing:
          custom ? column.template : (column.path.isEmpty ? "—" : column.path),
      children: [
        CanvasControlGroup(label: "Field", hideCaption: true, children: [
          CanvasTextField(
            label: "Header",
            value: column.header,
            width: 110,
            onChanged: (v) => _setColumn(i, column.copyWith(header: v)),
            onCommit: target.commit,
          ),
          // One control, not two. A free-text path beside a list of the
          // paths that exist is the same answer asked for twice, and the
          // typed one is the one that can be wrong. So once a refresh has
          // said what is actually in the data, this is a list -- with
          // whatever the column is set to already in it, even if the
          // source has since stopped sending it, because silently
          // changing a mapping to something else would be worse.
          if (fields.isNotEmpty && !builds)
            CanvasDropdown<String>(
              label: "Field",
              value: column.path,
              width: 150,
              options: [
                if (!fields.contains(column.path))
                  (
                    column.path,
                    column.path.isEmpty
                        ? "—"
                        : "${column.path} (not in the data)"
                  ),
                for (var field in fields) (field, field),
              ],
              onChanged: (v) => _setColumn(i, column.copyWith(path: v)),
            )
          else if (!builds)
            // Before the first refresh there is nothing to list, so the
            // path is typed -- which is also the way in for a source
            // nobody has written a preset for.
            CanvasTextField(
              label: "Path",
              value: column.path,
              width: 130,
              onChanged: (v) => _setColumn(i, column.copyWith(path: v)),
              onCommit: target.commit,
            ),
          // A column becomes custom by being given a recipe. A toggle
          // rather than a text box, because the first thing a custom
          // field is is a copy of the field it replaces -- "{points}".
          CanvasToggle(
            label: "Built from fields",
            value: builds,
            onChanged: (v) => _setColumn(
                i,
                column.copyWith(
                    template: v
                        ? "{${column.path.isEmpty && fields.isNotEmpty ? fields.first : column.path}}"
                        : "")),
          ),
        ]),

        // What it is built from, where it is built rather than taken. This
        // was a section of its own listing the same columns again, which is
        // one column in two places: a custom field *is* a column, and the
        // recipe belongs with the rest of its settings.
        if (custom)
          CanvasControlGroup(label: "Built from", children: [
            CanvasTextField(
              label: "",
              value: column.template,
              width: 190,
              onChanged: (v) => _setColumn(i, column.copyWith(template: v)),
              onCommit: target.commit,
            ),
            CanvasNumberField(
              label: "Slots",
              value: column.spread.toDouble(),
              min: 0,
              max: 20,
              decimals: 0,
              width: 56,
              onChanged: (v) =>
                  _setColumn(i, column.copyWith(spread: v.round())),
              onCommit: target.commit,
            ),
            CanvasTextField(
              label: "Divider",
              value: column.divider,
              width: 56,
              onChanged: (v) => _setColumn(i, column.copyWith(divider: v)),
              onCommit: target.commit,
            ),
            CanvasHint(
                "Put a field's name in braces and it is replaced by what is "
                "there — \"{team.tla} ({points})\" gives \"MCI (6)\". Slots "
                "lays a comma-separated value out across that many places, "
                "padded on the left so the newest is always in the same one."
                "${fields.isEmpty ? "" : " Fields: ${fields.join(", ")}."}"),
          ]),

        // The two conversions, next to the field they convert. Both are
        // about the value that arrives rather than about the design, and
        // both are the difference between a readable column and a wall of
        // atoms or a row of epoch seconds.
        CanvasControlGroup(label: "As it arrives", children: [
          CanvasNumberField(
            label: "Divide by",
            value: column.divide,
            min: 1,
            max: 1e12,
            decimals: 0,
            width: 84,
            onChanged: (v) =>
                _setColumn(i, column.copyWith(divide: v <= 0 ? 1 : v)),
            onCommit: target.commit,
          ),
          CanvasTextField(
            label: "As a date",
            value: column.date,
            hint: "MMM yy",
            width: 84,
            onChanged: (v) => _setColumn(i, column.copyWith(date: v)),
            onCommit: target.commit,
          ),
          if (target.picturesMatter) ...[
            CanvasToggle(
              label: "A picture",
              value: column.picture,
              onChanged: (v) => _setColumn(i, column.copyWith(picture: v)),
            ),
            CanvasToggle(
              label: "Keep mine",
              value: column.keep,
              onChanged: (v) => _setColumn(i, column.copyWith(keep: v)),
            ),
          ],
          const CanvasHint(
              "Divide by brings a number into the units the chart is drawn in "
              "— a chain counts money in hundred-millionths. As a date reads "
              "the value as a time and writes it out in that format."),
        ]),

        // The order of the columns is the order of the table, so moving one
        // is a thing people want and there was no way to do it: a column in
        // the wrong place had to be deleted and the rest re-mapped by hand.
        CanvasControlGroup(label: "This column", children: [
          CanvasIconButton(
            icon: Icons.west,
            tooltip: "Move this column earlier",
            onPressed: i > 0 ? () => target.moveColumn(i, i - 1) : null,
          ),
          CanvasIconButton(
            icon: Icons.east,
            tooltip: "Move this column later",
            onPressed: i < source.columns.length - 1
                ? () => target.moveColumn(i, i + 1)
                : null,
          ),
          CanvasIconButton(
            icon: Icons.delete_outline,
            tooltip: "Remove this column from the mapping",
            onPressed: () => target.removeColumn(i),
          ),
        ]),
      ],
    );
  }

  void _setColumn(int index, SourceColumn column) => _set(source.copyWith(
        columns: [
          for (var i = 0; i < source.columns.length; i++)
            i == index ? column : source.columns[i],
        ],
      ));
}

/// _axisLabel says which axis the categories run along, which depends on how
/// the chart is drawn: along the bottom for most of them, down the side for
/// horizontal bars, and round the middle for a pie.
///
/// "Along the axis" said none of that, on a chart that has two of them.
String _axisLabel(ChartType type) => switch (type) {
      ChartType.horizontalBar => "Along the y axis",
      ChartType.radar => "One per spoke",
      ChartType.pie ||
      ChartType.donut ||
      ChartType.radialBar =>
        "One per slice",
      _ => "Along the x axis",
    };

/// _unitWords is an interval's unit as a word, singular or plural to match
/// the number in front of it: "year", "2 years".
String _unitWords(IntervalUnit unit, int many) {
  var word = switch (unit) {
    IntervalUnit.none => "point",
    IntervalUnit.day => "day",
    IntervalUnit.week => "week",
    IntervalUnit.month => "month",
    IntervalUnit.quarter => "quarter",
    IntervalUnit.year => "year",
  };
  return many == 1 ? word : "${word}s";
}

/// _ordinal is a day of the month as somebody would say it: 1st, 2nd, 7th.
String _ordinal(int day) {
  if (day >= 11 && day <= 13) return "${day}th";
  return switch (day % 10) {
    1 => "${day}st",
    2 => "${day}nd",
    3 => "${day}rd",
    _ => "${day}th",
  };
}

/// _intervalWords says an interval the way somebody would: "One reading a
/// year, on 7 February" rather than "unit: year, month: 2, day: 7".
String _intervalWords(ChartInterval interval) {
  const months = [
    "January", "February", "March", "April", "May", "June", //
    "July", "August", "September", "October", "November", "December",
  ];
  const days = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", //
    "Saturday", "Sunday",
  ];

  var how = interval.every == 1
      ? "a ${_unitWords(interval.unit, 1)}"
      : "every ${interval.every} ${_unitWords(interval.unit, interval.every)}";
  var on = switch (interval.unit) {
    IntervalUnit.year => ", on ${interval.day} ${months[interval.month - 1]}",
    IntervalUnit.month ||
    IntervalUnit.quarter =>
      ", on the ${_ordinal(interval.day)}",
    IntervalUnit.week => ", on a ${days[interval.weekday - 1]}",
    _ => "",
  };
  return "One reading $how$on";
}

/// rowsMissingFrom is which of the things asked for did not come back.
///
/// Matched on the same loose key the request was built from, so "Bitcoin
/// Cash" asked for as bitcoin-cash is found in a row that came back saying
/// "Bitcoin Cash". Empty where nothing was asked for by name.
///
/// Two things want the answer: the message, which names them rather than
/// leaving somebody to notice, and the refresh itself, which keeps their rows
/// instead of cutting them out -- the row is where the spelling would be
/// corrected, and a refresh that deletes it makes the way to add a coin the
/// way to lose one.
List<String> rowsMissingFrom(
    List<String> wanted, List<List<String>> rows, int matchColumn,
    {String Function(String)? idOf}) {
  if (wanted.isEmpty) return const [];
  var at = matchColumn < 0 ? 0 : matchColumn;
  var key = idOf ?? asRowKey;
  var came = <String>{
    for (var row in rows)
      if (at < row.length) key(row[at]),
  };
  // The rows that come back name the coin, and the key asked for is the id --
  // which for almost every coin is the same word. Where a source names things
  // differently from the way it files them, this says so too, which is the
  // honest answer: what came back is not what was asked for.
  return [
    for (var key in wanted)
      if (!came.contains(key)) key,
  ];
}

/// _keyOf is what the source files a cell under, for matching a row that came
/// back against one that was asked for.
String _keyOf(DataSource source, String cell) {
  var preset = presetById(source.preset);
  return preset == null ? asRowKey(cell) : CanvasRowNames.idFor(preset, cell);
}

/// _fromRows is the choice that means "ask for whatever the element already
/// has rows for". Not a real choice code, so it can never collide with one.
const String _fromRows = "\u0000rows";

/// _choiceOf works out which of a preset's choices the current address is, so
/// the dropdown shows what is actually set rather than always the first one.
String _choiceOf(DataPreset preset, DataSource source) {
  for (var (code, _) in preset.choices) {
    if (source.where == preset.address(code)) return code;
  }
  return preset.choices.first.$1;
}

/// _KeyField takes an API key and saves it, and never shows one back.
///
/// Its own widget holding its own text, which is the whole reason it exists.
/// A CanvasTextField is bound to a value and resets itself to that value
/// whenever the panel rebuilds -- and this one's value is deliberately empty,
/// so the key vanished out of the box the moment anything else on the panel
/// changed. After a refresh that is everything, and it looked exactly as
/// though the key had been forgotten. It had not; the box had.
///
/// Saved on a button rather than as it is typed, so a key half pasted is not
/// a key half saved.
class _KeyField extends StatefulWidget {
  final String host;

  /// saved is whether there is already a key for this host, which is all the
  /// interface ever says about one. A key is never shown back.
  final bool saved;

  final VoidCallback onSaved;

  const _KeyField(
      {required this.host, required this.saved, required this.onSaved});

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await CanvasApiKeys.write(widget.host, _text.text);
    _text.clear();
    widget.onSaved();
  }

  /// _buttonRoom is what the save button beside the field takes.
  static const double _buttonRoom = 40;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // The width that is actually there, rather than the width the control
      // scope would like. A raw SizedBox is what overflowed the sidebar in the
      // first place, and asking the scope only moved the number that was too
      // big -- the room this row has is what its own parent gives it, and
      // nothing else knows that.
      //
      // Unbounded in the settings band above the canvas, which scrolls
      // sideways; there the field takes a fixed width like everything else.
      builder: (context, constraints) {
        var room = constraints.maxWidth.isFinite
            ? constraints.maxWidth - _buttonRoom
            : 190.0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: math.max(60, math.min(190, room)),
            height: controlHeight,
            child: TextField(
              controller: _text,
              obscureText: true,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.saved ? "Replace it" : "Paste it here",
                hintStyle: const TextStyle(fontSize: 11),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          CanvasIconButton(
            icon: Icons.save_outlined,
            tooltip: "Save this key on this machine",
            onPressed: _save,
          ),
        ]);
      },
    );
  }
}

/// _isCustom is whether a column builds its cell rather than taking one.
///
/// A template or a spread is a recipe rather than a field name. So is a path
/// the preset fills in itself: a column mapped to one of those is a custom
/// field whether or not it has been given any settings yet, and it has to be
/// listed here -- otherwise the preset quietly fills a column in and the
/// settings that lay it out are behind a section it does not appear in, which
/// is exactly what happened to a Form column added by hand before the preset
/// took an interest in it.
bool _isCustom(SourceColumn column, DataPreset? preset) =>
    column.template.isNotEmpty ||
    column.spread > 0 ||
    (preset?.derived.contains(column.path) ?? false);

/// boundSeries is [element] with series [index] drawn from [column].
///
/// One definition, because two controls ask for it -- the row per series in
/// the Data source settings and the picker on the grid's own headers -- and
/// two answers about which field "the third spare one" is would bind a series
/// to the wrong numbers.
///
/// [column] past the end of the mapping is one of [fields] that has no column
/// yet: it gets one, named after itself, and the series is bound to that. So
/// a field is offered and chosen in one gesture rather than "add a column,
/// then come back and draw it". Below zero means typed in -- the series stays
/// and simply stops being filled from the source.
ChartElement boundSeries(
    ChartElement element, int index, int column, List<String> fields) {
  var map = element.fromSource;
  var source = element.source;

  var at = column;
  if (at >= source.columns.length) {
    var spare = spareFields(source.columns, fields);
    var which = at - source.columns.length;
    if (which < 0 || which >= spare.length) return element;
    var path = spare[which];
    at = source.columns.length;
    source = source.copyWith(
        columns: [...source.columns, SourceColumn(header: path, path: path)]);
  }

  var next = <int>[
    for (var (i, c) in map.valueColumns.indexed) i == index ? at : c,
    if (index >= map.valueColumns.length) at,
  ]..removeWhere((c) => c < 0);
  return element.copyWith(
      source: source, fromSource: map.copyWith(valueColumns: next));
}

/// spareFields are the paths a refresh found that the mapping has no column
/// for, in the order they are offered.
///
/// One definition, because two things have to agree about it: the list a
/// series can be pointed at, and the arithmetic that turns "the third spare
/// one" back into a column. Two orders would bind a series to the wrong
/// field, which is the kind of mistake nobody would look for.
List<String> spareFields(List<SourceColumn> columns, List<String> fields) => [
      for (var field in fields)
        if (!columns.any((c) => c.path == field || c.template == field)) field,
    ];

/// seriesPicker is one series and where its numbers come from.
///
/// Shared by the chart's Data settings and by the header of its own grid,
/// because "which of the source's columns is this series" is one question and
/// answering it in two places with two controls is two answers to keep in
/// step. [fields] are the paths the last refresh turned out to hold: offered
/// alongside the mapped columns, and choosing one adds a column for it, so
/// the list is everything the source has rather than everything somebody has
/// already mapped.
Widget seriesPicker({
  required int index,
  required int column,
  required List<SourceColumn> columns,
  required List<String> fields,
  required void Function(int column) onChanged,
  String? label,
  double width = 168,
}) {
  var spare = spareFields(columns, fields);
  return CanvasDropdown<int>(
    key: ValueKey("chartSeriesColumn$index"),
    label: label ?? "Series ${index + 1}",
    // A field that has no column yet is numbered past the end of the mapping,
    // in the order they are listed -- so the value handed back says both
    // "this field" and "the column it will become".
    value: column,
    width: width,
    options: [
      for (var (c, source) in columns.indexed)
        (c, source.header.isEmpty ? "Column ${c + 1}" : source.header),
      for (var (i, field) in spare.indexed) (columns.length + i, field),
    ],
    onChanged: onChanged,
  );
}

/// _LookUpNames asks a source for everything it has, once.
///
/// Its own widget for the reason the Refresh button is: it owns whether a
/// request is already running, and a second press would make a second one.
class _LookUpNames extends StatefulWidget {
  final DataPreset preset;
  final String noun;

  const _LookUpNames({required this.preset, required this.noun});

  @override
  State<_LookUpNames> createState() => _LookUpNamesState();
}

class _LookUpNamesState extends State<_LookUpNames> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Whatever was fetched in some earlier sitting, so the list is there
    // without anybody pressing anything twice.
    CanvasRowNames.load(widget.preset.id).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    var known = CanvasRowNames.known(widget.preset.id)?.length ?? 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CanvasIconButton(
        key: const ValueKey("lookUpNames"),
        icon: _busy ? Icons.hourglass_empty : Icons.travel_explore_outlined,
        tooltip: known > 0
            ? "Look up the ${widget.noun} again — $known known"
            : "Look up every one of the ${widget.noun} this source has",
        onPressed: _busy ? null : _look,
      ),
      CanvasHint(known > 0
          ? "$known ${widget.noun} known, so typing one offers it and asks "
              "for it by the name the source files it under."
          : "Until this is pressed, typing a row offers a short built-in "
              "list. Pressing it asks the source for everything it has — one "
              "request, kept for next time — after which every name it knows "
              "is offered and spelled the way it files it."),
    ]);
  }

  Future<void> _look() async {
    var snackbar = SnackBarModel.of(context);
    var allowed = context.read<CanvasPreferences>().allowFetching;
    if (!allowed) {
      snackbar.error("Fetching is switched off. Turn it on in Settings > "
          "Plugins > Canvas.");
      return;
    }
    setState(() => _busy = true);
    try {
      var proxied = await networkIsProxied();
      if (proxied) {
        if (!mounted) return;
        snackbar.error("This app is set to reach the network through a "
            "proxy, which a fetch from the canvas cannot use.");
        return;
      }
      var found = await CanvasRowNames.fetch(widget.preset,
          (url) => fetchJsonAt(url, allowFetching: allowed, proxied: proxied));
      if (!mounted) return;
      if (found == null) {
        snackbar.error("The list of ${widget.noun} could not be read.");
        return;
      }
      snackbar.success("$found ${widget.noun} known.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
