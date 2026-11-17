part of 'data_charts_design.dart';

// The panel for each part of a chart picked: title, description, legend, plot,
// numbers, axes, series, marks and highlights. Part of ChartsDesignState: its
// fields, lifecycle and build are in data_charts_design.dart.

extension ChartsPartPanels on ChartsDesignState {
  (List<Widget>, List<Widget>) _titlePanel(BuildContext context) => (
        [
          _field(_Field(
              key: const ValueKey("chartsTitleText"),
              text: e.title,
              hint: "A title",
              words: wordChoices(e.data),
              reads: (t) => liveWords(e.data, t),
              onChanged: (v) => _live(e.copyWith(title: v)))),
        ],
        [
          studioSection(
              remember: "charts.titleWords",
              icon: Icons.title,
              title: "Its words",
              summary:
                  "${e.titleSpec.fontFamily} · ${e.titleSpec.fontSize.round()}px",
              open: true,
              children: [
                studioGroup(
                    "",
                    _typeface(
                        "chartsTitleFont",
                        e.titleSpec,
                        (spec) => _set(e.copyWith(titleSpec: spec)),
                        _slider(
                            "Size",
                            e.titleSpec.fontSize,
                            8,
                            72,
                            24,
                            (v) => _live(e.copyWith(
                                titleSpec: e.titleSpec.copyWith(fontSize: v)))),
                        _swatches(
                            "chartsTitleInk",
                            "Colour",
                            e.titleSpec.color,
                            (v) => _set(e.copyWith(
                                titleSpec: e.titleSpec.copyWith(color: v))))),
                    help: "Words in { } are worked out from the numbers, and "
                        "change when they do."),
              ]),
        ]
      );

  (List<Widget>, List<Widget>) _descriptionPanel(BuildContext context) {
    var spec = e.descriptionText;
    return (
      [
        _field(_Field(
            key: const ValueKey("chartsDescriptionText"),
            text: e.description,
            hint: "A line under the title",
            words: wordChoices(e.data),
            reads: (t) => liveWords(e.data, t),
            onChanged: (v) => _live(e.copyWith(description: v)))),
      ],
      [
        studioSection(
            remember: "charts.descriptionWords",
            icon: Icons.short_text,
            title: "Its words",
            summary: "${spec.fontFamily} · ${spec.fontSize.round()}px",
            open: true,
            children: [
              studioGroup(
                  "",
                  _typeface(
                      "chartsDescriptionFont",
                      spec,
                      (next) => _set(e.copyWith(descriptionSpec: next)),
                      _slider(
                          "Size",
                          spec.fontSize,
                          6,
                          48,
                          e.labelSpec.fontSize,
                          (v) => _live(e.copyWith(
                              descriptionSpec: spec.copyWith(fontSize: v)))),
                      _swatches(
                          "chartsDescriptionInk",
                          "Colour",
                          spec.color,
                          (v) => _set(e.copyWith(
                              descriptionSpec: spec.copyWith(color: v)))))),
            ]),
      ]
    );
  }

  (List<Widget>, List<Widget>) _legendPanel(BuildContext context) => (
        [
          StudioSwitchRow(
              key: const ValueKey("chartsLegend"),
              label: "Show the key",
              value: e.showLegend,
              onChanged: (v) => _set(e.copyWith(showLegend: v))),
        ],
        [
          if (e.showLegend)
            studioSection(
                remember: "charts.legend",
                icon: Icons.list_alt,
                title: "Where and how",
                summary: [
                  e.legend.placement.label,
                  e.legend.vertical ? "one a line" : "in a row",
                ].join(" · "),
                open: true,
                children: [
                  studioGroup("", [
                    studioSeg<String>(
                        id: "chartsLegendPlace",
                        label: "Where",
                        value: e.legend.placement.name,
                        options: [
                          for (var p in LegendPlacement.values)
                            (p.name, p.label)
                        ],
                        onChanged: (v) => _set(e.copyWith(
                            legend: e.legend.copyWith(
                                placement: LegendPlacement.values.byName(v))))),
                    studioRow([
                      studioSeg<bool>(
                          id: "chartsLegendStack",
                          label: "Entries",
                          value: e.legend.vertical,
                          options: const [
                            (false, "In a row"),
                            (true, "One a line")
                          ],
                          onChanged: (v) => _set(e.copyWith(
                              legend: e.legend.copyWith(vertical: v)))),
                      _slider(
                          "Key size",
                          e.legend.scale,
                          0.5,
                          2,
                          1,
                          (v) => _live(
                              e.copyWith(legend: e.legend.copyWith(scale: v))),
                          percent: true,
                          step: 0.05),
                    ], flex: [
                      3,
                      2
                    ]),
                  ]),
                ]),
        ]
      );

  (List<Widget>, List<Widget>) _plotPanel(BuildContext context) {
    var design = _designParts(context);
    return (
      [
        StudioSwitchRow(
            key: const ValueKey("chartsGrid"),
            label: "Grid",
            value: e.showGrid,
            onChanged: (v) => _set(e.copyWith(showGrid: v))),
        StudioSwitchRow(
            key: const ValueKey("chartsAxes"),
            label: "Axes",
            value: e.showAxes,
            onChanged: (v) => _set(e.copyWith(showAxes: v))),
        StudioSwitchRow(
            key: const ValueKey("chartsValues"),
            label: "Values on the marks",
            value: e.showValues,
            onChanged: (v) => _set(e.copyWith(showValues: v))),
      ],
      [
        studioSection(
            remember: "charts.grid",
            icon: Icons.grid_4x4,
            title: "Grid and scale",
            summary: [
              e.showGrid ? "Grid" : "No grid",
              if (e.type.isCartesian) e.logScale ? "log scale" : "even steps",
            ].join(" · "),
            open: true,
            children: [
              studioGroup("", [
                if (e.showGrid)
                  studioRow([
                    _swatches("chartsGridColour", "Grid colour", e.gridColor,
                        (v) => _set(e.copyWith(gridColor: v))),
                    const SizedBox.shrink(),
                  ]),
                if (e.type.isCartesian)
                  studioSeg<bool>(
                      id: "chartsLogScale",
                      label: "Scale",
                      value: e.logScale,
                      options: const [
                        (false, "Even steps"),
                        (true, "Log (×10 a step)")
                      ],
                      onChanged: (v) => _set(e.copyWith(logScale: v))),
              ]),
            ]),
        studioSection(
            remember: "charts.marks",
            icon: Icons.bar_chart,
            title: "Marks",
            summary: [
              "corners ${e.barRadius.round()}",
              if (e.type.isBar || e.type == ChartType.lollipop)
                "gap ${(e.barGap * 100).round()}%",
            ].join(" · "),
            open: true,
            children: [
              studioGroup("", [
                studioRow([
                  _slider("Corners", e.barRadius, 0, 24, 0,
                      (v) => _live(e.copyWith(barRadius: v))),
                  if (e.type.isBar || e.type == ChartType.lollipop)
                    _slider("Gap between", e.barGap, 0, 0.9, 0.2,
                        (v) => _live(e.copyWith(barGap: v)),
                        percent: true, step: 0.05)
                  else
                    const SizedBox.shrink(),
                ]),
                ...design,
              ]),
            ]),
        studioSection(
            remember: "charts.numbers",
            icon: Icons.tag,
            title: "Numbers",
            summary: [
              e.numbers.style.label,
              "${e.numbers.decimals} decimals",
              if (e.numbers.before.isNotEmpty || e.numbers.after.isNotEmpty)
                "${e.numbers.before}1${e.numbers.after}",
            ].join(" · "),
            children: _numbersParts(context)),
      ]
    );
  }

  /// _designParts are how its marks are drawn beyond its type (ChartDesign):
  /// tracks, values inside, names above, steps, quadrants, trend, joins.
  List<Widget> _designParts(BuildContext context) {
    var d = e.design;
    void put(ChartDesign next) => _set(e.copyWith(design: next));
    Widget onOff(String id, String label, bool value,
            ChartDesign Function(bool) next) =>
        StudioSwitchRow(
            key: ValueKey(id),
            label: label,
            value: value,
            onChanged: (v) => put(next(v)));
    Widget two(String id, String label, bool value,
            ChartDesign Function(bool) next,
            {required String on, required String off}) =>
        studioSeg<bool>(
            id: id,
            label: label,
            value: value,
            options: [(true, on), (false, off)],
            onChanged: (v) => put(next(v)));
    return [
      if (e.type.isBar && !e.type.isStacked) ...[
        onOff("chartsTrack", "Tracks behind the bars", d.track,
            (v) => d.copyWith(track: v)),
        if (e.showValues)
          two("chartsValuesInside", "Values", d.valuesInside,
              (v) => d.copyWith(valuesInside: v),
              on: "Inside the bars", off: "Past the ends"),
      ],
      if (e.type == ChartType.horizontalBar)
        two("chartsLabelsAbove", "Names", d.labelsAbove,
            (v) => d.copyWith(labelsAbove: v),
            on: "Above each bar", off: "Beside"),
      if (e.type == ChartType.line)
        two("chartsStep", "Between points", d.step, (v) => d.copyWith(step: v),
            on: "Steps", off: "Straight or curved"),
      if (e.type == ChartType.scatter) ...[
        onOff("chartsQuadrants", "Quadrants", d.quadrants,
            (v) => d.copyWith(quadrants: v)),
        onOff(
            "chartsTrend", "Trend line", d.trend, (v) => d.copyWith(trend: v)),
        onOff("chartsConnect", "Points joined", d.connect,
            (v) => d.copyWith(connect: v)),
      ],
    ];
  }

  /// _numbersParts is how the chart writes its numbers: shortened or in
  /// full, decimals, and a sign or unit either side ("\$300", "40%").
  List<Widget> _numbersParts(BuildContext context) {
    var n = e.numbers;
    void put(ChartNumbers next) => _set(e.copyWith(numbers: next));
    return [
      studioGroup("", [
        studioRow([
          _menu<String>(
              const ValueKey("chartsNumberStyle"),
              "Written",
              n.style.name,
              [for (var st in NumberStyle.values) (st.name, st.label)],
              (v) => put(n.copyWith(style: NumberStyle.values.byName(v)))),
          studioSeg<int>(
              id: "chartsDecimals",
              label: "Decimals",
              value: n.decimals,
              options: const [(0, "0"), (1, "1"), (2, "2"), (3, "3")],
              onChanged: (v) => put(n.copyWith(decimals: v))),
        ]),
        studioRow([
          _field(_Field(
              key: const ValueKey("chartsNumberBefore"),
              text: n.before,
              hint: "Before: \$",
              onChanged: (v) =>
                  _live(e.copyWith(numbers: e.numbers.copyWith(before: v))))),
          _field(_Field(
              key: const ValueKey("chartsNumberAfter"),
              text: n.after,
              hint: "After: %",
              onChanged: (v) =>
                  _live(e.copyWith(numbers: e.numbers.copyWith(after: v))))),
        ]),
      ]),
    ];
  }

  (List<Widget>, List<Widget>) _axisPanel(BuildContext context,
          {required bool x}) =>
      (
        [
          StudioSwitchRow(
              key: ValueKey(x ? "chartsXShown" : "chartsYShown"),
              label: x ? "Show the labels" : "Show the numbers",
              value: x ? e.showXLabels : e.showYLabels,
              onChanged: (v) => _set(
                  x ? e.copyWith(showXLabels: v) : e.copyWith(showYLabels: v))),
        ],
        [
          studioSection(
              remember: x ? "charts.xWords" : "charts.yWords",
              icon: Icons.text_fields,
              title: "Their words",
              summary: [
                "${((x ? e.xLabelSize : e.yLabelSize) ?? e.labelSpec.fontSize).round()}px",
                "${(x ? e.xLabelGap : e.yLabelGap).round()} away",
                if (!x) "${e.axisSteps} steps",
              ].join(" · "),
              open: true,
              children: [
                studioGroup("", [
                  studioRow([
                    _slider(
                        "Size",
                        (x ? e.xLabelSize : e.yLabelSize) ??
                            e.labelSpec.fontSize,
                        6,
                        40,
                        e.labelSpec.fontSize,
                        (v) => _live(x
                            ? e.copyWith(xLabelSize: v)
                            : e.copyWith(yLabelSize: v))),
                    _swatches(
                        x ? "chartsXInk" : "chartsYInk",
                        "Colour",
                        (x ? e.xLabelColor : e.yLabelColor) ??
                            e.labelSpec.color,
                        (v) => _set(x
                            ? e.copyWith(xLabelColor: v)
                            : e.copyWith(yLabelColor: v))),
                  ]),
                  studioRow([
                    _slider(
                        "Distance",
                        x ? e.xLabelGap : e.yLabelGap,
                        0,
                        40,
                        0,
                        (v) => _live(x
                            ? e.copyWith(xLabelGap: v)
                            : e.copyWith(yLabelGap: v))),
                    if (!x)
                      _slider("Steps", e.axisSteps.toDouble(), 2, 12, 5,
                          (v) => _live(e.copyWith(axisSteps: v.round())))
                    else
                      const SizedBox.shrink(),
                  ]),
                ]),
              ]),
          studioSection(
              remember: x ? "charts.xTitle" : "charts.yTitle",
              icon: Icons.title,
              title: "Its title",
              summary: (x ? e.xAxisLabel : e.yAxisLabel).trim().isEmpty
                  ? "None"
                  : (x ? e.xAxisLabel : e.yAxisLabel),
              children: [
                studioGroup("", [
                  _field(_Field(
                      key: ValueKey(x ? "chartsXTitle" : "chartsYTitle"),
                      text: x ? e.xAxisLabel : e.yAxisLabel,
                      hint:
                          x ? "What runs along: Month" : "What goes up: Points",
                      onChanged: (v) => _live(x
                          ? e.copyWith(
                              xAxisLabel: v, showXTitle: v.trim().isNotEmpty)
                          : e.copyWith(
                              yAxisLabel: v,
                              showYTitle: v.trim().isNotEmpty)))),
                ]),
              ]),
        ]
      );

  (List<Widget>, List<Widget>) _seriesPanel(BuildContext context, int s) {
    if (s < 0 || s >= e.data.series.length) {
      return (const <Widget>[], const <Widget>[]);
    }
    var series = e.data.series[s];
    var linear = e.type.isLinear || e.type.usesSmooth;
    return (
      [
        studioRow([
          _swatches("chartsSeriesColour", "Colour", series.color, (v) {
            var all = [...e.data.series];
            all[s] = series.copyWith(color: v);
            _set(e.copyWith(data: e.data.copyWith(series: all)));
          }),
          const SizedBox.shrink(),
        ]),
        const SizedBox(height: 6),
        const StudioNote("A highlight or colour-by colours its own marks over "
            "this one. Click a mark again for that one alone."),
      ],
      [
        if (linear)
          studioSection(
              remember: "charts.line",
              icon: Icons.show_chart,
              title: "Its line",
              summary: [
                "${e.strokeWidth.toStringAsFixed(1)}px",
                if (e.type.usesSmooth) e.smooth ? "curved" : "straight",
                e.showPoints ? "points" : "no points",
              ].join(" · "),
              open: true,
              children: [
                studioGroup("", [
                  studioRow([
                    _slider("Line", e.strokeWidth, 0.5, 12, 2.5,
                        (v) => _live(e.copyWith(strokeWidth: v)),
                        decimals: 1, step: 0.5),
                    if (e.showPoints)
                      _slider("Point size", e.pointSize, 1, 16, 4,
                          (v) => _live(e.copyWith(pointSize: v)))
                    else
                      const SizedBox.shrink(),
                  ]),
                  if (e.type.usesSmooth)
                    studioSeg<bool>(
                        id: "chartsSmooth",
                        label: "Between points",
                        value: e.smooth,
                        options: const [(false, "Straight"), (true, "Curved")],
                        onChanged: (v) => _set(e.copyWith(smooth: v))),
                  StudioSwitchRow(
                      key: const ValueKey("chartsPoints"),
                      label: "Points",
                      value: e.showPoints,
                      onChanged: (v) => _set(e.copyWith(showPoints: v))),
                ]),
              ]),
        if (e.type.isCandles)
          studioSection(
              remember: "charts.candles",
              icon: Icons.candlestick_chart,
              title: "Up and down",
              open: true,
              children: [
                studioGroup("", [
                  studioRow([
                    _swatches("chartsRise", "Up", e.riseColor,
                        (v) => _set(e.copyWith(riseColor: v))),
                    _swatches("chartsFall", "Down", e.fallColor,
                        (v) => _set(e.copyWith(fallColor: v))),
                  ]),
                ]),
              ]),
      ]
    );
  }

  (List<Widget>, List<Widget>) _markPanel(BuildContext context, int s, int i) {
    var label = _markLabel(i);
    return (
      [
        studioButtons([
          studioButton("Highlight $label",
              key: const ValueKey("chartsHighlightMark"),
              icon: Icons.star_outline,
              primary: true,
              onPressed: () => _addHighlight(
                  ChartHighlight(who: label, fade: true, named: true))),
          studioButton("Label it",
              key: const ValueKey("chartsLabelMark"),
              icon: Icons.push_pin_outlined,
              onPressed: () => _addNote(ChartNote(
                  kind: ChartNoteKind.label,
                  who: label,
                  colour: const Color(0xFFFFFFFF)))),
          studioButton("Pick $label out everywhere",
              key: const ValueKey("chartsSpotlight"),
              icon: Icons.visibility_outlined,
              tooltip: "In every chart of this sheet, and its tables' rows",
              onPressed: () {
            var sheet = _sheet;
            if (sheet != null) c.setSheet(sheet.copyWith(spotlight: label));
          }),
          studioButton("Its series",
              key: const ValueKey("chartsMarkSeries"),
              onPressed: () => _pick(ChartPick("series", series: s))),
        ]),
      ],
      const <Widget>[]
    );
  }

  (List<Widget>, List<Widget>) _highlightPanel(BuildContext context, int i) {
    var h = e.highlights[i];
    void put(ChartHighlight next, {bool live = false}) {
      var all = [...e.highlights];
      all[i] = next;
      live
          ? _live(e.copyWith(highlights: all))
          : _set(e.copyWith(highlights: all));
    }

    var numberColumns = [
      for (var col in _columns)
        if (_numbers(col)) col
    ];
    var labels = [
      for (var l in e.data.categories)
        if (l != "…") l
    ];
    return (
      [
        _field(_Field(
            key: ValueKey("chartsHighlightName-$i"),
            text: h.name,
            hint: _highlightName(h.copyWith(name: "")),
            onChanged: (v) => put(h.copyWith(name: v), live: true))),
        const SizedBox(height: 8),
        _offDelete("Highlight", h.off, () => put(h.copyWith(off: !h.off)), () {
          _set(e.copyWith(highlights: [...e.highlights]..removeAt(i)));
          _pick(ChartPick.chart);
        }),
      ],
      [
        studioSection(
            remember: "charts.picksOut",
            icon: Icons.star_outline,
            title: "Picks out",
            summary: _highlightName(h.copyWith(name: "")),
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    studioSeg<ChartReach>(
                        id: "chartsReach",
                        value: h.reach,
                        options: [
                          for (var r in ChartReach.values) (r, r.label)
                        ],
                        onChanged: (v) => put(h.copyWith(
                            reach: v,
                            who: v == ChartReach.one &&
                                    h.who.isEmpty &&
                                    labels.isNotEmpty
                                ? labels.first
                                : null))),
                    if (h.reach == ChartReach.one)
                      studioRow([
                        _menu<String>(
                            const ValueKey("chartsWho"),
                            "Which",
                            labels.contains(h.who)
                                ? h.who
                                : (labels.firstOrNull ?? ""),
                            [for (var l in labels) (l, l)],
                            (v) => put(h.copyWith(who: v))),
                      ])
                    else
                      studioRow([
                        if (h.reach == ChartReach.top ||
                            h.reach == ChartReach.bottom)
                          _slider("How many", h.n.toDouble(), 1, 20, 3,
                              (v) => put(h.copyWith(n: v.round()), live: true))
                        else
                          _field(_Field(
                              key: ValueKey("chartsValue-$i"),
                              text: ChartsDesignState._num(h.value),
                              hint: "A number",
                              onChanged: (v) {
                                var n = double.tryParse(v.trim());
                                if (n != null) {
                                  put(h.copyWith(value: n), live: true);
                                }
                              })),
                        _menu<int>(
                            const ValueKey("chartsBy"),
                            "By",
                            h.by,
                            [
                              (-1, "Its first series"),
                              for (var col in numberColumns)
                                (col, _columnName(col)),
                            ],
                            (v) => put(h.copyWith(by: v))),
                      ]),
                    if (h.reach == ChartReach.when)
                      studioSeg<String>(
                          id: "chartsOp",
                          label: "Is",
                          value: h.op,
                          options: const [
                            (">=", "at least"),
                            ("<=", "at most"),
                            (">", "over"),
                            ("<", "under"),
                            ("=", "exactly"),
                          ],
                          onChanged: (v) => put(h.copyWith(op: v))),
                  ],
                  help: "Made like a table style: what it picks out, then "
                      "its look. Later highlights win where two pick out the "
                      "same mark."),
            ]),
        studioSection(
            remember: "charts.highlightLook",
            icon: Icons.palette_outlined,
            title: "Its look",
            summary: h.fade ? "The rest faded" : "The rest as they are",
            open: true,
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("chartsHighlightColour", "Colour", h.colour,
                      (v) => put(h.copyWith(colour: v))),
                  studioSeg<bool>(
                      id: "chartsFade",
                      label: "The rest",
                      value: h.fade,
                      options: const [(false, "As they are"), (true, "Faded")],
                      onChanged: (v) => put(h.copyWith(fade: v))),
                ], flex: [
                  2,
                  3
                ]),
              ]),
            ]),
      ]
    );
  }
}
