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
          // The type first. What the numbers are drawn as is the first
          // decision about them and it was at the top of the panel, three
          // sections away from the numbers themselves.
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
            // Four series, not one, and named rather than counted where the names
            // say which is which. Said here because a candlestick chart with three
            // series draws nothing at all, which reads as broken.
            if (e.type.needsFourSeries && e.data.series.length < 4)
              const CanvasHint(
                  "Candlesticks need four series — the open, the high, the low and "
                  "the close. Name them and the order does not matter; unnamed, "
                  "the first four are taken in that order. CoinGecko's OHLC preset "
                  "under Data source fills all four in."),
          ]),
          ChartDataEditor(
            data: e.data,
            chartType: e.type,
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
          // And how it looks, at the foot of the section that decides what it
          // is: the colours and the weights are about this drawing of these
          // numbers rather than about the words on it.
          // Split by what each setting is about, rather than one long run of
          // everything.
          //
          // It was one run, and it read as a jumble because it is four
          // unrelated questions: what colour the rules are, how bars are
          // shaped, how lines are drawn, and whether the readings are marked.
          // Worse, the chart's own line width sat in the middle of it while
          // each series' width sat in the series list, so the two looked like
          // the same setting in two places.
          CanvasControlGroup(label: "Style", children: [
            CanvasColorButton(
              label: "Grid",
              color: e.gridColor,
              onChanged: (c) => now(e.copyWith(gridColor: c)),
            ),
            // On a candlestick the colour is the reading rather than a label
            // for a series, so the two of them belong with the chart's own
            // style and not in the series list.
            if (e.type.isCandles) ...[
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
            ],
          ]),
          // Bars, Lines and Points used to be three groups here. They are on
          // the series now, behind each series' own button, because a chart
          // of bars with a line over it made them three groups that were each
          // about half of the chart and said nothing about which half.
          //
          // Candlesticks are the exception, and stay. A candlestick's four
          // series are the open, high, low and close of one drawing -- the
          // bodies belong to the chart the way the up and down colours above
          // do, and there is no "the series that is drawn as bars" to put
          // them behind.
          if (e.type.isCandles)
            CanvasControlGroup(label: "Bodies", children: [
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
            ]),
        ],
      ),
    ),
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
          // The writing along the axes belongs with the rest of the writing.
          // It was a bare group at the top of the panel, above three
          // sections, which is a strange place for the switch that hides the
          // category names.
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
              // Beside the words it shows. A switch rather than emptying the
              // field, so a chart can be shown without its axis titles and
              // have them back without anybody typing them again. The tick
              // values are Axes labels' business, below.
              if (e.xAxisLabel.isNotEmpty)
                CanvasToggle(
                  key: const ValueKey("chartShowXTitle"),
                  label: "Show",
                  value: e.showXTitle,
                  onChanged: (v) => now(e.copyWith(showXTitle: v)),
                ),
              CanvasTextField(
                label: "Y label",
                value: e.yAxisLabel,
                width: 108,
                onChanged: (v) => write(e.copyWith(yAxisLabel: v)),
                onCommit: commit,
              ),
              if (e.yAxisLabel.isNotEmpty)
                CanvasToggle(
                  key: const ValueKey("chartShowYTitle"),
                  label: "Show",
                  value: e.showYTitle,
                  onChanged: (v) => now(e.copyWith(showYTitle: v)),
                ),
              // The two words naming the axes have their own size and their
              // own distance from the plot. Their own size, because making
              // the figures up the side smaller used to shrink the words with
              // them; their own distance, because how much air a design wants
              // around them is a layout decision and not one a drawing
              // routine can make.
              // The two label types had a size and a gap and no colour at
              // all, so a chart on a pale background wrote its figures in
              // whatever the default was and there was nowhere to say
              // otherwise.
              // The colour both axes take until one of them is given its
              // own, and the colour of everything else written in the label
              // type -- the legend, a pie's slice names.
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
              // One switch each. It was one for both, on the grounds that
              // they are read together or not at all -- often enough they are
              // not: a bar chart named by its categories does not always want
              // the figures up the side as well.
              //
              // By axis rather than by what is written there, because which
              // of the two an axis carries depends on which way the chart is
              // drawn: on horizontal bars the categories run up the side.
              const CanvasLineBreak(),
              CanvasToggle(
                key: const ValueKey("chartShowXLabels"),
                label: "X labels",
                value: e.showXLabels,
                onChanged: (v) => now(e.copyWith(showXLabels: v)),
              ),
              if (e.showXLabels) ...[
                CanvasNumberField(
                  key: const ValueKey("chartXLabelSize"),
                  label: "Size",
                  // What it is actually written at, so the field is never a
                  // bare nought that has to be decoded. See Figures below for
                  // what it takes until it is given one of its own.
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
                label: "Y labels",
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
              const CanvasLineBreak(),
              CanvasToggle(
                label: "Log scale",
                value: e.logScale,
                onChanged: (v) => now(e.copyWith(logScale: v)),
              ),
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
              CanvasHint(e.axisSteps == 0
                  ? "Lines is how many gridlines rule the value axis. 0 lets "
                      "the chart decide, which is about five."
                  : e.logs
                      ? "On a log axis the lines are powers of ten, so this "
                          "is how many of them are worth labelling — there "
                          "is nothing between two decades to move."
                      : "Near enough, not exactly: the lines have to land on "
                          "numbers somebody can read, so a chart that cannot "
                          "give you seven round ones gives six or eight "
                          "rather than seven awkward ones."),
            ],
            CanvasToggle(
              label: "Values",
              value: e.showValues,
              onChanged: (v) => now(e.copyWith(showValues: v)),
            ),
            const CanvasLineBreak(),
            // How a number is written, wherever this chart writes one. The
            // example beside each name is what a million looks like in it,
            // because these are far easier to tell apart by their answers
            // than by their names.
            CanvasDropdown<NumberStyle>(
              label: "Numbers",
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
                onChanged: (v) =>
                    now(e.copyWith(numbers: e.numbers.copyWith(separators: v))),
              ),
              CanvasHint("A million is written "
                  "\"${e.numbers.format(1000000)}\" on the bars and in the "
                  "legend, and \"${e.axisFigures.format(1000000)}\" up the "
                  "side. Zero places leaves no decimal point at all."),
            ],
            if (!e.type.isCircular)
              const CanvasHint(
                  "Axes labels is everything written along the axes: the numbers, "
                  "the category names and the two titles above. They are read "
                  "together or not at all."),
            // Switched on over data it cannot describe, a log scale would simply
            // do nothing -- which reads as a broken switch. Said here instead.
            if (e.logScale && !e.type.isCircular && !e.positiveOnly)
              const CanvasHint(
                  "A log scale needs every number above zero — there is no place "
                  "on one for zero or a negative — so this chart is still drawn "
                  "evenly. It rules the axis by decades, each gridline ten times "
                  "the one below, which is what makes something that has grown a "
                  "thousandfold readable at both ends."),
            // Rings a few pixels thick have nowhere to write a number and no axis
            // to read one against, so theirs go in the key -- which is no use with
            // the key switched off.
            if (e.type == ChartType.radialBar &&
                !(e.showLegend && e.legend.values))
              const CanvasHint(
                  "A radial bar has no room to write a number on and no axis to "
                  "read one against, so its values go in the legend. Switch the "
                  "legend on, and its values with it, to see them."),
          ]),
          // No caption: the field says which it is when it is empty, and
          // what it says when it is not.
          CanvasControlGroup(label: "Title", hideCaption: true, children: [
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
              hideCaption: true,
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
          CanvasControlGroup(label: "Labels", hideCaption: true, children: [
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
    // Where the numbers come from, which is three sections: the source
    // itself, the columns it maps, and the fields built out of them. The
    // link to a table on this canvas is inside the first of them, because it
    // answers the same question.
    chartSourceSection(context, controller, e, write, begin, commit),
    // Its own section, like the data. An animation is a handful of choices
    // made once and then left alone, and open by default they were four more
    // rows between the numbers and the axes.
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
