import 'dart:async';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio_side.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// data_connect.dart is Connect data, in the Data Studio (Ken, 2026-11-15:
// "how do you choose, add and edit data set e.g. manually ... but how do you
// import or use an API?"; prototype v4, chosen 2026-11-16 over reusing the
// old settings panel). A sheet owns its connection: where its numbers come
// from, mapped into columns, and every table and chart of it follows a
// refresh.
//
// Four steps, in the studio's side panel, the sheet beside them showing what
// will arrive: where it comes from (a preset, a web address or a file); what
// to ask it for (a competition, coins; a key, kept on this computer); which
// list is the rows and which columns to keep, named and ordered; and where
// it goes -- this sheet, keeping its own columns, or a new one.
//
// Underneath is the engine the tables used before: loadJson/mapData,
// the presets and their derived columns (the football form guide), pictures
// collected on the way in, keys filed by host, and fetching off unless the
// reader has turned it on (and never through a proxy it cannot use).

/// SheetFetched is what a refresh of a sheet brought, header first, or why
/// nothing came; and any rows asked for by name that did not come back.
class SheetFetched {
  final List<List<String>>? rows;
  final String? problem;
  final List<String> missing;
  const SheetFetched(this.rows, {this.missing = const []}) : problem = null;
  const SheetFetched.failed(this.problem)
      : rows = null,
        missing = const [];
  bool get worked => rows != null;
}

/// askingFor is [source] as it is asked: for a preset whose choice is the
/// sheet's own rows (the coins in its first column), the address built from
/// [current]'s rows now, never saved, since the rows change.
(DataSource, List<String>) askingFor(
    DataSource source, List<List<String>> current) {
  var preset = presetById(source.preset);
  if (!source.fromRows || preset == null || !preset.choiceFromRows) {
    return (source, const []);
  }
  var at = source.matchColumn < 0 ? 0 : source.matchColumn;
  var wanted = [
    for (var row in current.skip(1))
      if (at < row.length && CanvasRowNames.idFor(preset, row[at]).isNotEmpty)
        CanvasRowNames.idFor(preset, row[at]),
  ];
  if (wanted.isEmpty) return (source, const []);
  return (source.copyWith(where: preset.address(wanted.join(","))), wanted);
}

/// fetchSheetRows reads [source] for a sheet now holding [current]: the
/// rows mapped, the preset's second look (the form guide) taken, rows asked
/// for and not sent kept from [current], and pictures collected.
Future<SheetFetched> fetchSheetRows(
    DataSource source, List<List<String>> current,
    {required bool allowed, required bool proxied}) async {
  var (asking, wanted) = askingFor(source, current);
  var preset = presetById(source.preset);
  var result = await loadData(asking, allowFetching: allowed, proxied: proxied);
  if (!result.worked) return SheetFetched.failed(result.problem);
  var rows = result.rows!;
  if (preset?.derive != null) {
    rows = await preset!.derive!(rows, asking,
        (url) => fetchJsonAt(url, allowFetching: allowed, proxied: proxied));
  }
  var missing = rowsMissingFrom(wanted, rows, asking.matchColumn,
      idOf:
          preset == null ? null : (cell) => CanvasRowNames.idFor(preset, cell));
  if (missing.isNotEmpty) {
    var at = asking.matchColumn < 0 ? 0 : asking.matchColumn;
    rows = [
      ...rows,
      for (var row in current.skip(1))
        if (at < row.length &&
            preset != null &&
            missing.contains(CanvasRowNames.idFor(preset, row[at])))
          row,
    ];
  }
  rows =
      await collectPictures(rows, asking, allowFetching: allowed && !proxied);
  return SheetFetched(rows, missing: missing);
}

/// sourceSays names where a sheet's numbers come from, shortly: the preset,
/// else the web address's host, else the file's name.
String sourceSays(DataSource s) {
  if (!s.on) return "Typed in";
  var preset = presetById(s.preset);
  if (preset != null) {
    return preset.shortLabel.isEmpty ? preset.label : preset.shortLabel;
  }
  if (s.kind == DataKind.url) return s.host;
  return s.where.split(RegExp(r"[\\/]")).last;
}

/// refreshSheet fetches sheet [id]'s source and puts what came in it,
/// asking first before a file it has not been allowed to read. It answers
/// the cells that changed, null when nothing came (having said why).
Future<Set<(int, int)>?> refreshSheet(
    BuildContext context, CanvasController c, String id) async {
  var sheet = c.sheetById(id);
  if (sheet == null || !sheet.source.on) return null;
  var source = sheet.source;
  var snackbar = SnackBarModel.of(context);
  if (source.kind == DataKind.file && !await DataFiles.allowed(source.where)) {
    if (!context.mounted) return null;
    var ok = await askToConfirm(context,
        title: "Read this file?",
        message: "This sheet reads ${source.where}. Only agree if it is a "
            "file you meant it to read.",
        confirm: "Read it");
    if (!ok || !context.mounted) return null;
    await DataFiles.allow(source.where);
  }
  if (!context.mounted) return null;
  var allowed = context.read<CanvasPreferences>().allowFetching;
  var proxied = allowed && await networkIsProxied();
  var got = await fetchSheetRows(source, sheet.cells,
      allowed: allowed, proxied: proxied);
  if (!context.mounted) return null;
  if (!got.worked) {
    snackbar.error(got.problem!);
    return null;
  }
  var changed =
      c.receiveSheet(id, got.rows!, source.copyWith(fetchedAt: DateTime.now()));
  snackbar.success("${got.rows!.length - 1} rows, ${changed.length} cells "
      "changed.${got.missing.isEmpty ? "" : " Not found: ${got.missing.join(", ")}."}");
  return changed;
}

/// SheetSourceCard is a connected sheet's card: where its numbers come from
/// and when they last came, with Refresh, Edit connection and Disconnect.
class SheetSourceCard extends StatefulWidget {
  final CanvasController controller;
  final DataSheet sheet;
  final VoidCallback onEdit;
  final void Function(Set<(int, int)> changed) onRefreshed;
  const SheetSourceCard(
      {required this.controller,
      required this.sheet,
      required this.onEdit,
      required this.onRefreshed,
      super.key});

  @override
  State<SheetSourceCard> createState() => _SheetSourceCardState();
}

class _SheetSourceCardState extends State<SheetSourceCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var s = widget.sheet.source;
    var preset = presetById(s.preset);
    var when = s.fetchedAt == null
        ? "Not fetched yet"
        : "Refreshed ${DateFormat("d MMM, HH:mm").format(s.fetchedAt!.toLocal())}";
    return Container(
      key: const ValueKey("sheetSourceCard"),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(9)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sourceSays(s),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: colors.onSurface)),
        Text(
            "${preset?.label ?? s.kind.label} · ${s.columns.length} columns · $when",
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StudioPill(
              key: const ValueKey("sheetSourceRefresh"),
              label: _busy ? "Fetching…" : "Refresh",
              filled: true,
              onTap: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        var changed = await refreshSheet(
                            context, widget.controller, widget.sheet.id);
                        if (changed != null) widget.onRefreshed(changed);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    }),
          StudioPill(
              key: const ValueKey("sheetSourceEdit"),
              label: "Edit connection",
              onTap: widget.onEdit),
          StudioPill(
              key: const ValueKey("sheetSourceDisconnect"),
              label: "Disconnect",
              tooltip: "Keep the numbers it has, typed in from now on",
              onTap: () => widget.controller
                  .setSheetSource(widget.sheet.id, const DataSource())),
        ]),
      ]),
    );
  }
}

/// ConnectData is the four steps, in the studio's side panel. [onPreview]
/// shows what will arrive in the sheet (null to stop); [onConnected] is
/// told which sheet it went into and which cells changed.
class ConnectData extends StatefulWidget {
  final CanvasController controller;
  final String sheetId;

  /// editing starts from the sheet's own connection, at its settings.
  final bool editing;
  final ValueChanged<List<List<String>>?> onPreview;
  final void Function(String sheetId, Set<(int, int)> changed) onConnected;
  final VoidCallback onCancel;
  const ConnectData(
      {required this.controller,
      required this.sheetId,
      required this.onPreview,
      required this.onConnected,
      required this.onCancel,
      this.editing = false,
      super.key});

  @override
  State<ConnectData> createState() => _ConnectDataState();
}

/// _Kind is which sort of source step 1 chose.
enum _Kind { preset, web, file }

class _ConnectDataState extends State<ConnectData> {
  CanvasController get c => widget.controller;
  int _step = 1;
  _Kind? _kind;
  DataPreset? _preset;
  String _choice = "";
  DataSource _src = const DataSource();
  final TextEditingController _key = TextEditingController();
  bool _hasKey = false;
  dynamic _json;
  bool _fetched = false;
  String? _problem;
  bool _busy = false;
  bool _intoNew = false;
  final TextEditingController _newName = TextEditingController();

  DataSheet? get _sheet => c.sheetById(widget.sheetId);

  @override
  void initState() {
    super.initState();
    var s = _sheet;
    if (widget.editing && s != null && s.source.on) {
      _src = s.source;
      _preset = presetById(s.source.preset);
      _kind = _preset != null
          ? _Kind.preset
          : s.source.kind == DataKind.file
              ? _Kind.file
              : _Kind.web;
      _choice = _preset == null ? "" : _choiceOf(_preset!, s.source);
      _step = 2;
      _checkKey();
    }
    // A sheet with nothing in it is filled; one holding numbers is not
    // overwritten unless chosen.
    _intoNew = s != null && s.rowCount > 0 && !s.source.on;
  }

  @override
  void dispose() {
    _key.dispose();
    _newName.dispose();
    super.dispose();
  }

  static String _choiceOf(DataPreset p, DataSource s) {
    for (var (code, _) in p.choices) {
      if (p.address(code) == s.where) return code;
    }
    return p.choices.firstOrNull?.$1 ?? "";
  }

  Future<void> _checkKey() async {
    var host = _src.host;
    var has = host.isNotEmpty && await CanvasApiKeys.has(host);
    if (mounted) setState(() => _hasKey = has);
  }

  void _choose(_Kind kind, [DataPreset? preset]) {
    setState(() {
      _kind = kind;
      _preset = preset;
      _json = null;
      _fetched = false;
      _problem = null;
      if (preset != null) {
        _choice = preset.choices.firstOrNull?.$1 ?? "";
        _src = preset.applyTo(const DataSource(), _choice);
        _newName.text =
            preset.shortLabel.isEmpty ? preset.label : preset.shortLabel;
      } else {
        _src = DataSource(
            kind: kind == _Kind.file ? DataKind.file : DataKind.url, where: "");
        _newName.text = kind == _Kind.file ? "From a file" : "From the web";
      }
    });
    widget.onPreview(null);
    _checkKey();
  }

  /// _fetch is "Fetch an example": the answer read once and kept, so the
  /// columns can be chosen and previewed without asking again.
  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      if (_key.text.trim().isNotEmpty && _src.host.isNotEmpty) {
        await CanvasApiKeys.write(_src.host, _key.text.trim());
        _key.clear();
        await _checkKey();
      }
      // A file named here, by the person at this computer, may be read: the
      // permission the file picker gives (DataFiles guards against a path
      // that arrived inside somebody else's canvas).
      if (_src.kind == DataKind.file && _src.where.isNotEmpty) {
        await DataFiles.allow(_src.where);
      }
      if (!mounted) return;
      var allowed = context.read<CanvasPreferences>().allowFetching;
      var proxied = allowed && await networkIsProxied();
      var (asking, _) = askingFor(_src, _sheet?.cells ?? const []);
      var got =
          await loadJson(asking, allowFetching: allowed, proxied: proxied);
      if (!mounted) return;
      if (!got.worked) {
        setState(() => _problem = got.problem);
        return;
      }
      _json = got.json;
      _fetched = true;
      // Where the rows are, when nobody has said: the biggest list in it.
      if (_src.rowsPath.isEmpty && _json is! List) {
        var lists = listsIn(_json)..sort((a, b) => b.$2.compareTo(a.$2));
        if (lists.isNotEmpty) _src = _src.copyWith(rowsPath: lists.first.$1);
      }
      if (_src.columns.isEmpty) _src = _withFields(_src);
      setState(() => _step = 3);
      _showPreview();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _withFields is [s] with a column for each of the first dozen fields
  /// its rows have, for a source nobody has mapped.
  DataSource _withFields(DataSource s) => s.copyWith(columns: [
        for (var f in fieldsAt(_json, s.rowsPath, sorted: false).take(12))
          SourceColumn(header: _headerOf(f), path: f, picture: _pictureish(f)),
      ], matchColumn: 0);

  static String _headerOf(String path) {
    var last = path.split(".").last;
    return last.isEmpty ? path : last[0].toUpperCase() + last.substring(1);
  }

  static bool _pictureish(String path) =>
      RegExp(r"crest|image|logo|icon|flag", caseSensitive: false)
          .hasMatch(path);

  void _setSource(DataSource next) {
    setState(() => _src = next);
    _showPreview();
  }

  void _showPreview() {
    if (!_fetched) return;
    var got = mapData(_json, _src);
    widget.onPreview(got.worked ? got.rows : null);
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      var allowed = context.read<CanvasPreferences>().allowFetching;
      var proxied = allowed && await networkIsProxied();
      var sheet = _sheet;
      var current =
          _intoNew ? const <List<String>>[] : sheet?.cells ?? const [];
      var got = await fetchSheetRows(_src, current,
          allowed: allowed, proxied: proxied);
      if (!mounted) return;
      if (!got.worked) {
        setState(() => _problem = got.problem);
        return;
      }
      c.beginInteraction();
      var id = _intoNew || sheet == null
          ? c.addSheet(name: _newName.text)
          : sheet.id;
      var changed = c.receiveSheet(
          id, got.rows!, _src.copyWith(fetchedAt: DateTime.now()));
      c.endInteraction();
      widget.onPreview(null);
      if (got.missing.isNotEmpty) {
        SnackBarModel.of(context)
            .error("Not found: ${got.missing.join(", ")}.");
      }
      widget.onConnected(id, changed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const says = [
      "Where the data comes from.",
      "What to ask it for.",
      "Which list is the rows, and which columns to keep.",
      "Where it goes.",
    ];
    const names = ["Source", "Ask", "Columns", "Into"];
    const icons = [
      Icons.hub_outlined,
      Icons.tune,
      Icons.view_column_outlined,
      Icons.input,
    ];
    void cancel() {
      widget.onPreview(null);
      widget.onCancel();
    }

    // The Studio's sidebar shape (data_studio_side.dart; Ken, 2026-11-17:
    // "Build all four"): the way back to the sheet in its header, where the
    // run has got to under it, each step as an open section, and Back and
    // Next pinned at the foot.
    return StudioSide(
      header: StudioSideHeader(
        icon: Icons.link,
        crumbs: [
          ("Sheet", cancel),
          (widget.editing ? "Edit connection" : "Connect data", null),
        ],
        crumbKey: "connectCrumb",
        title: widget.editing ? "Edit connection" : "Connect data",
        titleKey: const ValueKey("connectTitle"),
        onUp: cancel,
      ),
      scrollKey: ValueKey("connectPanel-$_step"),
      quick: [
        StudioSteps(
            names: names,
            at: _step,
            onBack: _busy ? null : (i) => setState(() => _step = i)),
        const SizedBox(height: 8),
        Text("Step $_step of 4 · ${says[_step - 1]}",
            key: const ValueKey("connectStep"),
            style: TextStyle(
                fontSize: 12,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant)),
      ],
      body: [
        StudioStepCard(
            icon: icons[_step - 1],
            title: says[_step - 1].replaceAll(".", ""),
            children: switch (_step) {
              1 => _sources(context),
              2 => _settings(context),
              3 => _columns(context),
              _ => _into(context),
            }),
        if (_problem != null)
          Text(_problem!,
              key: const ValueKey("connectProblem"),
              style: const TextStyle(fontSize: 12, color: Color(0xFFE8645A))),
      ],
      footer: studioButtons([
        studioButton("Cancel",
            key: const ValueKey("connectCancel"), onPressed: cancel),
        if (_step > 1)
          studioButton("Back",
              key: const ValueKey("connectBack"),
              icon: Icons.arrow_back,
              onPressed: _busy ? null : () => setState(() => _step--)),
        studioButton(
            _busy
                ? "Fetching…"
                : switch (_step) {
                    2 => "Fetch an example",
                    4 => "Connect",
                    _ => "Next",
                  },
            key: const ValueKey("connectNext"),
            primary: true,
            onPressed: _busy || !_canGo ? null : _next),
      ]),
    );
  }

  bool get _canGo => switch (_step) {
        1 => _kind != null,
        2 => _src.where.trim().isNotEmpty,
        3 => _src.columns.isNotEmpty,
        _ => true,
      };

  void _next() {
    switch (_step) {
      case 1:
        setState(() => _step = 2);
      case 2:
        _fetch();
      case 3:
        setState(() => _step = 4);
      default:
        _connect();
    }
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant)),
      );

  Widget _card(BuildContext context, String id, String title, String says,
          bool on, VoidCallback tap) =>
      StudioItem(
          key: ValueKey("connectSource-$id"),
          mark: Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16),
          title: title,
          subtitle: says,
          lit: on,
          subtitleLines: 3,
          onTap: tap);

  List<Widget> _sources(BuildContext context) => [
        const StudioLabel("Ready-made"),
        for (var p in presetsFor(chart: false))
          _card(
              context,
              p.id,
              p.label,
              p.note,
              _kind == _Kind.preset && _preset?.id == p.id,
              () => _choose(_Kind.preset, p)),
        const StudioLabel("Your own"),
        _card(
            context,
            "web",
            "A web address",
            "Any address that answers with JSON. Only https, and only when "
                "fetching is on.",
            _kind == _Kind.web,
            () => _choose(_Kind.web)),
        _card(
            context,
            "file",
            "A JSON file on this computer",
            "Read again on Refresh. No connection needed. (A spreadsheet "
                "file comes in with Import.)",
            _kind == _Kind.file,
            () => _choose(_Kind.file)),
      ];

  List<Widget> _settings(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var prefs = context.watch<CanvasPreferences>();
    var p = _preset;
    return [
      if (p != null) ...[
        StudioLabel(p.label),
        if (p.choices.isNotEmpty && !_src.fromRows) ...[
          StudioLabel(p.choiceLabel.isEmpty ? "Which" : p.choiceLabel),
          _Choices(
            key: const ValueKey("connectChoice"),
            value: _choice,
            options: p.choices,
            onChanged: (v) {
              _choice = v;
              _setSource(p.applyTo(_src, v));
            },
          ),
        ],
        if (p.choiceFromRows)
          StudioPills<bool>(
              id: "connectFromRows",
              label: "Ask for",
              value: _src.fromRows,
              options: const [
                (false, "These"),
                (true, "Whatever the sheet's first column names"),
              ],
              onChanged: (v) => _setSource(_src.copyWith(fromRows: v))),
        if (p.note.isNotEmpty) _hint(context, p.note),
      ],
      if (_kind == _Kind.web) ...[
        const StudioLabel("Address"),
        _Field(
            key: const ValueKey("connectAddress"),
            text: _src.where,
            hint: "https://…",
            onChanged: (v) {
              setState(() => _src = _src.copyWith(where: v.trim()));
              _checkKey();
            }),
        const StudioLabel("Laid out as"),
        StudioPills<DataShape>(
            id: "connectShape",
            label: "",
            value: _src.shape,
            options: [for (var s in DataShape.values) (s, s.label)],
            onChanged: (v) => setState(() => _src = _src.copyWith(shape: v))),
      ],
      if (_kind == _Kind.file) ...[
        const StudioLabel("File"),
        _Field(
            key: const ValueKey("connectPath"),
            text: _src.where,
            hint: "Its path, or choose it",
            onChanged: (v) =>
                setState(() => _src = _src.copyWith(where: v.trim()))),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("connectPickFile"),
                label: "Choose a file…",
                onTap: () async {
                  var got = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ["json"]);
                  var path = got?.files.singleOrNull?.path;
                  if (path == null) return;
                  await DataFiles.allow(path);
                  if (mounted) {
                    setState(() => _src = _src.copyWith(where: path));
                  }
                }),
          ),
        ),
      ],
      if (_src.kind == DataKind.url) ...[
        const StudioLabel("Your key, if it needs one"),
        TextField(
          key: const ValueKey("connectKey"),
          controller: _key,
          obscureText: true,
          style: TextStyle(fontSize: 13, color: colors.onSurface),
          decoration: _fieldLook(
              colors,
              _hasKey
                  ? "A key is saved for ${_src.host}"
                  : "Paste a key (most need none)"),
        ),
        _hint(
            context,
            "Kept on this computer for ${_src.host.isEmpty ? "that address" : _src.host}, "
            "never in the canvas: a canvas you send carries numbers, never "
            "keys."),
        if (!prefs.allowFetching)
          Container(
            key: const ValueKey("connectFetchingOff"),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  "Fetching is off. The canvas asks the web for nothing "
                  "until you turn it on, and never through a proxy it "
                  "cannot use.",
                  style: TextStyle(fontSize: 12, color: colors.onSurface)),
              const SizedBox(height: 6),
              StudioPill(
                  key: const ValueKey("connectFetchingOn"),
                  label: "Turn fetching on",
                  onTap: () => prefs.allowFetching = true),
            ]),
          ),
      ],
    ];
  }

  List<Widget> _columns(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var lists = _json == null ? const <(String, int)>[] : listsIn(_json);
    var used = {for (var col in _src.columns) col.path};
    var spare = _json == null
        ? const <String>[]
        : [
            for (var f in fieldsAt(_json, _src.rowsPath))
              if (!used.contains(f)) f
          ];
    var preview = _json == null ? null : mapData(_json, _src);
    var first = preview?.rows != null && preview!.rows!.length > 1
        ? preview.rows![1]
        : const <String>[];
    return [
      if (lists.length > 1) ...[
        const StudioLabel("The rows"),
        for (var (path, n) in lists.take(6))
          _card(
              context,
              "rows-$path",
              path.isEmpty ? "The answer itself" : path,
              "$n rows",
              _src.rowsPath == path, () {
            var next = _src.copyWith(rowsPath: path);
            if (_preset == null) next = _withFields(next);
            _setSource(next);
          }),
      ],
      StudioLabel("Columns · ${_src.columns.length}"),
      _hint(context,
          "Name them and put them in order; untick one to leave it out. The sheet shows what will come."),
      const SizedBox(height: 6),
      for (var (i, col) in _src.columns.indexed)
        Container(
          key: ValueKey("connectColumn-$i"),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Checkbox(
                key: ValueKey("connectColumnOn-$i"),
                value: true,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => _setSource(_src.withoutColumn(i))),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Field(
                        key: ValueKey("connectHeader-$i-${col.path}"),
                        text: col.header,
                        hint: col.path,
                        dense: true,
                        onChanged: (v) => _setSource(_src.copyWith(columns: [
                              for (var (j, x) in _src.columns.indexed)
                                j == i ? x.copyWith(header: v) : x
                            ]))),
                    Text(
                        "${col.template.isNotEmpty ? col.template : col.path.isEmpty ? "(worked out)" : col.path}"
                        "${i < first.length && first[i].isNotEmpty ? " · ${first[i]}" : ""}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                    if (_pictureish(col.path) || col.picture)
                      Row(children: [
                        Checkbox(
                            key: ValueKey("connectPicture-$i"),
                            value: col.picture,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) =>
                                _setSource(_src.copyWith(columns: [
                                  for (var (j, x) in _src.columns.indexed)
                                    j == i ? x.copyWith(picture: v ?? false) : x
                                ]))),
                        Flexible(
                          child: Text("As a picture",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: colors.onSurface)),
                        ),
                      ]),
                  ]),
            ),
            IconButton(
                key: ValueKey("connectEarlier-$i"),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.arrow_upward),
                onPressed: i == 0
                    ? null
                    : () => _setSource(_src.withColumnMoved(i, i - 1))),
            IconButton(
                key: ValueKey("connectLater-$i"),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.arrow_downward),
                onPressed: i == _src.columns.length - 1
                    ? null
                    : () => _setSource(_src.withColumnMoved(i, i + 1))),
          ]),
        ),
      if (spare.isNotEmpty) ...[
        StudioLabel("Also in it · ${spare.length}"),
        for (var f in spare.take(40))
          InkWell(
            key: ValueKey("connectSpare-$f"),
            onTap: () => _setSource(_src.copyWith(columns: [
              ..._src.columns,
              SourceColumn(
                  header: _headerOf(f), path: f, picture: _pictureish(f)),
            ])),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.add, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(f,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
      ],
      if (_preset?.derive != null)
        _hint(context,
            "Some of its columns are worked out with a second look (a form guide from the results) when it connects, so the preview leaves them empty."),
    ];
  }

  List<Widget> _into(BuildContext context) {
    var sheet = _sheet;
    var own = sheet == null || sheet.cells.isEmpty
        ? 0
        : sheet.cells.first.length - _src.columns.length;
    return [
      StudioPills<bool>(
          id: "connectInto",
          label: "Into",
          value: _intoNew,
          options: [
            (false, "“${sheet?.name ?? "This sheet"}”"),
            (true, "A new sheet"),
          ],
          onChanged: (v) => setState(() => _intoNew = v)),
      if (_intoNew) ...[
        const StudioLabel("Its name"),
        TextField(
          key: const ValueKey("connectNewName"),
          controller: _newName,
          style: const TextStyle(fontSize: 13),
          decoration:
              _fieldLook(ThemeNotifier.of(context).colors, "A new sheet"),
        ),
      ] else
        _hint(
            context,
            sheet == null || sheet.cells.isEmpty
                ? "The sheet is empty: it fills."
                : "In place of what it holds now; the tables and charts showing it follow."),
      StudioLabel("Which column says which row"),
      _Choices(
        key: const ValueKey("connectMatch"),
        value: "${_src.matchColumn < 0 ? 0 : _src.matchColumn}",
        options: [
          for (var (i, col) in _src.columns.indexed)
            ("$i", col.header.isEmpty ? col.path : col.header)
        ],
        onChanged: (v) =>
            setState(() => _src = _src.copyWith(matchColumn: int.parse(v))),
      ),
      _hint(
          context,
          !_intoNew && own > 0
              ? "Your own $own column${own == 1 ? "" : "s"} past these are kept, each row's staying with the row this column names."
              : "So a row keeps what is typed beside it as the order changes."),
      _hint(context,
          "It is fetched again when you press Refresh, never on its own."),
    ];
  }
}

InputDecoration _fieldLook(ColorScheme colors, String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
      filled: true,
      fillColor: colors.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7), borderSide: BorderSide.none),
    );

/// _Field is a one-line field that keeps what is typed while the panel
/// rebuilds under it.
class _Field extends StatefulWidget {
  final String text, hint;
  final bool dense;
  final ValueChanged<String> onChanged;
  const _Field(
      {required this.text,
      required this.hint,
      required this.onChanged,
      this.dense = false,
      super.key});

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _c =
      TextEditingController(text: widget.text);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      style: TextStyle(
          fontSize: widget.dense ? 12.5 : 13, color: colors.onSurface),
      decoration: _fieldLook(colors, widget.hint),
    );
  }
}

/// _Choices is a dropdown of (code, name) choices.
class _Choices extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _Choices(
      {required this.value,
      required this.options,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var has = options.any((o) => o.$1 == value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(7)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: has ? value : null,
          style: TextStyle(fontSize: 13, color: colors.onSurface),
          dropdownColor: colors.surfaceContainerHigh,
          items: [
            for (var (v, name) in options)
              DropdownMenuItem(
                  value: v, child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// SheetRefreshButton is a sheet's Refresh, as an icon, for a table's panel
/// on the canvas.
class SheetRefreshButton extends StatefulWidget {
  final CanvasController controller;
  final String sheetId;
  const SheetRefreshButton(
      {required this.controller, required this.sheetId, super.key});

  @override
  State<SheetRefreshButton> createState() => _SheetRefreshButtonState();
}

class _SheetRefreshButtonState extends State<SheetRefreshButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => CanvasIconButton(
        tight: true,
        icon: _busy ? Icons.hourglass_empty : Icons.refresh,
        tooltip: "Fetch the sheet's data again",
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await refreshSheet(
                      context, widget.controller, widget.sheetId);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      );
}
