part of 'data_charts_design.dart';

// The left column of columns and charts, the board of every view of the sheet,
// what each column holds, and suggestions by how a chart looks with these
// numbers. Part of ChartsDesignState: its fields, lifecycle and build are in
// data_charts_design.dart.

extension ChartsBoard on ChartsDesignState {
  Widget _left(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var charts = viewsOf(c.document, widget.sheetId).whereType<ChartElement>();
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const StudioLabel("Columns"),
          Text("Click one to put it in a slot.",
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var col in _columns) _chip(context, col),
          ]),
          const StudioLabel("Charts of this sheet"),
          for (var ch in charts)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: colors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: ch.id == e.id
                            ? colors.primary
                            : const Color(0x00000000))),
                child: InkWell(
                  key: ValueKey("chartsPick-${ch.id}"),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onPickChart(ch.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ch.name.isEmpty ? "Chart" : ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface)),
                          Text(ch.type.label,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant)),
                        ]),
                  ),
                ),
              ),
            ),
          if (_sheet case var sheet? when sheet.spotlight.isNotEmpty) ...[
            const StudioLabel("Picked out everywhere"),
            Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: sheet.spotlightColour,
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(sheet.spotlight,
                    key: const ValueKey("chartsSpotlightName"),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: colors.onSurface)),
              ),
              StudioPill(
                  key: const ValueKey("chartsSpotlightOff"),
                  label: "Stop",
                  onTap: () => c.setSheet(sheet.copyWith(spotlight: ""))),
            ]),
            Text("In every chart of this sheet, and its tables.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("chartsNew"),
                label: "+ New chart",
                filled: true,
                onTap: () => setState(() {
                      _gallery = _startingPicks();
                      _offering = null;
                      _boardOn = false;
                      _galleryKind = null;
                      _galleryPreset = null;
                      _galleryMods = {};
                      _galleryStyle = e.style;
                    })),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("chartsBoard"),
                label: "Board",
                selected: _boardOn,
                tooltip: "Every view of this sheet together",
                onTap: () => setState(() {
                      _boardOn = !_boardOn;
                      _gallery = null;
                    })),
          ),
        ]),
      ),
    );
  }

  /// _onPage is the tables and charts of this sheet on the page being made.
  List<CanvasElement> get _onPage => [
        for (var v in c.document.elements)
          if (linkOf(v)?.sheet == widget.sheetId) v
      ];

  Widget _board(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var views = viewsOf(c.document, widget.sheetId);
    return GridView.extent(
      key: const ValueKey("chartsBoardGrid"),
      padding: const EdgeInsets.all(14),
      maxCrossAxisExtent: 340,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        for (var v in views)
          Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey("chartsBoardView-${v.id}"),
              onTap: v is ChartElement
                  ? () {
                      setState(() => _boardOn = false);
                      widget.onPickChart(v.id);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _ViewThumb(v, c.images,
                                c.document.background.spec.background),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          "${v is ChartElement ? "Chart" : "Table"} · "
                          "${v.name.isEmpty ? v.kind.label : v.name}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface)),
                    ]),
              ),
            ),
          ),
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Menu<PageLayout>(
                  key: const ValueKey("chartsLayout"),
                  value: _pageLayout,
                  options: [for (var l in PageLayout.values) (l, l.label)],
                  onChanged: (l) => setState(() => _pageLayout = l)),
              const SizedBox(height: 8),
              StudioPill(
                  key: const ValueKey("chartsLayOut"),
                  label: "Lay them out together",
                  filled: true,
                  onTap: _layOut),
              _hint(context,
                  "The ones on this page, filling it below where the top one is, as one step to undo."),
            ]),
          ),
        ),
      ],
    );
  }

  /// _layOut puts this sheet's views over the page in the layout chosen,
  /// filling it below where the top one starts (page_style.dart).
  void _layOut() {
    var views = _onPage;
    if (views.isEmpty) return;
    _end();
    c.layOutPage(views, _pageLayout);
  }

  ColumnKind _kindOf(int col) {
    var s = _sheet;
    if (s == null) return ColumnKind.empty;
    if (!identical(_kindsOf, s) || _kindsRange != _link.range) {
      _kindsOf = s;
      _kindsRange = _link.range;
      _kindsCache = columnKinds(s, _link.range);
    }
    return col < _kindsCache.length ? _kindsCache[col] : ColumnKind.empty;
  }

  Widget _chip(BuildContext context, int col) {
    final colors = ThemeNotifier.of(context).colors;
    var numbers = _numbers(col);
    // A column of weeks or years says so: the gallery reads it as when.
    var when = _kindOf(col) == ColumnKind.dates;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
              color: _offering == col || (_gallery?.contains(col) ?? false)
                  ? colors.primary
                  : colors.outlineVariant,
              width: _gallery?.contains(col) ?? false ? 2 : 1)),
      child: InkWell(
        key: ValueKey("chartsColumn-$col"),
        borderRadius: BorderRadius.circular(7),
        onTap: () => setState(() {
          var g = _gallery;
          if (g != null) {
            _gallery = g.contains(col) ? ([...g]..remove(col)) : [...g, col];
          } else {
            _offering = _offering == col ? null : col;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
                when
                    ? "date"
                    : numbers
                        ? "123"
                        : "abc",
                style: TextStyle(
                    fontSize: 9,
                    color: when
                        ? const Color(0xFF5FD3A8)
                        : numbers
                            ? const Color(0xFF6FA4F8)
                            : const Color(0xFFF2B33D))),
            const SizedBox(width: 5),
            Text(_columnName(col),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
          ]),
        ),
      ),
    );
  }

  /// _offer is the slots a column clicked on the left can go in.
  Widget _offer(BuildContext context, int col) {
    final colors = ThemeNotifier.of(context).colors;
    var l = _link;
    var numbers = _numbers(col);
    return Container(
      key: const ValueKey("chartsOffer"),
      width: double.infinity,
      color: colors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("Put ${_columnName(col)} in:",
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            if (!numbers)
              StudioPill(
                  key: const ValueKey("chartsPutLabels"),
                  label: "Labels",
                  onTap: () {
                    _setLink(l.copyWith(
                        labels: col, through: l.through == col ? -1 : null));
                    setState(() => _offering = null);
                  }),
            if (numbers && !l.series.contains(col))
              StudioPill(
                  key: const ValueKey("chartsPutValues"),
                  label: "Values",
                  onTap: () {
                    _setLink(l.copyWith(series: [...l.series, col]));
                    setState(() => _offering = null);
                  }),
            StudioPill(
                key: const ValueKey("chartsPutColour"),
                label: "Colour by",
                onTap: () {
                  _setLink(l.copyWith(colourBy: col));
                  setState(() => _offering = null);
                }),
            if (!numbers && col != l.labels)
              StudioPill(
                  key: const ValueKey("chartsPutThrough"),
                  label: "Play through",
                  onTap: () {
                    _setLink(l.copyWith(through: col, at: ""));
                    setState(() => _offering = null);
                  }),
            if (!numbers && col != l.labels)
              StudioPill(
                  key: const ValueKey("chartsPutSplit"),
                  label: "Small charts by",
                  onTap: () {
                    _setLink(l.copyWith(split: col));
                    setState(() => _offering = null);
                  }),
            StudioPill(
                label: "Cancel", onTap: () => setState(() => _offering = null)),
          ]),
    );
  }

  /// _startingPicks are the columns ticked when the gallery opens: the one
  /// naming the rows (or a date) and the last of numbers.
  List<int> _startingPicks() {
    var s = _sheet;
    if (s == null) return const [];
    var g = _link.range;
    var kinds = columnKinds(s, g);
    var date = kinds.indexOf(ColumnKind.dates);
    // The column naming the rows best (a name, not a code: namingScore).
    var name = -1;
    var most = 0.0;
    for (var (col, k) in kinds.indexed) {
      if (k != ColumnKind.names) continue;
      var score = namingScore(s, g, col);
      if (score > most) {
        most = score;
        name = col;
      }
    }
    var number = kinds.lastIndexOf(ColumnKind.numbers);
    return [
      if (date >= 0) date,
      if (name >= 0) name,
      if (number >= 0) number,
    ];
  }
}
