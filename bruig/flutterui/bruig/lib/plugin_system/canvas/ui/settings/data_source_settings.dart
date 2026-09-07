import 'dart:math' as math;
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
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
  void choosePreset(DataPreset preset, String choice);

  /// receive puts what came back into the element, and says what happened.
  ///
  /// Async because a table collects its pictures on the way in, which is one
  /// request per badge.
  Future<String> receive(List<List<String>> rows, DataSource next,
      {required bool allowed, required bool proxied});

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
  List<Widget> extras(List<List<String>> lastRows) => const [];
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
  void choosePreset(DataPreset preset, String choice) {
    // A preset brings its hidden headings with it. Its badge and position
    // columns are named so the mapping can refer to them and are not drawn,
    // and making the reader switch those off by hand after choosing a preset
    // would be a preset that half worked.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice),
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
      {required bool allowed, required bool proxied}) async {
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
            other.copyWith(data: chartDataFromTable(table, other.fromTable)),
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
  void choosePreset(DataPreset preset, String choice) {
    // A chart preset brings its mapping with it: which column is the axis,
    // which are the series, and how many points are worth drawing. Without
    // that, choosing "Coin supply" leaves a chart that has fetched four
    // thousand rows and drawn none of them.
    begin();
    write(element.copyWith(
      source: preset.applyTo(source, choice),
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
      {required bool allowed, required bool proxied}) async {
    var data = chartDataFromRows(rows, element.fromSource);
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
  List<Widget> extras(List<List<String>> lastRows) {
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
                          data: chartDataFromTable(table, link)));
                      commit();
                    }
                  : null,
            ),
            CanvasHint("Refreshing the table brings the chart with it, so the "
                "two cannot drift apart."),
          ]),
        ],
      ],
      CanvasControlGroup(label: "What is drawn", children: [
        CanvasDropdown<int>(
          label: "Along the axis",
          value: map.categoryColumn,
          width: 150,
          options: [for (var c = 0; c < columns.length; c++) named(c)],
          onChanged: (v) => _setMap(map.copyWith(categoryColumn: v), lastRows),
        ),
        for (var c = 0; c < columns.length; c++)
          if (c != map.categoryColumn)
            CanvasToggle(
              label: columns[c].header.isEmpty
                  ? "Column ${c + 1}"
                  : columns[c].header,
              value: map.valueColumns.contains(c),
              onChanged: (v) => _setMap(
                  map.copyWith(valueColumns: [
                    for (var i = 0; i < columns.length; i++)
                      if (i == c ? v : map.valueColumns.contains(i)) i,
                  ]),
                  lastRows),
            ),
        CanvasNumberField(
          label: "Most points",
          value: map.maxPoints.toDouble(),
          min: 0,
          max: 2000,
          decimals: 0,
          width: 66,
          onChanged: (v) =>
              _setMap(map.copyWith(maxPoints: v.round()), lastRows),
          onCommit: commit,
        ),
        const CanvasHint(
            "A daily series going back years is thousands of points, and a "
            "canvas is a few inches wide: drawn in full it is a grey smear. "
            "Most points keeps that many, evenly spread, ending on the latest "
            "— they are real readings, not an average. Zero draws every one."),
      ]),
    ];
  }

  /// _setMap changes what is drawn, and redraws it where it can.
  ///
  /// With the rows from this sitting's refresh in hand, changing which column
  /// is the axis is immediate. Without them -- a canvas opened this morning,
  /// nothing fetched yet -- the mapping is set and the chart keeps what it
  /// has until Refresh is pressed, which is honest: the column being asked
  /// for was never in the document to begin with.
  void _setMap(ChartSourceMap next, List<List<String>> rows) {
    begin();
    write(rows.isEmpty
        ? element.copyWith(fromSource: next)
        : element.copyWith(
            fromSource: next, data: chartDataFromRows(rows, next)));
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
  List<String> _fields = const [];

  /// _hasKey is whether a key has been saved for this address's host. The key
  /// itself is never read back into the interface -- there is nothing anybody
  /// needs to do with it except replace it.
  bool _hasKey = false;
  String _forHost = "";

  _Target get target => widget.target;
  DataSource get source => target.source;

  /// _rows is what the last refresh in this sitting returned.
  ///
  /// Kept for the same reason [_fields] is: it is a fact about what came back
  /// a minute ago rather than about the design, and it lets a chart change
  /// which column it draws without asking the server again.
  List<List<String>> _rows = const [];

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

  /// _refresh is the whole point of the panel: go and get it, map it, and
  /// hand it to whatever asked for it.
  Future<void> _refresh() async {
    var snackbar = SnackBarModel.of(context);
    var allowed = context.read<CanvasPreferences>().allowFetching;
    setState(() => _busy = true);
    try {
      var proxied =
          source.kind == DataKind.url ? await networkIsProxied() : false;
      var result =
          await loadData(source, allowFetching: allowed, proxied: proxied);
      if (!mounted) return;
      if (!result.worked) {
        snackbar.error(result.problem!);
        return;
      }

      var rows = result.rows!;

      // A second look, for a source that cannot say everything in one answer.
      // The football preset works its form guide out from the fixtures,
      // because the plan that sends it as a field is a paid one and the
      // results are free.
      var preset = presetById(source.preset);
      if (preset?.derive != null) {
        rows = await preset!.derive!(
            rows,
            source,
            (url) =>
                fetchJsonAt(url, allowFetching: allowed, proxied: proxied));
        if (!mounted) return;
      }

      var said = await target.receive(
          rows, source.copyWith(fetchedAt: DateTime.now()),
          allowed: allowed, proxied: proxied);
      if (!mounted) return;
      setState(() {
        _fields = result.fields;
        _rows = rows;
      });
      snackbar.success(said);
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
        boxed(
          context,
          CanvasExpander(
            label: "Custom fields",
            remember: "${target.remember}Custom",
            trailing: "${_customColumns(source, preset).length}",
            children: _customFieldControls(preset),
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
            value: _choiceOf(preset, source),
            width: 148,
            options: preset.choices,
            // Through the preset rather than the source, because the choice
            // decides the mapping as well as the address: dcrdata keeps every
            // series in an array named after itself.
            onChanged: (code) => target.choosePreset(preset, code),
          ),
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
      ...target.extras(_rows),

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
        _oneColumn(i, source.columns[i], fields),
      CanvasControlGroup(label: "Add", hideCaption: true, children: [
        CanvasIconButton(
          icon: Icons.add,
          tooltip: "Add a column to the mapping",
          onPressed: () => _set(source
              .copyWith(columns: [...source.columns, const SourceColumn()])),
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

  /// _oneColumn is a single column's mapping.
  ///
  /// Headed with the column's own name rather than "Column 7". A league table
  /// is a dozen of these, and a list headed by number is one that has to be
  /// counted through every time to find the one being looked for.
  Widget _oneColumn(int i, SourceColumn column, List<String> fields) =>
      CanvasControlGroup(label: _columnName(i), children: [
        CanvasTextField(
          label: "Header",
          value: column.header,
          width: 110,
          onChanged: (v) => _setColumn(i, column.copyWith(header: v)),
        ),
        // One control, not two. A free-text path beside a list of the
        // paths that exist is the same answer asked for twice, and the
        // typed one is the one that can be wrong. So once a refresh has
        // said what is actually in the data, this is a list -- with
        // whatever the column is set to already in it, even if the
        // source has since stopped sending it, because silently
        // changing a mapping to something else would be worse.
        if (fields.isNotEmpty)
          CanvasDropdown<String>(
            label: "Field",
            value: column.path,
            width: 150,
            options: [
              if (!fields.contains(column.path))
                (
                  column.path,
                  column.path.isEmpty ? "—" : "${column.path} (not in the data)"
                ),
              for (var field in fields) (field, field),
            ],
            onChanged: (v) => _setColumn(i, column.copyWith(path: v)),
          )
        else
          // Before the first refresh there is nothing to list, so the
          // path is typed -- which is also the way in for a source
          // nobody has written a preset for.
          CanvasTextField(
            label: "Path",
            value: column.path,
            width: 130,
            onChanged: (v) => _setColumn(i, column.copyWith(path: v)),
          ),
        // The two conversions, next to the field they convert. Both are
        // about the value that arrives rather than about the design, and
        // both are the difference between a readable column and a wall of
        // atoms or a row of epoch seconds.
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
        // A column becomes custom by being given a recipe. A toggle
        // rather than a text box, because the first thing a custom
        // field is is a copy of the field it replaces -- "{points}" --
        // and editing it from there is the Custom fields section's job.
        CanvasToggle(
          label: "Custom",
          value: column.template.isNotEmpty,
          onChanged: (v) => _setColumn(
              i, column.copyWith(template: v ? "{${column.path}}" : "")),
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
        // The order of the columns is the order of the table, so moving one
        // is a thing people want and there was no way to do it: a column in
        // the wrong place had to be deleted and the rest re-mapped by hand.
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
      ]);

  /// _customFieldControls is the columns that build their cell instead of
  /// taking it.
  ///
  /// Their own section because they are the ones somebody has to be told
  /// about -- a column built from a template or laid out as a run of results
  /// looks like magic in the Columns list, and the whole point of showing the
  /// recipe is that it can be copied.
  List<Widget> _customFieldControls(DataPreset? preset) {
    var fields = _fieldNames(preset);
    return [
      const CanvasHint(
          "A custom field builds its cell instead of taking it. Put a "
          "field's name in braces and it is replaced by what is there — "
          "\"{team.tla} ({points})\" gives \"MCI (6)\" — and anything "
          "outside the braces is written as it stands, which is how a "
          "column gets a dash, a unit or a word. Spread lays a "
          "comma-separated value out across that many slots, padded on "
          "the left so the newest is always in the same place."),
      if (preset?.derive != null)
        CanvasHint("${preset!.label} also fills the form guide in from "
            "somewhere the mapping cannot reach: the plan sends the "
            "field empty, so the last games are worked out from the "
            "finished results instead — one extra request when you "
            "refresh. The column is an ordinary custom field otherwise, "
            "and its slots and divider are yours to change."),
      for (var i = 0; i < source.columns.length; i++)
        if (_isCustom(source.columns[i], preset))
          _customControls(i, source.columns[i]),
      // The fields there are to build one out of, which is otherwise a list
      // that only exists inside a dropdown in another section.
      if (fields.isNotEmpty)
        CanvasHint("Fields you can put in braces: ${fields.join(", ")}."),
      CanvasControlGroup(label: "Add", hideCaption: true, children: [
        CanvasIconButton(
          icon: Icons.add,
          tooltip: "Add a custom field",
          onPressed: () => _set(source.copyWith(columns: [
            ...source.columns,
            SourceColumn(
                header: "New field",
                template: "{${fields.isEmpty ? "" : fields.first}}"),
          ])),
        ),
      ]),
    ];
  }

  /// _customControls is one custom field: what it is called, how it is built,
  /// and how it is laid out.
  Widget _customControls(int index, SourceColumn column) => CanvasControlGroup(
        label: _columnName(index),
        children: [
          CanvasTextField(
            label: "Header",
            value: column.header,
            width: 110,
            onChanged: (v) => _setColumn(index, column.copyWith(header: v)),
          ),
          CanvasTextField(
            label: "Built from",
            value:
                column.template.isEmpty ? "{${column.path}}" : column.template,
            width: 168,
            onChanged: (v) => _setColumn(index, column.copyWith(template: v)),
          ),
          CanvasNumberField(
            label: "Slots",
            value: column.spread.toDouble(),
            min: 0,
            max: 20,
            decimals: 0,
            width: 56,
            onChanged: (v) =>
                _setColumn(index, column.copyWith(spread: v.round())),
            onCommit: target.commit,
          ),
          CanvasTextField(
            label: "Divider",
            value: column.divider,
            width: 56,
            onChanged: (v) => _setColumn(index, column.copyWith(divider: v)),
          ),
          CanvasIconButton(
            icon: Icons.delete_outline,
            tooltip: "Remove this field",
            // Through the element rather than straight onto the source, so
            // that whatever pointed at the columns after this one -- which
            // chart series are drawn, which headings are hidden -- moves up
            // behind it instead of pointing at its neighbour.
            onPressed: () => target.removeColumn(index),
          ),
        ],
      );

  void _setColumn(int index, SourceColumn column) => _set(source.copyWith(
        columns: [
          for (var i = 0; i < source.columns.length; i++)
            i == index ? column : source.columns[i],
        ],
      ));
}

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

List<SourceColumn> _customColumns(DataSource source, DataPreset? preset) => [
      for (var c in source.columns)
        if (_isCustom(c, preset)) c
    ];
