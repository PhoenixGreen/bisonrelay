import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// chart_settings.dart is a chart's settings.

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
  /// settings: the words, a switch, and, once it has been moved off the
  /// chart's own arrangement, where it sits. Whether the chart or the reader
  /// places the label is a switch, not a mode: no automatic rule covers both.
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
        // The name is the empty field's placeholder, not a caption over it: in a
        // section called Labels a caption would be the word a third time.
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
            // Named after which label it is: there are four Size fields in this
            // section, and a key found by counting finds another when one is added.
            key: ValueKey("chart${name}Size"),
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
        // No button of its own to place it: "Over the chart" is the one switch
        // for all three labels. The words and the switches, then where it sits:
        // four coordinates on a line with a text field cannot be scanned.
        if (box.show && e.floatingLabels) const CanvasLineBreak(),
        if (box.show && e.floatingLabels)
          // Against the place it is drawn in: its own once dragged, the chart's
          // until then, so the fields never read NaN on a label not yet moved.
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

  return [
    section(e, "source",
        icon: Icons.cloud_download_outlined,
        title: "Data source",
        summary: e.source.kind.label,
        action: sourceRefreshButton(
            context, controller, e, write, begin, commit,
            whenOff: true),
        children: [
          chartSourceSection(context, controller, e, write, begin, commit),
        ]),
    section(e, "chart",
        icon: Icons.bar_chart,
        title: "Chart",
        summary: "${e.type.label} · ${e.data.categories.length} rows, "
            "${e.data.series.length} series",
        initiallyOpen: true,
        children: [
          boxed(
            context,
            CanvasExpander(
              // "Table", because that is what is in it: the numbers in rows and
              // columns, with the drawing above them and its look below.
              label: "Table",
              remember: "chartData",
              flat: true,
              trailing: "${e.data.categories.length} rows, "
                  "${e.data.series.length} series",
              // The same Refresh the Data source section carries, here where somebody
              // looking at the numbers wants them again.
              action: sourceRefreshButton(
                  context, controller, e, write, begin, commit),
              initiallyOpen: true,
              children: [
                ChartDataEditor(
                  data: e.data,
                  chartType: e.type,
                  // The numbers alone: what each column is called and how it is drawn
                  // is the section under this one.
                  showSeries: false,
                  animated: e.animation.on,
                  elementId: e.base.id,
                  // How the chart draws where a series has not been told otherwise.
                  // The series leading its kind of drawing writes this back, so the
                  // rest of that kind follow it.
                  style: ChartStyleDefaults(
                    width: e.strokeWidth,
                    gap: e.barGap,
                    corner: e.barRadius,
                    floor: e.barFloor,
                    smooth: e.smooth,
                    points: e.showPoints,
                    pointSize: e.pointSize,
                    pointColor: e.pointColor,
                  ),
                  onStyleChanged: (style) {
                    begin();
                    write(e.copyWith(
                      strokeWidth: style.width,
                      barGap: style.gap,
                      barRadius: style.corner,
                      barFloor: style.floor,
                      smooth: style.smooth,
                      showPoints: style.points,
                      pointSize: style.pointSize,
                      pointColor: style.pointColor,
                    ));
                  },
                  onChanged: (data) {
                    begin();
                    writeData(data);
                  },
                  onCommit: commit,
                  // Where each series comes from, said against the series, where
                  // somebody looking at the grid wonders. Only the columns the mapping
                  // already has: reaching a new field belongs where the mapping is.
                  // Where the chart's rows are what the source is asked for, typing a
                  // coin offers the coins.
                  names: e.source.fromRows
                      ? CanvasRowNames.suggestionsFor(
                          presetById(e.source.preset))
                      : const [],
                  sourceColumns: e.source.on ? e.source.columns : const [],
                  boundTo: e.fromSource.valueColumns,
                  // What the preset says a record carries, so the list is the whole of
                  // what the source has, not only what is mapped. A refresh can only
                  // add to it; see _fieldNames.
                  sourceFields: e.source.on
                      ? presetById(e.source.preset)?.fields ?? const []
                      : const [],
                  onBind: (series, column) {
                    begin();
                    write(boundSeries(e, series, column,
                        presetById(e.source.preset)?.fields ?? const []));
                    commit();
                  },
                ),
              ],
            ),
          ),
          // What each column of the table is: its name, how it is drawn, its
          // colour. Under the numbers rather than with them ("are these the right
          // figures" and "how should this one look" are two questions), and not a
          // section: most charts have one series, and a heading would hide it.
          CanvasControlGroup(
              label: "Series",
              // The grid under it is the same drawing, not a new subject.
              rule: false,
              children: [
                ChartDataEditor(
                  data: e.data,
                  chartType: e.type,
                  animated: e.animation.on,
                  elementId: e.base.id,
                  showGrid: false,
                  style: ChartStyleDefaults(
                    width: e.strokeWidth,
                    gap: e.barGap,
                    corner: e.barRadius,
                    floor: e.barFloor,
                    smooth: e.smooth,
                    points: e.showPoints,
                    pointSize: e.pointSize,
                    pointColor: e.pointColor,
                  ),
                  onStyleChanged: (style) {
                    begin();
                    write(e.copyWith(
                      strokeWidth: style.width,
                      barGap: style.gap,
                      barRadius: style.corner,
                      barFloor: style.floor,
                      smooth: style.smooth,
                      showPoints: style.points,
                      pointSize: style.pointSize,
                      pointColor: style.pointColor,
                    ));
                  },
                  // The first series' "Drawn as" is the chart's own type: one control,
                  // not two that could disagree. The series is put back to following the
                  // chart in the same write, so a series pinned to bars does not stay
                  // bars when the chart is changed under it.
                  onChartType: (type) => now(e.copyWith(
                    type: type,
                    data: ChartData(
                      categories: e.data.categories,
                      series: [
                        for (var (i, series) in e.data.series.indexed)
                          i == 0 ? series.copyWith(followChart: true) : series,
                      ],
                    ),
                  )),
                  onChanged: (data) {
                    begin();
                    writeData(data);
                  },
                  onCommit: commit,
                ),
                // Said here: grouped and stacked bars draw what plain bars do until
                // there is a second series, which looks like the setting doing nothing.
                if (e.type.needsMultipleSeries && e.data.series.length < 2)
                  const CanvasHint(
                      "Grouped and stacked bars need more than one series -- with one "
                      "they draw exactly what plain bars draw. Add a second series with "
                      "the button beside the table."),
                // Four series, named where the names say which is which: a candlestick
                // chart with three draws nothing, which reads as broken.
                if (e.type.needsFourSeries && e.data.series.length < 4)
                  const CanvasHint(
                      "Candlesticks need four series — the open, the high, the low and "
                      "the close. Name them and the order does not matter; unnamed, "
                      "the first four are taken in that order. CoinGecko's OHLC preset "
                      "under Data source fills all four in."),
                // Bars, Lines and Points settings are on each series, behind its own
                // button: a chart of bars with a line over it has a half for each.
                // Candlesticks stay here: their four series are the open, high, low
                // and close of one drawing, so the colour is the reading.
                if (e.type.isCandles) ...[
                  const CanvasLineBreak(),
                  CanvasColorButton(
                    label: "Up",
                    color: e.riseColor,
                    onChanged: (c) => now(e.copyWith(riseColor: c)),
                  ),
                  CanvasColorButton(
                    label: "Down",
                    color: e.fallColor,
                    onChanged: (c) => now(e.copyWith(fallColor: c)),
                  ),
                  CanvasNumberField(
                    label: "Spacing",
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
                    label: "Corner",
                    value: e.barRadius,
                    min: 0,
                    max: 100,
                    width: 54,
                    onChanged: (v) => write(e.copyWith(barRadius: v)),
                    onCommit: commit,
                  ),
                ],
              ]),
          // What the chart rules itself with: the grid, the axes and the scale
          // are one question, how this chart is measured. And a bar chart of one
          // series, whose bars are its values as a pie's slices are: see
          // barsTakeColours.
          if ((e.type.isCircular || barsTakeColours(e)) &&
              e.data.categories.isNotEmpty)
            CanvasControlGroup(
                label: e.type.isCircular ? "Slices" : "Bars",
                key: const ValueKey("chartSliceColours"),
                children: [
                  for (var (i, name) in e.data.categories.indexed)
                    CanvasColorButton(
                      key: ValueKey("chartSlice$i"),
                      label: name.isEmpty ? "${i + 1}" : name,
                      color: e.type.isCircular
                          ? sliceColour(e, i)
                          : barColour(e, i),
                      onChanged: (c) => now(e.copyWith(sliceColors: [
                        for (var j = 0; j < e.data.categories.length; j++)
                          j == i
                              ? c
                              : e.type.isCircular
                                  ? sliceColour(e, j)
                                  : barColour(e, j),
                      ])),
                    ),
                ]),
          // How a number is written, wherever this chart writes one: its own line,
          // not behind the grid's button, since a pie rules nothing but still
          // writes numbers on its slices.
        ]),
    if (!e.type.isCircular)
      section(e, "grid",
          icon: Icons.grid_on,
          title: "Grid",
          summary: "Lines across the chart",
          children: [
            if (!e.type.isCircular)
              CanvasMoreGroup(
                label: "Grid",
                remember: "chartGridMore",
                tooltip: "How finely it is ruled, and what colour",
                row: [
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
                    label: "Log scale",
                    value: e.logScale,
                    onChanged: (v) => now(e.copyWith(logScale: v)),
                  ),
                  // The numbers written on the bars themselves: they belong to neither
                  // axis, so they sit with what is drawn on the plot.
                  CanvasToggle(
                    label: "Values",
                    value: e.showValues,
                    onChanged: (v) => now(e.copyWith(showValues: v)),
                  ),
                ],
                more: [
                  // How finely the value axis is ruled. Zero is the chart's own
                  // judgement.
                  CanvasNumberField(
                    key: const ValueKey("chartAxisSteps"),
                    label: "Lines",
                    value: e.axisSteps.toDouble(),
                    min: 0,
                    max: 40,
                    decimals: 0,
                    width: 54,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(axisSteps: v.round()));
                    },
                    onCommit: commit,
                  ),
                  // The colour the rules are drawn in, behind the switch it belongs to.
                  CanvasColorButton(
                    key: const ValueKey("chartGridColour"),
                    label: "Colour",
                    labelWidth: 30,
                    color: e.gridColor,
                    onChanged: (c) => now(e.copyWith(gridColor: c)),
                  ),
                ],
              ),
            // The title and the description, one line each, with the rest of what
            // each can be on the line below: the title somebody came to type is
            // not lost among twenty controls of equal weight.
          ]),
    section(e, "words",
        icon: Icons.title,
        title: "Words on it",
        summary: e.title.isEmpty ? "Title, labels, numbers and key" : e.title,
        children: [
          CanvasControlGroup(
              label: "Title, description and labels",
              // No line under it: what follows is the same heading's second line,
              // split off only because it carries a button of its own.
              rule: false,
              children: [
                ...labelControls(
                    "Title",
                    e.title,
                    e.titleBox,
                    defaultTitlePlacement,
                    e.titleSpec.fontSize,
                    (v) => e.copyWith(title: v),
                    (b) => e.copyWith(titleBox: b),
                    (v) => e.copyWith(
                        titleSpec: e.titleSpec.copyWith(fontSize: v))),
                const CanvasLineBreak(),
                // Under the title, not on top of it. Its own size, not the label size
                // it starts at, so a bigger description does not enlarge the numbers
                // up the side.
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
          // The two words naming the axes, each with the switch that shows it;
          // how the axis writing looks is behind the button.
          if (!e.type.isCircular)
            CanvasMoreGroup(
              label: "X and Y labels",
              // Under the title and the description, with no caption and no rule
              // after it: the writing on the chart is one run of lines.
              hideCaption: true,
              rule: false,
              remember: "chartAxisLabelsMore",
              tooltip: "How the writing on the axes looks",
              row: [
                // The axis name is the empty field's placeholder, and the
                // switch beside it is named after the axis, not "Show".
                CanvasTextField(
                  label: "",
                  hint: "X label",
                  value: e.xAxisLabel,
                  // Narrow, so the two fields, their two switches and the button
                  // stay on one line in a sidebar somebody has pulled in.
                  width: 72,
                  onChanged: (v) => write(e.copyWith(xAxisLabel: v)),
                  onCommit: commit,
                ),
                // A switch rather than emptying the field, so the titles come
                // back without being typed again.
                CanvasToggle(
                  key: const ValueKey("chartShowXTitle"),
                  label: "X",
                  value: e.showXTitle,
                  onChanged: (v) => now(e.copyWith(showXTitle: v)),
                ),
                CanvasTextField(
                  label: "",
                  hint: "Y label",
                  value: e.yAxisLabel,
                  // Narrow, as above.
                  width: 72,
                  onChanged: (v) => write(e.copyWith(yAxisLabel: v)),
                  onCommit: commit,
                ),
                CanvasToggle(
                  key: const ValueKey("chartShowYTitle"),
                  label: "Y",
                  value: e.showYTitle,
                  onChanged: (v) => now(e.copyWith(showYTitle: v)),
                ),
              ],
              more: [
                // The axis titles have their own size, so smaller figures up the
                // side do not shrink them, and their own distance from the plot,
                // which is the design's choice.
                CanvasColorButton(
                  key: const ValueKey("chartAxisTitleColour"),
                  label: "Titles",
                  color: e.axisText.color,
                  gradient: e.axisText.fade,
                  onChanged: (c) {
                    begin();
                    write(e.copyWith(axisSpec: e.axisText.copyWith(color: c)));
                    commit();
                  },
                  onGradientChanged: (g) {
                    begin();
                    write(e.copyWith(
                        axisSpec: g == null
                            ? e.axisText.copyWith(flatText: true)
                            : e.axisText.copyWith(fade: g)));
                    commit();
                  },
                ),
                CanvasNumberField(
                  label: "Label size",
                  value: e.axisText.fontSize,
                  min: 4,
                  max: 200,
                  decimals: 0,
                  width: 56,
                  onChanged: (v) {
                    begin();
                    write(
                        e.copyWith(axisSpec: e.axisText.copyWith(fontSize: v)));
                  },
                  onCommit: commit,
                ),
                CanvasNumberField(
                  label: "Label gap",
                  value: e.axisGap,
                  min: 0,
                  max: 400,
                  decimals: 0,
                  width: 56,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(axisGap: v));
                  },
                  onCommit: commit,
                ),
                const CanvasLineBreak(),
                // One switch each for the tick values: a bar chart named by its
                // categories does not always want the figures up the side.
                CanvasToggle(
                  key: const ValueKey("chartShowXLabels"),
                  label: "X values",
                  value: e.showXLabels,
                  onChanged: (v) => now(e.copyWith(showXLabels: v)),
                ),
                if (e.showXLabels) ...[
                  CanvasNumberField(
                    key: const ValueKey("chartXLabelSize"),
                    label: "Size",
                    // What it is actually written at, so the field is never a bare
                    // nought. It takes the label size until it is given its own.
                    value: e.xLabels.fontSize,
                    min: 4,
                    max: 200,
                    decimals: 0,
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(xLabelSize: v));
                    },
                    onCommit: commit,
                  ),
                  // How far the values sit from the chart: more to push them
                  // out, below nothing to draw them in.
                  CanvasNumberField(
                    key: const ValueKey("chartXLabelGap"),
                    // Not "Gap": the animation section has one of its own.
                    label: "Distance",
                    value: e.xLabelGap,
                    min: -40,
                    max: 200,
                    decimals: 0,
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(xLabelGap: v));
                    },
                    onCommit: commit,
                  ),
                  CanvasColorButton(
                    key: const ValueKey("chartXLabelColour"),
                    label: "Colour",
                    labelWidth: 30,
                    color: e.xLabels.color,
                    onChanged: (c) => now(e.copyWith(xLabelColor: c)),
                  ),
                ],
                const CanvasLineBreak(),
                CanvasToggle(
                  key: const ValueKey("chartShowYLabels"),
                  label: "Y values",
                  value: e.showYLabels,
                  onChanged: (v) => now(e.copyWith(showYLabels: v)),
                ),
                if (e.showYLabels) ...[
                  CanvasNumberField(
                    key: const ValueKey("chartYLabelSize"),
                    label: "Size",
                    value: e.yLabels.fontSize,
                    min: 4,
                    max: 200,
                    decimals: 0,
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(yLabelSize: v));
                    },
                    onCommit: commit,
                  ),
                  // How far the values sit from the chart, as above.
                  CanvasNumberField(
                    key: const ValueKey("chartYLabelGap"),
                    label: "Distance",
                    value: e.yLabelGap,
                    min: -40,
                    max: 200,
                    decimals: 0,
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(yLabelGap: v));
                    },
                    onCommit: commit,
                  ),
                  CanvasColorButton(
                    key: const ValueKey("chartYLabelColour"),
                    label: "Colour",
                    labelWidth: 30,
                    color: e.yLabels.color,
                    onChanged: (c) => now(e.copyWith(yLabelColor: c)),
                  ),
                ],
              ],
            ),
          // A pie's slices are one series' values, so their colours are the
          // categories', a button each in the order the slices are drawn. And a
          // donut's hole: how big, and what is written in it.
          if (e.type == ChartType.donut)
            CanvasControlGroup(
                key: const ValueKey("chartDonutHole"),
                label: "Middle",
                rule: false,
                children: [
                  CanvasNumberField(
                    key: const ValueKey("chartHole"),
                    label: "Hole",
                    value: e.innerRadius * 100,
                    min: 10,
                    max: 90,
                    decimals: 0,
                    suffix: "%",
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(innerRadius: v / 100));
                    },
                    onCommit: commit,
                  ),
                  CanvasTextField(
                    key: const ValueKey("chartCentreLabel"),
                    label: "Says",
                    hint: "{total}",
                    value: e.centreLabel,
                    width: 140,
                    onChanged: (v) => write(e.copyWith(centreLabel: v)),
                    onCommit: commit,
                  ),
                  const CanvasHint("Words in the middle of the ring. {total} "
                      "is the slices added up, and counts up as they arrive."),
                ]),
          CanvasControlGroup(
              label: "Numbers",
              hideCaption: true,
              rule: false,
              children: [
                // A pie has no grid line to put this on, so its switch comes here.
                if (e.type.isCircular)
                  CanvasToggle(
                    label: "Values",
                    value: e.showValues,
                    onChanged: (v) => now(e.copyWith(showValues: v)),
                  ),
                // Rings a few pixels thick have nowhere to write a number and no axis,
                // so theirs go in the key, which is no use with the key off.
                if (e.type == ChartType.radialBar &&
                    !(e.showLegend && e.legend.values))
                  const CanvasHint(
                      "A radial bar has no room to write a number on and no axis to "
                      "read one against, so its values go in the legend. Switch the "
                      "legend on, and its values with it, to see them."),
                // The example beside each name is what a million looks like in it,
                // since these are told apart by their answers; hence no caption.
                CanvasDropdown<NumberStyle>(
                  label: "",
                  value: e.numbers.style,
                  width: 176,
                  options: [
                    for (var style in NumberStyle.values)
                      (
                        style,
                        // What a million looks like as this chart is set, not a fixed example:
                        // a fixed "Millions — 1.0M" reads as the only thing millions can be.
                        // Automatic keeps its own, since what it does varies.
                        style == NumberStyle.automatic
                            ? "${style.label} — ${style.example}"
                            : "${style.label} — "
                                "${e.numbers.copyWith(style: style).format(1000000)}"
                      )
                  ],
                  onChanged: (v) => now(e.copyWith(
                      numbers: e.numbers.copyWith(
                    style: v,
                    // Seeded from what Automatic was already doing, so choosing a
                    // style does not silently reset the places to none.
                    decimals: e.numbers.style == NumberStyle.automatic &&
                            v != NumberStyle.automatic
                        ? (v == NumberStyle.plain ? 0 : 1)
                        : null,
                  ))),
                ),
                // What goes either side: a currency, a unit. Offered whatever
                // the style, because "\$" means as much on 1.2K as on 1,200.
                CanvasTextField(
                  key: const ValueKey("chartNumbersBefore"),
                  label: "Before",
                  hint: "\$",
                  value: e.numbers.before,
                  width: 56,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(
                        numbers: e.numbers.copyWith(before: v),
                        axisNumbers: e.axisNumbers?.copyWith(before: v)));
                  },
                  onCommit: commit,
                ),
                CanvasTextField(
                  key: const ValueKey("chartNumbersAfter"),
                  label: "After",
                  hint: " DCR",
                  value: e.numbers.after,
                  width: 64,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(
                        numbers: e.numbers.copyWith(after: v),
                        axisNumbers: e.axisNumbers?.copyWith(after: v)));
                  },
                  onCommit: commit,
                ),
                // Automatic decides its own places.
                if (e.numbers.style != NumberStyle.automatic) ...[
                  CanvasNumberField(
                    label: "Decimal places",
                    value: e.numbers.decimals.toDouble(),
                    min: 0,
                    max: 6,
                    decimals: 0,
                    width: 56,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(
                          numbers: e.numbers.copyWith(decimals: v.round())));
                    },
                    onCommit: commit,
                  ),
                  // The axis reads the same as the values until told otherwise; the
                  // usual pairing then is an exact reading on the bar, a round number on
                  // the scale.
                  CanvasToggle(
                    label: "Axis the same",
                    value: e.axisNumbers == null,
                    onChanged: (v) => now(v
                        ? e.copyWith(axisFollowsValues: true)
                        : e.copyWith(axisNumbers: e.numbers)),
                  ),
                  if (e.axisNumbers != null) ...[
                    CanvasDropdown<NumberStyle>(
                      label: "Axis numbers",
                      value: e.axisFigures.style,
                      width: 176,
                      options: [
                        for (var style in NumberStyle.values)
                          (
                            style,
                            style == NumberStyle.automatic
                                ? "${style.label} — ${style.example}"
                                : "${style.label} — "
                                    "${e.axisFigures.copyWith(style: style).format(1000000)}"
                          )
                      ],
                      onChanged: (v) => now(e.copyWith(
                          axisNumbers: e.axisFigures.copyWith(style: v))),
                    ),
                    if (e.axisFigures.style != NumberStyle.automatic)
                      CanvasNumberField(
                        label: "Axis places",
                        value: e.axisFigures.decimals.toDouble(),
                        min: 0,
                        max: 6,
                        decimals: 0,
                        width: 56,
                        onChanged: (v) {
                          begin();
                          write(e.copyWith(
                              axisNumbers:
                                  e.axisFigures.copyWith(decimals: v.round())));
                        },
                        onCommit: commit,
                      ),
                  ],
                  CanvasToggle(
                    label: "Separators",
                    value: e.numbers.separators,
                    onChanged: (v) => now(
                        e.copyWith(numbers: e.numbers.copyWith(separators: v))),
                  ),
                  CanvasHint("A million is written "
                      "\"${e.numbers.format(1000000)}\" on the bars and in the "
                      "legend, and \"${e.axisFigures.format(1000000)}\" up the "
                      "side. Zero places leaves no decimal point at all."),
                ],
              ]),
          // Where the key goes, and whether the words on the chart take room from
          // it: the last thing set, after what the chart says, how it is measured
          // and how it is written.
          CanvasMoreGroup(
            label: "Legend",
            hideCaption: true,
            remember: "chartLegendMore",
            tooltip: "The key's own settings",
            row: [
              // The one switch for all three: taking room is what makes each of
              // their settings resize the chart.
              CanvasToggle(
                label: "Over the chart",
                value: e.floatingLabels,
                // Switched off, the box goes back round the chart: a floating label
                // dragged outside grew the box and inset the chart, and left so the
                // chart would sit small in a margin of nothing.
                onChanged: (v) => now(v
                    ? e.copyWith(floatingLabels: true)
                    : e.copyWith(floatingLabels: false).aroundTheChart()),
              ),
              CanvasToggle(
                key: const ValueKey("chartShowLegend"),
                label: "Legend",
                value: e.showLegend,
                onChanged: (v) => now(e.copyWith(showLegend: v)),
              ),
            ],
            more: [
              if (e.showLegend && e.legend.hasPlace)
                CanvasIconButton(
                  icon: Icons.filter_center_focus,
                  tooltip: "Put the key back where Place says",
                  onPressed: () =>
                      now(e.copyWith(legend: e.legend.copyWith(unplace: true))),
                ),
              if (e.showLegend) ...[
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
                // The colour of everything written in the label type (the legend, a
                // pie's slice names), here because the legend holds most of it.
                CanvasColorButton(
                  key: const ValueKey("chartFigureColour"),
                  label: "Figures",
                  color: e.labelSpec.color,
                  gradient: e.labelSpec.fade,
                  onChanged: (c) {
                    begin();
                    write(
                        e.copyWith(labelSpec: e.labelSpec.copyWith(color: c)));
                    commit();
                  },
                  onGradientChanged: (g) {
                    begin();
                    write(e.copyWith(
                        labelSpec: g == null
                            ? e.labelSpec.copyWith(flatText: true)
                            : e.labelSpec.copyWith(fade: g)));
                    commit();
                  },
                ),
                const CanvasLineBreak(),
                // Its own switch, not the chart's: a bar chart may want numbers on its
                // bars and a key without, and a radial bar has nowhere else for them.
                CanvasToggle(
                  label: "Values",
                  value: e.legend.values,
                  onChanged: (v) =>
                      now(e.copyWith(legend: e.legend.copyWith(values: v))),
                ),
                if (e.legend.values)
                  CanvasDropdown<String>(
                    label: "Between",
                    value: e.legend.separator,
                    width: 104,
                    options: ChartLegend.separators,
                    onChanged: (v) => now(
                        e.copyWith(legend: e.legend.copyWith(separator: v))),
                  ),
                const CanvasHint(
                    "Size is measured against the chart's own label size, so "
                    "the key stays in proportion when those are changed. "
                    "Spacing is the gap between one entry and the next."),
              ],
            ],
          ),
        ]),
    // How its bars come in, loop and go: the Chain's Motion view (Ken,
    // 2026-11-08).
  ];
}
