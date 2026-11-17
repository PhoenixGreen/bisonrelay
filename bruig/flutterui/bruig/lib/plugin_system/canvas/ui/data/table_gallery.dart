part of 'data_table_design.dart';

// The gallery of table designs. Part of _TableDesignState: its fields,
// lifecycle and build are in data_table_design.dart.

extension _TableGallery on _TableDesignState {
  Color get _ground =>
      dataStyleNamed(t.style)?.ground ?? c.document.background.spec.background;

  TableKind get _kindOpen => tableKinds.firstWhere((k) => k.id == _galleryKind);

  Widget _designCard(BuildContext context,
      {required Key key,
      required String name,
      required String says,
      required TableElement? shown,
      required bool picked,
      List<ChartUse> uses = const [],
      VoidCallback? onTap}) {
    final colors = ThemeNotifier.of(context).colors;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: picked ? colors.primary : colors.outlineVariant,
                width: picked ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: shown == null
                      ? ColoredBox(color: colors.surfaceContainerHighest)
                      : CustomPaint(
                          size: Size.infinite,
                          painter: _DesignThumb(shown, _ground, c.images)),
                ),
              ),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface)),
              Text(says,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: colors.onSurfaceVariant)),
              if (uses.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(uses.map((u) => u.label).join(" · "),
                    style: TextStyle(fontSize: 10.5, color: colors.primary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _designGrid(List<Widget> cards) =>
      LayoutBuilder(builder: (context, box) {
        var n = math.max(1, (box.maxWidth / 260).floor());
        var w = (box.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (var card in cards)
            SizedBox(width: w, height: w * 0.8, child: card),
        ]);
      });

  Widget _designs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var shape = TableShape(t);
    var head = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_galleryKind != null)
              StudioPill(
                  key: const ValueKey("tableGalleryBack"),
                  label: "All tables",
                  icon: Icons.arrow_back,
                  onTap: () => setState(() {
                        _galleryKind = null;
                        _galleryPreset = null;
                      })),
            for (var (u, name) in [
              (null, "All"),
              for (var x in ChartUse.values) (x, x.label)
            ])
              StudioPill(
                  key: ValueKey("tableGalleryUse-${u?.name ?? "all"}"),
                  label: name,
                  selected: _galleryUse == u,
                  onTap: () => setState(() => _galleryUse = u)),
          ]),
    );
    if (_galleryKind == null) {
      var kinds = [
        for (var k in tableKinds)
          if (_galleryUse == null ||
              k.presets.any((p) => p.uses.contains(_galleryUse)))
            k
      ];
      return SingleChildScrollView(
        key: const ValueKey("tableGallery"),
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          _designGrid([
            for (var k in kinds)
              () {
                var p = k.presets.firstWhere(
                    (p) => p.needs?.call(shape) == null,
                    orElse: () => k.presets.first);
                var can = k.presets.any((p) => p.needs?.call(shape) == null);
                return _designCard(context,
                    key: ValueKey("tableKind-${k.id}"),
                    name: k.name,
                    says:
                        can ? k.use : "Needs ${k.presets.first.needs!(shape)}",
                    shown: presetTable(p, t),
                    picked: false,
                    onTap: () => setState(() {
                          _galleryKind = k.id;
                          _galleryPreset = null;
                        }));
              }(),
          ]),
        ]),
      );
    }
    var kind = _kindOpen;
    return SingleChildScrollView(
      key: const ValueKey("tableGalleryPresets"),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Text(kind.name,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        _hint(context,
            "${kind.use} Pick a starting design; it keeps the cells and your own styles."),
        const SizedBox(height: 10),
        _designGrid([
          for (var (i, p) in kind.presets.indexed)
            if (_galleryUse == null || p.uses.contains(_galleryUse))
              _designCard(context,
                  key: ValueKey("tablePreset-$i"),
                  name: p.name,
                  says: p.needs?.call(shape) == null
                      ? p.says
                      : "Needs ${p.needs!(shape)}",
                  shown:
                      p.needs?.call(shape) == null ? presetTable(p, t) : null,
                  picked: _galleryPreset == i,
                  uses: p.uses,
                  onTap: p.needs?.call(shape) == null
                      ? () => setState(() => _galleryPreset = i)
                      : null),
        ]),
      ]),
    );
  }

  Widget _designPanel(BuildContext context) {
    var preset = _galleryKind != null && _galleryPreset != null
        ? _kindOpen.presets[_galleryPreset!]
        : null;
    var shown = preset == null ? null : presetTable(preset, t);
    return StudioSide(
      header: StudioSideHeader(
        icon: Icons.dashboard_customize_outlined,
        crumbs: [
          ("Table", () => setState(() => _gallery = false)),
          ("Designs", null),
        ],
        crumbKey: "tableGalleryCrumb",
        title:
            preset == null ? "Designs" : "${_kindOpen.name} · ${preset.name}",
        titleKey: const ValueKey("tableGalleryTitle"),
        onUp: () => setState(() => _gallery = false),
      ),
      quick: [
        if (shown == null)
          _note("Each kind of table drawn with this table's cells. Open one "
              "to see its starting designs.")
        else ...[
          AspectRatio(
            aspectRatio: 1.4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                  key: const ValueKey("tableGalleryPreview"),
                  size: Size.infinite,
                  painter: _DesignThumb(shown, _ground, c.images)),
            ),
          ),
          const SizedBox(height: 8),
          _note(preset!.says),
          const SizedBox(height: 4),
          _note("It sets the header, lines, stripes, which columns are drawn "
              "rather than written, and what stands out. The cells, your own "
              "styles and the table's style stay."),
        ],
        const SizedBox(height: 10),
        studioButtons([
          if (shown != null)
            studioButton("Use this design",
                key: const ValueKey("tableGalleryApply"),
                primary: true, onPressed: () {
              _set(shown);
              setState(() {
                _gallery = false;
                _galleryKind = null;
                _galleryPreset = null;
                _picked = TablePart.table;
              });
            }),
          studioButton("Cancel",
              key: const ValueKey("tableGalleryCancel"),
              onPressed: () => setState(() => _gallery = false)),
        ]),
      ],
      body: const [],
    );
  }
}
