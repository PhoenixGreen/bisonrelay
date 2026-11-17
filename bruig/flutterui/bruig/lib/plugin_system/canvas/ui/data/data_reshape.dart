import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_reshape.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_charts_design.dart'
    show columnKinds, ColumnKind;
import 'package:bruig/plugin_system/canvas/ui/data/data_studio_side.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_reshape.dart is the Data Studio's "A new sheet from this one": the
// same numbers in another shape (long, wide, grouped, or joined with
// another sheet) as a sheet that follows this one (sheet_reshape.dart);
// and, on a sheet made so, its source and a way to stop it following.

/// SheetReshapePart is the side panel's part for [sheet]: its source, if
/// any, and a new sheet's recipe; [onOpen] shows the one made.
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
  /// every row of a long one; a row a name, a column a date, filled from the
  /// last numbers, for a wide one; grouped by the first words that repeat.
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

    // A section's groups (data_studio_side.dart): its source, the new
    // shape as pictures, what it reads, and a look before it is made.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (made != null)
            studioGroup("Made from another", [
              SizedBox(
                width: double.infinity,
                child: Text(
                    from == null
                        ? "Its sheet has gone: it keeps what it had."
                        : "${made.says(from, c.sheetById(made.other))}. It follows "
                            "“${from.name}”: what is typed here is made again when "
                            "that changes.",
                    key: const ValueKey("dataStudioMadeFrom"),
                    style: TextStyle(fontSize: 12.5, color: colors.onSurface)),
              ),
              studioButtons([
                if (from != null)
                  studioButton("Go to “${from.name}”",
                      key: const ValueKey("dataStudioMadeOpen"),
                      onPressed: () => widget.onOpen(from.id)),
                studioButton("Stop following",
                    key: const ValueKey("dataStudioMadeStop"),
                    tooltip: "Keep the cells as they are, typed in from now on",
                    onPressed: () => c.setSheet(s.copyWith(unmade: true))),
              ]),
            ]),
          studioGroup("Its shape", [
            _shapes(context),
          ]),
          ...switch (_kind) {
            ReshapeKind.long => [
                studioGroup(
                    "Kept on every row",
                    [
                      _toggles([
                        for (var (i, h) in cols)
                          (
                            "dataStudioReshapeKeep-$i",
                            h,
                            _keep.contains(i),
                            () => setState(() => _keep.contains(i)
                                ? _keep.remove(i)
                                : _keep.add(i))
                          ),
                      ]),
                    ],
                    help: "Every other column becomes a row: its heading in "
                        "“Series”, its number in “Value”. A column a club "
                        "becomes a row a club a season."),
              ],
            ReshapeKind.wide => [
                studioGroup("", [
                  studioRow([
                    _drop("dataStudioReshapeRows", "A row for each", _rows,
                        cols, (v) => setState(() => _rows = v)),
                    _drop("dataStudioReshapeColumns", "A column for each",
                        _columns, cols, (v) => setState(() => _columns = v)),
                  ]),
                ]),
                // Filled from one column, or several: a column a word each.
                studioGroup(
                    "Filled from",
                    [
                      _toggles([
                        for (var (i, h) in cols)
                          if (i != _rows && i != _columns)
                            (
                              "dataStudioReshapeValue-$i",
                              h,
                              _values.contains(i),
                              () => setState(() {
                                    if (_values.contains(i)) {
                                      if (_values.length > 1) _values.remove(i);
                                    } else {
                                      _values.add(i);
                                    }
                                    _value = (_values.toList()..sort()).first;
                                  })
                            ),
                      ]),
                    ],
                    help: "A row a club a season becomes a column a season: "
                        "what a line chart of several clubs reads."),
              ],
            ReshapeKind.group => [
                studioGroup("", [
                  studioRow([
                    _drop("dataStudioReshapeBy", "Rows with the same", _by,
                        cols, (v) => setState(() => _by = v)),
                    studioDrop<String>(
                        key: const ValueKey("dataStudioReshapeHow"),
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
                  ]),
                ]),
              ],
            ReshapeKind.join => [
                studioGroup(
                    "",
                    [
                      if (others.isEmpty)
                        const StudioNote("There is no other sheet to join yet.")
                      else ...[
                        studioRow([
                          _drop<String>(
                              "dataStudioReshapeOther",
                              "With",
                              others.any((o) => o.id == _other) ? _other : "",
                              [("", "—"), for (var o in others) (o.id, o.name)],
                              (v) => setState(() {
                                    _other = v;
                                    _otherOn = 0;
                                  })),
                          _drop("dataStudioReshapeOn", "Where this sheet's",
                              _on, cols, (v) => setState(() => _on = v)),
                        ]),
                        if (c.sheetById(_other) case var o?)
                          studioRow([
                            _drop(
                                "dataStudioReshapeOtherOn",
                                "matches its",
                                _otherOn,
                                [
                                  for (var col = 0;
                                      col <= o.used.c1 - o.used.c0;
                                      col++)
                                    (col, o.raw(o.used.r0, o.used.c0 + col))
                                ],
                                (v) => setState(() => _otherOn = v)),
                            const SizedBox.shrink(),
                          ]),
                      ],
                    ],
                    help: "Its other columns go beside each row whose words "
                        "match."),
              ],
          },
          studioGroup("What it makes", [
            if (ready) _preview(context, preview),
            SizedBox(
              width: double.infinity,
              child: Row(children: [
                Expanded(
                  child: Text(
                      ready
                          ? "${preview.length - 1} rows by ${preview.first.length} columns"
                          : "Nothing to make yet.",
                      key: const ValueKey("dataStudioReshapeSize"),
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant)),
                ),
                studioButton("Make the sheet",
                    key: const ValueKey("dataStudioReshapeMake"),
                    primary: true,
                    onPressed: ready
                        ? () {
                            var id = c.addMadeSheet(_made);
                            if (id.isNotEmpty) widget.onOpen(id);
                          }
                        : null),
              ]),
            ),
          ]),
        ]);
  }

  /// _shapes is a new sheet's four shapes as tiles, the chosen one lit.
  Widget _shapes(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    (IconData, String, String) said(ReshapeKind k) => switch (k) {
          ReshapeKind.long => (
              Icons.view_agenda_outlined,
              "Long",
              "a row a value"
            ),
          ReshapeKind.wide => (
              Icons.view_week_outlined,
              "Wide",
              "a column a word"
            ),
          ReshapeKind.group => (
              Icons.functions,
              "Grouped",
              "totals by a column"
            ),
          ReshapeKind.join => (
              Icons.join_inner,
              "Joined",
              "with another sheet"
            ),
        };
    return SizedBox(
      width: double.infinity,
      child: Row(children: [
        for (var (i, k) in ReshapeKind.values.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: k == _kind
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
                      color:
                          k == _kind ? colors.primary : colors.outlineVariant)),
              child: InkWell(
                key: ValueKey("studioPill-dataStudioReshape-$k"),
                borderRadius: BorderRadius.circular(9),
                onTap: () => setState(() => _kind = k),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(said(k).$1,
                        size: 20,
                        color: k == _kind
                            ? colors.primary
                            : colors.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(said(k).$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                    Text(said(k).$3,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// _toggles is a line of columns, each on or off.
  Widget _toggles(List<(String, String, bool, VoidCallback)> items) => SizedBox(
        width: double.infinity,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (var (key, label, on, flip) in items)
            StudioPill(
                key: ValueKey(key), label: label, selected: on, onTap: flip),
        ]),
      );

  /// _preview is the new sheet's first few rows, as it will be made.
  Widget _preview(BuildContext context, List<List<String>> rows) {
    final colors = ThemeNotifier.of(context).colors;
    var shown = rows.take(5).toList();
    var cols = shown.first.length.clamp(1, 5);
    TextStyle st(bool head) => TextStyle(
        fontSize: 11,
        fontFamily: "monospace",
        fontWeight: head ? FontWeight.w600 : FontWeight.w400,
        color: head ? colors.onSurfaceVariant : colors.onSurface);
    return SizedBox(
      key: const ValueKey("dataStudioReshapePreview"),
      width: double.infinity,
      child: Table(
        border: TableBorder(
            horizontalInside: BorderSide(color: colors.outlineVariant)),
        children: [
          for (var (r, row) in shown.indexed)
            TableRow(children: [
              for (var col = 0; col < cols; col++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                  child: Text(col < row.length ? row[col] : "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: st(r == 0)),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _drop<T>(String key, String label, T value, List<(T, String)> options,
          ValueChanged<T> onChanged) =>
      studioDrop<T>(
          key: ValueKey(key),
          label: label,
          value: options.any((o) => o.$1 == value) ? value : options.first.$1,
          options: options,
          onChanged: onChanged);
}
