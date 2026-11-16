import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_reshape.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart'
    show columnKinds, ColumnKind;
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_reshape.dart is the Data Studio's "A new sheet from this one" (Ken,
// 2026-11-17, the improvements report's second item): the same numbers in
// another shape -- long, wide, grouped, or joined with another sheet -- as
// a sheet that follows this one (sheet_reshape.dart). And, on a sheet made
// so, what it is made from and a way to stop it following.

/// SheetReshapePart is the side panel's part for sheet [sheet]: what it is
/// made from, if it is, and the recipe for a new sheet made from it.
/// [onOpen] shows the sheet made (or the source).
class SheetReshapePart extends StatefulWidget {
  final CanvasController controller;
  final DataSheet sheet;
  final ValueChanged<String> onOpen;
  const SheetReshapePart(
      {required this.controller,
      required this.sheet,
      required this.onOpen,
      super.key});

  @override
  State<SheetReshapePart> createState() => _SheetReshapePartState();
}

class _SheetReshapePartState extends State<SheetReshapePart> {
  ReshapeKind _kind = ReshapeKind.long;
  Set<int> _keep = {0};
  Set<int> _values = {2};
  int _rows = 0, _columns = 1, _value = 2, _by = 0, _on = 0, _otherOn = 0;
  String _how = "total";
  String _other = "";

  CanvasController get c => widget.controller;
  DataSheet get s => widget.sheet;

  List<String> get _heads {
    var g = s.used;
    return [
      for (var col = g.c0; col <= g.c1; col++)
        s.raw(g.r0, col).trim().isEmpty
            ? "Column ${col - g.c0 + 1}"
            : s.raw(g.r0, col).trim(),
    ];
  }

  @override
  void initState() {
    super.initState();
    _guess();
  }

  @override
  void didUpdateWidget(SheetReshapePart old) {
    super.didUpdateWidget(old);
    // A new sheet: its own guesses, not the last one's columns.
    if (old.sheet.id != s.id) _guess();
  }

  /// _guess is the columns most sheets mean: the words and dates kept on
  /// every row of a long one; a row a name, a column a date, filled from
  /// the last numbers, for a wide one; grouped by the first words that
  /// repeat.
  void _guess() {
    var g = s.used;
    if (g.cols <= 0 || s.cells.isEmpty) return;
    var kinds = columnKinds(s, g);
    List<int> of(ColumnKind k) => [
          for (var i = 0; i < kinds.length; i++)
            if (kinds[i] == k) i
        ];
    var words = of(ColumnKind.names), dates = of(ColumnKind.dates);
    var numbers = of(ColumnKind.numbers);
    _keep = {...words, ...dates};
    if (_keep.isEmpty) _keep = {0};
    _rows = words.isNotEmpty ? words.first : 0;
    _columns = dates.isNotEmpty
        ? dates.first
        : (words.length > 1 ? words[1] : (g.cols > 1 ? 1 : 0));
    _value = numbers.isNotEmpty ? numbers.last : g.cols - 1;
    _values = {_value};
    _by = words.isNotEmpty ? words.last : 0;
    _on = words.isNotEmpty ? words.first : 0;
    _otherOn = 0;
    _other = "";
  }

  SheetMade get _made => SheetMade(s.id, _kind,
      keep: _keep.toList()..sort(),
      rows: _rows,
      columns: _columns,
      value: _value,
      values: _values.toList()..sort(),
      by: _by,
      how: _how,
      other: _other,
      on: _on,
      otherOn: _otherOn);

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var heads = _heads;
    var cols = [for (var (i, h) in heads.indexed) (i, h)];
    Widget hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)));
    var others = [
      for (var o in c.document.sheets)
        if (o.id != s.id) o
    ];
    var made = s.made;
    var from = made == null ? null : c.sheetById(made.from);
    var preview = heads.isEmpty
        ? const <List<String>>[]
        : reshaped(_made, s, c.sheetById(_other));
    var ready = heads.isNotEmpty &&
        (_kind != ReshapeKind.join || _other.isNotEmpty) &&
        preview.length > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (made != null) ...[
        const StudioLabel("Made from another"),
        Text(
            from == null
                ? "Its sheet has gone: it keeps what it had."
                : "${made.says(from, c.sheetById(made.other))}. It follows "
                    "“${from.name}”: what is typed here is made again when "
                    "that changes.",
            key: const ValueKey("dataStudioMadeFrom"),
            style: TextStyle(fontSize: 12.5, color: colors.onSurface)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (from != null)
            StudioPill(
                key: const ValueKey("dataStudioMadeOpen"),
                label: "Go to “${from.name}”",
                onTap: () => widget.onOpen(from.id)),
          StudioPill(
              key: const ValueKey("dataStudioMadeStop"),
              label: "Stop following",
              tooltip: "Keep the cells as they are, typed in from now on",
              onTap: () => c.setSheet(s.copyWith(unmade: true))),
        ]),
        const SizedBox(height: 12),
      ],
      const StudioLabel("A new sheet from this one"),
      StudioPills<ReshapeKind>(
          id: "dataStudioReshape",
          label: "Its shape",
          value: _kind,
          options: [for (var k in ReshapeKind.values) (k, k.label)],
          onChanged: (k) => setState(() => _kind = k)),
      const SizedBox(height: 6),
      ...switch (_kind) {
        ReshapeKind.long => [
            const StudioLabel("Kept on every row"),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var (i, h) in cols)
                StudioPill(
                    key: ValueKey("dataStudioReshapeKeep-$i"),
                    label: h,
                    selected: _keep.contains(i),
                    onTap: () => setState(() =>
                        _keep.contains(i) ? _keep.remove(i) : _keep.add(i))),
            ]),
            hint("Every other column becomes a row: its heading in "
                "“Series”, its number in “Value”. A column a club becomes "
                "a row a club a season."),
          ],
        ReshapeKind.wide => [
            _drop("dataStudioReshapeRows", "A row for each", _rows, cols,
                (v) => setState(() => _rows = v)),
            _drop("dataStudioReshapeColumns", "A column for each", _columns,
                cols, (v) => setState(() => _columns = v)),
            // Filled from one column, or several: a column a word each.
            const StudioLabel("Filled from"),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var (i, h) in cols)
                if (i != _rows && i != _columns)
                  StudioPill(
                      key: ValueKey("dataStudioReshapeValue-$i"),
                      label: h,
                      selected: _values.contains(i),
                      onTap: () => setState(() {
                            if (_values.contains(i)) {
                              if (_values.length > 1) _values.remove(i);
                            } else {
                              _values.add(i);
                            }
                            _value = (_values.toList()..sort()).first;
                          })),
            ]),
            hint("A row a club a season becomes a column a season: what a "
                "line chart of several clubs reads."),
          ],
        ReshapeKind.group => [
            _drop("dataStudioReshapeBy", "Rows with the same", _by, cols,
                (v) => setState(() => _by = v)),
            StudioPills<String>(
                id: "dataStudioReshapeHow",
                label: "Their numbers",
                value: _how,
                options: const [
                  ("total", "Added up"),
                  ("average", "Averaged"),
                  ("count", "Counted"),
                  ("most", "The most"),
                  ("least", "The least"),
                ],
                onChanged: (v) => setState(() => _how = v)),
          ],
        ReshapeKind.join => [
            if (others.isEmpty)
              hint("There is no other sheet to join yet.")
            else ...[
              _drop<String>(
                  "dataStudioReshapeOther",
                  "With",
                  others.any((o) => o.id == _other) ? _other : "",
                  [("", "—"), for (var o in others) (o.id, o.name)],
                  (v) => setState(() {
                        _other = v;
                        _otherOn = 0;
                      })),
              _drop("dataStudioReshapeOn", "Where this sheet's", _on, cols,
                  (v) => setState(() => _on = v)),
              if (c.sheetById(_other) case var o?)
                _drop(
                    "dataStudioReshapeOtherOn",
                    "matches its",
                    _otherOn,
                    [
                      for (var col = 0; col <= o.used.c1 - o.used.c0; col++)
                        (col, o.raw(o.used.r0, o.used.c0 + col))
                    ],
                    (v) => setState(() => _otherOn = v)),
              hint("Its other columns go beside each row whose words "
                  "match."),
            ],
          ],
      },
      const SizedBox(height: 8),
      Text(
          ready
              ? "${preview.length - 1} rows by ${preview.first.length} columns"
              : "Nothing to make yet.",
          key: const ValueKey("dataStudioReshapeSize"),
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      const SizedBox(height: 6),
      StudioPill(
          key: const ValueKey("dataStudioReshapeMake"),
          label: "Make the sheet",
          filled: true,
          onTap: ready
              ? () {
                  var id = c.addMadeSheet(_made);
                  if (id.isNotEmpty) widget.onOpen(id);
                }
              : null),
    ]);
  }

  Widget _drop<T>(String key, String label, T value, List<(T, String)> options,
      ValueChanged<T> onChanged) {
    final colors = ThemeNotifier.of(context).colors;
    var shown = options.any((o) => o.$1 == value) ? value : options.first.$1;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudioLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(7)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: ValueKey(key),
              isExpanded: true,
              value: shown,
              style: TextStyle(fontSize: 13, color: colors.onSurface),
              dropdownColor: colors.surfaceContainerHigh,
              items: [
                for (var (v, name) in options)
                  DropdownMenuItem(
                      value: v,
                      child: Text(name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ]),
    );
  }
}
