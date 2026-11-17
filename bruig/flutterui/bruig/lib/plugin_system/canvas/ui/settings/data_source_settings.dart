import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/ui/data/data_connect.dart';
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
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// data_source_settings.dart is the "where do these numbers come from" panel
// for tables and charts: preset, competition, Refresh. The preset's
// address, rows path and columns stay visible for whatever it misses.

/// dataSourceSection is a table's Data section, whole, as its heading's
/// Refresh works shut and must know whether one is running.
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

/// sourceRefreshButton is the same Refresh for the Table section, or null.
Widget? sourceRefreshButton(
    BuildContext context,
    CanvasController controller,
    CanvasElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {bool whenOff = false}) {
  var target = switch (e) {
    TableElement table => _TableTarget(table, controller, write, begin, commit),
    ChartElement chart => _ChartTarget(chart, controller, write, begin, commit),
    _ => null,
  };
  if (target == null || (!target.source.on && !whenOff)) return null;
  return _RefreshButton(target: target, key: ValueKey("refresh-${e.id}"));
}

class _RefreshButton extends StatefulWidget {
  final _Target target;

  const _RefreshButton({required this.target, super.key});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  /// _busy is a refresh running: a second would race it into the document.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    var source = widget.target.source;
    return CanvasIconButton(
      // It hangs off a section's heading, not a row of controls.
      tight: true,
      icon: _busy ? Icons.hourglass_empty : Icons.refresh,
      tooltip: !source.on
          ? "Choose where the data comes from first"
          : source.fetchedAt == null
              ? "Read the data and put it in the ${widget.target.noun}"
              : "Read the data again — last updated "
                  "${DateFormat("d MMM y, HH:mm").format(source.fetchedAt!.toLocal())}",
      onPressed: _busy || !source.on
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

/// chartSourceSection is the same panel on a chart, deliberately, as two
/// copies would drift; only what becomes of the rows differs ([_Target]).
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

/// _Target is the element being filled: a table keeps the reader's columns
/// and re-sorts; a chart picks columns and thins thousands of points.
abstract class _Target {
  final CanvasController controller;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;

  _Target(this.controller, this.write, this.begin, this.commit);

  CanvasElement get element;
  DataSource get source;

  /// chart is which presets are offered and which extra controls shown.
  bool get chart;

  /// remember prefixes the open sections' keys, so table and chart differ.
  String get remember;

  /// noun is what tooltips call the thing being filled.
  String get noun;

  /// label is the heading: a chart's Data section is already its numbers.
  String get label;

  /// setSource writes the recipe back, fetching nothing.
  void setSource(DataSource next) {
    begin();
    write(withSource(next));
    commit();
  }

  /// typeSource writes while typing, one change closed by [commit].
  void typeSource(DataSource next) {
    begin();
    write(withSource(next));
  }

  CanvasElement withSource(DataSource next);

  /// choosePreset applies a recipe and what it implies, with [fromRows] in
  /// the same change, as a second write would read the old element.
  void choosePreset(DataPreset preset, String choice, {bool? fromRows});

  /// receive takes the rows in; async, as a table fetches its badges.
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed,
      required bool proxied,
      List<List<String>> raw = const []});

  /// rowKeys is what the element has rows for, in order (DataSource
  /// .fromRows): a table's match cells, a chart's axis labels.
  List<String> get rowKeys => const [];

  /// rowsFor is the current rows for [keys], kept when the source omits one.
  List<List<String>> rowsFor(List<String> keys) => const [];

  /// picturesMatter is whether a column can hold a picture kept across a
  /// refresh: a table's badge, yes; on a chart the switches do nothing.
  bool get picturesMatter => true;

  /// moveColumn shifts a column, carrying references by number.
  void moveColumn(int from, int to);

  /// removeColumn removes one, likewise.
  void removeColumn(int at);

  /// extras are the element's own controls (a chart's drawn columns and
  /// point count). [lastRows] is passed in, not saved: thousands of rows in
  /// every canvas are not worth it.
  List<Widget> extras(List<List<String>> lastRows,
          [List<List<String>> lastRaw = const [],
          List<String> fields = const []]) =>
      const [];
}

/// _TableTarget is a table filling itself in.
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
    // A preset brings its hidden badge and position columns.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice).copyWith(fromRows: fromRows),
      hiddenHeaders: preset.hiddenHeaders,
    ));
    commit();
  }

  @override
  void moveColumn(int from, int to) {
    // The cells move with the mapping now, not on the next refresh.
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

  /// _cellsMoved shifts a cell along a row; a short row is being typed.
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
    rows =
        await collectPictures(rows, next, allowFetching: allowed && !proxied);
    // The table as it is now, keeping edits made during the fetch.
    var element = freshOf(controller, this.element);
    if (element == null) return "The table has gone.";

    // The reader's own columns, put back by name so a badge follows its team.
    rows = keepColumns(element.rows, rows, next, headerRow: element.headerRow);
    // And the reader's column names, which rules pick cells by.
    rows = keepHeaders(element.rows, rows, headerRow: element.headerRow);

    // Sorted on the way in, keeping the table's order, not the source's.
    begin();
    var table = element.copyWith(rows: rows, source: next).sorted();
    write(table);

    // The sheet's charts follow in the same step (see data_sync.dart).
    var followers = element.sheet == null
        ? 0
        : viewsOf(controller.document, element.sheet!.sheet)
            .whereType<ChartElement>()
            .length;
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
    // A chart row put back is its label alone: a gap, which is the truth.
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
    // A chart preset brings its axis, series and point count.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice).copyWith(fromRows: fromRows),
      fromSource: ChartSourceMap(
        categoryColumn: preset.chartCategory,
        valueColumns: preset.chartValues,
        maxPoints: preset.chartPoints,
      ),
      // And its drawing: open, high, low and close are candlesticks.
      type: preset.chartType,
    ));
    commit();
  }

  @override
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed,
      required bool proxied,
      List<List<String>> raw = const []}) async {
    // The chart as it is now: see the table's.
    var element = freshOf(controller, this.element);
    if (element == null) return "The chart has gone.";
    // Series looks are kept: a refresh brings values, not colours.
    var data = chartDataFromRows(rows, element.fromSource,
        when: datesIn(raw, element.fromSource.categoryColumn),
        keeping: element.data.series);
    begin();
    // Into the chart's own data, so fetched numbers edit like typed ones.
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
    var sheetLink = element.sheet;
    void setSheetLink(SheetLink next) {
      begin();
      write(element.copyWith(sheet: next));
      commit();
    }

    var map = element.fromSource;
    (int, String) named(int c) =>
        (c, columns[c].header.isEmpty ? "Column ${c + 1}" : columns[c].header);

    // A date axis, from the column's format, gives an interval meaning.
    var axisIsDate = map.categoryColumn >= 0 &&
        map.categoryColumn < columns.length &&
        columns[map.categoryColumn].date.isNotEmpty;

    return [
      // The sheet columns it draws (data_sheet.dart), live.
      if (sheetLink case var link?)
        if (controller.sheetById(link.sheet) case var sheet?) ...[
          CanvasControlGroup(label: "Labels", children: [
            CanvasDropdown<int>(
              key: const ValueKey("chartSheetLabels"),
              label: "From column",
              value: link.labels.clamp(0, link.range.cols - 1),
              width: 148,
              options: [
                for (var c = 0; c < link.range.cols; c++)
                  (c, sheetColumnName(sheet, link, c)),
              ],
              onChanged: (c) => setSheetLink(link.copyWith(labels: c, series: [
                for (var x in link.series)
                  if (x != c) x
              ])),
            ),
          ]),
          CanvasControlGroup(label: "Values", children: [
            for (var c = 0; c < link.range.cols; c++)
              if (c != link.labels)
                CanvasToggle(
                  key: ValueKey("chartSheetSeries-$c"),
                  label: sheetColumnName(sheet, link, c),
                  value: link.series.contains(c),
                  onChanged: (v) => setSheetLink(link.copyWith(series: [
                    for (var i = 0; i < link.range.cols; i++)
                      if (i == c ? v : link.series.contains(i)) i,
                  ])),
                ),
            CanvasHint("Each column you choose becomes a series, named by its "
                "heading. The chart reads the sheet "
                "\"${sheet.name}\" (${link.range.a1}), so a table of it "
                "and this chart always agree."),
          ]),
        ],
      // A row per series and its source; a field with no column adds one.
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
          // Narrow, so the row fits one line in a narrow sidebar.
          seriesPicker(
            index: i,
            column: c,
            columns: columns,
            fields: fields,
            width: 94,
            onChanged: (next) =>
                _bindSeries(i, next, lastRows, lastRaw, fields),
          ),
          // This series' figure style, on its source row.
          CanvasDropdown<NumberStyle?>(
            key: ValueKey("chartSeriesNumbers$i"),
            label: "Shown as",
            value: i < element.data.series.length
                ? element.data.series[i].numbers?.style
                : null,
            width: 94,
            // The name alone: at this width the example is cut.
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
        // Readings on chosen dates, for a date axis.
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
              // The unit, so it reads "A reading — Yearly. Every — 2 years."
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
            // The anchor: a yearly reading on 7 February compares with last
            // year's; one from wherever the data begins does not.
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
            // Sum or not: daily transactions add up; block times do not.
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

  /// _bindSeries points series [index] at [column], adding it if missing;
  /// [column] past the mapping is a new field's column (see seriesPicker).
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

  /// _writeSeriesStyle writes or reverts a series' figure style; null goes
  /// through writtenLikeChart, as plain copyWith keeps a null's old value.
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

  /// _nextFree is an undrawn column for a new series, else the first.
  int _nextFree(ChartSourceMap map, List<SourceColumn> columns) {
    for (var c = 0; c < columns.length; c++) {
      if (c != map.categoryColumn && !map.valueColumns.contains(c)) return c;
    }
    return columns.isEmpty ? 0 : columns.length - 1;
  }

  /// _setMap changes what is drawn, redrawn now or on the next Refresh.
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

/// _runRefresh fetches, maps and hands the rows over, shared by both
/// sections' buttons so the coin list and form guide are never lost. Null
/// where nothing came back, having said why.
Future<FetchedRows?> _runRefresh(
    BuildContext context, _Target target, bool allowed) async {
  var snackbar = SnackBarModel.of(context);
  var source = target.source;

  // Worked out now, not saved into the address, as the rows change.
  var asking = source;
  var wanted = <String>[];
  var preset = presetById(source.preset);
  if (source.fromRows && preset != null && preset.choiceFromRows) {
    // What the source files each row under: XRP is ripple (idFor).
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

  if (!await confirmSource(context, source) || !context.mounted) return null;

  // Asked whatever the source: a file's rows can still name pictures.
  var proxied = allowed && await networkIsProxied();
  var result = await loadData(asking, allowFetching: allowed, proxied: proxied);
  if (!context.mounted) return null;
  if (!result.worked) {
    snackbar.error(result.problem!);
    return null;
  }

  var rows = result.rows!;

  // A second look where needed: the form guide is derived from fixtures.
  if (preset?.derive != null) {
    rows = await preset!.derive!(rows, asking,
        (url) => fetchJsonAt(url, allowFetching: allowed, proxied: proxied));
    if (!context.mounted) return null;
  }

  // A row not returned is kept: nearly always a different spelling (BNB is
  // binancecoin), corrected on the row. Matched by the request's mapping.
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
  /// _busy is a refresh in progress, as in _RefreshButtonState.
  bool _busy = false;

  /// _fields is the paths in the last refresh's first record, not saved.
  List<String> get _fields =>
      target.controller.lastFetched[target.element.id]?.fields ?? const [];

  /// _hasKey is whether a key is saved for this host; it is never shown.
  bool _hasKey = false;
  String _forHost = "";

  _Target get target => widget.target;
  DataSource get source => target.source;

  /// _rawRows is the rows with dates intact, for date-chosen points.
  List<List<String>> get _rawRows =>
      target.controller.lastFetched[target.element.id]?.raw ?? const [];

  /// _rows is this sitting's last refresh, from the controller.
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

  /// _refresh reads the source and remembers what it held.
  Future<void> _refresh() async {
    var allowed = context.read<CanvasPreferences>().allowFetching;
    setState(() => _busy = true);
    try {
      await _runRefresh(context, target, allowed);
      if (!mounted) return;
      // _runRefresh put the rows on the controller; just redraw.
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
    if (path == null) return;
    await DataFiles.allow(path);
    _set(source.copyWith(kind: DataKind.file, where: path));
  }

  @override
  Widget build(BuildContext context) {
    var preset = presetById(source.preset);
    var allowed = context.watch<CanvasPreferences>().allowFetching;

    // Its own flat section, the refresh on its heading.
    var flat = CanvasCards.on(context);
    var where = boxed(
      context,
      CanvasExpander(
        label: target.label,
        remember: target.remember,
        flat: flat,
        trailing: _summary(source),
        // On the heading: one press refreshes, and shows the last update.
        action: CanvasIconButton(
          tight: true,
          icon: _busy ? Icons.hourglass_empty : Icons.refresh,
          tooltip: !source.on
              ? "Choose where the data comes from first"
              : source.fetchedAt == null
                  ? "Read the data and put it in the ${target.noun}"
                  : "Read the data again — last updated "
                      "${DateFormat("d MMM y, HH:mm").format(source.fetchedAt!.toLocal())}",
          onPressed: source.on && !_busy ? _refresh : null,
        ),
        children: [
          ..._sourceControls(context, preset, allowed),
        ],
      ),
    );

    // The mapping is its own sections, hidden while numbers are typed.
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

  /// _fieldNames is the refresh's fields plus the preset's.
  List<String> _fieldNames(DataPreset? preset) => <String>{
        ...?preset?.fields,
        ..._fields,
      }.toList()
        ..sort();

  /// _sourceControls is the preset, address or file, and key.
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
              // Whatever the element has rows for, beside the presets' sets.
              if (preset.choiceFromRows)
                (
                  _fromRows,
                  "Choose ${preset.choiceLabel.toLowerCase()} "
                      "for the ${target.noun}"
                ),
            ],
            // Through the preset, as the choice sets the mapping too.
            onChanged: (code) {
              if (code == _fromRows) {
                // The address waits for a refresh, or it goes stale.
                _set(source.copyWith(fromRows: true));
                return;
              }
              // One write, not two: see _Target.choosePreset.
              target.choosePreset(preset, code, fromRows: false);
            },
          ),
        // With this off, renaming a row does not change what is fetched.
        if (preset != null && !source.fromRows && preset.choiceFromRows)
          CanvasHint(
              "The ${preset.choiceLabel.toLowerCase()} above are fixed lists: "
              "a refresh asks for those, whatever the ${target.noun} says. To "
              "choose your own, pick “Whatever is in the ${target.noun}” — "
              "then the rows decide, and renaming one changes what is asked "
              "for."),
        // Ask the source what it has: the built-in list is short and
        // sometimes wrong (Firo is "zcoin"). Kept for next time.
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

      // What this element does with arriving rows; empty for a table.
      ...target.extras(_rows, _rawRows, _fieldNames(preset)),

      if (source.kind == DataKind.file)
        CanvasControlGroup(label: "File", children: [
          CanvasTextField(
            label: "Path",
            value: source.where,
            width: 240,
            onChanged: (v) => target.typeSource(source.copyWith(where: v)),
            onCommit: target.commit,
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
            onChanged: (v) => target.typeSource(source.copyWith(where: v)),
            onCommit: target.commit,
          ),
        ]),
        // The group's caption says whether there is a key.
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

  /// _columnControls is the mapping: which field in which column.
  List<Widget> _columnControls(DataPreset? preset) {
    var fields = _fieldNames(preset);
    return [
      CanvasControlGroup(label: "Rows", children: [
        CanvasTextField(
          label: "Path to the list",
          value: source.rowsPath,
          width: 200,
          onChanged: (v) => target.typeSource(source.copyWith(rowsPath: v)),
          onCommit: target.commit,
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
        // A custom field is a column with a recipe, added here.
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

  /// _oneColumn is a column as an opening line (a league table has a dozen
  /// of six settings each), remembered by name so it stays open when moved.
  Widget _oneColumn(
      int i, SourceColumn column, List<String> fields, DataPreset? preset) {
    // "builds": the cell is a recipe, with no field to choose. "custom": it
    // is laid out as one, including a preset-filled column (the form guide).
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
          // A path list keeping the column's setting even if no longer sent.
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
            // Before a refresh there is nothing to list: type the path.
            CanvasTextField(
              label: "Path",
              value: column.path,
              width: 130,
              onChanged: (v) => _setColumn(i, column.copyWith(path: v)),
              onCommit: target.commit,
            ),
          // A recipe makes it custom, starting as its field ("{points}").
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

        // What a built column is built from.
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

        // Conversions from atoms or epoch seconds, beside the field.
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

        // Column order is table order, so a column can be moved here.
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

/// _axisLabel says which axis the categories run along: the bottom for
/// most, the side for horizontal bars, round the middle for a pie.
String _axisLabel(ChartType type) => switch (type) {
      ChartType.horizontalBar => "Along the y axis",
      ChartType.radar => "One per spoke",
      ChartType.pie ||
      ChartType.donut ||
      ChartType.radialBar =>
        "One per slice",
      ChartType.waffle => "One per colour",
      _ => "Along the x axis",
    };

/// _unitWords is an interval's unit as a word: "year", "2 years".
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

/// _ordinal is a day of the month as said: 1st, 2nd, 7th.
String _ordinal(int day) {
  if (day >= 11 && day <= 13) return "${day}th";
  return switch (day % 10) {
    1 => "${day}st",
    2 => "${day}nd",
    3 => "${day}rd",
    _ => "${day}th",
  };
}

/// _intervalWords says an interval in words: "One reading a year, on 7
/// February" rather than "unit: year, month: 2, day: 7".
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

/// rowsMissingFrom is what was asked for by name and did not come back,
/// matched on the loose key ("Bitcoin Cash" as bitcoin-cash). The message
/// names them, and the refresh keeps their rows.
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
  // Rows name the coin and the key is the id, nearly always one word; where
  // a source files it otherwise, this says so.
  return [
    for (var key in wanted)
      if (!came.contains(key)) key,
  ];
}

/// _keyOf is what the source files a cell under, for matching.
String _keyOf(DataSource source, String cell) {
  var preset = presetById(source.preset);
  return preset == null ? asRowKey(cell) : CanvasRowNames.idFor(preset, cell);
}

/// _fromRows is the "ask for the element's rows" choice; no real code.
const String _fromRows = "\u0000rows";

/// _choiceOf is which preset choice the current address is.
String _choiceOf(DataPreset preset, DataSource source) {
  for (var (code, _) in preset.choices) {
    if (source.where == preset.address(code)) return code;
  }
  return preset.choices.first.$1;
}

/// _KeyField takes and saves an API key, never showing one back. It keeps
/// its own text, as a CanvasTextField resets to its (empty) bound value on
/// rebuild; a button saves, so a half-pasted key is not half saved.
class _KeyField extends StatefulWidget {
  final String host;

  /// saved is whether a key exists for this host; it is never shown.
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

  /// _buttonRoom is the save button's width beside the field.
  static const double _buttonRoom = 40;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // In the unbounded settings band the field takes a fixed width.
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

/// _isCustom is whether a column builds its cell (template, spread, or
/// preset-filled path), so its layout settings are always listed.
bool _isCustom(SourceColumn column, DataPreset? preset) =>
    column.template.isNotEmpty ||
    column.spread > 0 ||
    (preset?.derived.contains(column.path) ?? false);

/// boundSeries is [element] with series [index] from [column]. Past the
/// mapping it is a new field's column, named after it; below zero is typed,
/// the series no longer filled from the source.
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

/// spareFields are the refresh's paths with no column, in offer order, so
/// the list and "the third spare one" agree.
List<String> spareFields(List<SourceColumn> columns, List<String> fields) => [
      for (var field in fields)
        if (!columns.any((c) => c.path == field || c.template == field)) field,
    ];

/// seriesPicker is one series and its source, for the chart's Data settings
/// and grid header; picking one of [fields] adds a column.
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
    // A field with no column is numbered past the mapping's end in list
    // order, so the value names both the field and its new column.
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

/// _LookUpNames asks a source for all it has, once, tracking the request.
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
    // Whatever an earlier sitting fetched, so the list is there unasked.
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

/// sheetColumnName is column [c]'s heading, or its letter.
String sheetColumnName(DataSheet sheet, SheetLink link, int c) {
  var heading = sheetShown(sheet, link.range.r0, link.range.c0 + c).trim();
  var letter = columnName(link.range.c0 + c);
  return heading.isEmpty ? "Column $letter" : "$heading ($letter)";
}
