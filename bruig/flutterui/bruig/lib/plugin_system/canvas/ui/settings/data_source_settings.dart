import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
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
Widget dataSourceSection(
        BuildContext context,
        CanvasController controller,
        TableElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    boxed(
      context,
      CanvasExpander(
        label: "Data",
        remember: "tableSource",
        trailing: _summary(e.source),
        children: [
          _DataSourcePanel(
            controller: controller,
            element: e,
            write: write,
            begin: begin,
            commit: commit,
          )
        ],
      ),
    );

String _summary(DataSource source) {
  if (!source.on) return "Typed in";
  var preset = presetById(source.preset);
  var name = preset?.label ?? source.kind.label;
  if (source.fetchedAt == null) return name;
  return "$name · ${DateFormat("d MMM, HH:mm").format(source.fetchedAt!.toLocal())}";
}

class _DataSourcePanel extends StatefulWidget {
  final CanvasController controller;
  final TableElement element;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;

  const _DataSourcePanel({
    required this.controller,
    required this.element,
    required this.write,
    required this.begin,
    required this.commit,
  });

  @override
  State<_DataSourcePanel> createState() => _DataSourcePanelState();
}

class _DataSourcePanelState extends State<_DataSourcePanel> {
  /// _busy is a refresh in progress. A second press would make a second
  /// request and race the first one into the document.
  bool _busy = false;

  /// _hasKey is whether a key has been saved for this address's host. The key
  /// itself is never read back into the interface -- there is nothing anybody
  /// needs to do with it except replace it.
  bool _hasKey = false;
  String _forHost = "";

  DataSource get source => widget.element.source;

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

  void _set(DataSource next) {
    widget.begin();
    widget.write(widget.element.copyWith(source: next));
    widget.commit();
  }

  /// _refresh is the whole point of the panel: go and get it, map it, and put
  /// it in the table in the order the table is already sorted in.
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

      var rows =
          await collectPictures(result.rows!, source, allowFetching: allowed);
      if (!mounted) return;

      // Sorted on the way in, so a refresh puts the rows back in the order the
      // table was already in rather than the order the source happened to send
      // them. A league table that re-sorted itself only when somebody
      // remembered to press Sort would be wrong twice a week.
      widget.begin();
      var table = widget.element
          .copyWith(
              rows: rows, source: source.copyWith(fetchedAt: DateTime.now()))
          .sorted();
      widget.write(table);

      // The charts reading this table come with it. Without this the two would
      // drift the moment anybody refreshed -- a table showing this week and a
      // chart of last week, side by side on one canvas, with nothing to say
      // which was which.
      var followers = 0;
      for (var element in widget.controller.document.elements) {
        if (element is ChartElement && element.fromTable.tableId == table.id) {
          widget.controller.replaceElement(
              element.copyWith(
                  data: chartDataFromTable(table, element.fromTable)),
              transient: true);
          followers++;
        }
      }
      widget.commit();
      snackbar.success(followers == 0
          ? "${rows.length - 1} rows."
          : "${rows.length - 1} rows, and $followers chart"
              "${followers == 1 ? "" : "s"}.");
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

    return Column(children: [
      CanvasControlGroup(label: "Source", children: [
        CanvasDropdown<String>(
          label: "Preset",
          value: source.preset,
          width: 168,
          options: [
            ("", "None — set it up myself"),
            for (var p in dataPresets) (p.id, p.label),
          ],
          onChanged: (id) {
            var chosen = presetById(id);
            _set(chosen == null
                ? source.copyWith(preset: "")
                : chosen.applyTo(source, chosen.choices.first.$1));
          },
        ),
        if (preset != null)
          CanvasDropdown<String>(
            label: preset.choiceLabel,
            value: _choiceOf(preset, source),
            width: 148,
            options: preset.choices,
            onChanged: (code) => _set(preset.applyTo(source, code)),
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
        CanvasControlGroup(label: "Key", children: [
          CanvasTextField(
            label: _hasKey ? "Replace the key" : "Key",
            value: "",
            width: 240,
            onChanged: (v) async {
              await CanvasApiKeys.write(source.host, v);
              await _checkKey();
            },
          ),
          CanvasHint(_hasKey
              ? "A key is saved for ${source.host}. It is kept on this "
                  "machine and never written into the canvas, so a canvas you "
                  "send carries the table and not your key."
              : "Kept on this machine, never written into the canvas."),
        ]),
        if (!allowed)
          CanvasHint("Fetching is switched off. Turn on \"Let a canvas fetch "
              "data\" in Settings > Plugins > Canvas — it is off because "
              "nothing else in this app connects out on its own, and a fetch "
              "from here would not go through the proxy in Settings."),
      ],

      // The mapping, under everything else. A preset has already filled it in
      // and most readers will never open it; it is here because a source
      // nobody wrote a preset for is otherwise unreachable.
      CanvasExpander(
        label: "Columns",
        remember: "tableSourceColumns",
        trailing: "${source.columns.length}",
        children: [
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
            CanvasControlGroup(label: "Column ${i + 1}", children: [
              CanvasTextField(
                label: "Header",
                value: source.columns[i].header,
                width: 110,
                onChanged: (v) =>
                    _setColumn(i, source.columns[i].copyWith(header: v)),
              ),
              CanvasTextField(
                label: "Path",
                value: source.columns[i].path,
                width: 130,
                onChanged: (v) =>
                    _setColumn(i, source.columns[i].copyWith(path: v)),
              ),
              CanvasToggle(
                label: "A picture",
                value: source.columns[i].picture,
                onChanged: (v) =>
                    _setColumn(i, source.columns[i].copyWith(picture: v)),
              ),
              CanvasIconButton(
                icon: Icons.delete_outline,
                tooltip: "Remove this column",
                onPressed: () => _set(source.copyWith(columns: [
                  for (var c = 0; c < source.columns.length; c++)
                    if (c != i) source.columns[c],
                ])),
              ),
            ]),
          CanvasControlGroup(label: "Add", children: [
            CanvasIconButton(
              icon: Icons.add,
              tooltip: "Add a column",
              onPressed: () => _set(source.copyWith(
                  columns: [...source.columns, const SourceColumn()])),
            ),
          ]),
        ],
      ),

      CanvasControlGroup(label: "Refresh", children: [
        CanvasIconButton(
          icon: _busy ? Icons.hourglass_empty : Icons.refresh,
          tooltip: source.on
              ? "Read the data again and put it in the table"
              : "Choose where the data comes from first",
          onPressed: source.on && !_busy ? _refresh : null,
        ),
        if (source.fetchedAt != null)
          CanvasHint("Last updated "
              "${DateFormat("d MMM y, HH:mm").format(source.fetchedAt!.toLocal())}."),
      ]),
    ]);
  }

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
