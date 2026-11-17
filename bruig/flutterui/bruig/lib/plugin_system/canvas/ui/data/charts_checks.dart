part of 'data_charts_design.dart';

// Checks: what makes a chart hard to read, each with a fix. Part of
// ChartsDesignState: its fields, lifecycle and build are in
// data_charts_design.dart.

extension ChartsChecks on ChartsDesignState {
  /// _checks is what might make the chart hard to read, with fixes.
  List<(String, List<(String, VoidCallback)>)> _checks() {
    var s = _sheet;
    if (s == null) return const [];
    var l = _link,
        data = e.data,
        out = <(String, List<(String, VoidCallback)>)>[];
    var n = data.categories.length;
    if ((e.type == ChartType.pie || e.type == ChartType.donut) && n > 8) {
      out.add((
        "$n slices are hard to read.",
        [
          (
            "Ranked bars",
            () => _setLinkAndType(
                l.copyWith(sortBy: l.series.firstOrNull ?? -1),
                ChartType.horizontalBar)
          ),
          (
            "The biggest eight",
            () =>
                _setLink(l.copyWith(sortBy: l.series.firstOrNull ?? -1, top: 8))
          ),
        ]
      ));
    }
    // Labels repeated and nothing gathering them: only each last shows.
    if (l.group.isEmpty && l.through < 0 && !(l.colourBy >= 0 && n > 0)) {
      var g = l.range, seen = <String>{}, twice = false;
      for (var r = g.r0 + 1; r <= g.r1; r++) {
        if (!seen.add(sheetShown(s, r, g.c0 + l.labels))) twice = true;
      }
      if (twice) {
        var kinds = columnKinds(s, g);
        var date = kinds.indexOf(ColumnKind.dates);
        out.add((
          "Each ${_columnName(l.labels)} has several rows; only the last is shown.",
          [
            if (date >= 0 && date != l.labels)
              (
                "Play through ${_columnName(date)}",
                () => _setLink(l.copyWith(through: date))
              ),
            ("Total for each", () => _setLink(l.copyWith(group: "total"))),
          ]
        ));
      }
    }
    if ((e.type == ChartType.line || e.type == ChartType.area) &&
        data.series.length > 8 &&
        !e.highlights.any((h) => !h.off) &&
        s.spotlight.isEmpty) {
      out.add((
        "${data.series.length} lines are hard to follow.",
        [
          (
            "Light up the top 3",
            () => _set(e.copyWith(highlights: [
                  ...e.highlights,
                  const ChartHighlight(
                      reach: ChartReach.top,
                      n: 3,
                      colour: Color(0xFF2FE08A),
                      named: true),
                ]))
          ),
        ]
      ));
    }
    var base = data.series.isEmpty ? null : data.series.first.color;
    for (var (i, h) in e.highlights.indexed) {
      if (h.off || base == null || h.colour != base) continue;
      out.add((
        "“${_highlightName(h)}” is the same colour as the rest.",
        [
          (
            "Make it gold",
            () {
              var all = [...e.highlights];
              all[i] = h.copyWith(colour: const Color(0xFFF2B33D));
              _set(e.copyWith(highlights: all));
            }
          ),
        ]
      ));
    }
    return out;
  }

  void _setLinkAndType(SheetLink link, ChartType type) =>
      _set(withLink(e.copyWith(type: type), link) as ChartElement);

  List<Widget> _checkRows(BuildContext context) {
    var checks = _checks();
    if (checks.isEmpty) return const [];
    return [
      Container(
        key: const ValueKey("chartsChecks"),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(children: [
          for (var (i, (say, fixes)) in checks.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Text(say,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFF2B33D))),
                ),
                for (var (j, (label, fix)) in fixes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: StudioPill(
                        key: ValueKey("chartsFix-$i-$j"),
                        label: label,
                        onTap: fix),
                  ),
              ]),
            ),
        ]),
      ),
    ];
  }
}
