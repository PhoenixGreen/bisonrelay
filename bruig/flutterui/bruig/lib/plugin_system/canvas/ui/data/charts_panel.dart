part of 'data_charts_design.dart';

// The panel: the Studio's sidebar, the part picked in its header, and the
// chart's own settings. Part of ChartsDesignState: its fields, lifecycle and
// build are in data_charts_design.dart.

extension ChartsPanel on ChartsDesignState {
  String _pickName(ChartPick p) {
    var data = e.data;
    String seriesName(int s) =>
        s >= 0 && s < data.series.length ? data.series[s].name : "Series";
    return switch (p.kind) {
      "chart" => "Chart",
      "title" => "Title",
      "description" => "Description",
      "legend" => "Key",
      "plot" => "Plot",
      "xLabels" => "Labels along",
      "yLabels" => "Numbers up",
      "series" => seriesName(p.series),
      "mark" => _markLabel(p.index),
      "highlight" => "Highlight",
      "note" => "Note",
      _ => "Chart",
    };
  }

  Widget _panel(BuildContext context) {
    var p = _picked;
    var data = e.data;
    String seriesName(int s) =>
        s >= 0 && s < data.series.length ? data.series[s].name : "Series";
    var title = switch (p.kind) {
      "chart" => e.name.isEmpty ? "The whole chart" : e.name,
      "title" => "Title",
      "description" => "Description",
      "legend" => "Key",
      "plot" => "Plot",
      "xLabels" => "Labels along",
      "yLabels" => "Numbers up",
      "series" => seriesName(p.series),
      "mark" when data.panels.isNotEmpty => _markLabel(p.index),
      "mark" =>
        p.index < data.categories.length ? data.categories[p.index] : "Mark",
      "highlight" => _highlightName(e.highlights[p.index]),
      "note" => switch (e.notes[p.index].kind) {
          ChartNoteKind.line => "Line",
          ChartNoteKind.band => "Band",
          ChartNoteKind.label => "Label",
          ChartNoteKind.callout => "Callout",
          ChartNoteKind.arrow => "Arrow",
          ChartNoteKind.bracket => "Bracket",
        },
      _ => "Chart",
    };
    // Chart › Pts › Arsenal: a mark is reached through its series.
    var trail = <ChartPick>[
      ChartPick.chart,
      if (p.kind == "mark") ChartPick("series", series: p.series),
      if (p.kind != "chart") p,
    ];
    var (quick, body) = switch (p.kind) {
      "chart" => _chartPanel(context),
      "title" => _titlePanel(context),
      "description" => _descriptionPanel(context),
      "legend" => _legendPanel(context),
      "plot" => _plotPanel(context),
      "xLabels" => _axisPanel(context, x: true),
      "yLabels" => _axisPanel(context, x: false),
      "series" => _seriesPanel(context, p.series),
      "mark" => _markPanel(context, p.series, p.index),
      "highlight" => _highlightPanel(context, p.index),
      "note" => _notePanel(context, p.index),
      _ => (const <Widget>[], const <Widget>[]),
    };
    return StudioSide(
      header: StudioSideHeader(
        icon: switch (p.kind) {
          "highlight" => Icons.star_outline,
          "note" => Icons.push_pin_outlined,
          "title" || "description" => Icons.title,
          _ => Icons.bar_chart,
        },
        crumbs: [
          for (var (i, step) in trail.indexed)
            (
              _pickName(step),
              i == trail.length - 1 ? null : () => _pick(step),
            ),
        ],
        crumbKey: "chartsCrumb",
        title: title,
        titleKey: const ValueKey("chartsTitle"),
        onUp: p.kind == "chart"
            ? null
            : () => _pick(p.kind == "mark"
                ? ChartPick("series", series: p.series)
                : ChartPick.chart),
      ),
      scrollKey: ValueKey("chartsPanel-${p.kind}"),
      quick: quick,
      body: body,
    );
  }

  /// _markLabel is mark [i]'s category, or on a split chart, its panel.
  String _markLabel(int i) {
    var data = e.data;
    if (data.panels.isNotEmpty) {
      return i >= 0 && i < data.panels.length ? data.panels[i].name : "";
    }
    return i >= 0 && i < data.categories.length ? data.categories[i] : "";
  }

  Widget _hint(BuildContext context, String text) => CanvasHint(text);

  /// _styleColours are the colours of the chart's style, offered first.
  List<Color> get _styleColours {
    var s = dataStyleNamed(e.style);
    if (s == null) {
      return [for (var x in e.data.series.take(6)) x.color];
    }
    return [s.ink, s.dim, s.accent, s.grid, ...s.palette.take(6)];
  }

  Widget _swatches(
          String id, String label, Color value, ValueChanged<Color> set) =>
      StudioColourField(
          id: id,
          label: label,
          value: value,
          styleColours: _styleColours,
          palette: _palette,
          asMade: false,
          onPick: (v) {
            if (v.a > 0) set(v);
          });

  Widget _slider(String label, double value, double min, double max,
          double rest, void Function(double) live,
          {int decimals = 0, double? step, bool percent = false}) =>
      studioStepper(
          key: ValueKey("chartsSlider-$label"),
          label: label,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          rest: rest,
          decimals: decimals,
          step: step,
          percent: percent,
          onChanged: live,
          onCommit: _end);

  Widget _field(Widget f) => SizedBox(width: double.infinity, child: f);

  /// _menu is a choice among many, as the kit's dropdown.
  Widget _menu<T>(Key key, String label, T value, List<(T, String)> options,
          ValueChanged<T> onChanged) =>
      studioDrop<T>(
          key: key,
          label: label,
          value: options.any((o) => o.$1 == value)
              ? value
              : (options.isEmpty ? value : options.first.$1),
          options: options,
          onChanged: onChanged);

  (List<Widget>, List<Widget>) _chartPanel(BuildContext context) {
    var l = _link;
    var st = dataStyleNamed(e.style);
    var ways = chartModes[e.type.name];
    var kind = _kindParts(context);
    var named = <(String, String, String)>[
      ("title", "Title", e.title.trim().isEmpty ? "none" : "shown"),
      (
        "description",
        "Description",
        e.description.trim().isEmpty ? "none" : "shown"
      ),
      ("legend", "Key", e.showLegend ? "shown" : "hidden"),
      ("plot", "Grid and axes", e.showGrid ? "grid" : "no grid"),
      ("xLabels", "Labels along", e.showXLabels ? "shown" : "hidden"),
      ("yLabels", "Numbers up", e.showYLabels ? "shown" : "hidden"),
    ];
    return (
      [
        studioRow([
          _menu<String>(
              const ValueKey("chartsQuickStyle"), "Style", st?.name ?? "", [
            if (st == null) ("", "Its own"),
            for (var s in dataStyles) (s.name, s.name),
          ], (name) {
            if (dataStyleNamed(name) case var s?) {
              _set(chartInStyle(e, s, panel: e.panel.a > 0 || e.style.isEmpty));
            }
          }),
          studioSeg<bool>(
              id: "chartsGround",
              label: "Ground",
              value: e.panel.a > 0,
              options: const [(true, "Its own"), (false, "Canvas")],
              onChanged: (v) => _set(e.copyWith(
                  panel: v
                      ? (dataStyleNamed(e.style)?.ground ??
                          const Color(0xFFFFFFFF))
                      : const Color(0x00000000)))),
        ]),
        if (ways != null) ...[
          const SizedBox(height: 8),
          studioRow([
            _menu<String>(
                const ValueKey("chartsMode"),
                "Drawn as",
                modeOf(e.design, e.type.name),
                [for (var (m, says) in ways) (m, says)],
                (m) => _set(e.copyWith(design: e.design.copyWith(mode: m)))),
          ]),
        ],
        // A timeline's events by their dates, or evenly in order with the
        // time between them written in the gaps.
        if (e.type == ChartType.timeline) ...[
          const SizedBox(height: 4),
          StudioSwitchRow(
              key: const ValueKey("chartsEven"),
              label: "Evenly spaced",
              note: "the time between written in",
              value: e.design.even,
              onChanged: (v) =>
                  _set(e.copyWith(design: e.design.copyWith(even: v)))),
        ],
        if (l.charted) ...[
          const SizedBox(height: 8),
          const StudioNote(
              "Read as only a chart can (grouped, by places, one date at a "
              "time): its numbers are worked out from the sheet and not "
              "written back to it."),
        ],
      ],
      [
        studioSection(
            remember: "charts.style",
            icon: Icons.palette_outlined,
            title: "Style",
            summary: [
              st?.name ?? "Its own",
              e.panel.a > 0 ? "its own ground" : "the canvas behind it",
            ].join(" · "),
            children: [
              studioGroup(
                  "",
                  [
                    // The six styles.
                    DataStylePicker(
                        key: const ValueKey("chartsStyles"),
                        element: e,
                        onPick: (s) => _set(chartInStyle(e, s,
                            panel: e.panel.a > 0 || e.style.isEmpty))),
                    // The page around it too: every chart, table and word on
                    // it, and its ground (page_style.dart).
                    if (st != null)
                      studioButton("The whole page in ${st.name}",
                          key: const ValueKey("chartsStylePage"),
                          icon: Icons.auto_awesome,
                          tooltip: "Every chart, table and word on this page, "
                              "and its ground, as one step to undo",
                          onPressed: () {
                        _end();
                        c.stylePage(st);
                      }),
                  ],
                  help: "A style sets its colours, typefaces and corners; "
                      "the data and your words stay. Its own ground keeps a "
                      "dark style readable on a light page."),
            ]),
        studioSection(
            remember: "charts.highlights",
            icon: Icons.star_outline,
            title: "Highlights",
            count: e.highlights.length,
            summary: e.highlights.isEmpty
                ? "None"
                : [for (var h in e.highlights) _highlightName(h)].join(", "),
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    for (var (i, h) in e.highlights.indexed)
                      StudioItem(
                        key: ValueKey("chartsHighlight-$i"),
                        mark: studioDot(h.colour),
                        title: _highlightName(h),
                        subtitle:
                            h.fade ? "the rest faded" : "the rest as they are",
                        off: h.off,
                        lit: _hoverHighlight == i,
                        onHover: (on) =>
                            setState(() => _hoverHighlight = on ? i : null),
                        eyeKey: ValueKey("chartsHighlightEye-$i"),
                        onEye: () {
                          var all = [...e.highlights];
                          all[i] = h.copyWith(off: !h.off);
                          _set(e.copyWith(highlights: all));
                        },
                        onTap: () => _pick(ChartPick("highlight", index: i)),
                      ),
                    studioChips([
                      (
                        "+ The top 3",
                        const ValueKey("chartsAddHighlight"),
                        () => _addHighlight(const ChartHighlight(
                            reach: ChartReach.top, n: 3, fade: true))
                      ),
                      (
                        "+ One of them",
                        const ValueKey("chartsAddHighlightOne"),
                        () => _addHighlight(ChartHighlight(
                            who: _ranked(0), fade: true, named: true))
                      ),
                      (
                        "+ Above a number",
                        const ValueKey("chartsAddHighlightRule"),
                        () => _addHighlight(ChartHighlight(
                            reach: ChartReach.when,
                            op: ">=",
                            value: _middle(),
                            fade: true))
                      ),
                    ]),
                  ],
                  help: "A highlight follows the numbers: “top 3” lights "
                      "whoever is in the top three after a refresh."),
            ]),
        studioSection(
            remember: "charts.notes",
            icon: Icons.push_pin_outlined,
            title: "Notes",
            count: e.notes.length,
            summary: e.notes.isEmpty
                ? "None"
                : [for (var n in e.notes) ChartsDesignState._noteName(n)]
                    .join(", "),
            children: [
              studioGroup("", [
                for (var (i, n) in e.notes.indexed)
                  StudioItem(
                    key: ValueKey("chartsNote-$i"),
                    mark: studioDot(n.colour),
                    title: ChartsDesignState._noteName(n),
                    off: n.off,
                    eyeKey: ValueKey("chartsNoteEye-$i"),
                    onEye: () {
                      var all = [...e.notes];
                      all[i] = n.copyWith(off: !n.off);
                      _set(e.copyWith(notes: all));
                    },
                    onTap: () => _pick(ChartPick("note", index: i)),
                  ),
                studioChips([
                  (
                    "+ Average line",
                    const ValueKey("chartsAddAverage"),
                    () => _addNote(const ChartNote(text: "Average"))
                  ),
                  (
                    "+ Band",
                    const ValueKey("chartsAddBand"),
                    () => _addNote(ChartNote(
                        kind: ChartNoteKind.band,
                        from: 1,
                        to: math.min(3, math.max(1, e.data.categories.length)),
                        text: "Top",
                        colour: const Color(0xFF2FE08A)))
                  ),
                  // Bound by name: on the largest, or between the two
                  // largest.
                  (
                    "+ Callout",
                    const ValueKey("chartsAddCallout"),
                    () => _addNote(ChartNote(
                        kind: ChartNoteKind.callout, who: _ranked(0), text: ""))
                  ),
                  (
                    "+ Arrow",
                    const ValueKey("chartsAddArrow"),
                    () => _addNote(ChartNote(
                        kind: ChartNoteKind.arrow,
                        who: _ranked(0),
                        colour: const Color(0xFFFF7A59)))
                  ),
                  (
                    "+ Bracket",
                    const ValueKey("chartsAddBracket"),
                    () => _addNote(ChartNote(
                        kind: ChartNoteKind.bracket,
                        who: _ranked(1),
                        whom: _ranked(0),
                        colour: const Color(0xFF6FA4F8)))
                  ),
                ]),
              ]),
            ]),
        // Every part by name, found without hunting on the chart.
        studioSection(
            remember: "charts.parts",
            icon: Icons.widgets_outlined,
            title: "Parts",
            summary: "Title, key, grid, labels, numbers, "
                "${e.data.series.length == 1 ? e.data.series.first.name : "series"}",
            open: true,
            children: [
              studioGroup("", [
                studioParts([
                  for (var (k, name, says) in named)
                    StudioPartButton(
                        key: ValueKey("chartsPart-$k"),
                        label: name,
                        says: says,
                        onTap: () => _pick(ChartPick(k))),
                  for (var (s, series) in e.data.series.indexed)
                    StudioPartButton(
                        key: ValueKey("chartsPart-series-$s"),
                        label: series.name,
                        says: "its marks",
                        onTap: () => _pick(ChartPick("series", series: s))),
                ]),
                const StudioNote("Or click the part on the chart."),
              ]),
            ]),
        if (kind.isNotEmpty)
          studioSection(
              remember: "charts.shape",
              icon: Icons.donut_large,
              title: "Its shape",
              summary: e.type.label,
              open: true,
              children: kind),
        // Sharp at any size, its words still words.
        studioSection(
            remember: "charts.save",
            icon: Icons.save_alt,
            title: "Save it",
            summary: "As SVG or PDF, sharp at any size",
            children: [
              studioGroup(
                  "",
                  [
                    studioButtons([
                      for (var f in VectorFormat.values)
                        studioButton(f.label,
                            key: ValueKey("chartsSave-${f.extension}"),
                            icon: Icons.download_outlined,
                            tooltip: "This chart as it stands, as an "
                                "${f.label}: shapes and words, not pixels",
                            onPressed: () => saveVector(context, e, f,
                                ground: c.document.background.spec.background)),
                    ]),
                  ],
                  help: "Drawn as it finally stands. Its words stay words "
                      "and its shapes stay shapes, so it prints sharp and "
                      "can be edited in a drawing program. A gradient, a "
                      "blur or a picture in it goes in as a picture."),
            ]),
        studioSection(
            remember: "charts.motion",
            icon: Icons.animation,
            title: "Motion",
            summary: _playable
                ? (e.play <= 0
                    ? "Still"
                    : "${e.play.toStringAsFixed(1)}s a ${e.steps.length > 1 ? "step" : "date"}")
                : e.steps.length > 1
                    ? "${e.steps.length} steps"
                    : "Arrives, then still",
            children: _motionParts(context)),
      ]
    );
  }
}
