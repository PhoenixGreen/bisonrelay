part of 'data_charts_design.dart';

// The gallery: every kind of chart, built from the ticked columns. Part of
// ChartsDesignState: its fields, lifecycle and build are in
// data_charts_design.dart.

extension ChartsGallery on ChartsDesignState {
  Picks? get _picks {
    var s = _sheet, g = _gallery;
    if (s == null || g == null) return null;
    var range = _link.range;
    var kinds = columnKinds(s, range);
    List<int> of(ColumnKind k) => [
          for (var c = 0; c < kinds.length; c++)
            if (kinds[c] == k) c
        ];
    return picksOf(s, range, g, of(ColumnKind.numbers), of(ColumnKind.dates),
        of(ColumnKind.names));
  }

  DataStyle? get _gStyle => dataStyleNamed(_galleryStyle);

  /// _galleryChart is [kind]'s [preset] made from the ticked columns, in
  /// the gallery's style; null when it can't be.
  ChartElement? _galleryChart(ChartKind kind, ChartPreset preset,
      {Set<ChartModifier> mods = const {}}) {
    var p = _picks;
    if (p == null) return null;
    var made = presetChart(kind, preset, p, e.copyWith(title: ""), mods: mods);
    if (made == null) return null;
    var st = _gStyle;
    return st == null ? made : reread(chartInStyle(made, st), p.sheet);
  }

  Color get _galleryGround =>
      _gStyle?.ground ?? c.document.background.spec.background;

  bool _kindShown(ChartKind k) {
    if (_galleryQuestion != null && !k.questions.contains(_galleryQuestion)) {
      return false;
    }
    if (_galleryUse != null &&
        !k.presets.any((pr) => pr.uses.contains(_galleryUse))) {
      return false;
    }
    var q = _galleryQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    var text = "${k.name} ${k.use} ${k.presets.map((pr) => pr.name).join(" ")}"
        .toLowerCase();
    if (text.contains(q)) return true;
    return ChartsDesignState._synonyms.entries
        .any((en) => en.key.startsWith(q) && en.value.contains(k.type));
  }

  Widget _galleryView(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var p = _picks;
    if (p == null || p.numbers.isEmpty) {
      return Center(
          child: Text("Tick at least one column of numbers on the left.",
              style: TextStyle(color: colors.onSurfaceVariant)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: _Field(
                    key: const ValueKey("chartsGallerySearch"),
                    text: _galleryQuery,
                    hint: "Search: race, spider, share…",
                    onChanged: (v) => setState(() {
                          _galleryQuery = v;
                          _galleryKind = null;
                          _galleryPreset = null;
                        })),
              ),
              for (var (u, name) in [
                (null, "All"),
                for (var x in ChartUse.values) (x, x.label),
              ])
                StudioPill(
                    key: ValueKey("chartsGalleryUse-${u?.name ?? "all"}"),
                    label: name,
                    selected: _galleryUse == u,
                    onTap: () => setState(() => _galleryUse = u)),
              SizedBox(
                width: 170,
                child: _Menu<String>(
                    key: const ValueKey("chartsGalleryStyle"),
                    value: _galleryStyle,
                    options: [
                      ("", "Style: as it is"),
                      for (var st in dataStyles) (st.name, "Style: ${st.name}"),
                    ],
                    onChanged: (v) => setState(() => _galleryStyle = v)),
              ),
            ]),
      ),
      if (_galleryKind == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (var (q, name) in [
              (null, "All charts"),
              for (var x in ChartQuestion.values) (x, x.label),
            ])
              StudioPill(
                  key: ValueKey("chartsGalleryAsk-${q?.name ?? "all"}"),
                  label: name,
                  selected: _galleryQuestion == q,
                  onTap: () => setState(() => _galleryQuestion = q)),
          ]),
        ),
      Expanded(
          child: _galleryKind == null
              ? _kindGrid(context, p)
              : _presetGrid(context, p)),
    ]);
  }

  Widget _kindGrid(BuildContext context, Picks p) {
    final colors = ThemeNotifier.of(context).colors;
    var s = _sheet!;
    var ideas = chartIdeas(s, _link.range, _gallery!);
    var best = ideas.isEmpty ? null : ideas.first.type;
    var shown = chartKinds.where(_kindShown).toList();
    var fit = [
      for (var k in shown)
        if (k.reads(p) != null) k
    ];
    var unfit = [
      for (var k in shown)
        if (k.reads(p) == null) k
    ];
    // The best fit for the ticked columns first; then by how well each
    // suits them (kindFit), a poor one saying why.
    var suits = {for (var k in fit) k.type: kindFit(k, p)};
    var order = {for (var (i, k) in fit.indexed) k.type: i};
    fit.sort((a, b) {
      var first = (a.type == best ? 0 : 1).compareTo(b.type == best ? 0 : 1);
      if (first != 0) return first;
      var bySuit = suits[b.type]!.score.compareTo(suits[a.type]!.score);
      return bySuit != 0 ? bySuit : order[a.type]!.compareTo(order[b.type]!);
    });
    Widget card(ChartKind k, bool fits) {
      var preset = k.presets.firstWhere(
          (pr) => _galleryUse == null || pr.uses.contains(_galleryUse),
          orElse: () => k.presets.first);
      var chart = fits ? _galleryChart(k, preset) : null;
      var suit = suits[k.type] ?? KindFit.good;
      return Opacity(
        opacity: !fits
            ? 0.45
            : suit.poor
                ? 0.7
                : 1,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: k.type == best && fits
                      ? colors.primary
                      : colors.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey("chartsKind-${k.type.name}"),
            onTap: fits
                ? () => setState(() {
                      _galleryKind = k.type;
                      _galleryPreset = null;
                      _galleryMods = {};
                    })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: chart == null
                            ? ColoredBox(
                                color: colors.surfaceContainerHighest,
                                child: Center(
                                    child: Text(k.type.label,
                                        style: TextStyle(
                                            color: colors.onSurfaceVariant))))
                            : CustomPaint(
                                size: Size.infinite,
                                painter: _Thumb(chart, _galleryGround)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: Text(
                            "${k.name}${k.type == best && fits ? " · best fit" : ""}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface)),
                      ),
                      if (k.isNew)
                        _badge(context, "New", const Color(0xFFFF7A59)),
                    ]),
                    Text(!fits ? "Needs ${k.needs}" : suit.why ?? k.use,
                        key: ValueKey("chartsKindSays-${k.type.name}"),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // A warning in amber: the theme's tertiary is a panel
                        // fill, and words in it vanish.
                        style: TextStyle(
                            fontSize: 11.5,
                            color: fits && suit.why == null
                                ? colors.onSurfaceVariant
                                : const Color(0xFFD99A3E))),
                  ]),
            ),
          ),
        ),
      );
    }

    // Every card built (a few dozen thumbnails), so none waits for a scroll.
    return SingleChildScrollView(
        key: const ValueKey("chartsGallery"),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (shown.isEmpty)
            Text("Nothing matches “$_galleryQuery”.",
                style: TextStyle(color: colors.onSurfaceVariant)),
          _cardGrid([for (var k in fit) card(k, true)]),
          if (unfit.isNotEmpty) ...[
            const StudioLabel("Need other columns"),
            Text("Tick columns like these on the left to use them.",
                style:
                    TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            _cardGrid([for (var k in unfit) card(k, false)]),
          ],
        ]));
  }

  Widget _cardGrid(List<Widget> cards) =>
      LayoutBuilder(builder: (context, box) {
        var n = math.max(1, (box.maxWidth / 250).floor());
        var w = (box.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (var c in cards) SizedBox(width: w, height: w * 0.82, child: c),
        ]);
      });

  Widget _badge(BuildContext context, String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4)),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
                color: colour)),
      );

  ChartKind get _kind => chartKinds.firstWhere((k) => k.type == _galleryKind);

  Widget _presetGrid(BuildContext context, Picks p) {
    final colors = ThemeNotifier.of(context).colors;
    var kind = _kind;
    Widget card(int i, ChartPreset pr) {
      var needs = pr.needs?.call(p);
      var chart = needs == null ? _galleryChart(kind, pr) : null;
      return Opacity(
        opacity: needs == null ? 1 : 0.45,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: _galleryPreset == i
                      ? colors.primary
                      : colors.outlineVariant,
                  width: _galleryPreset == i ? 2 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey("chartsPreset-$i"),
            onTap: needs != null
                ? null
                : () {
                    setState(() {
                      _galleryPreset = i;
                      _galleryMods = {};
                    });
                    _galleryPlay.forward(from: 0);
                  },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: chart == null
                            ? ColoredBox(color: colors.surfaceContainerHighest)
                            : CustomPaint(
                                size: Size.infinite,
                                painter: _Thumb(chart, _galleryGround)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: Text(pr.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface)),
                      ),
                      if (pr.plays)
                        _badge(context, "Plays", const Color(0xFFF2B33D)),
                    ]),
                    Text(needs == null ? pr.says : "Needs $needs",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      for (var u in pr.uses)
                        _badge(context, u.label,
                            ChartsDesignState._useColours[u]!),
                    ]),
                  ]),
            ),
          ),
        ),
      );
    }

    var presets = [
      for (var (i, pr) in kind.presets.indexed)
        if (_galleryUse == null || pr.uses.contains(_galleryUse)) (i, pr)
    ];
    if (presets.isEmpty) presets = [...kind.presets.indexed];
    // Every card built (a few dozen thumbnails), so none waits for a scroll.
    return SingleChildScrollView(
        key: const ValueKey("chartsGalleryPresets"),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            StudioPill(
                key: const ValueKey("chartsGalleryBack"),
                label: "All charts",
                icon: Icons.arrow_back,
                onTap: () => setState(() {
                      _galleryKind = null;
                      _galleryPreset = null;
                    })),
            const SizedBox(width: 10),
            Expanded(
              child: Text(kind.name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface)),
            ),
          ]),
          _hint(context,
              "${kind.use} Pick a starting design; every part can still be changed afterwards."),
          if (kind.caveat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(kind.caveat,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFF2B33D))),
            ),
          const SizedBox(height: 10),
          _cardGrid([for (var (i, pr) in presets) card(i, pr)]),
        ]));
  }

  Widget _galleryPanel(BuildContext context) {
    var p = _picks;
    var preset = _galleryKind != null && _galleryPreset != null
        ? _kind.presets[_galleryPreset!]
        : null;
    var chart = preset == null
        ? null
        : _galleryChart(_kind, preset, mods: _galleryMods);
    void cancel() => setState(() {
          _gallery = null;
          _replacing = false;
        });
    var mods = p == null || chart == null
        ? const <ChartModifier>[]
        : [
            for (var m in ChartModifier.values)
              if (m.fits(_kind.type, p)) m
          ];
    return StudioSide(
      header: StudioSideHeader(
        icon: Icons.add_chart,
        crumbs: [("Chart", cancel), ("New chart", null)],
        crumbKey: "chartsGalleryCrumb",
        title: preset == null ? "New chart" : "${_kind.name} · ${preset.name}",
        titleKey: const ValueKey("chartsTitle"),
        onUp: cancel,
      ),
      quick: [
        if (chart == null || p == null)
          const StudioNote(
              "Tick the columns to show on the left. Every kind of chart is "
              "drawn with them; the best fit first. Open one to see its "
              "starting designs.")
        else ...[
          AspectRatio(
            aspectRatio: 1.45,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                  key: const ValueKey("chartsGalleryPreview"),
                  size: Size.infinite,
                  painter: _PlayThumb(
                      chart, _galleryGround, _galleryPlay.value, _sheet)),
            ),
          ),
          const SizedBox(height: 8),
          StudioNote(preset!.says),
          const SizedBox(height: 8),
          studioButtons([
            studioButton("Play its arrival",
                key: const ValueKey("chartsGalleryReplay"),
                icon: Icons.play_arrow,
                onPressed: () => _galleryPlay.forward(from: 0)),
          ]),
        ],
        const SizedBox(height: 10),
        studioButtons([
          if (chart != null)
            studioButton("Start with this",
                key: const ValueKey("chartsGalleryStart"),
                primary: true,
                onPressed: () => _makePreset(chart)),
          studioButton("Cancel",
              key: const ValueKey("chartsGalleryCancel"), onPressed: cancel),
        ]),
      ],
      body: [
        if (chart != null && mods.isNotEmpty)
          studioSection(
              remember: "charts.galleryAdd",
              icon: Icons.add_circle_outline,
              title: "Add to it",
              summary: _galleryMods.isEmpty
                  ? "Nothing yet"
                  : [for (var m in _galleryMods) m.label].join(", "),
              open: true,
              children: [
                studioGroup(
                    "",
                    [
                      studioButtons([
                        for (var m in mods)
                          studioButton(m.label,
                              key: ValueKey("chartsGalleryMod-${m.name}"),
                              icon: _galleryMods.contains(m)
                                  ? Icons.check
                                  : Icons.add,
                              primary: _galleryMods.contains(m),
                              tooltip: m.says,
                              onPressed: () => setState(() =>
                                  _galleryMods.contains(m)
                                      ? _galleryMods.remove(m)
                                      : _galleryMods.add(m))),
                      ]),
                    ],
                    help: "It sets the layout, labels, what's picked out, "
                        "notes, grid and how it arrives. It keeps your data "
                        "and words; the style sets the colours and "
                        "typefaces."),
              ]),
      ],
    );
  }

  /// _makePreset puts [chart], made from the ticked columns, on the canvas
  /// as one of this sheet's charts, one undo step, and opens it.
  void _makePreset(ChartElement chart) {
    var s = _sheet;
    if (s == null) return;
    _end();
    c.beginInteraction();
    String id;
    if (_replacing && c.document.elementById(e.id) != null) {
      c.replaceElement(chart.rebase(e.base));
      id = e.id;
    } else {
      var made = c.addDataView(ElementKind.chart, s.id, _link.range);
      c.replaceElement(chart.rebase(made.base));
      id = made.id;
    }
    // Its arrival laid on the timeline, or a preset draws no different.
    if (chart.animation.on) {
      if (c.document.elementById(id) case ChartElement now) {
        c.applyChartAnimation(now, chart.animation.preset);
      }
    }
    c.endInteraction();
    setState(() {
      _gallery = null;
      _replacing = false;
    });
    widget.onPickChart(id);
  }
}
