part of 'data_charts_design.dart';

// The panel's motion, kind, note and highlight settings. Part of
// ChartsDesignState: its fields, lifecycle and build are in
// data_charts_design.dart.

extension ChartsMotionPanels on ChartsDesignState {
  /// _middle is halfway up the first numbers, for a highlight above it.
  double _middle() {
    var d = e.data;
    if (d.series.isEmpty || d.categories.isEmpty) return 0;
    var v = [
      for (var i = 0; i < d.categories.length; i++)
        if (d.hasValueAt(0, i)) d.valueAt(0, i)
    ]..sort();
    return v.isEmpty ? 0 : v[v.length ~/ 2].roundToDouble();
  }

  void _addHighlight(ChartHighlight h) {
    _set(e.copyWith(highlights: [...e.highlights, h]));
    _pick(ChartPick("highlight", index: e.highlights.length));
  }

  /// _motionParts is how it moves once arrived: steps or dates, and pace.
  List<Widget> _motionParts(BuildContext context) => [
        if (e.steps.length > 1)
          studioGroup("", [
            _menu<String>(
                const ValueKey("chartsFollow"),
                "Steps move on with",
                e.follow,
                [for (var f in ChartStepsFollow.values) (f.name, f.label)],
                (v) => _set(e.copyWith(follow: v))),
            StudioNote(switch (ChartStepsFollow.fromName(e.follow)) {
              ChartStepsFollow.time =>
                "Once it has arrived, a step after another at the pace below.",
              ChartStepsFollow.marks =>
                "A step from each mark on the timeline. At a Stop mark the canvas waits, so in a presentation the next step comes at a click.",
              ChartStepsFollow.scenes =>
                "A step in each scene or page it is in: step 1 in the first, step 2 in the next. Put linked copies of it in the scenes after.",
              ChartStepsFollow.speech =>
                "A step as each line of the narration is spoken: timed by the voice. A camera aimed at what the narration names follows it.",
            }),
          ]),
        // The narration's lines as its steps (chart_story.dart): each
        // titled with its line, lighting the names it says.
        if (narrationLines(c.document) case var lines when lines.isNotEmpty)
          studioGroup("", [
            studioButton("Steps from the narration",
                key: const ValueKey("chartsStorySteps"),
                icon: Icons.record_voice_over_outlined,
                tooltip: "A step for each of its ${lines.length} lines, "
                    "lighting the names each says, taken as the line is "
                    "spoken",
                onPressed: () => _set(storySteps(e, lines))),
          ]),
        studioGroup("", [
          if (_playable &&
              (e.steps.length < 2 ||
                  e.follow == ChartStepsFollow.time.name)) ...[
            studioRow([
              studioStepper(
                  key: const ValueKey("chartsSlider-Each"),
                  label: e.steps.length > 1 ? "Each step" : "Each date",
                  value: e.play,
                  min: 0,
                  max: 6,
                  rest: 0,
                  decimals: 1,
                  step: 0.1,
                  suffix: "s",
                  onChanged: (v) =>
                      _live(e.copyWith(play: (v * 10).roundToDouble() / 10)),
                  onCommit: _end),
              const SizedBox.shrink(),
            ]),
            StudioNote(e.play <= 0
                ? "Still: it shows ${e.steps.length > 1 ? "this step" : "one date"}. Give it seconds and, once it has arrived on the canvas, it plays through them."
                : "Once it has arrived on the canvas it plays through its ${e.steps.length > 1 ? "steps" : "dates"}, ${e.play.toStringAsFixed(1)}s each: ${_sheet == null ? 0 : playLength(e, _sheet!).toStringAsFixed(1)}s in all. ▶ Preview, above the chart, shows it here."),
          ] else
            const StudioNote(
                "Play through a column of dates, or add steps, and it can move."),
        ]),
      ];

  /// _kindParts are settings only some kinds have: a pie's shape, a
  /// doughnut's hole and words, a pictogram's icons.
  List<Widget> _kindParts(BuildContext context) => [
        if (e.type == ChartType.pie || e.type == ChartType.donut)
          studioGroup("", [
            studioSeg<bool>(
                id: "chartsHalf",
                value: e.design.half,
                options: const [(false, "A whole circle"), (true, "An arch")],
                onChanged: (v) =>
                    _set(e.copyWith(design: e.design.copyWith(half: v)))),
            studioSeg<bool>(
                id: "chartsGaps",
                label: "Between the slices",
                value: e.design.gaps,
                options: const [(false, "Touching"), (true, "A gap")],
                onChanged: (v) =>
                    _set(e.copyWith(design: e.design.copyWith(gaps: v)))),
          ]),
        if (e.type == ChartType.donut || e.type == ChartType.gauge)
          studioGroup(e.type == ChartType.donut ? "Its middle" : "The dial", [
            studioRow([
              _slider("Hole", e.innerRadius, 0.2, 0.9, 0.55,
                  (v) => _live(e.copyWith(innerRadius: v)),
                  percent: true, step: 0.05),
              const SizedBox.shrink(),
            ]),
            _field(_Field(
                key: const ValueKey("chartsCentreWords"),
                text: e.centreLabel,
                hint: "Words in the middle: {total of Points}",
                words: wordChoices(e.data),
                reads: (t) => liveWords(e.data, t),
                onChanged: (v) => _live(e.copyWith(centreLabel: v)))),
          ]),
        if (e.type == ChartType.pictogram)
          studioGroup("Its icons", [
            studioRow([
              _menu<String>(
                  const ValueKey("chartsPictoShape"),
                  "Shape",
                  e.pictoShape.name,
                  [for (var p in PictoShape.values) (p.name, p.label)],
                  (v) => _set(e.copyWith(pictoShape: PictoShape.fromName(v)))),
              _slider("How many", e.pictoCount.toDouble(), 5, 100, 20,
                  (v) => _live(e.copyWith(pictoCount: v.round()))),
            ]),
          ]),
      ];

  /// _ranked is the name of the [n]th largest by the first numbers
  /// ("" where there are not that many).
  String _ranked(int n) {
    var d = e.data;
    if (d.series.isEmpty) return "";
    var order = [
      for (var i = 0; i < d.categories.length; i++)
        if (d.hasValueAt(0, i)) i
    ]..sort((a, b) => d.valueAt(0, b).compareTo(d.valueAt(0, a)));
    return n < order.length ? d.categories[order[n]] : "";
  }

  void _addNote(ChartNote note) {
    _set(e.copyWith(notes: [...e.notes, note]));
    _pick(ChartPick("note", index: e.notes.length));
  }

  /// _offDelete is a highlight's or a note's own two buttons.
  Widget _offDelete(
          String what, bool off, VoidCallback flip, VoidCallback delete) =>
      studioButtons([
        studioButton(off ? "Switch on" : "Switch off",
            key: ValueKey("charts${what}Off"),
            icon:
                off ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            onPressed: flip),
        studioButton("Delete",
            key: ValueKey("charts${what}Delete"),
            icon: Icons.delete_outline,
            onPressed: delete),
      ]);

  (List<Widget>, List<Widget>) _notePanel(BuildContext context, int i) {
    var n = e.notes[i];
    void put(ChartNote next, {bool live = false}) {
      var all = [...e.notes];
      all[i] = next;
      live ? _live(e.copyWith(notes: all)) : _set(e.copyWith(notes: all));
    }

    var count = math.max(1, e.data.categories.length);
    var bound = n.kind == ChartNoteKind.callout ||
        n.kind == ChartNoteKind.arrow ||
        n.kind == ChartNoteKind.label ||
        n.kind == ChartNoteKind.bracket;
    return (
      [
        _field(_Field(
            key: ValueKey("chartsNoteText-$i"),
            text: n.text,
            hint: n.kind == ChartNoteKind.label ? n.who : "Words beside it",
            words: wordChoices(e.data),
            reads: (t) => liveWords(e.data, t),
            onChanged: (v) => put(n.copyWith(text: v), live: true))),
        const SizedBox(height: 8),
        _offDelete("Note", n.off, () => put(n.copyWith(off: !n.off)), () {
          _set(e.copyWith(notes: [...e.notes]..removeAt(i)));
          _pick(ChartPick.chart);
        }),
      ],
      [
        studioSection(
            remember: "charts.noteWhere",
            icon: Icons.place_outlined,
            title: "Where",
            summary: switch (n.kind) {
              ChartNoteKind.line => n.value.isNaN
                  ? "At the average"
                  : "At ${ChartsDesignState._num(n.value)}",
              ChartNoteKind.band => "Places ${n.from}–${n.to}",
              ChartNoteKind.bracket => "${n.who} to ${n.whom}",
              _ => "On ${n.who}",
            },
            open: true,
            children: [
              // Which marks it is bound to, by name: it follows them.
              if (bound)
                studioGroup(
                    "",
                    [
                      studioRow([
                        _menu<String>(
                            ValueKey("chartsNoteWho-$i"),
                            n.kind == ChartNoteKind.bracket ? "From" : "On",
                            n.who,
                            [for (var c in e.data.categories) (c, c)],
                            (v) => put(n.copyWith(who: v))),
                        if (n.kind == ChartNoteKind.bracket)
                          _menu<String>(
                              ValueKey("chartsNoteWhom-$i"),
                              "To",
                              n.whom,
                              [for (var c in e.data.categories) (c, c)],
                              (v) => put(n.copyWith(whom: v)))
                        else
                          const SizedBox.shrink(),
                      ]),
                    ],
                    help: n.kind == ChartNoteKind.bracket
                        ? "Says the gap between them unless it has its own words."
                        : null),
              if (n.kind == ChartNoteKind.line)
                studioGroup("", [
                  studioSeg<bool>(
                      id: "chartsNoteAt",
                      label: "At",
                      value: n.value.isNaN,
                      options: const [
                        (true, "The average"),
                        (false, "A number")
                      ],
                      onChanged: (v) =>
                          put(n.copyWith(value: v ? double.nan : 0))),
                  if (!n.value.isNaN)
                    _field(_Field(
                        key: ValueKey("chartsNoteValue-$i"),
                        text: ChartsDesignState._num(n.value),
                        hint: "A number",
                        onChanged: (v) {
                          var x = double.tryParse(v.trim());
                          if (x != null) put(n.copyWith(value: x), live: true);
                        })),
                ]),
              if (n.kind == ChartNoteKind.band)
                studioGroup(
                    "",
                    [
                      studioRow([
                        _slider(
                            "From place",
                            n.from.toDouble(),
                            1,
                            count.toDouble(),
                            1,
                            (v) => put(
                                n.copyWith(
                                    from: v.round(),
                                    to: math.max(v.round(), n.to)),
                                live: true)),
                        _slider(
                            "To place",
                            n.to.toDouble(),
                            1,
                            count.toDouble(),
                            1,
                            (v) => put(
                                n.copyWith(
                                    to: v.round(),
                                    from: math.min(v.round(), n.from)),
                                live: true)),
                      ]),
                    ],
                    help: "Behind those places, whoever is in them: a "
                        "cut-off that stays put."),
            ]),
        studioSection(
            remember: "charts.noteLook",
            icon: Icons.palette_outlined,
            title: "Its look",
            summary:
                "#${(n.colour.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, "0").toUpperCase()}",
            open: true,
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("chartsNoteColour", "Colour", n.colour,
                      (v) => put(n.copyWith(colour: v))),
                  const SizedBox.shrink(),
                ]),
              ]),
            ]),
      ]
    );
  }

  String _highlightName(ChartHighlight h) {
    if (h.name.trim().isNotEmpty) return h.name.trim();
    var by = h.by < 0
        ? (e.data.series.isEmpty ? "" : e.data.series.first.name)
        : _columnName(h.by);
    return switch (h.reach) {
      ChartReach.one => "Just ${h.who.isEmpty ? "one" : h.who}",
      ChartReach.top => "Top ${h.n} by $by",
      ChartReach.bottom => "Bottom ${h.n} by $by",
      ChartReach.when => "$by ${switch (h.op) {
          ">=" => "at least",
          "<=" => "at most",
          ">" => "over",
          "<" => "under",
          _ => "exactly",
        }} ${ChartsDesignState._num(h.value)}",
    };
  }

  /// _typeface is a face, a weight, a size and a colour for words: the
  /// same block wherever the chart writes.
  List<Widget> _typeface(String id, TextSpec spec, ValueChanged<TextSpec> set,
          Widget size, Widget colour) =>
      [
        studioRow([
          _menu<String>(
              ValueKey(id),
              "Typeface",
              spec.fontFamily,
              [
                if (!canvasFonts.contains(spec.fontFamily))
                  (spec.fontFamily, spec.fontFamily),
                for (var f in canvasFonts) (f, f),
              ],
              (f) => set(spec.copyWith(fontFamily: f))),
          size,
        ], flex: [
          3,
          2
        ]),
        studioRow([
          studioSeg<int>(
              id: "${id}Weight",
              label: "Weight",
              value: spec.weight,
              options: const [
                (400, "Regular"),
                (600, "Semibold"),
                (800, "Bold")
              ],
              onChanged: (w) => set(spec.copyWith(weight: w))),
          colour,
        ], flex: [
          3,
          2
        ]),
      ];
}
