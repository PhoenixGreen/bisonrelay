part of 'data_charts_design.dart';

// The slots the columns are put in, and the stage the chart is drawn on. Part
// of ChartsDesignState: its fields, lifecycle and build are in
// data_charts_design.dart.

extension ChartsSlotsStage on ChartsDesignState {
  Widget _shelf(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var l = _link;
    Widget slot(String name, List<Widget> children) => Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(name.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant)),
            const SizedBox(width: 6),
            ...children,
          ]),
        );
    var numberColumns = [
      for (var col in _columns)
        if (_numbers(col)) col
    ];
    var wordColumns = [
      for (var col in _columns)
        if (!_numbers(col)) col
    ];
    var dates = l.through >= 0 ? _dates(l.through) : const <String>[];
    var rows = l.places.trim().isNotEmpty
        ? "places"
        : l.top > 0
            ? (l.bottom ? "bottom" : "top")
            : "all";
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            slot("Labels", [
              _Menu<int>(
                  key: const ValueKey("chartsLabels"),
                  width: 140,
                  value: l.labels,
                  options: [for (var col in _columns) (col, _columnName(col))],
                  onChanged: (v) => _setLink(l.copyWith(labels: v))),
              _Menu<String>(
                  key: const ValueKey("chartsGroup"),
                  width: 104,
                  value: l.group,
                  options: _groups,
                  onChanged: (v) => _setLink(l.copyWith(group: v))),
            ]),
            slot("Values", [
              for (var col in l.series)
                _SlotChip(
                    key: ValueKey("chartsValue-$col"),
                    label: _columnName(col),
                    onRemove: l.series.length < 2
                        ? null
                        : () => _setLink(
                            l.copyWith(series: [...l.series]..remove(col)))),
              _Menu<int>(
                  key: const ValueKey("chartsAddValue"),
                  width: 64,
                  value: -1,
                  options: [
                    (-1, "+"),
                    for (var col in numberColumns)
                      if (!l.series.contains(col)) (col, _columnName(col)),
                  ],
                  onChanged: (v) {
                    if (v >= 0) _setLink(l.copyWith(series: [...l.series, v]));
                  }),
            ]),
            slot("Colour by", [
              _Menu<int>(
                  key: const ValueKey("chartsColourBy"),
                  width: 130,
                  value: l.colourBy,
                  options: [
                    (-1, "Nothing"),
                    for (var col in _columns) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(colourBy: v))),
            ]),
            slot("Small charts by", [
              _Menu<int>(
                  key: const ValueKey("chartsSplit"),
                  width: 130,
                  value: l.split,
                  options: [
                    (-1, "One chart"),
                    for (var col in wordColumns)
                      if (col != l.labels) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(split: v))),
            ]),
            slot("Play through", [
              _Menu<int>(
                  key: const ValueKey("chartsThrough"),
                  width: 130,
                  value: l.through,
                  options: [
                    (-1, "Nothing"),
                    for (var col in wordColumns)
                      if (col != l.labels) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(through: v, at: ""))),
              if (dates.isNotEmpty)
                _Menu<String>(
                    key: const ValueKey("chartsAt"),
                    width: 110,
                    value: dates.contains(l.at) ? l.at : "",
                    options: [
                      ("", "the last"),
                      for (var d in dates) (d, d),
                    ],
                    onChanged: (v) => _setLink(l.copyWith(at: v))),
            ]),
            // Which rows, in what order: beside the rest it reads.
            slot("Rows", [
              _Menu<String>(
                  key: const ValueKey("chartsRows"),
                  width: 104,
                  value: rows,
                  options: const [
                    ("all", "Every one"),
                    ("top", "Top"),
                    ("bottom", "Bottom"),
                    ("places", "Places"),
                  ],
                  onChanged: (v) => _setLink(switch (v) {
                        "top" => l.copyWith(
                            top: l.top > 0 ? l.top : 5,
                            bottom: false,
                            places: ""),
                        "bottom" => l.copyWith(
                            top: l.top > 0 ? l.top : 5,
                            bottom: true,
                            places: ""),
                        "places" =>
                          l.copyWith(top: 0, bottom: false, places: "1-3"),
                        _ => l.copyWith(top: 0, bottom: false, places: ""),
                      })),
              if (rows == "top" || rows == "bottom")
                _Menu<int>(
                    key: const ValueKey("chartsTopN"),
                    width: 64,
                    value: l.top,
                    options: [
                      for (var n in {
                        ...const [3, 5, 8, 10, 12, 15, 20, 25, 30],
                        l.top
                      }.toList()
                        ..sort())
                        (n, "$n"),
                    ],
                    onChanged: (n) => _setLink(l.copyWith(top: n))),
              if (rows == "places") ...[
                SizedBox(
                  width: 96,
                  child: _Field(
                      key: const ValueKey("chartsPlaces"),
                      text: l.places,
                      hint: "1-3, 16-19",
                      onChanged: (v) => _live(
                          withLink(e, l.copyWith(places: v)) as ChartElement)),
                ),
                _Menu<bool>(
                    key: const ValueKey("chartsGap"),
                    width: 104,
                    value: l.gap,
                    options: const [(true, "A gap (…)"), (false, "Close up")],
                    onChanged: (v) => _setLink(l.copyWith(gap: v))),
              ],
            ]),
            slot("In order of", [
              _Menu<int>(
                  key: const ValueKey("chartsSort"),
                  width: 150,
                  value: l.sortBy,
                  options: [
                    (-1, "The sheet's own"),
                    for (var col in numberColumns) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(sortBy: v))),
              if (l.sortBy >= 0)
                _Menu<bool>(
                    key: const ValueKey("chartsDescending"),
                    width: 118,
                    value: l.descending,
                    options: const [
                      (true, "Largest first"),
                      (false, "Smallest first")
                    ],
                    onChanged: (v) => _setLink(l.copyWith(descending: v))),
            ]),
            slot("Kind", [
              _Menu<ChartType>(
                  key: const ValueKey("chartsType"),
                  width: 150,
                  value: e.type,
                  options: [
                    for (var t in _commonTypes) (t, t.label),
                    for (var t in ChartType.values)
                      if (!_commonTypes.contains(t)) (t, t.label),
                  ],
                  onChanged: (v) => _set(e.copyWith(type: v))),
            ]),
          ]),
    );
  }

  Widget _stage(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
      var k = math
          .min((box.maxWidth - 40) / w, (box.maxHeight - 40) / h)
          .clamp(0.1, 2.5)
          .toDouble();
      var o = Offset((box.maxWidth - w * k) / 2, (box.maxHeight - h * k) / 2);
      _k = k;
      _o = o;
      ChartPick? pickAt(Offset p) {
        var at = (p - o) / k;
        ChartPart? best;
        for (var part in parts) {
          if (!part.contains(at)) continue;
          // A mark over the plot it sits in; writing over everything.
          if (best == null ||
              ChartsDesignState._rank(part.kind) >
                  ChartsDesignState._rank(best.kind)) {
            best = part;
          }
        }
        if (best == null) return null;
        if (best.kind == ChartPartKind.mark) {
          return ChartPick("mark", series: best.series, index: best.index);
        }
        if (best.kind == ChartPartKind.note) {
          return ChartPick("note", index: best.index);
        }
        return ChartPick(best.kind.name);
      }

      return Container(
        color: colors.surfaceContainerLowest,
        child: MouseRegion(
          onHover: (ev) {
            var p = pickAt(ev.localPosition);
            if (p?.kind == "mark" &&
                _picked.kind != "series" &&
                _picked.kind != "mark") {
              p = ChartPick("series", series: p!.series);
            }
            if (p != _hover) setState(() => _hover = p);
          },
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _focus.requestFocus();
              var p = pickAt(d.localPosition);
              if (p == null) return _pick(ChartPick.chart);
              if (p.kind == "mark") {
                // A mark: first its series, then that mark alone.
                var again =
                    (_picked.kind == "series" && _picked.series == p.series) ||
                        _picked.kind == "mark";
                return _pick(again ? p : ChartPick("series", series: p.series));
              }
              _pick(p);
            },
            child: CustomPaint(
              key: const ValueKey("chartsStage"),
              size: Size(box.maxWidth, box.maxHeight),
              painter: _ChartStage(
                e: _shown(),
                k: k,
                o: o,
                ground: c.document.background.spec.background,
                picked: _picked,
                hover: _hover,
                accent: colors.primary,
                onParts: (p) => parts = p,
              ),
            ),
          ),
        ),
      );
    });
  }

  /// stageOffsetOf is where a part was drawn, on the stage: for tests.
  Offset stageOffsetOf(ChartPart part) => stageAt(part.rect.center);

  /// stageAt is a point of the chart's own, on the stage.
  Offset stageAt(Offset local) => _o + local * _k;
}
