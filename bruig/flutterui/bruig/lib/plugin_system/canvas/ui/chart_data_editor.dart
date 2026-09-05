import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// chart_data_editor.dart is the numbers behind a chart, in either of the two
// forms anybody wants them in.
//
// Pasted text is the fast way in and is why it was the only way for a while:
// copying a block out of a spreadsheet and getting a chart is the shortest
// path there is. It is a bad way to change one number in the middle of forty,
// which is the other thing people do to a chart all day -- so there is a grid
// as well, and a switch between them. The same ChartData either way; the grid
// writes values straight into it and the text goes through ChartData.parse.
//
// It is as wide as the sidebar and as tall as it has been dragged, both
// because a table crammed into a 240-pixel control with two visible lines is a
// table nobody can read.

class ChartDataEditor extends StatefulWidget {
  final ChartData data;

  /// onChanged is a change to keep. The caller opens the undo step.
  final ValueChanged<ChartData> onChanged;
  final VoidCallback onCommit;

  const ChartDataEditor({
    required this.data,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<ChartDataEditor> createState() => _ChartDataEditorState();
}

class _ChartDataEditorState extends State<ChartDataEditor> {
  ChartData get data => widget.data;

  void _write(ChartData next) {
    widget.onChanged(next);
    widget.onCommit();
  }

  /// _withValue writes one cell, growing the series to reach it.
  ///
  /// Ragged data is normal here -- a series added to a chart that already has
  /// five rows has no values at all until somebody types them -- so a write
  /// past the end fills the gap rather than being refused.
  void _withValue(int series, int row, double value) {
    var out = [...data.series];
    var values = [...out[series].values];
    while (values.length <= row) {
      values.add(0);
    }
    values[row] = value;
    out[series] = out[series].copyWith(values: values);
    _write(ChartData(categories: data.categories, series: out));
  }

  /// _addRow adds a category and a zero for it in every series.
  ///
  /// The zero matters. A row added without one leaves the series a value
  /// short, and the next row removed then takes a value that belongs to a
  /// different row -- so the numbers walk up the table one delete at a time.
  void _addRow() {
    _write(ChartData(
      categories: [...data.categories, "Row ${data.categories.length + 1}"],
      series: [
        for (var s in data.series)
          s.copyWith(values: [
            ...s.values,
            for (var i = s.values.length; i <= data.categories.length; i++) 0.0,
          ]),
      ],
    ));
  }

  void _addSeries() {
    var series = [...data.series];
    series.add(ChartSeries(
      name: "Series ${series.length + 1}",
      color: chartPalette[series.length % chartPalette.length],
      values: List.filled(data.categories.length, 0),
    ));
    _write(ChartData(categories: data.categories, series: series));
  }

  void _removeSeries(int index) {
    var series = [...data.series]..removeAt(index);
    _write(ChartData(categories: data.categories, series: series));
  }

  void _writeSeries(int index, ChartSeries next) {
    var series = [...data.series];
    series[index] = next;
    _write(ChartData(categories: data.categories, series: series));
  }

  void _removeRow(int row) {
    var categories = [...data.categories]..removeAt(row);
    var series = [
      for (var s in data.series)
        s.copyWith(
            values: row < s.values.length
                ? ([...s.values]..removeAt(row))
                : s.values),
    ];
    _write(ChartData(categories: categories, series: series));
  }

  @override
  Widget build(BuildContext context) => CanvasDataEditorShell(
        remember: "canvasChartData",
        gridTooltip: "Edit the numbers in a table",
        textTooltip: "Edit the numbers as pasted text",
        toolbar: [
          // The two ways a chart grows, side by side, because they are the
          // same kind of thing: a row is another category and a series is
          // another column of numbers against the same ones.
          CanvasIconButton(
            icon: Icons.add,
            tooltip: "Add a row",
            onPressed: _addRow,
          ),
          CanvasIconButton(
            icon: Icons.add_chart,
            tooltip: "Add a series — give it its own type below to lay one "
                "kind of chart over another",
            onPressed: _addSeries,
          ),
        ],
        text: (_) => _raw(),
        grid: (context) => _table(ThemeNotifier.of(context)),
        below: [
          // Clear of the table. The series rows are about the columns above
          // them, not another row of them, and butted up against the grid
          // they read as one more line of it.
          const SizedBox(height: 8),
          // Under the table, because a series is a column of it: what it is
          // called, what colour it is and how it is drawn all belong beside
          // the numbers they describe rather than in a section of their own
          // three headings away.
          for (var i = 0; i < data.series.length; i++) _seriesRow(i),
        ],
      );

  /// _seriesRow is one series' name, colour and type, in a line.
  ///
  /// Captioned on the first row only. One caption per column says as much as
  /// one per control and leaves a chart of six series six lines rather than
  /// eighteen.
  Widget _seriesRow(int i) {
    var series = data.series[i];
    // Wrapped rather than a row: a narrow sidebar has no room for a swatch, a
    // name and a dropdown side by side, and a Row that does not fit is an
    // overflow stripe rather than a second line.
    return Wrap(crossAxisAlignment: WrapCrossAlignment.start, children: [
      CanvasColorButton(
        label: i == 0 ? "Colour" : "",
        color: series.color,
        onChanged: (c) => _writeSeries(i, series.copyWith(color: c)),
      ),
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? controlLabelHeight : 0),
        child: SizedBox(
          width: 96,
          height: controlHeight,
          child: CanvasGridCell(
            value: series.name,
            dense: true,
            onChanged: (v) {
              var out = [...data.series];
              out[i] = out[i].copyWith(name: v);
              widget.onChanged(
                  ChartData(categories: data.categories, series: out));
            },
            onCommit: widget.onCommit,
          ),
        ),
      ),
      const SizedBox(width: 5),
      // "As the chart" rather than a second copy of the chart's own type: a
      // series that follows the chart keeps following it when the chart is
      // changed, which is what almost every series wants.
      CanvasDropdown<String>(
        label: i == 0 ? "Drawn as" : "",
        value: series.type?.name ?? "",
        width: 118,
        options: [
          ("", "As the chart"),
          for (var t in ChartType.values)
            if (!t.isCircular) (t.name, t.label),
        ],
        onChanged: (v) => _writeSeries(
            i,
            v.isEmpty
                ? series.copyWith(followChart: true)
                : series.copyWith(type: ChartType.fromName(v))),
      ),
    ]);
  }

  /// _grip drags the editor taller or shorter.
  /// _raw is the whole table as one block of text, in the tab or comma
  /// separated form a spreadsheet copies.
  Widget _raw() => CanvasGridCell(
        value: data.asText(),
        multiline: true,
        hint: "Name\tSeries\nWeek 1\t120",
        // Parsed against the series it is replacing, so editing the numbers
        // does not throw away a series' colour or the fact that it was drawn
        // as a line.
        onChanged: (text) =>
            widget.onChanged(ChartData.parse(text, keep: data.series)),
        onCommit: widget.onCommit,
      );

  /// _table is the grid: a column of category names and one column per series.
  Widget _table(ThemeNotifier theme) {
    if (data.series.isEmpty) {
      return Center(
        child: Text("No series yet",
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      );
    }

    const nameWidth = 86.0;
    const valueWidth = 62.0;

    Widget header() => Row(children: [
          const SizedBox(width: nameWidth + 4),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: valueWidth,
                  child: CanvasGridCell(
                    value: data.series[s].name,
                    dense: true,
                    onChanged: (v) {
                      var out = [...data.series];
                      out[s] = out[s].copyWith(name: v);
                      widget.onChanged(
                          ChartData(categories: data.categories, series: out));
                    },
                    onCommit: widget.onCommit,
                  ),
                ),
                // Against the column it removes, which is the only place a
                // "remove this series" control is unambiguous -- a list of
                // them somewhere else is a list of names to match up.
                CanvasIconButton(
                  icon: Icons.close,
                  tooltip: "Remove this series",
                  onPressed: () => _removeSeries(s),
                ),
              ]),
            ),
        ]);

    Widget row(int i) => Row(children: [
          SizedBox(
            width: nameWidth,
            child: CanvasGridCell(
              value: data.categories[i],
              dense: true,
              onChanged: (v) {
                var out = [...data.categories];
                out[i] = v;
                widget
                    .onChanged(ChartData(categories: out, series: data.series));
              },
              onCommit: widget.onCommit,
            ),
          ),
          const SizedBox(width: 4),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: valueWidth,
                child: CanvasGridCell(
                  value: _number(data.valueAt(s, i)),
                  dense: true,
                  onChanged: (v) =>
                      _withValue(s, i, double.tryParse(v.trim()) ?? 0),
                  onCommit: widget.onCommit,
                ),
              ),
            ),
          CanvasIconButton(
            icon: Icons.close,
            tooltip: "Remove this row",
            onPressed: () => _removeRow(i),
          ),
        ]);

    // Both ways, because a chart with eight series is wider than any sidebar
    // and a chart with forty rows is taller than any panel.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            header(),
            for (var i = 0; i < data.categories.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: row(i),
              ),
          ],
        ),
      ),
    );
  }

  static String _number(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}
