import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_view_settings.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// chart_settings.dart is a chart's settings.

/// chartPanel is [e]'s panel (see element_panel.dart): quick strip, Content
/// (source, numbers, series, words) and Look (grid, axes, looks).
Widget chartPanel(
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

  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        // Table or chart, and of which sheet: one Data element either way.
        dataViewStrip(controller, e),
        const SizedBox(height: 6),
        dataStudioButton(controller, e),
        const SizedBox(height: 8),
        panelRow([
          cell(
              CanvasDropdown<ChartType>(
                key: const ValueKey("quickChartType"),
                label: "Chart",
                value: e.type,
                options: [for (var t in ChartType.values) (t, t.label)],
                // As the numbers' "Drawn as" does: the first series follows.
                onChanged: (type) => now(e.copyWith(
                  type: type,
                  data: ChartData(
                    categories: e.data.categories,
                    series: [
                      for (var (i, series) in e.data.series.indexed)
                        i == 0 ? series.copyWith(followChart: true) : series,
                    ],
                  ),
                )),
              ),
              flex: 3,
              min: 120),
          cell(
              CanvasSwitch(
                key: const ValueKey("quickChartLegend"),
                value: e.showLegend,
                onChanged: (v) => now(e.copyWith(showLegend: v)),
              ),
              width: 52),
        ]),
        const SizedBox(height: 8),
        CanvasTextField(
          key: const ValueKey("quickChartTitle"),
          label: "Title",
          value: e.title,
          width: 220,
          onChanged: (v) => write(e.copyWith(title: v)),
          onCommit: commit,
        ),
      ]),
      // Its numbers are why its settings are opened: not folded away.
      contentOpen: true,
      bits: chartBits(context, controller, e, write, begin, commit));
}

/// chartBits are what of [e] goes in which of its panel's sections.
List<PanelBit> chartBits(
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

  /// labelControls is the title's and description's settings: words, a
  /// switch, and once moved, its place. Who places it is a switch, as no
  /// automatic rule covers both.
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
        // The name is the placeholder, not a caption: in a section called
        // Labels a caption would repeat the word a third time.
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
            // Keyed by label: there are four Size fields here, and a key
            // found by counting breaks when one is added.
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
        // "Over the chart" places all three labels. Words and switches first,
        // place on its own line, as four coordinates beside text do not scan.
        if (box.show && e.floatingLabels) const CanvasLineBreak(),
        if (box.show && e.floatingLabels)
          // Against where it is drawn: its own once dragged, the chart's
          // until then, so the fields never read NaN.
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
    // Which rows of its sheet it draws, and how ordered (Data element).
    PanelBit(PanelSection.content, children: [dataRowsGroup(controller, e)]),
    // Where the numbers come from, a fold with its Refresh on its heading.
    PanelBit(PanelSection.content, summary: e.source.kind.label, children: [
      CanvasExpander(
        label: "Data source",
        remember: "chartSource",
        trailing: e.source.kind.label,
        action: sourceRefreshButton(
            context, controller, e, write, begin, commit,
            whenOff: true),
        children: [
          chartSourceSection(context, controller, e, write, begin, commit),
        ],
      ),
    ]),
    PanelBit(PanelSection.content,
        summary: "${e.type.label} · ${e.data.categories.length} rows, "
            "${e.data.series.length} series",
        children: [
          boxed(
            context,
            CanvasExpander(
              // "Table", as that is what it holds: the numbers in rows and
              // columns, the drawing above and its look below.
              label: "Table",
              remember: "chartData",
              flat: true,
              trailing: "${e.data.categories.length} rows, "
                  "${e.data.series.length} series",
              // The Data source section's Refresh, also here where someone
              // looking at the numbers wants them again.
              action: sourceRefreshButton(
                  context, controller, e, write, begin, commit),
              initiallyOpen: true,
              children: [
                ChartDataEditor(
                  data: e.data,
                  chartType: e.type,
                  // The numbers alone: column names and drawing are the next
                  // section.
                  showSeries: false,
                  animated: e.animation.on,
                  elementId: e.base.id,
                  // The chart's default drawing; the leading series of a kind
                  // writes it back, so the rest of that kind follow.
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
                  // Each series' source, against the series: only mapped
                  // columns (new fields belong with the mapping). Typing a coin
                  // offers the coins where rows are what is asked.
                  names: e.source.fromRows
                      ? CanvasRowNames.suggestionsFor(
                          presetById(e.source.preset))
                      : const [],
                  sourceColumns: e.source.on ? e.source.columns : const [],
                  boundTo: e.fromSource.valueColumns,
                  // The preset's record fields too, so the list is all the
                  // source has, not only what is mapped (see _fieldNames).
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
          // Each column's name, drawing and colour, under the numbers (two
          // questions) and not a section: most charts have one series, which
          // a heading would hide.
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
                  // The first series' "Drawn as" is the chart type, one
                  // control; the same write resets the series to follow it,
                  // so a series pinned to bars changes with the chart.
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
                // Grouped and stacked bars look like plain bars until there
                // is a second series, so the setting would seem to do nothing.
                if (e.type.needsMultipleSeries && e.data.series.length < 2)
                  const CanvasHint(
                      "Grouped and stacked bars need more than one series -- with one "
                      "they draw exactly what plain bars draw. Add a second series with "
                      "the button beside the table."),
                // Four named series: a candlestick chart with three draws
                // nothing, which reads as broken.
                if (e.type.needsFourSeries && e.data.series.length < 4)
                  const CanvasHint(
                      "Candlesticks need four series — the open, the high, the low and "
                      "the close. Name them and the order does not matter; unnamed, "
                      "the first four are taken in that order. CoinGecko's OHLC preset "
                      "under Data source fills all four in."),
                // Bar, line and point settings are per series, so bars with a
                // line have a half each. Candlesticks stay here: four series
                // make one drawing, and the colour is the reading.
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
          // How the chart is measured: grid, axes, scale. Also a one-series
          // bar chart, whose bars take colours as slices do (barsTakeColours).
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
          // How a number is written, on its own line, not behind the grid's
          // button: a pie rules nothing but writes numbers on its slices.
        ]),
    if (!e.type.isCircular)
      PanelBit(PanelSection.look, summary: "Lines across the chart", children: [
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
              // Numbers on the bars belong to neither axis, so they sit with
              // the plot.
              CanvasToggle(
                label: "Values",
                value: e.showValues,
                onChanged: (v) => now(e.copyWith(showValues: v)),
              ),
            ],
            more: [
              // How finely the value axis is ruled; zero is the chart's own
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
              // The rules' colour, behind the switch it belongs to.
              CanvasColorButton(
                key: const ValueKey("chartGridColour"),
                label: "Colour",
                labelWidth: 30,
                color: e.gridColor,
                onChanged: (c) => now(e.copyWith(gridColor: c)),
              ),
            ],
          ),
        // Title and description one line each, the rest on the line below,
        // so the title is not lost among twenty equal controls.
      ]),
    PanelBit(PanelSection.content,
        summary: e.title.isEmpty ? "Title, labels, numbers and key" : e.title,
        children: [
          CanvasControlGroup(
              label: "Title, description and labels",
              // No rule: what follows is this heading's second line, split
              // off only for its own button.
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
                // Under the title, at its own size, so a bigger description
                // does not enlarge the axis numbers.
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
          // The two axis names, each with its show switch; how axis writing
          // looks is behind the button.
          if (!e.type.isCircular)
            CanvasMoreGroup(
              label: "X and Y labels",
              // No caption or rule: the writing on the chart is one run of
              // lines.
              hideCaption: true,
              rule: false,
              remember: "chartAxisLabelsMore",
              tooltip: "How the writing on the axes looks",
              row: [
                // The axis name is the placeholder, and the switch is named
                // after the axis, not "Show".
                CanvasTextField(
                  label: "",
                  hint: "X label",
                  value: e.xAxisLabel,
                  // Narrow, so both fields, switches and the button fit one
                  // line in a narrowed sidebar.
                  width: 72,
                  onChanged: (v) => write(e.copyWith(xAxisLabel: v)),
                  onCommit: commit,
                ),
                // A switch rather than clearing the field, so titles come back
                // without retyping.
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
                // Axis titles have their own size, so smaller tick figures do
                // not shrink them, and their own distance from the plot.
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
                // A switch per axis's tick values: a bar chart named by its
                // categories may not want figures up the side.
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
                    // What it is written at, so the field is never a bare
                    // nought; the label size until given its own.
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
                  // How far the values sit from the chart: more pushes them
                  // out, below nothing draws them inside.
                  CanvasNumberField(
                    key: const ValueKey("chartXLabelGap"),
                    // Not "Gap": the animation section has one.
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
          // A pie's slice colours are the categories', a button each in
          // slice order; and a donut's hole: its size and text.
          if (e.type == ChartType.donut || e.type == ChartType.gauge)
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
          // A pictogram's icons: what they are, and how many share the whole.
          if (e.type == ChartType.pictogram)
            CanvasControlGroup(
                key: const ValueKey("chartPictogram"),
                label: "Icons",
                rule: false,
                children: [
                  CanvasDropdown<PictoShape>(
                    key: const ValueKey("chartPictoShape"),
                    label: "Shape",
                    value: e.pictoShape,
                    options: [for (var p in PictoShape.values) (p, p.label)],
                    onChanged: (v) => now(e.copyWith(pictoShape: v)),
                  ),
                  CanvasNumberField(
                    key: const ValueKey("chartPictoCount"),
                    label: "How many",
                    value: e.pictoCount.toDouble(),
                    min: 1,
                    max: 200,
                    decimals: 0,
                    width: 52,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(pictoCount: v.round()));
                    },
                    onCommit: commit,
                  ),
                  const CanvasHint("Each icon is an equal share of the whole: "
                      "ten, a tenth each."),
                ]),
          // How the data is read, where it is read differently.
          if (switch (e.type) {
            ChartType.sankey => "Write a flow as \"From > To\" with its "
                "amount; a category on its own flows from the series' name.",
            ChartType.timeline => "Each event is placed along the line by its "
                "value: a year, or any number.",
            ChartType.gauge => "Several values: the first as a share of them "
                "all. One: out of the axis top, or of a hundred.",
            ChartType.bullet => "The first series is the bar, the second its "
                "target.",
            ChartType.slope => "The first series is the left end, the second "
                "the right.",
            _ => null,
          }
              case var how?)
            CanvasHint(how, key: const ValueKey("chartReadsAs")),
          CanvasControlGroup(
              label: "Numbers",
              hideCaption: true,
              rule: false,
              children: [
                // A pie has no grid line for this switch, so it comes here.
                if (e.type.isCircular)
                  CanvasToggle(
                    label: "Values",
                    value: e.showValues,
                    onChanged: (v) => now(e.copyWith(showValues: v)),
                  ),
                // Infographics, pies and radial bars name items by the x-axis
                // labels' switch, having no axis settings.
                if (e.type.isInfographic ||
                    e.type == ChartType.pie ||
                    e.type == ChartType.donut ||
                    e.type == ChartType.radialBar)
                  CanvasToggle(
                    key: const ValueKey("chartNames"),
                    label: "Names",
                    value: e.showXLabels,
                    onChanged: (v) => now(e.copyWith(showXLabels: v)),
                  ),
                if (e.type == ChartType.radialBar)
                  const CanvasHint(
                      "Each bar bends round three quarters of a turn at most -- to "
                      "the axis's top value where one is set, else the largest -- "
                      "with its name at its start and its value past its end."),
                // Beside each name, what a million looks like in it, as that
                // is what tells them apart; hence no caption.
                CanvasDropdown<NumberStyle>(
                  label: "",
                  value: e.numbers.style,
                  width: 176,
                  options: [
                    for (var style in NumberStyle.values)
                      (
                        style,
                        // A million as this chart is set, not a fixed example
                        // (which reads as the only way); Automatic varies.
                        style == NumberStyle.automatic
                            ? "${style.label} — ${style.example}"
                            : "${style.label} — "
                                "${e.numbers.copyWith(style: style).format(1000000)}"
                      )
                  ],
                  onChanged: (v) => now(e.copyWith(
                      numbers: e.numbers.copyWith(
                    style: v,
                    // Seeded from what Automatic was doing, so choosing a
                    // style does not reset the places to none.
                    decimals: e.numbers.style == NumberStyle.automatic &&
                            v != NumberStyle.automatic
                        ? (v == NumberStyle.plain ? 0 : 1)
                        : null,
                  ))),
                ),
                // A currency or unit either side, whatever the style: "\$"
                // means as much on 1.2K as on 1,200.
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
                  // The axis reads as the values until told otherwise; the
                  // usual pairing is exact on the bar, round on the scale.
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
          // Where the key goes, and whether the chart's words take room from
          // it: set last, after content, measure and writing.
          CanvasMoreGroup(
            label: "Legend",
            hideCaption: true,
            remember: "chartLegendMore",
            tooltip: "The key's own settings",
            row: [
              // One switch for all three: taking room makes each label's
              // settings resize the chart.
              CanvasToggle(
                label: "Over the chart",
                value: e.floatingLabels,
                // Off, the box goes back round the chart, or a label dragged
                // out would leave the chart small in an empty margin.
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
                // The colour of all label-type writing (legend, slice names),
                // here as the legend holds most of it.
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
                // Its own switch: a bar chart may want numbers on its bars and
                // a key without, and a radial bar has nowhere else for them.
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
    // How its bars come in, loop and go: the Chain's Motion view.
  ];
}
