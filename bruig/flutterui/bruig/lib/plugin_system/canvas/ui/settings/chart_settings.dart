import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
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
            // Named after which label it is. There are four Size fields in
            // this section now -- the title's, the description's, and one per
            // axis -- and finding one by counting is finding a different one
            // the next time a field is added.
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

  return [
    // Where the numbers come from, above the numbers themselves: a chart
    // that fetches is set up once, top to bottom, and a chart that does not
    // has one shut section to scroll past.
    chartSourceSection(context, controller, e, write, begin, commit),
    boxed(
      context,
      CanvasExpander(
        // "Table", because that is what is in it: the numbers, laid out in
        // rows and columns, with the drawing they are drawn as above them and
        // the way that drawing looks below.
        label: "Table",
        remember: "chartData",
        trailing: "${e.data.categories.length} rows, "
            "${e.data.series.length} series",
        // The same Refresh the Data source section carries. This is where
        // somebody is standing when they want the numbers again -- looking at
        // them -- and sending them to another section to press it is asking
        // them to know which section owns the wire.
        action:
            sourceRefreshButton(context, controller, e, write, begin, commit),
        initiallyOpen: true,
        children: [
          ChartDataEditor(
            data: e.data,
            chartType: e.type,
            // The numbers alone. What each column is called, what colour it
            // is and how it is drawn are the section under this one: a table
            // holding both was the longest thing in the panel and the first
            // thing anybody met.
            showSeries: false,
            animated: e.animation.on,
            elementId: e.base.id,
            // How the chart draws where a series has not been told
            // otherwise. The series that leads its kind of drawing writes
            // this back, so the rest of that kind follow it.
            style: ChartStyleDefaults(
              width: e.strokeWidth,
              gap: e.barGap,
              corner: e.barRadius,
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
            // Where each series comes from, said against the series rather
            // than in the Data source section: the grid is where somebody is
            // looking when they wonder. Only the columns the mapping already
            // has -- reaching a field it has not is a bigger question and
            // belongs where the mapping is.
            // What the source has, where the chart's rows are what it is
            // asked for: typing a coin offers the coins.
            names: e.source.fromRows
                ? CanvasRowNames.suggestionsFor(presetById(e.source.preset))
                : const [],
            sourceColumns: e.source.on ? e.source.columns : const [],
            boundTo: e.fromSource.valueColumns,
            // What the preset says a record carries, so the list is the whole
            // of what the source has rather than the handful somebody has
            // mapped -- a coin comparison maps five columns out of twenty
            // fields. A refresh can only add to it; see _fieldNames.
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
    // colour. Under the numbers rather than inside the box with them --
    // "are these the right figures" and "how should this one look" are two
    // questions, and one box holding both was the longest thing in the panel.
    //
    // Not a section of its own either. It is one line per series and most
    // charts have one: a heading that has to be opened to find three controls
    // is a heading that hides them.
    CanvasControlGroup(
        label: "Series",
        // The grid under it is the next thing about the same drawing, not a
        // new subject.
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
                smooth: style.smooth,
                showPoints: style.points,
                pointSize: style.pointSize,
                pointColor: style.pointColor,
              ));
            },
            // The first series' "Drawn as" is the chart's own type. There was a
            // Type dropdown three sections above as well, saying the same thing
            // in a second place: a one-series chart has one answer to "what is
            // this drawn as", and two controls for it that could disagree.
            //
            // The series is put back to following the chart in the same write, so
            // that a series pinned to bars does not stay bars when the chart is
            // changed under it.
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
          // Said here rather than left to be discovered. Grouped and stacked bars
          // draw exactly what plain bars draw until there is a second series to
          // group or stack, so choosing one on a one-series chart looks like the
          // setting doing nothing at all.
          if (e.type.needsMultipleSeries && e.data.series.length < 2)
            const CanvasHint(
                "Grouped and stacked bars need more than one series -- with one "
                "they draw exactly what plain bars draw. Add a second series with "
                "the button beside the table."),
          // Four series, not one, and named rather than counted where the names
          // say which is which. Said here because a candlestick chart with three
          // series draws nothing at all, which reads as broken.
          if (e.type.needsFourSeries && e.data.series.length < 4)
            const CanvasHint(
                "Candlesticks need four series — the open, the high, the low and "
                "the close. Name them and the order does not matter; unnamed, "
                "the first four are taken in that order. CoinGecko's OHLC preset "
                "under Data source fills all four in."),
          // Bars, Lines and Points used to be groups of chart settings of their
          // own. They are on the series now, behind each series' own button,
          // because a chart of bars with a line over it made them groups that
          // were each about half of the chart and said nothing about which half.
          //
          // Candlesticks are the exception, and stay. A candlestick's four series
          // are the open, high, low and close of one drawing, so the colour is
          // the reading rather than a label for a series, and there is no "the
          // series that is drawn as bars" to put the bodies behind.
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
    // What the chart rules itself with. Gathered rather than scattered: the
    // grid, the axes and the scale are one question -- how is this chart
    // measured -- and they were down the middle of a group called "Axes and
    // values" with the axis titles above them and the legend below.
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
          // The numbers written on the bars themselves. They belong to
          // neither axis, so they sit with the rest of what is drawn on the
          // plot rather than with the words around it.
          CanvasToggle(
            label: "Values",
            value: e.showValues,
            onChanged: (v) => now(e.copyWith(showValues: v)),
          ),
        ],
        more: [
          // How finely the value axis is ruled. Zero is the chart's own
          // judgement, which is right until somebody wants the gridlines
          // closer together or a taller chart ruled less often.
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
          // The colour the rules are drawn in, behind the same button. It was
          // in a section called Style, two headings away from the switch it
          // belongs to.
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
    // each of them can be on the line below it. Everything on one level was
    // twenty controls of equal weight, where the title somebody came to type
    // sat between a colour and a gap.
    CanvasControlGroup(
        label: "Title, description and labels",
        // No line under it. What follows is the same heading's second line --
        // the two words naming the axes -- split off only because it carries
        // a button of its own.
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
              (v) => e.copyWith(titleSpec: e.titleSpec.copyWith(fontSize: v))),
          const CanvasLineBreak(),
          // Under the title, not on top of it. A description above a title
          // is almost never what anybody means, and two labels placed at
          // the same corner is what that looked like.
          //
          // Its own size, not the label size it starts at. Sharing meant
          // making the description bigger made the numbers up the side of
          // the chart bigger with it.
          ...labelControls(
              "Description",
              e.description,
              e.descriptionBox,
              defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty),
              e.descriptionText.fontSize,
              (v) => e.copyWith(description: v),
              (b) => e.copyWith(descriptionBox: b),
              (v) => e.copyWith(
                  descriptionSpec: e.descriptionText.copyWith(fontSize: v))),
        ]),
    // The two words naming the axes, each with the switch that shows it
    // beside it. Everything about how the writing on the axes looks --
    // its colour, its size, the gap it keeps -- is behind the button.
    if (!e.type.isCircular)
      CanvasMoreGroup(
        label: "X and Y labels",
        // Under the title and the description, with no caption of its own
        // and no rule after it: the writing on the chart is one run of lines,
        // not four groups.
        hideCaption: true,
        rule: false,
        remember: "chartAxisLabelsMore",
        tooltip: "How the writing on the axes looks",
        row: [
          // The axis name is the empty field's placeholder, and the
          // switch beside it is named after the axis rather than
          // "Show" -- two fields and two switches all reading "Show"
          // is four controls telling you nothing about which is which.
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
          // A switch rather than emptying the field, so a chart can be
          // shown without its axis titles and have them back without
          // anybody typing them again.
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
            // Narrow, so the two fields, their two switches and the button
            // stay on one line in a sidebar somebody has pulled in.
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
          // The two words naming the axes have their own size and their
          // own distance from the plot. Their own size, because making
          // the figures up the side smaller used to shrink the words
          // with them; their own distance, because how much air a design
          // wants around them is a layout decision and not one a drawing
          // routine can make.
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
              write(e.copyWith(axisSpec: e.axisText.copyWith(fontSize: v)));
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
          // One switch each for the tick values. It was one for both, on
          // the grounds that they are read together or not at all --
          // often enough they are not: a bar chart named by its
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
              // What it is actually written at, so the field is never a
              // bare nought that has to be decoded. It takes the label
              // size until it is given one of its own.
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
    // How a number is written, wherever this chart writes one. Its own line
    // under the grid's and not behind its button: a pie rules nothing and
    // still writes numbers on its slices.
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
          // Rings a few pixels thick have nowhere to write a number and no axis
          // to read one against, so theirs go in the key -- which is no use with
          // the key switched off.
          if (e.type == ChartType.radialBar &&
              !(e.showLegend && e.legend.values))
            const CanvasHint(
                "A radial bar has no room to write a number on and no axis to "
                "read one against, so its values go in the legend. Switch the "
                "legend on, and its values with it, to see them."),
          // The example beside each name is what a million looks like in it,
          // because these are far easier to tell apart by their answers than
          // by their names -- which is also why it needs no caption. A box
          // reading "In full — 1,000,000.00" has said what it is for.
          CanvasDropdown<NumberStyle>(
            label: "",
            value: e.numbers.style,
            width: 176,
            options: [
              for (var style in NumberStyle.values)
                (
                  style,
                  // What a million would actually look like *as this chart
                  // is set*, rather than a fixed example. Listed as a fixed
                  // one, "Millions — 1.0M" reads as the only thing millions
                  // can be, and the places beside it look like something
                  // else's setting -- which is exactly how somebody with
                  // 1.00M in mind concludes they cannot have it.
                  //
                  // Automatic keeps its own, because what it does is vary:
                  // one example would be a promise it does not make.
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
          // Automatic decides its own, so a box saying "1" under it would
          // be a control that does nothing.
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
            // The axis reads the same as the values until somebody says
            // otherwise, because they are the same numbers. Said otherwise,
            // it is the usual pairing: an exact reading on the bar, a round
            // number on the scale.
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
                onChanged: (v) => now(
                    e.copyWith(axisNumbers: e.axisFigures.copyWith(style: v))),
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
              onChanged: (v) =>
                  now(e.copyWith(numbers: e.numbers.copyWith(separators: v))),
            ),
            CanvasHint("A million is written "
                "\"${e.numbers.format(1000000)}\" on the bars and in the "
                "legend, and \"${e.axisFigures.format(1000000)}\" up the "
                "side. Zero places leaves no decimal point at all."),
          ],
        ]),
    // Where the key goes, and whether the words on the chart take room from
    // it. Below the numbers because it is the last thing anybody sets: what
    // the chart says, then how it is measured, then how it is written, then
    // where the key for all of it sits.
    CanvasMoreGroup(
      label: "Legend",
      hideCaption: true,
      remember: "chartLegendMore",
      tooltip: "The key's own settings",
      row: [
        // The one switch for all three of them. Taking room is what made
        // every one of their settings a setting that resized the chart.
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
        CanvasToggle(
          key: const ValueKey("chartShowLegend"),
          label: "Legend",
          value: e.showLegend,
          onChanged: (v) => now(e.copyWith(showLegend: v)),
        ),
      ],
      more: [
        if (e.showLegend && e.floatingLabels && e.legend.hasPlace)
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
          // The colour of everything written in the label type -- the
          // legend, a pie's slice names. It lives here because the legend
          // is where most of that writing is.
          CanvasColorButton(
            key: const ValueKey("chartFigureColour"),
            label: "Figures",
            color: e.labelSpec.color,
            gradient: e.labelSpec.fade,
            onChanged: (c) {
              begin();
              write(e.copyWith(labelSpec: e.labelSpec.copyWith(color: c)));
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
          // Its own switch, not the chart's. A bar chart may want numbers
          // on its bars and a key without them, and a radial bar has
          // nowhere to put a number except the key.
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
              onChanged: (v) =>
                  now(e.copyWith(legend: e.legend.copyWith(separator: v))),
            ),
          const CanvasHint(
              "Size is measured against the chart's own label size, so "
              "the key stays in proportion when those are changed. "
              "Spacing is the gap between one entry and the next."),
        ],
      ],
    ),
    boxed(
      context,
      CanvasExpander(
        label: "Animation",
        remember: "chartAnimation",
        trailing: e.animation.on
            ? (e.animation.closes
                ? "${e.animation.preset.label} · ${e.animation.exit.label}"
                : e.animation.preset.label)
            : (e.animation.closes ? e.animation.exit.label : null),
        children: [
          // The same group every other element's animation section carries:
          // the easing belongs to the keyframe, and a chart's keyframes are
          // keyframes like any other.
          keyframeEasingGroup(controller, e, begin, commit),
          const CanvasHint(
              "Choosing one draws the chart on over two seconds and puts a "
              "keyframe at each end of it on the timeline. Drag those to "
              "decide how long it takes and when it happens — the same two "
              "keyframes a headline uses, so a chart and the words above it "
              "can arrive together."),
          // A dropdown rather than a row of switches, which is what this was.
          // Switches say "any number of these", and only one of them can be
          // on; the one that is on is also the hardest to find, since it
          // looks like the seven that are not. It is one choice out of a
          // list, which is what a dropdown is for -- and it now reads the
          // same as every other element's animation section.
          CanvasControlGroup(label: "Arriving", children: [
            CanvasDropdown<ChartAnimationPreset>(
              key: const ValueKey("chartAnimationPreset"),
              label: "Draws on",
              value: e.animation.preset,
              width: 168,
              options: [
                for (var preset in ChartAnimationPreset.values)
                  if (preset == ChartAnimationPreset.none ||
                      (e.type.isCircular
                          ? preset.suitsCircular
                          : preset.suitsCartesian))
                    (
                      preset,
                      preset == ChartAnimationPreset.none
                          ? "None"
                          : preset.label
                    ),
              ],
              // Choosing applies it and lays the keyframes together: a preset
              // with nothing pinning the reveal channel draws exactly what a
              // still chart draws.
              onChanged: (preset) => controller.applyChartAnimation(e, preset),
            ),
          ]),
          // The way out, using the same presets played backwards. A second
          // list of "fade out, shrink away, unwipe" would be this list
          // reversed and two lists to keep in step.
          // Always offered, unlike the text element's, which hides this until
          // something arrives. A chart that is there from the first frame and
          // leaves at the end is an ordinary thing to want, and it was
          // possible here before.
          CanvasControlGroup(label: "Leaving", children: [
            CanvasDropdown<ChartAnimationPreset>(
              key: const ValueKey("chartAnimationExit"),
              label: "Goes off",
              value: e.animation.exit,
              width: 168,
              options: [
                for (var preset in ChartAnimationPreset.values)
                  if (preset == ChartAnimationPreset.none ||
                      (e.type.isCircular
                          ? preset.suitsCircular
                          : preset.suitsCartesian))
                    (
                      preset,
                      preset == ChartAnimationPreset.none
                          ? "None"
                          : "${preset.label}, reversed"
                    ),
              ],
              onChanged: (preset) => controller.applyChartExit(e, preset),
            ),
            // Which end it starts from, which is a different question from
            // which preset. Reversed is the entrance run backwards, so the
            // last bar sinks first and the chart unwinds; in order runs the
            // same shrinking front to back, so it empties from the left.
            if (e.animation.closes)
              CanvasToggle(
                label: "In the same order",
                value: e.animation.exitInOrder,
                onChanged: (v) => now(e.copyWith(
                    animation: e.animation.copyWith(exitInOrder: v))),
              ),
            if (e.animation.closes)
              const CanvasHint(
                  "A second pair of keyframes at the end of the timeline, "
                  "so the chart arrives, sits there, and leaves. The two "
                  "ends of each pair are joined on the strip below: drag "
                  "the bar to move both, or either mark to change how long "
                  "it takes."),
            if (e.animation.closes && e.animation.exit.staggers)
              CanvasHint(e.animation.exitInOrder
                  ? "The first bar goes first and the last goes last, so "
                      "the chart empties the way it filled."
                  : "The last bar goes first, which is the entrance played "
                      "backwards — the chart unwinds. Switch it on above to "
                      "empty it from the front instead."),
          ]),
          if (e.animation.on || e.animation.closes)
            CanvasControlGroup(label: "Timing", children: [
              CanvasNumberField(
                key: const ValueKey("chartAnimationLength"),
                label: "Length",
                min: 1,
                max: 3600,
                decimals: 0,
                width: 62,
                value: (e.animation.length > 0
                        ? e.animation.length
                        : controller.defaultAnimationFrames)
                    .toDouble(),
                onChanged: (v) {
                  begin();
                  write(e.copyWith(
                      animation: e.animation.copyWith(length: v.round())));
                },
                onCommit: commit,
              ),
              CanvasDropdown<ChartEase>(
                key: const ValueKey("chartAnimationEase"),
                label: "Curve",
                value: e.animation.ease,
                width: 118,
                options: [for (var c in ChartEase.values) (c, c.label)],
                onChanged: (v) =>
                    now(e.copyWith(animation: e.animation.copyWith(ease: v))),
              ),
              // Only where there is more than one thing to space out. A wipe
              // and a sweep are one edge crossing everything at once.
              if (e.animation.preset.staggers || e.animation.exit.staggers)
                CanvasNumberField(
                  key: const ValueKey("chartAnimationGap"),
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
              const CanvasHint(
                  "Length is how many frames a new arrival or exit is laid "
                  "down with. Once it is on the timeline the keyframes are "
                  "where it is: changing this does not move them, and neither "
                  "does trying another preset."),
              if (e.animation.preset.staggers || e.animation.exit.staggers)
                const CanvasHint(
                    "Gap is how long after one bar starts before the next "
                    "does, as a share of one bar's own movement. 1 is "
                    "strictly one after another; below 1 they overlap; above "
                    "1 leaves a pause between them. It is shared by the way "
                    "in and the way out."),
            ]),
        ],
      ),
    ),
  ];
}
