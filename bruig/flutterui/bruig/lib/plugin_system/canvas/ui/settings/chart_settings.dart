import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// chart settings.dart is a chart's settings.

List<Widget> chartSettings(
    BuildContext context,
    CanvasController controller,
    ChartElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(ChartElement next) {
    begin();
    write(next);
    commit();
  }

  void writeData(ChartData data) => write(e.copyWith(data: data));

  /// labelControls is the shared shape of the title's and the description's
  /// settings: the words, a switch, and -- once it has been moved off the
  /// chart's own arrangement -- where it sits.
  ///
  /// Placing is a button rather than a mode. A chart lays its title out at the
  /// top and gives the rest to the plot, which is right until somebody wants
  /// it somewhere else, and there is no set of automatic rules that covers
  /// both. So the label is either the chart's to place or the reader's, and
  /// the button says which.
  List<Widget> labelControls(
    String name,
    String text,
    ChartLabel box,
    ChartLabel whenPlaced,
    double size,
    ChartElement Function(String) withText,
    ChartElement Function(ChartLabel) withBox,
    ChartElement Function(double) withSize,
  ) =>
      [
        // The name is the empty field's own placeholder rather than a caption
        // over it. A caption saying "Title" above a field saying "Chart
        // title" is the word twice and a line of panel for the second one,
        // and in a section already called Labels it is the third.
        CanvasTextField(
          label: "",
          value: text,
          hint: name,
          width: 160,
          onChanged: (v) => write(withText(v)),
          onCommit: commit,
        ),
        CanvasToggle(
          label: "Show",
          value: box.show,
          onChanged: (v) => now(withBox(box.copyWith(show: v))),
        ),
        if (box.show)
          CanvasNumberField(
            label: "Size",
            min: 4,
            max: 400,
            decimals: 1,
            width: 58,
            value: size,
            onChanged: (v) {
              begin();
              write(withSize(v));
            },
            onCommit: commit,
          ),
        // No button of its own to place it. There was one, and it was a
        // second switch saying the same thing as "Over the chart" -- a label
        // that floats is a label that sits where it is put, and a label that
        // does not is one the chart arranges. One switch, three labels.
        //
        // The words and the switches, then where it sits. Four coordinates
        // sharing a line with a text field and two buttons is four numbers
        // nobody can scan.
        if (box.show && e.floatingLabels) const CanvasLineBreak(),
        if (box.show && e.floatingLabels)
          // Against the place it is drawn in, which is its own once it has
          // been dragged and the chart's idea of one until then -- otherwise
          // the fields read NaN on a label nobody has moved yet.
          for (var (label, value, apply)
              in <(String, double, ChartLabel Function(double))>[
            (
              "X",
              (box.hasPlace ? box : whenPlaced).x,
              (v) => (box.hasPlace ? box : whenPlaced).copyWith(x: v)
            ),
            (
              "Y",
              (box.hasPlace ? box : whenPlaced).y,
              (v) => (box.hasPlace ? box : whenPlaced).copyWith(y: v)
            ),
            (
              "W",
              (box.hasPlace ? box : whenPlaced).width,
              (v) => (box.hasPlace ? box : whenPlaced).copyWith(width: v)
            ),
            (
              "H",
              (box.hasPlace ? box : whenPlaced).height,
              (v) => (box.hasPlace ? box : whenPlaced).copyWith(height: v)
            ),
          ])
            CanvasNumberField(
              label: label,
              min: -1,
              max: 2,
              decimals: 3,
              width: 58,
              value: value,
              onChanged: (v) {
                begin();
                write(withBox(apply(v)));
              },
              onCommit: commit,
            ),
      ];

  // Whether Smooth means anything here: the chart's own type, or any series
  // that has overridden it. Offered otherwise, it was a switch that did
  // nothing on a bar chart, which is indistinguishable from a broken one.
  var smoothable = e.type.usesSmooth ||
      e.data.series.any((s) => s.typeIn(e.type).usesSmooth);

  return [
    // "Type", not "Chart". The settings are already headed with the element's
    // own name, so a group called Chart under a heading called Chart said the
    // word twice and the dropdown under it said a third.
    CanvasControlGroup(label: "Type", children: [
      CanvasDropdown<ChartType>(
        label: "",
        value: e.type,
        width: 132,
        options: [for (var t in ChartType.values) (t, t.label)],
        onChanged: (v) => now(e.copyWith(type: v)),
      ),
      // Said here rather than left to be discovered. Grouped and stacked bars
      // draw exactly what plain bars draw until there is a second series to
      // group or stack, so choosing one on a one-series chart looks like the
      // setting doing nothing at all.
      if (e.type.needsMultipleSeries && e.data.series.length < 2)
        const CanvasHint(
            "Grouped and stacked bars need more than one series -- with one "
            "they draw exactly what plain bars draw. Add a second series "
            "under Series below."),
    ]),
    // "Axes and values", and the values are in it: they are all the same
    // question -- what does this chart write on itself -- and the switches
    // were split across two groups with a boxed section between them.
    CanvasControlGroup(label: "Axes and values", children: [
      // A pie has no axes, so it is offered none of the axis controls. It
      // still has values.
      if (!e.type.isCircular) ...[
        CanvasTextField(
          label: "X label",
          value: e.xAxisLabel,
          width: 108,
          onChanged: (v) => write(e.copyWith(xAxisLabel: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          label: "Y label",
          value: e.yAxisLabel,
          width: 108,
          onChanged: (v) => write(e.copyWith(yAxisLabel: v)),
          onCommit: commit,
        ),
        // The two axis titles are text, and the switches below are switches.
        // On one line the first switch sat on the end of the Y label's row
        // and read as part of it.
        const CanvasLineBreak(),
        CanvasToggle(
          label: "Grid",
          value: e.showGrid,
          onChanged: (v) => now(e.copyWith(showGrid: v)),
        ),
        CanvasToggle(
          label: "Axes",
          value: e.showAxes,
          onChanged: (v) => now(e.copyWith(showAxes: v)),
        ),
        CanvasToggle(
          label: "Axes labels",
          value: e.showAxisLabels,
          onChanged: (v) => now(e.copyWith(showAxisLabels: v)),
        ),
      ],
      CanvasToggle(
        label: "Values",
        value: e.showValues,
        onChanged: (v) => now(e.copyWith(showValues: v)),
      ),
      if (!e.type.isCircular)
        const CanvasHint(
            "Axes labels is everything written along the axes: the numbers, "
            "the category names and the two titles above. They are read "
            "together or not at all."),
      // Rings a few pixels thick have nowhere to write a number and no axis
      // to read one against, so theirs go in the key -- which is no use with
      // the key switched off.
      if (e.type == ChartType.radialBar && !(e.showLegend && e.legend.values))
        const CanvasHint(
            "A radial bar has no room to write a number on and no axis to "
            "read one against, so its values go in the legend. Switch the "
            "legend on, and its values with it, to see them."),
    ]),
    CanvasControlGroup(label: "Style", children: [
      CanvasColorButton(
        label: "Grid",
        color: e.gridColor,
        onChanged: (c) => now(e.copyWith(gridColor: c)),
      ),
      CanvasNumberField(
        label: "Bar gap",
        min: 0,
        decimals: 2,
        width: 62,
        value: e.barGap,
        max: 0.9,
        onChanged: (v) {
          begin();
          write(e.copyWith(barGap: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Bar radius",
        value: e.barRadius,
        min: 0,
        max: 100,
        width: 54,
        onChanged: (v) => write(e.copyWith(barRadius: v)),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Stroke",
        value: e.strokeWidth,
        min: 0.5,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) => write(e.copyWith(strokeWidth: v)),
        onCommit: commit,
      ),
      // Only where there is a line to curve. Bars have nothing to curve and a
      // scatter is unconnected by definition.
      if (smoothable)
        CanvasToggle(
          label: "Smooth",
          value: e.smooth,
          onChanged: (v) => now(e.copyWith(smooth: v)),
        ),
    ]),
    // Taking the numbers from a table on the same canvas. Its own section
    // beside the chart's own data, because it replaces that data rather than
    // adding to it -- and because a canvas with a league table and a chart of
    // the same league should be showing one set of figures.
    _tableSection(context, controller, e, write, begin, commit),

    // The words on the chart, together, in a section of their own. The title,
    // the description and the key are the same kind of thing -- writing laid
    // over a picture -- and they were three separate clusters and an expander
    // scattered down the panel with the data and the animation between them.
    boxed(
      context,
      CanvasExpander(
        label: "Labels",
        remember: "chartLabels",
        trailing: [
          if (e.title.isNotEmpty && e.titleBox.show) "title",
          if (e.description.isNotEmpty && e.descriptionBox.show) "description",
          if (e.showLegend) "legend",
        ].join(", "),
        children: [
          // No caption: the field says which it is when it is empty, and
          // what it says when it is not.
          CanvasControlGroup(label: "Title", bandOnlyLabel: true, children: [
            ...labelControls(
                "Title",
                e.title,
                e.titleBox,
                defaultTitlePlacement,
                e.titleSpec.fontSize,
                (v) => e.copyWith(title: v),
                (b) => e.copyWith(titleBox: b),
                (v) =>
                    e.copyWith(titleSpec: e.titleSpec.copyWith(fontSize: v))),
          ]),
          CanvasControlGroup(
              label: "Description",
              bandOnlyLabel: true,
              children: [
                // Under the title, not on top of it. A description above a title is
                // almost never what anybody means, and two labels placed at the same
                // corner is what that looked like.
                // Its own size, not the label size it starts at. Sharing meant making
                // the description bigger made the numbers up the side of the chart
                // bigger with it.
                ...labelControls(
                    "Description",
                    e.description,
                    e.descriptionBox,
                    defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty),
                    e.descriptionText.fontSize,
                    (v) => e.copyWith(description: v),
                    (b) => e.copyWith(descriptionBox: b),
                    (v) => e.copyWith(
                        descriptionSpec:
                            e.descriptionText.copyWith(fontSize: v))),
              ]),
          // Its own section, opened and closed. The numbers are the longest thing in
          // these settings and the least often changed once they are right, so they
          // were pushing everything else off the bottom of the panel.
          // Boxed, and with room after it. Open, it is a table and three rows of
          // series settings in the middle of a column of ordinary controls, and
          // without an edge of its own it ran straight into the axis settings under
          // it -- so the first thing under the table looked like part of the table.
          // No caption: the section this sits in is already called Labels.
          CanvasControlGroup(label: "Legend", children: [
            CanvasToggle(
              label: "Show",
              value: e.showLegend,
              onChanged: (v) => now(e.copyWith(showLegend: v)),
            ),
            if (e.showLegend && e.floatingLabels && e.legend.hasPlace)
              CanvasIconButton(
                icon: Icons.filter_center_focus,
                tooltip: "Put the key back where Place says",
                onPressed: () =>
                    now(e.copyWith(legend: e.legend.copyWith(unplace: true))),
              ),
            if (e.showLegend) ...[
              // Its own switch, not the chart's. A bar chart may want numbers
              // on its bars and a key without them, and a radial bar has
              // nowhere to put a number except the key.
              CanvasToggle(
                label: "Values",
                value: e.legend.values,
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(values: v))),
              ),
              const CanvasLineBreak(),
              CanvasDropdown<LegendPlacement>(
                label: "Place",
                value: e.legend.placement,
                width: 104,
                options: [for (var p in LegendPlacement.values) (p, p.label)],
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(placement: v))),
              ),
              CanvasDropdown<bool>(
                label: "Along",
                value: e.legend.vertical,
                width: 104,
                options: const [(false, "A row"), (true, "A column")],
                onChanged: (v) =>
                    now(e.copyWith(legend: e.legend.copyWith(vertical: v))),
              ),
              const CanvasLineBreak(),
              CanvasNumberField(
                label: "Size",
                min: 0.3,
                max: 4,
                decimals: 2,
                width: 58,
                value: e.legend.scale,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(legend: e.legend.copyWith(scale: v)));
                },
                onCommit: commit,
              ),
              CanvasNumberField(
                label: "Spacing",
                min: 0,
                max: 6,
                decimals: 2,
                width: 62,
                value: e.legend.spacing,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(legend: e.legend.copyWith(spacing: v)));
                },
                onCommit: commit,
              ),
              if (e.legend.values)
                CanvasDropdown<String>(
                  label: "Between",
                  value: e.legend.separator,
                  width: 104,
                  options: ChartLegend.separators,
                  onChanged: (v) =>
                      now(e.copyWith(legend: e.legend.copyWith(separator: v))),
                ),
              const CanvasHint(
                  "Size is measured against the chart's own label size, so "
                  "the key stays in proportion when those are changed. "
                  "Spacing is the gap between one entry and the next."),
            ],
          ]),
          CanvasControlGroup(label: "Labels", bandOnlyLabel: true, children: [
            // The one switch for all three of them. Taking room is what made every
            // one of their settings a setting that resized the chart.
            CanvasToggle(
              label: "Over the chart",
              value: e.floatingLabels,
              // Switched off, the box goes back round the chart. Dragging a
              // floating label outside it grew the box to hold the label and
              // inset the chart to keep it where it was -- and left like that
              // the chart sat small in the middle of an element with a margin
              // of nothing round it, so the switch did not go both ways after
              // all.
              onChanged: (v) => now(v
                  ? e.copyWith(floatingLabels: true)
                  : e.copyWith(floatingLabels: false).aroundTheChart()),
            ),
            const CanvasHint(
                "The title, the description and the legend sit over the chart and "
                "leave its size alone. Switched off they take room from it, which "
                "is right for a plot that fills its box -- a bar reaching the top "
                "will otherwise run behind a title floating over it."),
          ]),
        ],
      ),
    ),
    boxed(
      context,
      CanvasExpander(
        label: "Data",
        remember: "chartData",
        trailing: "${e.data.categories.length} rows, "
            "${e.data.series.length} series",
        initiallyOpen: true,
        children: [
          ChartDataEditor(
            data: e.data,
            onChanged: (data) {
              begin();
              writeData(data);
            },
            onCommit: commit,
          ),
        ],
      ),
    ),
    // Its own section, like the data. An animation is a handful of choices
    // made once and then left alone, and open by default they were four more
    // rows between the numbers and the axes.
    boxed(
      context,
      CanvasExpander(
        label: "Animation",
        remember: "chartAnimation",
        trailing: e.animation.on ? e.animation.preset.label : null,
        children: [
          CanvasControlGroup(label: "Preset", children: [
            const CanvasHint(
                "Choosing one draws the chart on over two seconds and puts a "
                "keyframe at each end of it on the timeline. Drag those to "
                "decide how long it takes and when it happens."),
            const CanvasLineBreak(),
            for (var preset in ChartAnimationPreset.values)
              if (e.type.isCircular
                  ? preset.suitsCircular
                  : preset.suitsCartesian)
                CanvasToggle(
                  label: preset.label,
                  value: e.animation.preset == preset,
                  // A press applies it and lays the keyframes together: a
                  // preset with nothing pinning the reveal channel draws
                  // exactly what a still chart draws.
                  onChanged: (_) => controller.applyChartAnimation(e, preset),
                ),
          ]),
          if (e.animation.on)
            CanvasControlGroup(label: "Timing", children: [
              // Only where there is more than one thing to space out. A wipe
              // and a sweep are one edge crossing everything at once.
              if (e.animation.preset.staggers)
                CanvasNumberField(
                  label: "Gap",
                  min: 0,
                  max: 4,
                  decimals: 2,
                  width: 62,
                  value: e.animation.gap,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(animation: e.animation.copyWith(gap: v)));
                  },
                  onCommit: commit,
                ),
              if (e.animation.preset.staggers)
                const CanvasHint(
                    "How long after one starts before the next does, as a "
                    "share of one item's own movement. 1 is strictly one "
                    "after another; below 1 they overlap; above 1 leaves a "
                    "pause between them."),
              CanvasDropdown<ChartEase>(
                label: "End curve",
                value: e.animation.ease,
                width: 118,
                options: [for (var c in ChartEase.values) (c, c.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(animation: e.animation.copyWith(ease: v)));
                  commit();
                },
              ),
            ]),
        ],
      ),
    ),
  ];
}

/// _tableSection is "take the numbers from a table on this canvas".
///
/// Only shown when there is a table to take them from. A section offering to
/// read something that does not exist is a section that reads as broken.
Widget _tableSection(
  BuildContext context,
  CanvasController controller,
  ChartElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var tables = [
    for (var element in controller.document.elements)
      if (element is TableElement) element,
  ];
  if (tables.isEmpty) return const SizedBox();

  var link = e.fromTable;
  TableElement? chosen;
  for (var table in tables) {
    if (table.id == link.tableId) chosen = table;
  }
  var columns = chosen?.columnCount ?? 0;

  void set(TableLink next) {
    begin();
    write(e.copyWith(fromTable: next));
    commit();
  }

  return boxed(
    context,
    CanvasExpander(
      label: "From a table",
      remember: "chartFromTable",
      trailing: chosen == null
          ? "Not linked"
          : "${link.valueColumns.length} column"
              "${link.valueColumns.length == 1 ? "" : "s"}",
      children: [
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
            onChanged: (id) => set(link.copyWith(tableId: id)),
          ),
        ]),
        if (chosen case var table?) ...[
          CanvasControlGroup(label: "Labels", children: [
            CanvasDropdown<int>(
              label: "From column",
              value: link.categoryColumn,
              width: 148,
              options: [
                for (var c = 0; c < columns; c++) (c, table.columnName(c)),
              ],
              onChanged: (c) => set(link.copyWith(categoryColumn: c)),
            ),
          ]),
          CanvasControlGroup(label: "Values", children: [
            for (var c = 0; c < columns; c++)
              CanvasToggle(
                label: table.columnName(c),
                value: link.valueColumns.contains(c),
                onChanged: (v) => set(link.copyWith(valueColumns: [
                  for (var i = 0; i < columns; i++)
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
                      write(e.copyWith(data: chartDataFromTable(table, link)));
                      commit();
                    }
                  : null,
            ),
            CanvasHint("Refreshing the table brings the chart with it, so the "
                "two cannot drift apart."),
          ]),
        ],
      ],
    ),
  );
}
