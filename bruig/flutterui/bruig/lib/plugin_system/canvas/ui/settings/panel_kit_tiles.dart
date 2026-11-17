part of 'panel_kit.dart';

// Choices made by looking: CanvasTiles and its kept tile pictures, the
// scrolling and folding rows they are laid out in, and CanvasToolTiles for a
// section's tools. Part of panel_kit.dart.

/// CanvasTile is one choice in [CanvasTiles]: a picture and its name.
class CanvasTile<T> {
  final T value;
  final String label;

  /// preview draws what choosing it does. Null shows [icon] instead.
  final WidgetBuilder? preview;
  final IconData? icon;

  /// paint draws the choice once into a kept picture (see TileSnapshot);
  /// preferred to [preview] for anything through a layer or filter.
  final TilePaint? paint;

  /// drawnFrom is what [preview] draws from beyond [value]; given, a tile in
  /// a folding card is built once and kept (see CanvasKept).
  final Object? drawnFrom;

  const CanvasTile(this.value, this.label,
      {this.preview, this.icon, this.drawnFrom, this.paint});
}

typedef TilePaint = void Function(Canvas canvas, Size size);

/// _snapshots is every tile's picture, drawn once, most recent last.
final LinkedHashMap<String, ui.Image> _snapshots = LinkedHashMap();

const int _snapshotsKept = 240;

/// TileSnapshot is [paint] drawn once at its size and kept as [id].
class TileSnapshot extends StatelessWidget {
  final String id;

  /// slot is which tile this is: while [holding], its last picture shows.
  final String? slot;
  final TilePaint paint;
  final Color ground;
  final double radius;
  const TileSnapshot(
      {required this.id,
      this.slot,
      required this.paint,
      required this.ground,
      this.radius = 5,
      super.key});

  /// holding is whether a control is dragged: tiles keep their pictures till
  /// it ends, or thirty (some 3D) would redraw each step.
  static bool Function() holding = _never;
  static bool _never() => false;

  /// letGo is the panels closed: their editor and kept pictures go.
  static void letGo() {
    holding = _never;
    for (var image in _snapshots.values) {
      image.dispose();
    }
    _snapshots.clear();
  }

  /// stoodIn counts pictures drawn with a stand-in (a body being made): not
  /// kept, and redrawn when [arrived] says the real thing is here.
  static int Function() stoodIn = _none;
  static int _none() => 0;
  static Listenable? arrived;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.infinite,
      painter: _SnapshotPainter(id, slot, paint, ground, radius,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, arrived));
}

/// _lastIn is the snapshot each tile slot last showed, by key.
final Map<String, String> _lastIn = {};

class _SnapshotPainter extends CustomPainter {
  final String id;
  final String? slot;
  final TilePaint draw;
  final Color ground;
  final double radius;
  final double ratio;
  _SnapshotPainter(this.id, this.slot, this.draw, this.ground, this.radius,
      this.ratio, Listenable? arrived)
      : super(repaint: arrived);

  /// _stale is whether this showed a picture held during a drag.
  bool _stale = false;

  ui.Image _image(Size size) {
    var w = math.max(1, (size.width * ratio).round());
    var h = math.max(1, (size.height * ratio).round());
    var key = "$id|${ground.toARGB32()}|${w}x$h";
    var at = slot == null ? null : "$slot|${w}x$h";
    var kept = _snapshots.remove(key);
    if (kept != null) {
      if (at != null) _lastIn[at] = key;
      return _snapshots[key] = kept;
    }
    if (at != null && TileSnapshot.holding()) {
      if (_snapshots[_lastIn[at]] case var held?) {
        _stale = true;
        return held;
      }
    }
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder)..scale(w / size.width, h / size.height);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var stood = TileSnapshot.stoodIn();
    draw(canvas, size);
    var picture = recorder.endRecording();
    var made = picture.toImageSync(w, h);
    picture.dispose();
    if (TileSnapshot.stoodIn() != stood) {
      // Not kept: drawn again when what stood in has arrived.
      _stale = true;
      return made;
    }
    if (at != null) _lastIn[at] = key;
    _snapshots[key] = made;
    while (_snapshots.length > _snapshotsKept) {
      _snapshots.remove(_snapshots.keys.first)!.dispose();
    }
    return made;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    var image = _image(size);
    var all = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(all, Radius.circular(radius)));
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        all,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnapshotPainter old) =>
      old._stale || old.id != id || old.ground != ground || old.ratio != ratio;
}

/// CanvasTiles is a choice made by looking: small named pictures, each
/// tried on the canvas through [onPreview] while pointed at (null on leave).
/// With [multiple], each toggles and wears a tick.
class CanvasTiles<T> extends StatelessWidget {
  final String? label;
  final List<CanvasTile<T>> tiles;
  final bool Function(T) selected;
  final ValueChanged<T> onPick;
  final ValueChanged<T?>? onPreview;
  final int columns;
  final bool multiple;

  /// keyOf names each tile, for tests.
  final String Function(T)? keyOf;

  final double previewHeight;

  /// help is what the choice does, behind its card's "?".
  final String help;

  /// ticked is which tiles wear a tick where that differs from lit (an
  /// effect on, settings shut); null is the lit ones.
  final bool Function(T)? ticked;

  /// scrolls lays the tiles in one scrolling line at [tileWidth] each.
  final bool scrolls;
  final double tileWidth;

  /// foldAs makes the card fold, remembered by that name: shut, one line
  /// with the chosen tile named; open, all.
  final String? foldAs;

  const CanvasTiles({
    this.scrolls = false,
    this.tileWidth = 78,
    this.help = "",
    this.ticked,
    this.foldAs,
    required this.tiles,
    required this.selected,
    required this.onPick,
    this.label,
    this.onPreview,
    this.columns = 3,
    this.multiple = false,
    this.keyOf,
    this.previewHeight = 38,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var gap = card ? 8.0 : 6.0;
    var grid = LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
      var each = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var t in tiles)
            SizedBox(
                width: math.max(40, each), child: _tile(context, theme, t)),
        ],
      );
    });
    if (card && foldAs != null) return _FoldingTiles<T>(tiles: this);
    if (card && scrolls) return _ScrollingTiles<T>(tiles: this);
    // In a section, a card of its own, named, with "?" beside the name.
    if (card) {
      return canvasCard(context,
          title: label == null ? null : canvasCardTitle(context, label!),
          help: help,
          body:
              Padding(padding: const EdgeInsets.only(right: 10), child: grid));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: canvasRowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: controlLabelGap + 1),
              child: Text(label!,
                  style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      color: theme.colors.onSurfaceVariant)),
            ),
          LayoutBuilder(builder: (context, box) {
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var t in tiles)
                  SizedBox(
                      width: math.max(40, each),
                      child: _tile(context, theme, t)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ThemeNotifier theme, CanvasTile<T> t,
      {bool hover = true, VoidCallback? tapped}) {
    var on = selected(t.value);
    var accent = theme.colors.primary;
    var tries = hover && onPreview != null && !multiple;
    return MouseRegion(
      onEnter: tries ? (_) => onPreview!(t.value) : null,
      onExit: tries ? (_) => onPreview!(null) : null,
      child: Semantics(
        button: true,
        selected: on,
        label: t.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: keyOf == null ? null : ValueKey(keyOf!(t.value)),
            borderRadius: BorderRadius.circular(8),
            onTap: tapped ??
                () {
                  onPreview?.call(null);
                  onPick(t.value);
                },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: on ? accent.withValues(alpha: 0.14) : null,
                border: Border.all(
                    color: on ? accent : theme.colors.outlineVariant,
                    width: on ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(children: [
                  if (t.paint != null)
                    // Drawn once and kept (see TileSnapshot).
                    SizedBox(
                      height: previewHeight,
                      width: double.infinity,
                      child: TileSnapshot(
                          id: "${t.value.runtimeType}:${t.value}:"
                              "${t.drawnFrom.hashCode}",
                          slot: "${t.label}|${t.value.runtimeType}:${t.value}",
                          paint: t.paint!,
                          ground: theme.colors.surfaceContainerHighest),
                    )
                  else
                    Container(
                      height: previewHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: theme.colors.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: t.preview != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child:
                                  SizedBox.expand(child: t.preview!(context)))
                          : Icon(t.icon ?? Icons.circle_outlined,
                              size: 20,
                              color:
                                  on ? accent : theme.colors.onSurfaceVariant),
                    ),
                  if ((ticked?.call(t.value) ?? (multiple && on)))
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                        child: Icon(Icons.check,
                            size: 10, color: theme.colors.onPrimary),
                      ),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                        color: theme.colors.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// _ToolRow is a scrolling line of tools keeping [active] in view.
class _ToolRow extends StatefulWidget {
  final int active;
  final double step;
  final double each;
  final Widget Function(ScrollController) builder;
  const _ToolRow(
      {required this.active,
      required this.step,
      required this.each,
      required this.builder});

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  final ScrollController _scroll = ScrollController();
  int _shown = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var at = widget.active;
    if (at >= 0 && at != _shown) {
      _shown = at;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        var p = _scroll.position;
        var left = at * widget.step, right = left + widget.each;
        var now = _scroll.offset, width = p.viewportDimension;
        var target = left < now
            ? left
            : right > now + width
                ? right - width
                : now;
        _scroll.jumpTo(target.clamp(0.0, p.maxScrollExtent).toDouble());
      });
    } else if (at < 0) {
      _shown = -1;
    }
    return widget.builder(_scroll);
  }
}

/// CanvasToolTiles is a section's tools as named tiles and, on a line
/// below, the held tool's settings. Pressing the held tool puts it down.
class CanvasToolTiles<T> extends StatelessWidget {
  final List<(T, IconData, String)> tools;
  final T? active;
  final ValueChanged<T?> onPick;
  final String Function(T) keyOf;
  final String Function(T) tooltipOf;

  /// settings are the active tool's, under the tiles.
  final List<Widget> settings;

  /// help is what the tools are for, behind their card's "?".
  final String help;

  /// alsoActive lights another tool too (select, under an align tool).
  final bool Function(T)? alsoActive;

  /// lit is whether [tool] is drawn as in hand.
  bool lit(T tool) => tool == active || (alsoActive?.call(tool) ?? false);

  /// idle is what is said under the tiles with none picked.
  final String idle;

  final String title;

  const CanvasToolTiles({
    this.idle = "Pick a tool to work on the canvas.",
    this.title = "Tools",
    this.help = "",
    this.alsoActive,
    required this.tools,
    required this.active,
    required this.onPick,
    required this.keyOf,
    required this.tooltipOf,
    this.settings = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    var card = CanvasCards.on(context);
    var held = [
      for (var t in tools)
        if (t.$1 == active) t
    ].firstOrNull;
    // The tool's notes go behind the card's "?", never on a settings row.
    var notes = [
      for (var w in settings)
        if (w is CanvasHint) w.message
    ];
    var controls = [
      for (var w in settings)
        if (w is! CanvasHint) w
    ];
    var about = [if (help.isNotEmpty) help, ...notes].join("\n\n");
    var body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(right: card ? 10 : 0),
          // A scrolling line, each tile its own width, so names are not cut.
          child: LayoutBuilder(builder: (context, box) {
            const gap = 6.0;
            var n = tools.length;
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = math.max(64.0, (width - gap * (n - 1)) / n);
            // The held tool kept in view when picked elsewhere (Add, a key).
            return _ToolRow(
                active: tools.indexWhere((t) => t.$1 == active),
                step: each + gap,
                each: each,
                builder: (scroll) => SizedBox(
                    height: card ? 56 : 46,
                    child: SingleChildScrollView(
                        key: const ValueKey("toolsRow"),
                        controller: scroll,
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (var (i, (tool, icon, short)) in tools.indexed)
                            Padding(
                                padding:
                                    EdgeInsets.only(left: i == 0 ? 0 : gap),
                                child: SizedBox(
                                  width: each,
                                  child: Tooltip(
                                    message: tooltipOf(tool),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        key: ValueKey(keyOf(tool)),
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => onPick(
                                            tool == active ? null : tool),
                                        child: Container(
                                          height: card ? 56 : 46,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            color: lit(tool)
                                                ? accent.withValues(alpha: 0.16)
                                                : null,
                                            border: Border.all(
                                                color: lit(tool)
                                                    ? accent
                                                    : theme
                                                        .colors.outlineVariant,
                                                width: lit(tool) ? 1.5 : 1),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(icon,
                                                  size: card ? 20 : 18,
                                                  color: lit(tool)
                                                      ? accent
                                                      : theme.colors
                                                          .onSurfaceVariant),
                                              const SizedBox(height: 4),
                                              Text(short,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize:
                                                          card ? 10.5 : 9.5,
                                                      color: theme
                                                          .colors.onSurface)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                        ]))));
          }),
        ),
        if (held == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(idle,
                style: TextStyle(
                    fontSize: card ? 12 : 10.5,
                    color: theme.colors.onSurfaceVariant)),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            child: Text(tooltipOf(held.$1),
                style: TextStyle(
                    fontSize: card ? 12.5 : 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.onSurface)),
          ),
          if (controls.isNotEmpty)
            CanvasWrap(
                runSpacing: card ? cardGapIn(context) : canvasRowGap,
                children: controls),
        ],
      ],
    );
    if (card) {
      return canvasCard(context,
          title: canvasCardTitle(context, title), help: about, body: body);
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
        child: body);
  }
}

/// _labelRoom is a strip tile's room under its picture at the text size.
double _labelRoom(BuildContext context) =>
    math.max(30.0, 16 + MediaQuery.textScalerOf(context).scale(9.5) * 1.35);

/// _ScrollingTiles is a card of tiles in one line, the choice kept in view.
class _ScrollingTiles<T> extends StatefulWidget {
  final CanvasTiles<T> tiles;
  const _ScrollingTiles({required this.tiles, super.key});

  @override
  State<_ScrollingTiles<T>> createState() => _ScrollingTilesState<T>();
}

class _ScrollingTilesState<T> extends State<_ScrollingTiles<T>> {
  final ScrollController _strip = ScrollController();

  /// _shown is the tile last scrolled into view: once when chosen, not
  /// every rebuild, which would snap the line back under someone scrolling.
  int _shown = -1;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var t = widget.tiles;
    const gap = 8.0;
    var at = t.tiles.indexWhere((tile) => t.selected(tile.value));
    return canvasCard(context,
        title: t.label == null ? null : canvasCardTitle(context, t.label!),
        help: t.help,
        body: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: LayoutBuilder(builder: (context, box) {
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            if (at >= 0 && at != _shown) {
              _shown = at;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_strip.hasClients) return;
                // Only as far as needed: one already in view stays put.
                var left = at * (t.tileWidth + gap);
                var right = left + t.tileWidth;
                var now = _strip.offset;
                var target = left < now
                    ? left
                    : right > now + width
                        ? right - width
                        : now;
                _strip.jumpTo(target
                    .clamp(0.0, _strip.position.maxScrollExtent)
                    .toDouble());
              });
            }
            return SizedBox(
              height: t.previewHeight + _labelRoom(context),
              // Every tile built: a handful, and off-screen ones are reachable.
              child: SingleChildScrollView(
                key: ValueKey("tilesRow-${t.label}"),
                controller: _strip,
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var (i, tile) in t.tiles.indexed)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                      child: SizedBox(
                          width: t.tileWidth,
                          child: t._tile(context, theme, tile, hover: false)),
                    ),
                ]),
              ),
            );
          }),
        ));
  }
}

/// _FoldingTiles is a card of tiles that folds: see CanvasTiles.foldAs.
class _FoldingTiles<T> extends StatefulWidget {
  final CanvasTiles<T> tiles;
  const _FoldingTiles({required this.tiles, super.key});

  @override
  State<_FoldingTiles<T>> createState() => _FoldingTilesState<T>();
}

class _FoldingTilesState<T> extends State<_FoldingTiles<T>> {
  late bool _open = rememberedSection(widget.tiles.foldAs!) ?? false;

  /// _kept is [tile], kept while unchanged (see CanvasKept); it picks
  /// through the current tiles, as the old build's pick is stale.
  Widget _kept(BuildContext context, ThemeNotifier theme, CanvasTile<T> tile) {
    var t = widget.tiles;
    void tapped() => widget.tiles.onPick(tile.value);
    if ((tile.preview != null || tile.paint != null) &&
        tile.drawnFrom == null) {
      return t._tile(context, theme, tile, hover: false, tapped: tapped);
    }
    return CanvasKept(
      key: ValueKey(tile.value),
      deps: [
        tile.value,
        tile.label,
        tile.icon,
        tile.drawnFrom,
        t.selected(tile.value),
        t.ticked?.call(tile.value),
        t.previewHeight,
        theme.colors,
      ],
      builder: (context) => widget.tiles
          ._tile(context, theme, tile, hover: false, tapped: tapped),
    );
  }

  final ScrollController _strip = ScrollController();

  /// _shown is the tile last brought into view, as in _ScrollingTiles.
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    var key = widget.tiles.foldAs!;
    if (rememberedSection(key) == null) {
      restoreSection(key, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _shown = -1;
    });
    keepSection(widget.tiles.foldAs, _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var t = widget.tiles;
    const gap = 8.0;
    var chosen = [
      for (var tile in t.tiles)
        if (t.selected(tile.value)) tile
    ];
    var title = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey("tilesFold-${t.foldAs}"),
        borderRadius: BorderRadius.circular(6),
        onTap: _toggle,
        child: Row(children: [
          AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(Icons.chevron_right,
                size: 18, color: theme.colors.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          // Its share of a narrow row, cut short at large text sizes.
          Flexible(
            child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: canvasCardTitle(context, t.label ?? "")),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(chosen.map((c) => c.label).join(" · "),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5, color: theme.colors.onSurfaceVariant)),
          ),
        ]),
      ),
    );
    var body = LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
      var each = math.max(40.0, (width - gap * (t.columns - 1)) / t.columns);
      // Open, clicked too: a tile tried on hover would be chosen, and its
      // settings would come and go under the pointer.
      if (_open) {
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var tile in t.tiles)
            SizedBox(width: each, child: _kept(context, theme, tile)),
        ]);
      }
      // The chosen one scrolled into view, once, when chosen.
      var at = t.tiles.indexWhere((tile) => t.selected(tile.value));
      if (at >= 0 && at != _shown) {
        _shown = at;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_strip.hasClients) return;
          var target = at * (each + gap) - (width - each) / 2;
          _strip.jumpTo(
              target.clamp(0.0, _strip.position.maxScrollExtent).toDouble());
        });
      }
      return SizedBox(
        height: t.previewHeight + _labelRoom(context),
        child: SingleChildScrollView(
          key: ValueKey("tilesStrip-${t.foldAs}"),
          controller: _strip,
          scrollDirection: Axis.horizontal,
          // Clicked, never tried on hover: a tried tile would scroll into
          // view and the pointer land on the next.
          child: Row(children: [
            for (var (i, tile) in t.tiles.indexed)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child:
                    SizedBox(width: each, child: _kept(context, theme, tile)),
              ),
          ]),
        ),
      );
    });
    return canvasCard(context,
        title: title,
        help: t.help,
        body: Padding(padding: const EdgeInsets.only(right: 10), child: body));
  }
}
